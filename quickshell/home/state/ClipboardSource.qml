import QtQml
import Quickshell
import Quickshell.Io
import "SourceParse.js" as Parse

// Clipboard presence, count, and the newest entry's length.
//
// HARD RULE: clipboard CONTENTS never reach this source. `clipboard-history.json`
// holds the user's copied text, so it is never read into QML at all. The only
// values crossing the boundary are the two scalars jq reduces it to, and the
// process is asked for exactly those.
//
// The surface therefore cannot render a preview even if a component wanted to.
QtObject {
    id: root

    property string sourceId: "clipboard"

    property string historyPath: {
        var stateHome = String(Quickshell.env("XDG_STATE_HOME") || "")
        if (stateHome === "")
            stateHome = String(Quickshell.env("HOME") || "") + "/.local/state"
        return stateHome + "/omarchy/clipboard-history.json"
    }

    property var snapshot: ({
        "available": false,
        "detail": "Waiting for the first sample",
        "updatedMs": 0
    })

    readonly property bool available: snapshot.available === true
    readonly property int count: available ? (snapshot.count || 0) : -1
    readonly property int newestLength: available && snapshot.newestLength >= 0
        ? snapshot.newestLength
        : -1

    readonly property bool hasEntries: available && count > 0

    // jq extracts the count and the newest entry's length. No filter can return
    // the text itself, because no filter is asked for it.
    property Process meta: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                var text = String(line === undefined || line === null ? "" : line).trim()
                if (text !== "")
                    root.values.push(text)
            }
        }
        onExited: function(exitCode) {
            root.meta.running = false
            root.watchdog.stop()
            root.finish(Number(exitCode))
        }
    }

    property var values: []
    property Timer watchdog: Timer {
        interval: 6000
        repeat: false
        onTriggered: {
            if (root.meta.running)
                root.meta.running = false
            root.finish(-1)
        }
    }

    property Timer poll: Timer {
        interval: 20000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    function sample() {
        if (root.meta.running)
            return
        root.values = []
        root.meta.command = [
            "/usr/bin/jq", "-r",
            // One output line: the entry count, then the newest entry's length.
            "(length|tostring), ((.[-1].text // \"\") | length | tostring)",
            root.historyPath
        ]
        root.meta.running = true
        root.watchdog.restart()
    }

    function finish(exitCode) {
        if (exitCode !== 0 || root.values.length < 2) {
            root.snapshot = {
                "available": false,
                "detail": "Clipboard history could not be summarised",
                "updatedMs": Date.now()
            }
            return
        }
        var parsed = Parse.parseClipboardMeta(root.values[0], root.values[1])
        if (parsed === null) {
            root.snapshot = {
                "available": false,
                "detail": "Clipboard summary was unreadable",
                "updatedMs": Date.now()
            }
            return
        }
        root.snapshot = {
            "available": true,
            "detail": "",
            "updatedMs": Date.now(),
            "count": parsed.count,
            "newestLength": parsed.newestLength
        }
    }
}
