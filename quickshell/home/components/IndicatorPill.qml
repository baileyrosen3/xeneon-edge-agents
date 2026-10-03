pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design

// A toggleable indicator pill: do-not-disturb, stay-awake, nightlight.
//
// The pill carries an allowlisted action id and dispatches it; it never names
// a command. An active pill is filled with the theme's text colour, which is
// the one high-contrast state on the strip and needs no invented accent hue.
Item {
    id: root

    required property var theme
    required property var dispatcher

    property string actionId: ""
    property string glyph: ""
    property string label: ""
    property string detail: ""

    // "active" | "idle" | "unavailable"
    property string pillState: "idle"

    property bool reducedMotion: false

    readonly property bool unavailable: state === "unavailable"
    readonly property bool active: state === "active"
    readonly property bool available: dispatcher.isAvailable(actionId)

    readonly property color glyphColor: root.unavailable || !root.available
        ? String(root.theme.textMuted)
        : root.active
            ? String(root.theme.canvas)
            : String(root.theme.textSecondary)

    readonly property bool hasContent: root.glyph !== ""

    implicitHeight: height
    implicitWidth: hasContent ? 34 : 0
    height: hasContent ? 32 : 0
    visible: hasContent

    Accessible.role: Accessible.Button
    Accessible.name: root.label
        + (root.unavailable ? ", unavailable" : root.active ? ", active" : ", inactive")
        + (root.detail === "" ? "" : ", " + root.detail)
    Accessible.description: root.available ? "" : "Not installed"
    Accessible.onPressAction: root.trigger()

    function trigger() {
        if (!root.available || root.unavailable)
            return
        root.dispatcher.dispatch(root.actionId)
    }

    MouseArea {
        id: press
        anchors.fill: parent
        enabled: root.available && !root.unavailable
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.trigger()
    }

    HoverHandler {
        id: hover
        enabled: root.available && !root.unavailable
    }

    GlassMaterial {
        anchors.fill: parent
        theme: root.theme
        elevation: 0
        corner: Design.radius.pill
        pressed: press.pressed ? 1 : 0
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.glyphColor
        font.family: Design.fontFamily
        font.pixelSize: Design.type.body.size
        font.weight: 600
    }
}