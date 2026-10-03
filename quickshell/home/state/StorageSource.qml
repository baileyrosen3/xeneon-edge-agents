import QtQml
import "SourceParse.js" as Parse

// Per-volume disk capacity, read with the same `df` invocation the current
// storage widget uses.
//
// Read-only in this surface: the folder ranking that widget offers is a `du`
// walk, which the parity plan keeps off the strip, so it is not implemented at
// all rather than implemented and hidden.
SourceBase {
    id: root

    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "storage"
    }

    function intervalMs() {
        return 60000
    }

    function probeList() {
        return [
            {
                "label": "df",
                "argv": [
                    "/usr/bin/df", "-P",
                    "-x", "tmpfs", "-x", "devtmpfs",
                    "-x", "efivarfs", "-x", "squashfs"
                ]
            }
        ]
    }

    readonly property var volumes: snapshot.volumes || []
    readonly property var worst: volumes.length > 0 ? volumes[0] : null
    readonly property real percent: worst === null ? -1 : worst.percent
    readonly property string severity: Parse.diskSeverity(percent)

    // A short label for the volume the user thinks of as "the disk": the root
    // mount when there is one, otherwise the fullest volume.
    readonly property string primaryLabel: primaryMount()

    function primaryMount() {
        for (var index = 0; index < root.volumes.length; index += 1) {
            if (root.volumes[index].mount === "/")
                return "/"
        }
        return root.worst === null ? "" : root.worst.mount
    }

    function ingest(results) {
        if (!root.probeSucceeded(results, "df")) {
            root.publishUnavailable("df did not report any filesystem")
            return
        }

        var volumes = Parse.parseDf(root.probeText(results, "df"))
        if (volumes === null || volumes.length === 0) {
            root.publishUnavailable("df reported no usable filesystem")
            return
        }

        root.publish({ "volumes": volumes })
    }
}
