import QtQml
import "SourceParse.js" as Parse

// GPU load, temperature, and video memory from sysfs, read exactly as the
// Omarchy system monitor reads them. There is deliberately no NVML path here:
// NVIDIA's proprietary driver publishes nothing readable through sysfs, so an
// NVIDIA-only host reports unavailable instead of spawning nvidia-smi.
//
// Cards are ranked so a card publishing a utilisation counter wins outright,
// then larger video memory breaks the tie. That keeps a discrete adapter on a
// hybrid machine without hardcoding a device id.
SourceBase {
    id: root

    // The uniform snapshot contract every source publishes, so the UI reads
    // one shape regardless of which tool backs it.
    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "gpu"
    }

    function intervalMs() {
        return 3000
    }

    readonly property string drmRoot: "/sys/class/drm"

    function probeList() {
        return [
            { "label": "cards", "argv": ["/usr/bin/ls", drmRoot] },
            { "label": "hwmon", "argv": ["/usr/bin/sensors", "-j"] },
            // The PCI id database is the only place on this class of machine
            // where a real GPU marketing name exists; sysfs publishes ids only.
            { "label": "pciids", "argv": ["/usr/bin/cat", "/usr/share/hwdata/pci.ids"] }
        ]
    }

    readonly property real busyPercent: numberOrMissing(snapshot.busyPercent)
    readonly property real celsius: numberOrMissing(snapshot.celsius)
    readonly property double vramUsedBytes: snapshot.vramUsedBytes || 0
    readonly property double vramTotalBytes: snapshot.vramTotalBytes || 0
    readonly property bool hasVram: vramUsedBytes > 0 && vramTotalBytes > 0
    readonly property string card: snapshot.card || ""
    readonly property string chip: snapshot.chip || ""

    // The heading. A marketing name is only used when the machine actually
    // publishes one; otherwise this falls back to the driver name plus the PCI
    // device id, which is the identity sysfs really does expose. A raw "card1"
    // is never presented as a model.
    readonly property string name: snapshot.name || ""
    readonly property string driver: snapshot.driver || ""
    readonly property string vramLabel: hasVram
        ? Parse.formatBytes(vramUsedBytes) + " / " + Parse.formatBytes(vramTotalBytes)
        : ""

    function numberOrMissing(value) {
        if (value === null || value === undefined)
            return -1
        var number = Number(value)
        return Number.isFinite(number) ? number : -1
    }

    // Card directories under /sys/class/drm, reduced to `cardN`.
    function cardDirectories(text) {
        var lines = String(text || "").split("\n")
        var cards = []
        for (var index = 0; index < lines.length; index += 1) {
            var name = lines[index].trim()
            if (/^card[0-9]+$/.test(name))
                cards.push(name)
        }
        cards.sort()
        return cards
    }

    // Reads the driver's own directory name from
    // /sys/class/drm/cardN/device/driver, which is a symlink whose basename is
    // the module in use.
    function followUpProbes(results) {
        if (!root.probeSucceeded(results, "cards"))
            return []

        var cards = root.cardDirectories(root.probeText(results, "cards"))
        var probes = []
        for (var index = 0; index < cards.length; index += 1) {
            var device = root.drmRoot + "/" + cards[index] + "/device"
            probes.push({ "label": "entries:" + cards[index], "argv": ["/usr/bin/ls", device] })
            probes.push({ "label": "vendor:" + cards[index], "argv": ["/usr/bin/cat", device + "/vendor"] })
            probes.push({ "label": "deviceid:" + cards[index], "argv": ["/usr/bin/cat", device + "/device"] })
            probes.push({ "label": "busy:" + cards[index], "argv": ["/usr/bin/cat", device + "/gpu_busy_percent"] })
            probes.push({ "label": "vram_used:" + cards[index], "argv": ["/usr/bin/cat", device + "/mem_info_vram_used"] })
            probes.push({ "label": "vram_total:" + cards[index], "argv": ["/usr/bin/cat", device + "/mem_info_vram_total"] })
        }
        return probes
    }

    function ingest(results) {
        if (!root.probeSucceeded(results, "cards")) {
            root.publishUnavailable("No DRM card directory is readable")
            return
        }

        var cards = root.cardDirectories(root.probeText(results, "cards"))
        var best = null
        var cardName = ""
        for (var index = 0; index < cards.length; index += 1) {
            var card = cards[index]
            var candidate = Parse.parseGpuSysfs({
                "card": card,
                "busyPercent": probeNumber(results, "busy:" + card),
                "vramUsedBytes": probeNumber(results, "vram_used:" + card),
                "vramTotalBytes": probeNumber(results, "vram_total:" + card),
                "driver": ""
            })
            if (candidate.busyPercent === null && candidate.vramTotalBytes === null)
                continue
            if (Parse.betterGpu(candidate, best)) {
                best = candidate
                cardName = card
            }
        }

        var temperature = null
        var chip = ""
        if (root.probeSucceeded(results, "hwmon")) {
            var reading = Parse.parseHwmon(root.probeText(results, "hwmon"), Parse.gpuChips)
            if (reading !== null) {
                temperature = reading.celsius
                chip = reading.chip
            }
        }

        if (best === null && temperature === null) {
            root.publishUnavailable("No supported GPU exposes load, memory, or temperature in sysfs")
            return
        }

        // The heading prefers a real marketing name resolved from the pci.ids
        // database, then the hwmon driver name, then the drm card name. It
        // never invents one, and it never presents a raw card index while a
        // resolvable identity exists.
        var heading = ""
        var vendorName = ""
        var modelName = ""
        if (best !== null) {
            var identity = Parse.parsePciIds(
                root.probeSucceeded(results, "pciids")
                    ? root.probeText(results, "pciids")
                    : "",
                root.probeText(results, "vendor:" + best.card),
                root.probeText(results, "deviceid:" + best.card)
            )
            if (identity !== null) {
                modelName = identity.short
                vendorName = identity.vendorName
                heading = modelName
            }
        }

        if (heading === "" && chip !== "")
            heading = chip
        if (heading === "" && best !== null)
            heading = best.card.toUpperCase()

        root.publish({
            "card": best === null ? "" : best.card,
            "driver": chip,
            "name": heading,
            "vendor": vendorName,
            "model": modelName,
            "chip": chip,
            "busyPercent": best === null ? null : best.busyPercent,
            "vramUsedBytes": best === null ? null : best.vramUsedBytes,
            "vramTotalBytes": best === null ? null : best.vramTotalBytes,
            "celsius": temperature === null ? null : temperature
        })
    }

    // A sysfs reading is one bare integer. Anything else is no reading at all.
    function probeNumber(results, label) {
        if (!root.probeSucceeded(results, label))
            return null
        var text = root.probeText(results, label).trim()
        if (!/^-?[0-9]+$/.test(text))
            return null
        return Number(text)
    }
}