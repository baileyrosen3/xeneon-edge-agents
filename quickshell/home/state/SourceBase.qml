import QtQml
import Quickshell
import Quickshell.Io

// The one base every home data source extends.
//
// A source declares a fixed list of probes, each a label and a fixed argv.
// The base runs them one at a time off a timer, never overlapping, hands the
// collected text to `ingest`, and publishes a single snapshot object with one
// shape for every source in this config:
//
//   { available: bool, detail: string, updatedMs: number, ...fields }
//
// `available` is false whenever the underlying tool, file, or service is
// absent or unreadable. A source therefore cannot present a zero as if it were
// a measurement: the UI reads `available` and renders an explicit unavailable
// state, and every field it does publish is a real reading.
QtObject {
    id: root

    // The subclass contract. Each source overrides exactly these three
    // methods, so there is one place that decides how a poll runs and no
    // subclass can change that behaviour by shadowing state.
    //
    //   sourceId()       stable id used in logs and unavailable messages
    //   intervalMs()     poll period; a service-backed source returns 0 and
    //                    pushes its own snapshot instead of polling
    //   probeList()      [{ "label": "...", "argv": [...] }, ...], fixed in
    //                    code, never extended or rewritten at run time
    function sourceId() {
        return "source"
    }

    function intervalMs() {
        return 4000
    }

    function probeList() {
        return []
    }

    property bool active: true

    // Milliseconds a probe may run before it is abandoned and reported as a
    // failed reading rather than blocking the next poll.
    readonly property int probeTimeoutMs: 4000

    property var snapshot: ({
        "available": false,
        "detail": "Waiting for the first sample",
        "updatedMs": 0
    })

    property int sampleCount: 0
    property bool sampling: false
    readonly property bool pending: root.sampling || root.runner.running
        || root.queue.length > 0

    property var queue: []
    property var collected: ({})
    property string currentLabel: ""
    property bool followedUp: false

    property Process runner: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                var text = String(line === undefined || line === null ? "" : line)
                root.lines.push(text)
            }
        }
        stderr: SplitParser {
            onRead: function(line) {
                root.errors.push(String(line === undefined || line === null ? "" : line))
            }
        }
        onStarted: root.probeTimer.restart()
        onExited: function(exitCode) {
            root.probeTimer.stop()
            root.finishProbe(Number(exitCode))
        }
    }

    property var lines: []
    property var errors: []

    property Timer probeTimer: Timer {
        interval: root.probeTimeoutMs
        repeat: false
        onTriggered: {
            // A probe that outruns its deadline is abandoned so a wedged tool
            // can never stall the surface or report a stale reading as fresh.
            if (root.runner.running)
                root.runner.running = false
            root.errors.push("probe timed out")
            root.finishProbe(-1)
        }
    }

    property Timer pollTimer: Timer {
        interval: root.intervalMs()
        repeat: true
        running: root.active && root.intervalMs() > 0
        onTriggered: root.poll()
    }

    onActiveChanged: {
        if (root.active)
            root.poll()
    }

    Component.onCompleted: {
        if (root.probeList().length === 0 && root.intervalMs() === 0)
            root.publishUnavailable("Source has no probe and no poll interval")
        else
            root.poll()
    }

    // Optional second stage. `followUpProbes` receives the fixed probe results
    // and returns further probes for paths it discovered, such as a sysfs file
    // under a card directory found by listing a directory. Only /proc and /sys
    // paths passing `validReadPath` may be probed this way, so a discovered
    // name can never become an arbitrary command line.
    function followUpProbes(_results) {
        return []
    }

    function validReadPath(path) {
        var text = String(path === null || path === undefined ? "" : path)
        if (text.indexOf("..") !== -1)
            return false
        return /^\/(proc|sys)\/[A-Za-z0-9._\/-]*$/.test(text)
    }

    // Starts one collection cycle. Overlapping cycles are refused so a slow
    // tool cannot queue work behind itself.
    function poll() {
        if (!root.active || root.pending)
            return

        var list = root.probeList()
        if (!Array.isArray(list) || list.length === 0) {
            root.publishUnavailable("Source has no probe")
            return
        }

        root.queue = list.slice()
        root.collected = ({})
        root.sampling = true
        root.runNext()
    }

    function runNext() {
        if (root.queue.length === 0) {
            // The fixed probe list may discover further /proc or /sys paths to
            // read. Those are appended once, then the cycle closes.
            if (!root.followedUp) {
                root.followedUp = true
                var extra = root.acceptProbes(root.followUpProbes(root.collected))
                if (extra.length > 0) {
                    root.queue = extra
                    root.runNext()
                    return
                }
            }
            root.sampling = false
            root.followedUp = false
            var results = root.collected
            root.collected = ({})
            root.ingest(results)
            return
        }

        var probe = root.queue[0]
        root.queue = root.queue.slice(1)
        root.currentLabel = String(probe.label || "")
        root.lines = []
        root.errors = []

        var argv = probe.argv
        if (!root.validArgv(argv)) {
            root.collected[root.currentLabel] = {
                "code": -1,
                "text": "",
                "error": "probe argv is not a fixed absolute command"
            }
            root.runNext()
            return
        }

        root.runner.command = argv
        root.runner.running = true
    }

    // A fixed probe is an absolute executable followed by either absolute
    // paths or simple flags. Only the executable must be absolute; every other
    // element is additionally refused if it looks like a shell construct, so a
    // probe argv can never be anything but the literal argument vector it
    // appears to be.
    function validArgv(argv) {
        if (!Array.isArray(argv) || argv.length < 1)
            return false
        if (typeof argv[0] !== "string" || argv[0].charAt(0) !== "/")
            return false
        for (var index = 1; index < argv.length; index += 1) {
            if (!validArg(argv[index]))
                return false
        }
        return true
    }

    // A permitted argument is an absolute path, a short flag such as `-j`, or
    // a bare word such as a hyprctl subcommand. Shell metacharacters, newlines,
    // globs, and relative paths containing separators are all refused, so a
    // probe argv can only ever be the literal argument vector it appears to be.
    // The patterns are inline because a JavaScript value cannot be declared at
    // QML object scope.
    function validArg(value) {
        if (typeof value !== "string" || value === "")
            return false
        if (/[\n\r;|&`$><*?()\[\]{}!\\"']/.test(value))
            return false
        if (/^-[A-Za-z0-9]{1,16}$/.test(value))
            return true
        if (value.charAt(0) === "/")
            return true
        // A bare word. No slashes, so it can never be a path, and nothing a
        // shell would treat specially.
        return /^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/.test(value)
    }

    // Keeps only follow-up probes that read a validated /proc or /sys path.
    function acceptProbes(list) {
        if (!Array.isArray(list))
            return []
        var accepted = []
        for (var index = 0; index < list.length; index += 1) {
            var probe = list[index]
            if (probe === null || probe === undefined)
                continue
            var argv = probe.argv
            if (!root.validArgv(argv))
                continue
            var target = argv[argv.length - 1]
            if (!root.validReadPath(target))
                continue
            accepted.push({
                "label": String(probe.label || ""),
                "argv": [argv[0], target]
            })
        }
        return accepted
    }


    function finishProbe(exitCode) {
        root.collected[root.currentLabel] = {
            "code": exitCode,
            "text": root.lines.join("\n"),
            "error": root.errors.join("\n")
        }
        root.lines = []
        root.errors = []
        root.runNext()
    }

    // Text of one completed probe, or an empty string when it did not run.
    function probeText(results, label) {
        if (results === null || results === undefined)
            return ""
        var entry = results[label]
        if (entry === undefined || entry === null)
            return ""
        return String(entry.text || "")
    }

    // True when the named probe ran and exited cleanly.
    function probeSucceeded(results, label) {
        if (results === null || results === undefined)
            return false
        var entry = results[label]
        if (entry === undefined || entry === null)
            return false
        return Number(entry.code) === 0 && String(entry.error || "") === ""
    }

    // The reason a probe did not produce a reading, for the unavailable state.
    function probeFailure(results, label) {
        if (results === null || results === undefined)
            return "no result"
        var entry = results[label]
        if (entry === undefined || entry === null)
            return "did not run"
        if (String(entry.error || "") !== "")
            return "reported an error"
        if (Number(entry.code) !== 0)
            return "exited with status " + Number(entry.code)
        return "produced no reading"
    }

    // Subclasses override this to turn probe output into fields.
    function ingest(_results) {
        root.publishUnavailable("Source did not implement ingest")
    }

    function publish(fields) {
        root.sampleCount += 1
        root.snapshot = Object.assign({
            "available": true,
            "detail": "",
            "updatedMs": Date.now()
        }, fields === undefined || fields === null ? ({}) : fields)
    }

    function publishUnavailable(detail) {
        root.sampleCount += 1
        root.snapshot = {
            "available": false,
            "detail": String(detail === undefined || detail === null ? "" : detail),
            "updatedMs": Date.now()
        }
    }

    function log(message) {
        console.log("xeneon-home[" + root.sourceId() + "] " + String(message)
        )
    }
}