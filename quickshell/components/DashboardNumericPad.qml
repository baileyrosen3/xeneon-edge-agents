pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

FocusScope {
    id: root
    required property var theme
    property bool open: false
    property string title: "VALUE"
    property string value: ""
    property bool integerOnly: false
    property bool signed: false
    property string error: ""
    property Item returnFocusItem: null
    property Item fallbackFocusItem: null
    signal accepted(string value)
    signal cancelled
    visible: open
    enabled: open
    Accessible.role: Accessible.Dialog
    Accessible.name: title
    Accessible.ignored: !open
    function focusTargets(item, targets) {
        if (!item.visible || !item.enabled) return;
        if (item.activeFocusOnTab) targets.push(item);
        for (var i = 0; i < item.children.length; ++i)
            focusTargets(item.children[i], targets);
    }
    function moveFocus(backwards) {
        var targets = [];
        focusTargets(pad, targets);
        var current = -1;
        for (var i = 0; i < targets.length; ++i)
            if (targets[i].activeFocus) { current = i; break; }
        if (!targets.length) return;
        var next = current < 0 ? (backwards ? targets.length - 1 : 0)
            : (current + (backwards ? -1 : 1) + targets.length) % targets.length;
        targets[next].forceActiveFocus(backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason);
    }
    function acquireFocus() {
        if (!open) return;
        if (!returnFocusItem && root.Window.window)
            returnFocusItem = root.Window.window.activeFocusItem;
        cancelButton.forceActiveFocus(Qt.OtherFocusReason);
    }
    onOpenChanged: {
        if (open) {
            Qt.callLater(acquireFocus);
        } else {
            var previous = returnFocusItem;
            returnFocusItem = null;
            Qt.callLater(function() {
                if (root.open) return;
                if (previous && previous.visible && previous.enabled)
                    previous.forceActiveFocus(Qt.OtherFocusReason);
                else if (root.fallbackFocusItem && root.fallbackFocusItem.visible && root.fallbackFocusItem.enabled)
                    root.fallbackFocusItem.forceActiveFocus(Qt.OtherFocusReason);
            });
        }
    }
    Component.onCompleted: { if (open) Qt.callLater(acquireFocus); }
    function confirm() {
        if (!open || !enabled) return;
        var number = Number(value);
        if (value.trim() === "" || !Number.isFinite(number))
            error = "Enter a valid number";
        else if (integerOnly && Math.floor(number) !== number)
            error = "Enter a whole number";
        else
            accepted(value);
    }
    function handleKey(event) {
        if (!open) return;
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            moveFocus(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) !== 0);
        } else if (event.key === Qt.Key_Escape) {
            if (!event.isAutoRepeat) cancelled();
        } else if (event.key === Qt.Key_Backspace) {
            error = "";
            value = value.slice(0, -1);
        } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                   && /^[0-9.]$/.test(event.text)) {
            append(event.text);
        } else if (signed && event.key === Qt.Key_Minus) {
            if (!event.isAutoRepeat) value = value.charAt(0) === "-" ? value.slice(1) : "-" + value;
        } else {
            return;
        }
        event.accepted = true;
    }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) { root.handleKey(event); }
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
        id: pad
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
                        Keys.forwardTo: [root]
                        Accessible.name: modelData === "⌫" ? "Backspace" : modelData === "." ? "Decimal point" : modelData
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
                    Keys.forwardTo: [root]
                    theme: root.theme
                    width: 150
                    height: 50
                    label: "CLEAR"
                    onClicked: root.value = ""
                }
                DashboardButton {
                    id: cancelButton
                    Keys.forwardTo: [root]
                    theme: root.theme
                    width: 150
                    height: 50
                    label: "CANCEL"
                    onClicked: root.cancelled()
                }
                DashboardButton {
                    Keys.forwardTo: [root]
                    theme: root.theme
                    width: 150
                    height: 50
                    label: "APPLY"
                    selected: true
                    onClicked: root.confirm()
                }
            }
        }
    }
}
