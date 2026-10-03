pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root
    required property var theme
    property string label: ""
    property string detail: ""
    property int labelPixelSize: 17
    property int detailPixelSize: 12
    property bool keyboardPressed: false
    property color accent: theme.accent
    property bool selected: false
    property bool destructive: false
    signal clicked
    implicitWidth: 140
    implicitHeight: 48
    radius: 12
    color: tap.pressed || keyboardPressed ? theme.surfacePressed : selected ? Qt.alpha(accent, 0.20) : theme.surfaceRaised
    border.width: activeFocus ? 3 : 1
    border.color: activeFocus || selected ? accent : theme.border
    opacity: enabled ? 1 : 0.42
    // Keep a focused item in the tab chain while it loses usability so Qt does
    // not reject the focus-order change on the item that currently holds focus.
    activeFocusOnTab: activeFocus || (enabled && visible)
    onActiveFocusChanged: { if (!activeFocus) keyboardPressed = false; }
    onEnabledChanged: { if (!enabled) keyboardPressed = false; }
    onVisibleChanged: { if (!visible) keyboardPressed = false; }
    function activate() {
        // Modality is expressed by enabled, so an obscured button can never
        // activate. Visibility stays in the focus chain and key routing.
        if (!enabled)
            return false;
        forceActiveFocus(Qt.OtherFocusReason);
        clicked();
        return true;
    }
    // Forwarded scope keys run first. A handled sidebar key never activates here.
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (!root.enabled || !root.visible || event.accepted)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true;
            if (!event.isAutoRepeat && !root.keyboardPressed) {
                root.keyboardPressed = true;
                root.activate();
            }
        }
    }
    Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (!event.isAutoRepeat)
                root.keyboardPressed = false;
            event.accepted = true;
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: detail
    Accessible.focusable: enabled && visible
    Accessible.focused: activeFocus
    Accessible.pressed: tap.pressed || keyboardPressed
    Accessible.ignored: !visible
    Accessible.onPressAction: root.activate()
    Column {
        anchors.centerIn: parent
        width: parent.width - 16
        spacing: 2
        Text {
            width: parent.width
            text: root.label
            textFormat: Text.PlainText
            color: root.destructive ? root.theme.error : root.selected ? root.accent : root.theme.textPrimary
            font.family: "monospace"
            font.pixelSize: root.labelPixelSize
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.detail !== ""
            text: root.detail
            textFormat: Text.PlainText
            color: root.theme.textMuted
            font.pixelSize: root.detailPixelSize
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
    TapHandler {
        id: tap
        enabled: root.enabled
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.activate()
    }
}
