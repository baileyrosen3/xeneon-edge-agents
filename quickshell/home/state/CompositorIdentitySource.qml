import QtQml
import "SourceParse.js" as Parse

// The serial the *compositor* reports for the configured output.
//
// Why this exists: Hyprland publishes no EDID serial to Qt, so
// `screen.serialNumber` is an empty string for every screen and a configured
// serial can never be contradicted from the screen list alone. Hyprland does
// report the real serial through its own IPC, and the packaged shell's
// deployment gate already trusts exactly that. This brings the same check into
// the surface, through the same bounded, validated probe machinery as every
// other source: a fixed argv, a timeout, and no shell string from QML.
//
// The verdict is three-valued, because "the serial differs" and "no serial is
// available anywhere" are different facts and must not be collapsed.
SourceBase {
    id: root

    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "compositorIdentity"
    }

    function intervalMs() {
        return 30000
    }

    function probeList() {
        return [
            { "label": "monitors", "argv": ["/usr/bin/hyprctl", "-j", "monitors"] }
        ]
    }

    // The output whose serial is being verified. Supplied from the configured
    // identity, never from anything a caller can reach.
    property string outputName: ""
    property string configuredSerial: ""

    readonly property string reportedSerial: available ? String(snapshot.reportedSerial || "") : ""

    // true = agrees, false = contradicts, null = nothing to verify against.
    readonly property var verdict: Parse.serialVerdict(
        snapshot.configuredSerial,
        snapshot.reportedSerial
    )

    readonly property bool verified: root.verdict === true
    readonly property bool contradicted: root.verdict === false
    readonly property bool unverifiable: root.verdict === null

    function configured() {
        return root.configuredSerial
    }

    function ingest(results) {
        if (!root.probeSucceeded(results, "monitors")) {
            root.publishUnavailable("the compositor did not report its monitors")
            return
        }

        var serial = Parse.parseMonitorSerial(
            root.probeText(results, "monitors"),
            root.outputName
        )

        // A configured serial that the compositor contradicts is a refusal, not
        // an unavailable reading: we have a real answer and it is "wrong".
        root.publish({
            "reportedSerial": serial === null ? "" : serial,
            "configuredSerial": root.configured()
        })
    }
}
