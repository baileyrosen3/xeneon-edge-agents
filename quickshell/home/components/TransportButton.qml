pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design
import "../state/ThemePalette.js" as ThemePalette

// One media transport control.
//
// The button names an allowlisted action id, never a player method, and it
// enables only when the dispatcher and the active player both allow it. A
// disabled button is therefore a truthful "the player will not accept this"
// rather than a control that looks dead but still fires.
Item {
    id: root

    required property var theme
    required property var dispatcher

    property string actionId: ""
    property string glyph: ""
    property string label: ""
    property int size: 38
    property bool primary: false
    property bool reducedMotion: false

    // Set by the parent from the player's advertised capability.
    property bool controlEnabled: true

    readonly property color glyphColor: root.controlEnabled
        ? ThemePalette.ensureContrast(
            root.primary ? String(root.theme.canvas) : String(root.theme.textPrimary),
            root.primary ? String(root.theme.textPrimary) : String(root.theme.surface),
            4.5
        )
        : String(root.theme.textMuted)

    implicitWidth: size
    implicitHeight: size

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.controlEnabled ? "" : "Unavailable"
    Accessible.onPressAction: root.trigger()

    function trigger() {
        if (!root.controlEnabled)
            return
        root.dispatcher.dispatch(root.actionId)
    }

    MouseArea {
        id: press
        anchors.fill: parent
        enabled: root.controlEnabled
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.trigger()
    }

    HoverHandler {
        id: hover
        enabled: root.controlEnabled
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: press.pressed && root.controlEnabled ? 1.5 : 0

        Behavior on anchors.margins {
            enabled: !root.reducedMotion
            NumberAnimation {
                duration: Design.motion.springDurationMs
                easing.type: Easing.OutCubic
            }
        }

        GlassMaterial {
            anchors.fill: parent
            theme: root.theme
            elevation: root.primary ? 2 : 1
            corner: root.size / 2
            pressed: press.pressed && root.controlEnabled ? 1 : 0
        }

        // The primary control is filled with the theme's text colour, which is
        // the one high-contrast moment on the card and gives the transport a
        // clear focal point without inventing a saturated accent.
        Squircle {
            anchors.fill: parent
            corner: root.size / 2
            fillColor: Qt.alpha(String(root.theme.textPrimary), root.primary && root.controlEnabled ? 0.92 : 0)
            visible: root.primary
        }

        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: root.glyphColor
            font.family: Design.fontFamily
            font.pixelSize: root.primary ? Design.type.body.size : Design.type.subheadline.size
            font.weight: 600
        }
    }
}