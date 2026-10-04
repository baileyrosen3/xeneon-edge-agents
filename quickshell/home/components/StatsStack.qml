import QtQuick
import "."
import "Design.js" as Design
import "../state/SourceParse.js" as Parse
import "../state/ThemePalette.js" as ThemePalette

// The hardware block: one row group per device.
//
// The reference lays these out as stacked rows rather than columns of meters,
// with the measurement label in a small filled pill and the value right-aligned
// in a lighter one, coloured by severity. That is what this renders.
//
// There is no card behind the group. Only the individual pills carry material,
// because the wallpaper is the surface.
Item {
    id: root

    required property var theme
    required property var cpu
    required property var gpu
    required property var memory

    property bool reducedMotion: false

    readonly property bool light: String(theme.mode) === "light"
    // At the live 270px height the three device groups plus the memory capacity
    // bar do not fit, so the least load-bearing measurement is dropped rather
    // than letting the last row be clipped.
    readonly property bool compact: height < 200
    readonly property bool veryCompact: height < 240
    readonly property int rowSpacing: compact ? 4 : 9
    readonly property int groupSpacing: compact ? 7 : 13

    // Severity is carried by the theme's own semantic roles, never by a literal.
    // On the monochrome vantablack theme those roles are greys, so the ramp
    // reads as weight and brightness rather than as hue — which is the correct
    // behaviour for a theme that publishes no colour.
    function severityColor(level) {
        if (level === "crit")
            return String(theme.error)
        if (level === "warn")
            return String(theme.needsHelp)
        return String(theme.success)
    }

    readonly property color pillText: ThemePalette.ensureContrast(
        String(theme.textPrimary), String(theme.canvas), 7)

    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        width: Math.min(parent.width, 380)
        spacing: root.groupSpacing

        // ---- CPU
        Column {
            width: parent.width
            spacing: 2

            DeviceHeading { width: parent.width; theme: root.theme; caption: root.cpuLabel }

            StatRow {
                width: parent.width
                theme: root.theme
                label: "Load"
                value: root.cpuLabelPercent
                level: root.cpuLevel
            }
            StatRow {
                width: parent.width
                theme: root.theme
                visible: !root.veryCompact
                label: "Pkg"
                value: root.cpuTempLabel
                level: root.cpuTempLevel
            }
        }

        // ---- GPU
        Column {
            width: parent.width
            spacing: 2

            DeviceHeading { width: parent.width; theme: root.theme; caption: root.gpuLabel }

            StatRow {
                width: parent.width
                theme: root.theme
                label: "Load"
                value: root.gpuLabelPercent
                level: root.gpuLevel
            }
            StatRow {
                width: parent.width
                theme: root.theme
                label: "Temp"
                value: root.gpuTempLabel
                level: root.gpuTempLevel
            }
            StatRow {
                width: parent.width
                theme: root.theme
                visible: !root.veryCompact
                label: "VRAM"
                value: root.gpuVramLabel
                level: root.gpuVramLevel
            }
        }

        // ---- Memory
        Column {
            width: parent.width
            spacing: 2

            DeviceHeading { width: parent.width; theme: root.theme; caption: root.memoryLabel }

            StatRow {
                width: parent.width
                theme: root.theme
                label: "RAM"
                value: root.memoryUsedLabel
                level: root.memoryLevel
            }

            // A thin capacity bar, then the used/total right-aligned beneath it.
            Rectangle {
                width: parent.width
                height: 3
                radius: 1.5
                color: Qt.alpha(String(root.theme.textMuted), 0.32)

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    width: root.memoryPercent >= 0
                        ? Math.max(0, Math.min(parent.width, parent.width * root.memoryPercent / 100))
                        : 0
                    radius: 1.5
                    color: root.severityColor(root.memoryLevel)
                }
            }

            Text {
                width: parent.width
                text: root.memoryTotalLabel
                color: String(root.theme.textSecondary)
                font.family: Design.fontFamily
                font.pixelSize: Design.type.caption.size
                font.weight: 400
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    readonly property string cpuLabel: root.cpu.modelLabel !== ""
        ? root.cpu.modelLabel
        : root.cpu.chip !== "" ? root.cpu.chip : "CPU"
    readonly property string gpuLabel: root.gpu.name !== ""
        ? root.gpu.name
        : root.gpu.chip !== "" ? root.gpu.chip
            : root.gpu.card !== "" ? root.gpu.card : "GPU"
    readonly property string memoryLabel: "Memory"

    readonly property string cpuLabelPercent: root.cpu.loadPercent >= 0
        ? Math.round(root.cpu.loadPercent) + "%" : "—"
    readonly property string cpuTempLabel: root.cpu.celsius >= 0
        ? Math.round(root.cpu.celsius) + "°" : "—"
    readonly property string cpuLevel: root.cpu.loadPercent >= 0
        ? severityFor(root.cpu.loadPercent) : "unknown"

    readonly property real cpuTempLevel: root.cpu.celsius >= 0
        ? severityFor(root.cpu.celsius, 100) : -1
    readonly property string cpuTempSeverity: root.cpu.celsius >= 0
        ? severityFor(root.cpu.celsius, 100) : "unknown"

    readonly property string gpuLabelPercent: root.gpu.busyPercent >= 0
        ? Math.round(root.gpu.busyPercent) + "%" : "—"
    readonly property string gpuTempLabel: root.gpu.celsius >= 0
        ? Math.round(root.gpu.celsius) + "°" : "—"
    readonly property string gpuVramLabel: root.gpu.hasVram
        ? Parse.formatBytes(root.gpu.vramUsedBytes) : "—"

    readonly property string gpuLevel: root.gpu.busyPercent >= 0
        ? severityFor(root.gpu.busyPercent) : "unknown"
    readonly property string gpuTempLevel: root.gpu.celsius >= 0
        ? severityFor(root.gpu.celsius, 100) : "unknown"
    readonly property string gpuVramLevel: root.gpu.hasVram
        ? severityFor(root.gpuVramPercent, 100) : "unknown"

    readonly property real gpuVramPercent: root.gpu.hasVram
        ? Math.max(0, Math.min(100, root.gpu.vramUsedBytes * 100 / root.gpu.vramTotalBytes))
        : -1

    readonly property string memoryUsedLabel: root.memory.available && root.memory.totalBytes > 0
        ? Parse.formatBytes(root.memory.usedBytes) : "—"
    readonly property string memoryTotalLabel: root.memory.available && root.memory.totalBytes > 0
        ? Parse.formatBytes(root.memory.usedBytes) + " / "
            + Parse.formatBytes(root.memory.totalBytes) : "unavailable"
    readonly property real memoryPercent: root.memory.percent
    readonly property string memoryLevel: root.memory.percent >= 0
        ? severityFor(root.memory.percent) : "unknown"

    // ok below 70, warn to 88, crit above. Mirrors the ramp the current widget
    // uses, derived from the measurement rather than from a printed string.
    function severityFor(percent, scale) {
        var value = Number(percent)
        if (!isFinite(value) || value < 0)
            return "unknown"
        var ceiling = scale === undefined ? 100 : scale
        var fraction = Math.max(0, Math.min(1, value / ceiling))
        if (fraction >= 0.9)
            return "crit"
        if (fraction >= 0.7)
            return "warn"
        return "ok"
    }
}
