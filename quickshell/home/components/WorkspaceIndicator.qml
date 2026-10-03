pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design

// The workspace indicator: one pill per workspace, the focused one filled.
//
// A tap dispatches the allowlisted `workspace.focus` action with a bounded
// integer id taken from the compositor's own snapshot. A workspace that
// Hyprland has not published is never drawn, and a snapshot that failed to
// read renders an explicit unavailable chip instead of an empty gap.
Item {
    id: root

    required property var theme
    required property var hyprland
    required property var dispatcher

    property bool reducedMotion: false

    readonly property bool available: hyprland.snapshot.available
    readonly property var workspaces: root.available ? root.hyprland.workspaces : []
    readonly property int focused: root.available ? root.hyprland.focusedWorkspace : -1

    // Bounded so a host with many dynamic workspaces cannot grow the strip
    // without limit.
    readonly property int maximumWorkspaces: 10
    readonly property var shown: root.workspaces.slice(0, root.maximumWorkspaces)

    readonly property int pillWidth: Design.compactHeight(root.height) ? 24 : 27
    readonly property real gap: 5

    implicitHeight: height
    implicitWidth: row.implicitWidth + 8
    height: 32

    Accessible.role: Accessible.StaticText
    Accessible.name: root.available
        ? root.shown.length + " workspaces, focused " + root.focused
        : "Workspaces unavailable"

    GlassMaterial {
        anchors.fill: parent
        theme: root.theme
        elevation: 0
        corner: Design.radius.pill
    }

    // An unavailable state names the reason. An empty pill would read as "this
    // host has no workspaces", which is a different and wrong claim.
    Text {
        anchors.centerIn: parent
        visible: !root.available
        text: "No workspaces"
        color: String(root.theme.textMuted)
        font.family: Design.fontFamily
        font.pixelSize: Design.type.caption.size
        font.weight: 500
        font.letterSpacing: 0.4
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.gap
        visible: root.available

        Repeater {
            model: root.shown

            delegate: Item {
                required property var modelData
                required property int index

                width: root.pillWidth
                height: root.pillWidth

                id: pill
                readonly property bool focused: modelData.id === root.focused

                // Dispatched by id, resolved through the allowlist against a
                // bounded integer taken from the compositor's own snapshot.
                function activate() {
                    root.dispatcher.dispatch("workspace.focus", Number(modelData.id))
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Workspace " + pill.modelData.id
                Accessible.onPressAction: pill.activate()

                MouseArea {
                    id: press
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onClicked: pill.activate()
                }

                HoverHandler {
                    id: hover
                }

                // The focused workspace is filled with the theme's text colour.
                // This is the same one-high-contrast-state language used by the
                // media transport, so the strip has a single emphasis idiom.
                Squircle {
                    anchors.fill: parent
                    corner: Design.radius.chip
                    fillColor: pill.focused
                        ? Qt.alpha(String(root.theme.textPrimary), 0.92)
                        : Qt.alpha(String(root.theme.textMuted), press.pressed ? 0.4 : hover.hovered ? 0.28 : 0.16)

                    Behavior on fillColor {
                        enabled: !root.reducedMotion
                        ColorAnimation {
                            duration: Design.motion.springDurationMs
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: String(pill.modelData.id)
                    color: pill.focused
                        ? String(root.theme.canvas)
                        : String(root.theme.textSecondary)
                    font.family: Design.fontFamily
                    font.pixelSize: Design.type.caption.size
                    font.weight: 600

                    Behavior on color {
                        enabled: !root.reducedMotion
                        ColorAnimation {
                            duration: Design.motion.springDurationMs
                        }
                    }
                }
            }
        }
    }

    function activate(workspaceId) {
        root.dispatcher.dispatch("workspace.focus", Number(workspaceId))
    }
}