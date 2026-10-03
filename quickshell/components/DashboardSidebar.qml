pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: root
    objectName: "dashboardSidebar"
    required property var theme
    required property var presets
    property int currentIndex: 0
    property bool open: false
    property bool reducedMotion: false
    property bool monitorBusy: false
    readonly property bool blocking: open || edgeDrag.active || dragging || revealAnimation.running || reveal > 0
    signal openRequested(bool value)
    signal selected(int index)
    signal monitorRequested()
    signal interactionOccurred()

    readonly property real railWidth: Math.min(64, width)
    readonly property real drawerWidth: Math.max(0, Math.min(560, width - railWidth))
    readonly property bool available: enabled && visible
    readonly property bool controlsEnabled: available && open && !edgeDrag.active && !dragging
        && !revealAnimation.running && Math.abs(reveal - drawerWidth) < 0.5
    property bool dragging: false
    property real dragStartReveal: 0
    property real dragReveal: 0
    // The drag owns only its offset. Neither geometry nor the parent's open binding is replaced.
    property real requestedReveal: dragging ? dragReveal : open ? drawerWidth : 0
    readonly property real reveal: Math.max(0, Math.min(drawerWidth, requestedReveal))
    clip: true

    function requestOpen(value) {
        if (!available || dragging)
            return;
        interactionOccurred();
        openRequested(value);
    }
    function restoreFocus() {
        if (available)
            handle.forceActiveFocus(Qt.OtherFocusReason);
    }
    function choose(index) {
        if (!controlsEnabled || index < 0 || index >= presetButtons.count)
            return;
        interactionOccurred();
        selected(index);
    }
    function requestMonitor() {
        if (!controlsEnabled)
            return;
        interactionOccurred();
        monitorRequested();
    }
    function focusPreset(index) {
        var button = presetButtons.itemAt(index);
        if (!controlsEnabled || !button)
            return;
        button.forceActiveFocus(Qt.TabFocusReason);
        var bottom = button.y + button.height;
        if (button.y < presetList.contentY)
            presetList.contentY = button.y;
        else if (bottom > presetList.contentY + presetList.height)
            presetList.contentY = bottom - presetList.height;
    }
    function focusedIndex() {
        for (var index = 0; index < presetButtons.count; ++index) {
            if (presetButtons.itemAt(index).activeFocus)
                return index;
        }
        return monitorButton.activeFocus ? presetButtons.count : presetButtons.count + 1;
    }
    function moveFocus(delta) {
        if (!controlsEnabled)
            return;
        var count = presetButtons.count + 2;
        var index = (focusedIndex() + delta + count) % count;
        interactionOccurred();
        if (index < presetButtons.count)
            focusPreset(index);
        else if (index === presetButtons.count)
            monitorButton.forceActiveFocus(Qt.TabFocusReason);
        else
            handle.forceActiveFocus(Qt.TabFocusReason);
    }

    onOpenChanged: {
        if (!available)
            return;
        if (open) {
            root.forceActiveFocus(Qt.OtherFocusReason);
            if (controlsEnabled)
                focusPreset(currentIndex);
        } else if (activeFocus) {
            handle.forceActiveFocus(Qt.OtherFocusReason);
        }
    }
    onControlsEnabledChanged: {
        if (controlsEnabled && root.activeFocus && !handle.activeFocus)
            focusPreset(currentIndex);
    }
    onAvailableChanged: {
        if (!available)
            dragging = false;
    }
    onReducedMotionChanged: {
        if (reducedMotion)
            revealAnimation.complete();
    }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (!root.available)
            return;
        if (event.key === Qt.Key_Escape && root.blocking) {
            root.dragging = false;
            root.requestOpen(false);
            event.accepted = true;
        } else if (root.open && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            root.moveFocus(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
            event.accepted = true;
        } else if (root.open && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
            root.moveFocus(event.key === Qt.Key_Up ? -1 : 1);
            event.accepted = true;
        } else if (root.open && (event.key === Qt.Key_Home || event.key === Qt.Key_End)) {
            if (root.controlsEnabled) {
                root.interactionOccurred();
                root.focusPreset(event.key === Qt.Key_Home ? 0 : presetButtons.count - 1);
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (event.isAutoRepeat) {
                event.accepted = true;
                return;
            }
            if (handle.activeFocus)
                root.requestOpen(!root.open);
            else if (monitorButton.activeFocus)
                root.requestMonitor();
            else if (root.controlsEnabled)
                root.choose(root.focusedIndex());
            event.accepted = true;
        }
    }

    Behavior on requestedReveal {
        enabled: !root.dragging
        NumberAnimation {
            id: revealAnimation
            duration: root.reducedMotion ? 0 : 220
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        objectName: "sidebarBackdrop"
        anchors.fill: parent
        visible: root.blocking
        color: Qt.alpha(root.theme.canvas, 0.64 * root.reveal / Math.max(1, root.drawerWidth))
        MouseArea {
            anchors.fill: parent
            enabled: root.available && root.blocking
            onClicked: root.requestOpen(false)
            onWheel: function(wheel) { wheel.accepted = true; }
        }
    }

    Rectangle {
        id: drawer
        objectName: "sidebarDrawer"
        width: root.drawerWidth
        height: parent.height
        x: root.reveal - width
        visible: root.blocking
        color: root.theme.surface
        border.width: 1
        border.color: root.theme.borderStrong
        clip: true

        // Blank drawer space absorbs input rather than dismissing or touching the page.
        MouseArea {
            anchors.fill: parent
            enabled: root.available && root.blocking
            onPressed: root.interactionOccurred()
            onWheel: function(wheel) { wheel.accepted = true; }
        }
        Column {
            x: 24
            y: 22
            width: Math.max(0, parent.width - 48)
            spacing: 5
            Text {
                width: parent.width
                text: "XENEON EDGE"
                textFormat: Text.PlainText
                font { family: "monospace"; pixelSize: 26; weight: Font.DemiBold; letterSpacing: 1.4 }
                color: root.theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: "WORKSPACE PRESETS  /  01–09"
                textFormat: Text.PlainText
                font { family: "monospace"; pixelSize: 18; letterSpacing: 0.6 }
                color: root.theme.textMuted
                elide: Text.ElideRight
            }
        }
        Flickable {
            id: presetList
            objectName: "sidebarPresetList"
            x: 20
            y: 104
            width: Math.max(0, parent.width - 40)
            height: Math.max(0, footer.y - y - 16)
            contentWidth: width
            contentHeight: presetColumn.height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            enabled: root.controlsEnabled
            interactive: enabled && contentHeight > height
            clip: true
            onMovementStarted: root.interactionOccurred()
            Column {
                id: presetColumn
                width: Math.max(0, presetList.width - 20)
                spacing: 8
                Repeater {
                    id: presetButtons
                    model: root.presets
                    DashboardButton {
                        required property int index
                        required property var modelData
                        objectName: "presetButton_" + index
                        width: presetColumn.width
                        height: 96
                        theme: root.theme
                        label: "0" + (index + 1) + "  " + String(modelData.label)
                        labelPixelSize: 30
                        selected: root.currentIndex === index
                        enabled: root.controlsEnabled
                        activeFocusOnTab: enabled
                        border.width: activeFocus ? 2 : 1
                        border.color: activeFocus || selected ? root.theme.accent : root.theme.border
                        Accessible.ignored: !root.controlsEnabled
                        Accessible.name: String(modelData.label)
                        Keys.forwardTo: [root]
                        Accessible.description: "Preset " + (index + 1) + " of " + presetButtons.count
                            + (selected ? ", current. " : ". ") + detail
                        Accessible.checkable: true
                        Accessible.checked: selected
                        onClicked: root.choose(index)
                    }
                }
            }
        }
        Rectangle {
            x: presetList.x + presetList.width - width
            y: presetList.y
            width: 10
            height: presetList.height
            radius: 5
            visible: presetList.contentHeight > presetList.height
            color: Qt.alpha(root.theme.textMuted, 0.2)
            Rectangle {
                width: parent.width
                height: Math.max(40, parent.height * presetList.height / Math.max(1, presetList.contentHeight))
                y: Math.max(0, Math.min(1, presetList.contentY / Math.max(1, presetList.contentHeight - presetList.height))) * (parent.height - height)
                radius: 5
                color: root.theme.accent
            }
        }
        Item {
            id: footer
            x: 20
            y: Math.max(88, parent.height - height - 20)
            width: Math.max(0, parent.width - 40)
            height: 112
            Rectangle {
                width: parent.width
                height: 1
                color: root.theme.border
            }
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: monitorButton.verticalCenter
                width: Math.max(0, monitorButton.x - 16)
                text: "DISPLAY SETTINGS"
                textFormat: Text.PlainText
                font { family: "monospace"; pixelSize: 18; letterSpacing: 0.5 }
                color: root.theme.textMuted
                elide: Text.ElideRight
            }
            DashboardButton {
                id: monitorButton
                objectName: "globalMonitorButton"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: Math.min(280, parent.width)
                height: 88
                labelPixelSize: 30
                theme: root.theme
                label: root.monitorBusy ? "MONITOR · BUSY" : "MONITOR"
                enabled: root.controlsEnabled
                activeFocusOnTab: enabled
                Keys.forwardTo: [root]
                border.width: activeFocus ? 2 : 1
                border.color: activeFocus ? root.theme.accent : root.theme.border
                Accessible.ignored: !root.controlsEnabled
                Accessible.description: "Open shared monitor settings"
                onClicked: root.requestMonitor()
            }
        }
    }

    Rectangle {
        id: handle
        objectName: "sidebarHandle"
        x: root.reveal
        width: root.railWidth
        height: parent.height
        color: root.theme.canvas
        enabled: root.available
        activeFocusOnTab: enabled
        Keys.forwardTo: [root]
        Accessible.role: Accessible.Button
        Accessible.ignored: !root.available
        Accessible.name: root.open ? "Close workspace presets" : "Open workspace presets"
        Accessible.description: "Tap or drag horizontally. Use arrow keys to browse presets when open."
        Accessible.onPressAction: root.requestOpen(!root.open)
        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: root.theme.borderStrong
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 16)
            height: Math.min(144, parent.height)
            radius: 16
            color: handleTap.pressed || edgeDrag.active ? root.theme.surfacePressed : root.theme.surfaceRaised
            border.width: handle.activeFocus ? 2 : 1
            border.color: handle.activeFocus || root.open ? root.theme.accent : root.theme.borderStrong
            Column {
                anchors.centerIn: parent
                spacing: 14
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 4
                    height: 30
                    radius: 2
                    color: root.theme.textMuted
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.open ? "‹" : "›"
                    textFormat: Text.PlainText
                    font { pixelSize: 28; weight: Font.DemiBold }
                    color: root.theme.textPrimary
                }
            }
        }
        TapHandler {
            id: handleTap
            enabled: root.available
            gesturePolicy: TapHandler.DragThreshold
            onTapped: root.requestOpen(!root.open)
        }
        DragHandler {
            id: edgeDrag
            enabled: root.available
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    var startReveal = root.reveal;
                    root.dragStartReveal = startReveal;
                    root.dragReveal = startReveal;
                    root.dragging = true;
                    handle.forceActiveFocus(Qt.MouseFocusReason);
                    root.interactionOccurred();
                } else if (root.dragging) {
                    var shouldOpen = root.dragReveal >= root.drawerWidth / 2;
                    if (root.available)
                        root.openRequested(shouldOpen);
                    root.dragging = false;
                }
            }
            onActiveTranslationChanged: {
                if (root.dragging)
                    root.dragReveal = Math.max(0, Math.min(root.drawerWidth, root.dragStartReveal + activeTranslation.x));
            }
        }
    }
}
