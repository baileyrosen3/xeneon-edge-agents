pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var theme
    property real value: 0
    property real maximum: 100
    property string accessibleName: ""
    // Qt's Slider accessible value interface reads ordinary item properties.
    readonly property real minimumValue: 0
    readonly property real maximumValue: maximum
    readonly property real stepSize: 1
    property bool dragging: false
    signal edited(int value)
    signal released(int value)
    implicitHeight: 48
    readonly property real fraction: maximum > 0 ? Math.max(0, Math.min(1, value / maximum)) : 0
    activeFocusOnTab: enabled && visible
    Accessible.role: Accessible.Slider
    Accessible.name: accessibleName
    Accessible.description: "Raw units " + minimumValue + " through " + maximumValue + ". Arrow keys adjust by one; Home and End select the limits."
    Accessible.focusable: enabled && visible
    Accessible.focused: activeFocus
    Accessible.ignored: !visible
    Accessible.onIncreaseAction: root.adjust(root.value + root.stepSize)
    Accessible.onDecreaseAction: root.adjust(root.value - root.stepSize)
    function adjust(target) {
        if (!enabled || !visible || !Number.isFinite(maximum) || maximum <= 0)
            return;
        var next = Math.max(0, Math.min(Math.floor(maximum), Math.round(target)));
        if (next !== value)
            released(next);
    }
    Keys.onPressed: function(event) {
        if (!root.enabled || !root.visible)
            return;
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down: root.adjust(root.value - root.stepSize); break;
        case Qt.Key_Right:
        case Qt.Key_Up: root.adjust(root.value + root.stepSize); break;
        case Qt.Key_Home: root.adjust(root.minimumValue); break;
        case Qt.Key_End: root.adjust(root.maximumValue); break;
        default: return;
        }
        event.accepted = true;
    }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: 8
        border.width: root.activeFocus ? 3 : 0
        border.color: root.theme.accent
    }
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
            root.forceActiveFocus(Qt.MouseFocusReason)
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
