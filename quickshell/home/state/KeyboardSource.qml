import QtQml
import "SourceParse.js" as Parse

// Keyboard layout, read from the same command the packaged bar widget uses.
//
// A physical keyboard is a device whose name contains characters such as `[`,
// `]` and spaces, so the device name is never accepted from QML: the cycle
// action resolves against the names this source last published.
SourceBase {
    id: root

    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "keyboard"
    }

    function intervalMs() {
        return 4000
    }

    function probeList() {
        return [
            { "label": "devices", "argv": ["/usr/bin/hyprctl", "-j", "devices"] }
        ]
    }

    // The device the user actually types on: the first keyboard that declares
    // more than one layout, or otherwise the first non-virtual keyboard.
    readonly property var device: snapshot.activeDevice
        ? snapshot.activeDevice
        : null

    readonly property string deviceName: device === null ? "" : String(device.name || "")
    readonly property string layoutLabel: device === null ? "" : String(device.activeKeymap || device.layout || "")

    // More than one layout is what makes the pill worth showing. With a single
    // layout there is nothing to cycle and nothing to say, so it is not rendered
    // at all. This is the same conditional-visibility rule the current widget
    // applies.
    readonly property int layoutCount: snapshot.layoutCount || 0
    readonly property bool multipleLayouts: layoutCount > 1

    // The exact device names published by the last read. A cycle action naming
    // anything else is refused.
    readonly property var deviceNames: snapshot.deviceNames || []

    function ingest(results) {
        if (!root.probeSucceeded(results, "devices")) {
            root.publishUnavailable("hyprctl did not report devices")
            return
        }

        var parsed = Parse.parseKeyboards(root.probeText(results, "devices"))
        if (parsed === null) {
            root.publishUnavailable("hyprctl devices could not be parsed")
            return
        }

        var names = []
        for (var index = 0; index < parsed.length; index += 1)
            names.push(parsed[index].name)

        var best = null
        for (var pick = 0; pick < parsed.length; pick += 1) {
            if (parsed[pick].layoutCount > 1) {
                best = parsed[pick]
                break
            }
            if (best === null && !parsed[pick].virtual)
                best = parsed[pick]
        }

        var widest = 0
        for (var count = 0; count < parsed.length; count += 1) {
            if (parsed[count].layoutCount > widest)
                widest = parsed[count].layoutCount
        }

        root.publish({
            "activeDevice": best,
            "deviceNames": names,
            "layoutCount": widest
        })
    }
}
