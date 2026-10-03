import QtQml
import "SourceParse.js" as Parse

// System memory from /proc/meminfo.
SourceBase {
    id: root

    // The uniform snapshot contract every source publishes, so the UI reads
    // one shape regardless of which tool backs it.
    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "memory"
    }

    function intervalMs() {
        return 5000
    }

    function probeList() {
        return [
            { "label": "meminfo", "argv": ["/usr/bin/cat", "/proc/meminfo"] }
        ]
    }

    readonly property real percent: snapshot.percent === null || snapshot.percent === undefined
        ? -1
        : snapshot.percent
    readonly property double usedBytes: snapshot.usedBytes || 0
    readonly property double totalBytes: snapshot.totalBytes || 0
    readonly property string usedLabel: Parse.formatBytes(snapshot.usedBytes)
    readonly property string totalLabel: Parse.formatBytes(snapshot.totalBytes)

    function ingest(results) {
        if (!root.probeSucceeded(results, "meminfo")) {
            root.publishUnavailable("/proc/meminfo is unreadable")
            return
        }

        var memory = Parse.parseMemInfo(root.probeText(results, "meminfo"))
        if (memory === null) {
            root.publishUnavailable("/proc/meminfo reported no MemTotal")
            return
        }

        root.publish({
            "percent": memory.percent,
            "usedBytes": memory.usedBytes,
            "totalBytes": memory.totalBytes,
            "swapTotalBytes": memory.swapTotalBytes,
            "swapUsedBytes": memory.swapUsedBytes
        })
    }
}