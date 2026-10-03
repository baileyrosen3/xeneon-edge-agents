pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design

// A read-only status chip: one glyph, one value, and an explicit unavailable
// state.
//
// A pill never invents a value. If its source reports unavailable, the pill
// renders an em dash, dims to the muted role, and carries the source's reason
// in its accessible name. A pill with no glyph still reserves its width so the
// strip's rhythm does not jump as sources come and go.
Item {
    id: root

    required property var theme

    property string glyph: ""
    property string label: ""
    property string value: "—"
    property string detail: ""

    // "active" | "idle" | "unavailable"
    property string pillState: "idle"

    property bool reducedMotion: false

    readonly property bool unavailable: state === "unavailable"
    readonly property bool active: state === "active"

    // An unavailable pill is dimmer and loses its glyph emphasis. In a
    // monochrome theme this is the only honest visual difference available,
    // and it is enough.
    readonly property color glyphColor: root.unavailable
        ? String(root.theme.textMuted)
        : root.active
            ? String(root.theme.textPrimary)
            : String(root.theme.textSecondary)

    readonly property color valueColor: root.unavailable
        ? String(root.theme.textMuted)
        : String(root.theme.textPrimary)

    // A pill with neither a glyph nor a value has nothing to say, so it takes
    // no space at all. An empty chip reading as a blank control is worse than
    // no chip.
    readonly property bool hasContent: root.glyph !== "" || root.value !== ""

    implicitHeight: height
    implicitWidth: hasContent ? row.implicitWidth + Design.type.subheadline.size + 12 : 0
    height: hasContent ? 32 : 0
    visible: hasContent

    Accessible.role: Accessible.StaticText
    Accessible.name: root.label + ": " + root.value
        + (root.detail === "" ? "" : ", " + root.detail)

    GlassMaterial {
        anchors.fill: parent
        theme: root.theme
        elevation: 0
        corner: Design.radius.pill
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph !== ""
            text: root.glyph
            color: root.glyphColor
            font.family: Design.fontFamily
            font.pixelSize: Design.type.subheadline.size + 1
            font.weight: 600
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.value !== ""
            text: root.value
            color: root.valueColor
            font.family: Design.fontFamily
            font.pixelSize: Design.type.subheadline.size + 1
            font.weight: 600
            font.letterSpacing: 0.1
        }
    }
}