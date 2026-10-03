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

    Row {
        id: columns
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Design.metrics.gutterCompact
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
                spacing: 9

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "load"
                    heading: root.cpuLabel
                    percent: root.cpu.loadPercent
                    detail: root.cpuDetail
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "temperature"
                    heading: "Package"
                    celsius: root.cpu.celsius
                    detail: root.cpu.available ? root.cpu.loadAverage : root.cpu.snapshot.detail
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
                spacing: 9

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "load"
                    heading: root.gpuLabel
                    percent: root.gpu.busyPercent
                    detail: root.gpuDetail
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "temperature"
                    heading: "Core"
                    celsius: root.gpu.celsius
                    detail: root.gpuDetail
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
                spacing: 9

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "capacity"
                    heading: root.memoryLabel
                    percent: root.memory.percent
                    capacityLabel: root.memoryUsedLabel
                    capacityDetail: root.memoryTotalLabel
                    detail: root.memory.snapshot.detail
                }

                StatMeter {
                    width: parent.width
                    theme: root.theme
                    reducedMotion: root.reducedMotion
                    kind: "capacity"
                    heading: "Swap"
                    percent: root.swapPercent
                    capacityLabel: root.swapUsedLabel
                    capacityDetail: root.swapTotalLabel
                    detail: root.memory.snapshot.available
                        && root.memory.snapshot.swapTotalBytes > 0
                        ? ""
                        : root.memory.snapshot.detail
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

    // The memory heading carries the installed capacity, which is the number a
    // user actually recognises.
    readonly property string memoryLabel: root.memory.available && root.memory.totalBytes > 0
        ? Parse.formatBytes(root.memory.totalBytes)
        : "Memory"

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

    readonly property string cpuDetail: root.cpu.available
        ? "load " + root.cpu.loadAverage
        : root.cpu.snapshot.detail

    readonly property string gpuDetail: root.gpu.snapshot.available === true && root.gpu.hasVram
        ? root.gpu.vramLabel
        : root.gpu.snapshot.detail
}