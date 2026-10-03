pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design
import "../state/SourceParse.js" as Parse
import "StatMeter.qml"

// The right-hand hardware block: one device heading per source, each with its
// load, temperature, and capacity meters.
//
// Every source keeps its heading even when it reports unavailable, so the
// block still names the machine's parts and says honestly that a reading is
// missing. A source that vanished from the layout would read as "not present",
// which is a different claim.
Item {
    id: root

    required property var theme
    required property var cpu
    required property var gpu
    required property var memory

    property bool reducedMotion: false

    GlassMaterial {
        anchors.fill: parent
        theme: root.theme
        elevation: 1
        corner: Design.radius.card
    }

    // The height each column actually has, and whether that is enough for a
    // full meter set. Decided from geometry, so the last row is always inside
    // the band on any surface height.
    readonly property int rowBudget: columns.height
    readonly property bool compact: rowBudget < 214
    readonly property int rowSpacing: compact ? 4 : 9

    Row {
        id: columns
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: root.compact ? 10 : Design.metrics.gutterCompact
        spacing: Design.metrics.columnGapCompact

        // CPU. The heading names the load and the package temperature; load is
        // a delta, so the first sample after start-up legitimately reads as
        // unavailable for one poll rather than as zero percent.
        Item {
            width: (columns.width - Design.metrics.columnGapCompact * 2) / 3
            height: columns.height

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: root.rowSpacing

                // The device this column measures, named once.
                Text {
                    width: parent.width
                    text: root.cpuLabel
                    color: String(root.theme.textSecondary)
                    font.family: Design.fontFamily
                    font.pixelSize: Design.type.subheadline.size
                    font.weight: Design.type.subheadline.weight
                    font.letterSpacing: Design.type.subheadline.tracking
                    elide: Text.ElideRight
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "load"
                    compact: root.compact
                    heading: "Load"
                    percent: root.cpu.loadPercent
                    // The load average is this meter's own subline. It is only
                    // shown once a real delta exists, so a first sample shows
                    // its real reason instead of a placeholder.
                    capacityDetail: root.cpuLoadAverageLabel
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "temperature"
                    compact: root.compact
                    heading: "Package"
                    celsius: root.cpu.celsius
                }
            }
        }

        // GPU. NVML is deliberately not used, so an NVIDIA-only host renders an
        // explicit unavailable reading instead of spawning a helper per sample.
        Item {
            width: (columns.width - Design.metrics.columnGapCompact * 2) / 3
            height: columns.height

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: root.rowSpacing

                Text {
                    width: parent.width
                    text: root.gpuLabel
                    color: String(root.theme.textSecondary)
                    font.family: Design.fontFamily
                    font.pixelSize: Design.type.subheadline.size
                    font.weight: Design.type.subheadline.weight
                    font.letterSpacing: Design.type.subheadline.tracking
                    elide: Text.ElideRight
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "load"
                    compact: root.compact
                    heading: "Load"
                    percent: root.gpu.busyPercent
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "temperature"
                    compact: root.compact
                    heading: "Core"
                    celsius: root.gpu.celsius
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "capacity"
                    compact: root.compact
                    heading: "Video"
                    percent: root.gpuVramPercent
                    capacityLabel: root.gpuVramUsedLabel
                    capacityDetail: root.gpuVramTotalLabel
                }
            }
        }

        // Memory. Capacity is rendered as used-of-total with the fraction as the
        // meter's level, which is how a capacity figure reads in system UI.
        Item {
            width: (columns.width - Design.metrics.columnGapCompact * 2) / 3
            height: columns.height

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: root.rowSpacing

                Text {
                    width: parent.width
                    text: root.memoryLabel
                    color: String(root.theme.textSecondary)
                    font.family: Design.fontFamily
                    font.pixelSize: Design.type.subheadline.size
                    font.weight: Design.type.subheadline.weight
                    font.letterSpacing: Design.type.subheadline.tracking
                    elide: Text.ElideRight
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "capacity"
                    compact: root.compact
                    heading: "In use"
                    percent: root.memory.percent
                    capacityLabel: root.memoryUsedLabel
                    capacityDetail: root.memoryTotalLabel
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "capacity"
                    compact: root.compact
                    heading: "Swap"
                    percent: root.swapPercent
                    capacityLabel: root.swapUsedLabel
                    capacityDetail: root.swapTotalLabel
                }
            }
        }
    }

    // Headings name what is actually installed. Each one prefers a real
    // published name and falls back to a raw device label only when the machine
    // publishes none; nothing is invented to fill the gap.
    readonly property string cpuLabel: root.cpu.modelLabel !== ""
        ? root.cpu.modelLabel
        : root.cpu.chip !== ""
            ? root.cpu.chip
            : "CPU"

    readonly property string gpuLabel: root.gpu.name !== ""
        ? root.gpu.name
        : root.gpu.chip !== ""
            ? root.gpu.chip
            : root.gpu.card !== ""
                ? root.gpu.card
                : "GPU"

    // D3: the memory heading must not repeat the capacity it sits above. The
    // installed capacity is already the value of the "In use" meter, so the
    // heading stays a neutral, honest label.
    readonly property string memoryLabel: "Memory"

    // The capacity reading. An unavailable memory source shows an em dash rather
    // than a fabricated total.
    readonly property string memoryUsedLabel: root.memory.available && root.memory.totalBytes > 0
        ? Parse.formatBytes(root.memory.usedBytes)
        : "—"

    readonly property string memoryTotalLabel: root.memory.available && root.memory.totalBytes > 0
        ? "of " + Parse.formatBytes(root.memory.totalBytes)
        : "unavailable"

    readonly property real swapPercent: root.memory.available && root.memory.snapshot.swapTotalBytes > 0
        ? root.memory.snapshot.swapUsedBytes * 100 / root.memory.snapshot.swapTotalBytes
        : -1

    readonly property string swapUsedLabel: root.swapPercent >= 0
        ? Parse.formatBytes(root.memory.snapshot.swapUsedBytes)
        : "—"

    readonly property string swapTotalLabel: root.swapPercent >= 0
        ? "of " + Parse.formatBytes(root.memory.snapshot.swapTotalBytes)
        : "unavailable"

    // The load average belongs to the load meter alone, formatted as
    // "1m 1.68". It appears only once a real delta exists, because before that
    // there is genuinely nothing to say.
    readonly property string cpuLoadAverageLabel: root.cpu.loadPercent >= 0
        && root.cpu.loadAverage !== ""
        ? "1m " + root.cpu.loadAverage.split(/\s+/)[0]
        : ""

    // Video memory gets its own meter rather than riding on the load meter's
    // subline, so every meter owns exactly one quantity.
    readonly property bool hasVram: root.gpu.hasVram

    readonly property real gpuVramPercent: root.gpu.hasVram
        ? Math.max(0, Math.min(100, root.gpu.vramUsedBytes * 100 / root.gpu.vramTotalBytes))
        : -1

    readonly property string gpuVramUsedLabel: root.gpu.hasVram
        ? Parse.formatBytes(root.gpu.vramUsedBytes)
        : "—"

    readonly property string gpuVramTotalLabel: root.gpu.hasVram
        ? "of " + Parse.formatBytes(root.gpu.vramTotalBytes)
        : "unavailable"
}