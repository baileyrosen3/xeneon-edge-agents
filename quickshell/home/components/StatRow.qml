import QtQuick
import "Design.js" as Design
import "../state/ThemePalette.js" as ThemePalette

// One measurement: a small filled label pill on the left, and the value
// right-aligned in a lighter pill.
//
// Only these two elements carry material. The value pill has its own backing
// because small text sits directly on an arbitrary photograph; the region
// around it deliberately has none.
Item {
    id: root

    required property var theme
    property string label: ""
    property string value: "—"

    // "ok" | "warn" | "crit" | "unknown"
    property string level: "unknown"

    implicitHeight: pillHeight
    implicitWidth: parent ? parent.width : 200

    readonly property int pillHeight: Design.type.caption.size + 12

    readonly property bool hasReading: level !== "unknown"

    readonly property color levelColor: root.hasReading
        ? (root.level === "crit" ? String(root.theme.error)
            : root.level === "warn" ? String(root.theme.needsHelp)
                : String(root.theme.success))
        : String(root.theme.textMuted)

    // The label pill is filled with the severity role at low alpha; the value
    // pill is a separate, slightly stronger backing so the number always reads.
    Rectangle {
        id: labelPill
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: labelText.implicitWidth + 14
        height: root.pillHeight
        radius: height / 2
        color: Qt.alpha(root.levelColor, root.hasReading ? 0.22 : 0.10)

        Text {
            id: labelText
            anchors.centerIn: parent
            text: root.label
            color: ThemePalette.ensureContrast(
                root.levelColor, String(root.theme.canvas), 4.5)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.caption.size
            font.weight: 700
            font.letterSpacing: 0.6
        }
    }

    Rectangle {
        anchors.left: labelPill.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.pillHeight
        radius: height / 2
        // The value's own backing. Low-alpha surface plus a hairline, so the
        // number stays readable over a bright photograph without the region
        // acquiring a visible panel.
        color: Qt.alpha(
            root.light ? "#000000" : String(root.theme.canvas), 0.42)
        border.color: Qt.alpha(String(root.theme.border), 0.5)
        border.width: 1

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            text: root.value
            color: root.hasReading
                ? ThemePalette.ensureContrast(
                    String(root.theme.textPrimary), String(root.theme.canvas), 7)
                : String(root.theme.textMuted)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.metricSmall.size
            font.weight: 600
            font.letterSpacing: Design.type.metricSmall.tracking
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    readonly property bool light: String(root.theme.mode) === "light"
}
