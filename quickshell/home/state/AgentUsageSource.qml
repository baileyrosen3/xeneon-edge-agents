import QtQml
import Quickshell
import Quickshell.Io
import "SourceParse.js" as Parse

// Aggregate agent utilisation, read from the per-agent usage records.
//
// DISPLAY ONLY, and deliberately narrow. Only the scalar counters are taken:
// prompts and sessions. A record's prompt text, message bodies, provider
// payloads, model detail, and anything from T3 Code checkpoints or secrets are
// never read into this object, so they cannot reach the surface. Nothing here
// is dispatched: this source has no actions.
QtObject {
    id: root

    property string sourceId: "agentUsage"

    property string usageDirectory: {
        var stateHome = String(Quickshell.env("XDG_STATE_HOME") || "")
        if (stateHome === "")
            stateHome = String(Quickshell.env("HOME") || "") + "/.local/state"
        return stateHome + "/omarchy/agents/usage"
    }

    property var snapshot: ({
        "available": false,
        "detail": "Waiting for the first sample",
        "updatedMs": 0
    })

    readonly property bool available: snapshot.available === true
    readonly property var agents: snapshot.agents || []
    readonly property int totalPrompts: snapshot.totalPrompts || 0
    readonly property int totalSessions: snapshot.totalSessions || 0

    // The file list, bounded. A directory listing is a bounded read; nothing
    // else is enumerated.
    property Process listing: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                root.names.push(String(line === undefined || line === null ? "" : line).trim())
            }
        }
        onExited: function(exitCode) {
            root.listing.running = false
            root.readFirst()
        }
    }

    property var names: []
    property var records: []
    property int readIndex: 0

    property Timer poll: Timer {
        interval: 120000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    property Timer watchdog: Timer {
        interval: 8000
        repeat: false
        onTriggered: {
            if (root.listing.running)
                root.listing.running = false
            root.finish()
        }
    }

    function sample() {
        if (root.listing.running || root.reading)
            return
        root.names = []
        root.reading = true
        root.listing.command = ["/usr/bin/find", root.usageDirectory, "-maxdepth", "1", "-name", "*.json"]
        root.listing.running = true
        root.watchdog.restart()
    }

    property bool reading: false
    property FileView record: FileView {
        preload: true
        blockLoading: true
        printErrors: false
        path: ""
        onLoaded: {
            root.records.push(root.record.text())
            root.readNext()
        }
        onLoadFailed: root.readNext()
    }

    function readFirst() {
        root.watchdog.stop()
        root.records = []
        root.readIndex = 0
        // Bounded: at most a handful of records are read, never an unbounded walk.
        if (root.names.length === 0) {
            root.finish()
            return
        }
        root.record.path = root.names[0]
    }

    function readNext() {
        root.readIndex += 1
        if (root.readIndex >= root.names.length || root.records.length >= 6) {
            root.finish()
            return
        }
        root.record.path = root.names[root.readIndex]
    }

    function finish() {
        root.record.path = ""
        root.reading = false

        var agents = []
        var prompts = 0
        var sessions = 0
        var readable = 0
        for (var index = 0; index < root.records.length; index += 1) {
            var parsed = Parse.parseAgentUsage(root.records[index])
            if (parsed === null)
                continue
            readable += 1
            prompts += parsed.prompts
            sessions += parsed.sessions
            agents.push({ "name": parsed.name, "ready": parsed.ready })
        }

        root.snapshot = readable === 0
            ? {
                "available": false,
                "detail": "No agent usage record could be read",
                "updatedMs": Date.now()
            }
            : {
                "available": true,
                "detail": "",
                "updatedMs": Date.now(),
                "agents": agents,
                "totalPrompts": prompts,
                "totalSessions": sessions
            }
    }
}
