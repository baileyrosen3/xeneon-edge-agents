import QtQml
import "SourceParse.js" as Parse

// CPU load from /proc/stat and the package temperature from hwmon, read the
// way the Omarchy system monitor reads them: `sensors -j` is the hwmon
// publisher on this host and reports k10temp, coretemp, or zenpower depending
// on vendor, so the chip name is selected from a list rather than assumed.
//
// Load is a delta, so the first sample legitimately publishes no percentage
// and the snapshot says so rather than rendering a fabricated zero.
SourceBase {
    id: root

    // The uniform snapshot contract every source publishes, so the UI reads
    // one shape regardless of which tool backs it.
    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "cpu"
    }

    function intervalMs() {
        return 2000
    }

    function probeList() {
        return [
            { "label": "stat", "argv": ["/usr/bin/cat", "/proc/stat"] },
        { "label": "cpuinfo", "argv": ["/usr/bin/cat", "/proc/cpuinfo"] },
            { "label": "loadavg", "argv": ["/usr/bin/cat", "/proc/loadavg"] },
            { "label": "hwmon", "argv": ["/usr/bin/sensors", "-j"] }
        ]
    }

    property var previousStat: null

    readonly property real loadPercent: snapshot.available === true
        ? (snapshot.loadPercent === null ? -1 : snapshot.loadPercent)
        : -1
    readonly property real celsius: snapshot.available === true
        && snapshot.celsius !== null && snapshot.celsius !== undefined
        ? snapshot.celsius
        : -1
    readonly property string loadAverage: snapshot.loadAverage || ""
    readonly property string chip: snapshot.chip || ""

    // The marketing name the machine actually publishes, e.g.
    // "AMD Ryzen AI 9 HX 370". Long on a narrow column, so a short form is
    // derived below; when the CPU publishes no name at all this is empty and
    // the stack falls back to the hwmon chip label.
    readonly property string model: snapshot.model || ""

    // A short heading derived from the real model name: the series and model
    // tokens, dropping the vendor prefix and any integrated-GPU suffix. A name
    // that cannot be shortened is returned unchanged rather than invented.
    readonly property string modelLabel: shortModel(model)

    function shortModel(name) {
        var text = String(name === null || name === undefined ? "" : name).trim()
        if (text === "")
            return ""
        var withoutMaker = text.replace(/^(AMD|Intel|Apple|NVIDIA|Qualcomm)\s+/i, "")
        var withoutGraphics = withoutMaker.replace(/\s+w\/\s+.*$/i, "")
        var withoutClock = withoutGraphics.replace(/\s+@.*$/i, "")
        var words = withoutClock.split(/\s+/)
        if (words.length <= 3)
            return words.join(" ")
        return words.slice(0, 3).join(" ")
    }
    readonly property int coreCount: snapshot.cores ? snapshot.cores.length : 0

    function ingest(results) {
        var cores = null
        var loadPercent = null
        var coreReads = []

        if (root.probeSucceeded(results, "stat")) {
            var stat = Parse.parseProcStat(
                root.probeText(results, "stat"),
                root.previousStat
            )
            if (stat !== null && Object.keys(stat.snapshot).length > 0) {
                root.previousStat = stat.snapshot
                loadPercent = stat.overall
                for (var index = 0; index < stat.cores.length; index += 1) {
                    var core = stat.cores[index]
                    if (core.percent !== null)
                        coreReads.push(core.percent)
                }
                cores = coreReads
            }
        }

        var loadAverage = ""
        if (root.probeSucceeded(results, "loadavg"))
            loadAverage = String(root.probeText(results, "loadavg")).trim().split(/\s+/).slice(0, 3).join(" ")

        var model = ""
        if (root.probeSucceeded(results, "cpuinfo"))
            model = Parse.parseCpuModel(root.probeText(results, "cpuinfo"))

        var celsius = null
        var chip = ""
        if (root.probeSucceeded(results, "hwmon")) {
            var temperature = Parse.parseHwmon(
                root.probeText(results, "hwmon"),
                Parse.cpuChips
            )
            if (temperature !== null) {
                celsius = temperature.celsius
                chip = temperature.chip
            }
        }

        if (loadPercent === null && celsius === null) {
            root.publishUnavailable("No CPU load or temperature reading is available")
            return
        }

        root.publish({
            "loadPercent": loadPercent,
            "coreLoads": cores,
            "loadAverage": loadAverage,
            "celsius": celsius,
            "chip": chip,
            "model": model
        })
    }
}