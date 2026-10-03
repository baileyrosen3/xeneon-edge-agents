pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design

// The volume pill: a mute glyph, a live level bar, and the percentage.
//
// Pressing the glyph mutes and un-mutes through an allowlisted action. The
// level bar is a capsule track whose fill is the real percentage; when the
// sink is muted the bar dims rather than reporting a level the user cannot
// hear, and when PulseAudio is absent the whole pill shows an em dash.
Item {
    id: root

    required property var theme
    required property var dispatcher

    required property var audio

    property bool reducedMotion: false

    readonly property bool available: audio.snapshot.available
    readonly property real percent: audio.percent
    readonly property bool muted: audio.muted

    implicitHeight: height
    implicitWidth: content.implicitWidth + 18
    height: 32

    Accessible.role: Accessible.Button
    Accessible.name: available
        ? (muted ? "Muted, " : "Volume ") + Math.round(Math.max(0, percent)) + " percent"
        : "Volume unavailable"
    Accessible.onPressAction: root.toggleMute()

    function toggleMute() {
        root.dispatcher.dispatch("audio.mute")
    }

    MouseArea {
        id: press
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.toggleMute()
    }

    HoverHandler {
        id: hover
    }

    GlassMaterial {
        anchors.fill: parent
        theme: root.theme
        elevation: 0
        corner: Design.radius.pill
        pressed: press.pressed ? 1 : 0
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !root.available
                ? "🔇"
                : root.muted || root.percent <= 0
                    ? "🔇"
                    : root.percent < 50
                        ? "🔉"
                        : "🔊"
            color: root.available
                ? String(root.theme.textSecondary)
                : String(root.theme.textMuted)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.subheadline.size + 1
            font.weight: 600
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.available ? Math.round(Math.max(0, root.percent)) + "" : "—"
            color: root.available
                ? String(root.theme.textPrimary)
                : String(root.theme.textMuted)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.subheadline.size + 1
            font.weight: 600
        }

        Squircle {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 4
            corner: 2
            fillColor: Qt.alpha(String(root.theme.textMuted), 0.3)
            visible: root.available

            Squircle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: root.muted
                    ? 0
                    : Math.max(parent.height, parent.width * Math.max(0, Math.min(1, root.percent / 100)))
                corner: 2
                fillColor: Qt.alpha(String(root.theme.textPrimary), 0.85)

                Behavior on width {
                    enabled: !root.reducedMotion
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}