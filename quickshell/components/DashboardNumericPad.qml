pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    required property var theme
    property bool open: false
    property string title: "VALUE"
    property string value: ""
    property bool integerOnly: false
    property bool signed: false
    property string error: ""
    signal accepted(string value)
    signal cancelled
    visible: open
    z: 100
    function append(digit) {
        error = "";
        if (value.length >= 16)
            return;
        if (digit === "." && (integerOnly || value.indexOf(".") >= 0))
            return;
        value = value === "0" && digit !== "." ? digit : value + digit;
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(root.theme.canvas, 0.88)
        TapHandler {
            onTapped: root.cancelled()
        }
    }
    DashboardCard {
        anchors.centerIn: parent
        width: 520
        height: 580
        theme: root.theme
        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14
            Text {
                text: root.title
                textFormat: Text.PlainText
                color: root.theme.textMuted
                font.family: "monospace"
                font.pixelSize: 18
            }
            Rectangle {
                width: parent.width
                height: 64
                radius: 12
                color: root.theme.surfaceRaised
                Text {
                    anchors.fill: parent
                    anchors.margins: 12
                    text: root.value || "0"
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font.family: "monospace"
                    font.pixelSize: 32
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideLeft
                }
            }
            Grid {
                columns: 3
                spacing: 10
                Repeater {
                    model: ["7", "8", "9", "4", "5", "6", "1", "2", "3", ".", "0", "⌫"]
                    DashboardButton {
                        required property string modelData
                        theme: root.theme
                        width: 150
                        height: 64
                        label: modelData
                        enabled: modelData !== "." || !root.integerOnly
                        onClicked: {
                            if (modelData === "⌫")
                                root.value = root.value.slice(0, -1);
                            else
                                root.append(modelData);
                        }
                    }
                }
            }
            Text {
                width: parent.width
                height: 24
                text: root.error
                textFormat: Text.PlainText
                color: root.theme.error
                font.pixelSize: 15
                elide: Text.ElideRight
            }
            Row {
                spacing: 10
                DashboardButton {
                    theme: root.theme
                    width: 150
                    height: 50
                    label: "CLEAR"
                    onClicked: root.value = ""
                }
                DashboardButton {
                    theme: root.theme
                    width: 150
                    height: 50
                    label: "CANCEL"
                    onClicked: root.cancelled()
                }
                DashboardButton {
                    theme: root.theme
                    width: 150
                    height: 50
                    label: "APPLY"
                    selected: true
                    onClicked: {
                        if (!Number.isFinite(Number(root.value)) || root.value === "")
                            root.error = "Enter a valid number";
                        else
                            root.accepted(root.value);
                    }
                }
            }
        }
    }
}
