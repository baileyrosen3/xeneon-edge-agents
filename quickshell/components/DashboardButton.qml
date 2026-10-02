pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root
    required property var theme
    property string label: ""
    property string detail: ""
    property color accent: theme.accent
    property bool selected: false
    property bool destructive: false
    signal clicked
    implicitWidth: 140
    implicitHeight: 48
    radius: 12
    color: tap.pressed ? theme.surfacePressed : selected ? Qt.alpha(accent, 0.20) : theme.surfaceRaised
    border.width: 1
    border.color: selected ? accent : theme.border
    opacity: enabled ? 1 : 0.42
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: detail
    Accessible.onPressAction: {
        if (root.enabled)
            root.clicked();
    }
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
            font.pixelSize: 17
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
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
    TapHandler {
        id: tap
        enabled: root.enabled
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.clicked()
    }
}
