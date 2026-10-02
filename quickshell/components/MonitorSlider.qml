pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var theme
    property real value: 0
    property real maximum: 100
    property bool dragging: false
    signal edited(int value)
    signal released(int value)
    implicitHeight: 48
    readonly property real fraction: maximum > 0 ? Math.max(0, Math.min(1, value / maximum)) : 0
    function valueAt(x) {
        return Math.round(Math.max(0, Math.min(1, (x - 14) / Math.max(1, width - 28))) * maximum)
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 14
        width: parent.width - 28
        height: 8
        radius: 4
        color: root.theme.borderStrong
        Rectangle {
            width: parent.width * root.fraction
            height: parent.height
            radius: 4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.theme.accent }
                GradientStop { position: 1; color: root.theme.magenta }
            }
        }
    }
    Rectangle {
        x: 14 + (parent.width - 28) * root.fraction - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 14
        color: root.theme.textPrimary
        border.width: root.dragging ? 4 : 2
        border.color: root.dragging ? root.theme.magenta : root.theme.accent
    }
    MouseArea {
        objectName: "monitorSliderTouchArea"
        anchors.fill: parent
        enabled: root.enabled
        preventStealing: true
        onPressed: function(mouse) {
            root.dragging = true
            root.edited(root.valueAt(mouse.x))
        }
        onPositionChanged: function(mouse) {
            if (pressed) root.edited(root.valueAt(mouse.x))
        }
        onReleased: function(mouse) {
            root.dragging = false
            root.released(root.valueAt(mouse.x))
        }
        onCanceled: root.dragging = false
    }
}
