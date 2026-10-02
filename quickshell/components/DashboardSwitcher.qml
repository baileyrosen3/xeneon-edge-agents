pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    required property var theme
    property int currentIndex: 0
    property bool reducedMotion: false
    signal selected(int index)
    readonly property real travel: Math.max(1, track.width - thumb.width - 8)
    function select(index) {
        selected(index <= 0 ? 0 : 1);
    }
    implicitHeight: 64
    Rectangle {
        anchors.fill: parent
        color: root.theme.canvas
        Rectangle {
            width: parent.width
            height: 1
            color: root.theme.border
        }
    }
    Row {
        anchors.centerIn: parent
        spacing: 22
        DashboardButton {
            objectName: "dashboardOmarchyLabel"
            theme: root.theme
            width: 270
            label: "OMARCHY + AGENTS"
            selected: root.currentIndex === 0
            onClicked: root.select(0)
        }
        Rectangle {
            id: track
            objectName: "dashboardSlider"
            width: 420
            height: 48
            radius: 24
            color: root.theme.surfaceRaised
            border.width: 1
            border.color: root.theme.borderStrong
            Accessible.role: Accessible.Slider
            Accessible.name: "Dashboard switcher"
            Accessible.description: root.currentIndex === 0 ? "Omarchy and agents" : "Riptide trading"
            Accessible.onIncreaseAction: root.select(1)
            Accessible.onDecreaseAction: root.select(0)
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: function (eventPoint) {
                    root.select(eventPoint.position.x >= track.width / 2 ? 1 : 0);
                }
            }
            Rectangle {
                id: thumb
                objectName: "dashboardSliderThumb"
                width: 120
                height: 40
                y: 4
                x: 4 + root.currentIndex * root.travel
                radius: 20
                color: root.theme.accent
                Behavior on x {
                    enabled: !drag.active
                    NumberAnimation {
                        duration: root.reducedMotion ? 0 : 200
                        easing.type: Easing.OutCubic
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: "‹  •  ›"
                    textFormat: Text.PlainText
                    color: root.theme.canvas
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                DragHandler {
                    id: drag
                    target: thumb
                    xAxis.minimum: 4
                    xAxis.maximum: 4 + root.travel
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (!active) {
                            root.select(thumb.x >= 4 + root.travel / 2 ? 1 : 0);
                            thumb.x = Qt.binding(function () {
                                return 4 + root.currentIndex * root.travel;
                            });
                        }
                    }
                }
            }
        }
        DashboardButton {
            objectName: "dashboardRiptideLabel"
            theme: root.theme
            width: 270
            label: "RIPTIDE"
            selected: root.currentIndex === 1
            onClicked: root.select(1)
        }
    }
}
