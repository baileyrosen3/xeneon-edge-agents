pragma ComponentBehavior: Bound
import QtQuick

FocusScope {
    id: root
    required property var store
    required property var bridge
    required property var activity
    required property var theme
    property bool open: false
    property bool previewMode: false
    property bool reducedMotion: false
    signal closeRequested
    readonly property var monitor: (store.omarchy || {}).monitor || ({})
    readonly property bool live: monitor.available === true && monitor.identity_verified === true && !store.freshSnapshotRequired && bridge.ready && !previewMode
    readonly property bool canRefresh: bridge.ready && !store.freshSnapshotRequired && !previewMode && pendingRequest === "" && queuedControls.length === 0 && keypadControl === ""
    property string pendingRequest: ""
    property string pendingControl: ""
    property var pendingValue: null
    property double pendingObservation: 0
    property bool acknowledged: false
    property bool needsRefresh: false
    property string feedback: ""
    property bool feedbackSuccess: false
    property var drafts: ({})
    // One command in flight; one replaceable target per continuous control.
    // The unique FIFO keeps other released controls from starving behind a drag.
    property var queuedControls: []
    property var queuedValues: ({})
    property double lastSentAt: 0
    readonly property int adjustmentInterval: 100
    property double observedAt: 0
    property string keypadControl: ""
    property int clockTick: 0
    readonly property var pictureControls: ["brightness", "backlight", "contrast"]
    readonly property var rgbControls: ["red_gain", "green_gain", "blue_gain"]
    readonly property var preset: control("color_preset", "Color preset")
    visible: open || opacity > 0
    enabled: open
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 160 } }
    z: 200
    Accessible.role: Accessible.Dialog
    Accessible.name: "Monitor hardware settings"
    Accessible.ignored: !open
    function focusTargets(item, targets) {
        if (!item.visible || !item.enabled) return
        if (item.activeFocusOnTab) targets.push(item)
        for (var i = 0; i < item.children.length; ++i)
            focusTargets(item.children[i], targets)
    }
    function moveFocus(backwards) {
        var targets = []
        focusTargets(panel, targets)
        if (!targets.length) { root.forceActiveFocus(Qt.TabFocusReason); return }
        var current = -1
        for (var i = 0; i < targets.length; ++i)
            if (targets[i].activeFocus) { current = i; break }
        var next = current < 0 ? (backwards ? targets.length - 1 : 0)
            : (current + (backwards ? -1 : 1) + targets.length) % targets.length
        targets[next].forceActiveFocus(backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason)
    }
    function acquireFocus() {
        if (open && keypadControl === "")
            closeButton.forceActiveFocus(Qt.OtherFocusReason)
    }
    onOpenChanged: {
        if (open) Qt.callLater(acquireFocus)
        else keypadControl = ""
    }
    Component.onCompleted: { if (open) Qt.callLater(acquireFocus) }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (!root.open) return
        if (root.keypadControl !== "") {
            keypad.handleKey(event)
            return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.moveFocus(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) !== 0)
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            event.accepted = true
            if (!event.isAutoRepeat) {
                root.activity.noteUserActivity()
                root.closeRequested()
            }
        }
    }

    function control(id, label) {
        var controls = monitor.controls || []
        for (var i = 0; i < controls.length; ++i)
            if (controls[i].id === id) return controls[i]
        return {id:id, label:label || id, kind:"continuous", supported:false, writable:false, current:null, maximum:null, choices:[], reason:String(monitor.reason || "Awaiting hardware capability discovery")}
    }
    function currentDraft(record) {
        return drafts[record.id] !== undefined ? Number(drafts[record.id]) : Number(record.current || 0)
    }
    function setDraft(id, value) {
        var next = Object.assign({}, drafts)
        next[id] = value
        drafts = next
    }
    function writable(record) {
        if (!live || needsRefresh || keypadControl !== "" || record.supported !== true || record.writable !== true) return false
        if (record.kind === "enum") return pendingRequest === "" && queuedControls.length === 0
        return pendingRequest === "" || pendingControl !== "" && control(pendingControl).kind === "continuous"
    }
    function validValue(record, numeric) {
        if (!Number.isFinite(numeric) || Math.floor(numeric) !== numeric) return false
        if (record.kind === "enum")
            return (record.choices || []).some(function(choice) { return Number(choice.value) === numeric })
        return record.current !== null && record.current !== undefined && record.maximum !== null && record.maximum !== undefined && numeric >= 0 && numeric <= Number(record.maximum)
    }
    function discardDraft(id) {
        var next = Object.assign({}, drafts)
        delete next[id]
        drafts = next
    }
    function removeQueued(id) {
        var next = Object.assign({}, queuedValues)
        delete next[id]
        queuedValues = next
        queuedControls = queuedControls.filter(function(item) { return item !== id })
    }
    function clearQueued() {
        adjustmentTimer.stop()
        queuedValues = ({})
        queuedControls = []
    }
    function send(payload, id, value) {
        if (pendingRequest !== "") return false
        activity.noteUserActivity()
        var requestId = bridge.omarchyAction(payload)
        if (!requestId) {
            needsRefresh = true
            finishFeedback(false, "Could not send command. Refresh hardware after checking the daemon connection.")
            return false
        }
        lastSentAt = Date.now()
        pendingControl = id
        pendingValue = value
        pendingRequest = String(requestId)
        pendingObservation = Number(monitor.refreshed_at_ms || 0)
        acknowledged = false
        feedbackSuccess = false
        feedback = id === "" ? "Reading exact monitor capabilities and values…" : "Writing " + control(id).label + " · waiting for confirmed hardware readback…"
        deadline.restart()
        return true
    }
    function refresh() {
        if (!canRefresh) return false
        return send({operation:"monitor_refresh"}, "", null)
    }
    function dispatchQueued() {
        if (pendingRequest !== "" || queuedControls.length === 0) return
        if (!live || needsRefresh) { clearQueued(); drafts = ({}); return }
        var remaining = adjustmentInterval - (Date.now() - lastSentAt)
        if (remaining > 0) {
            adjustmentTimer.interval = Math.ceil(remaining)
            adjustmentTimer.restart()
            return
        }
        while (queuedControls.length > 0) {
            var id = queuedControls[0]
            var numeric = Number(queuedValues[id])
            var record = control(id)
            removeQueued(id)
            if (!writable(record) || !validValue(record, numeric)) {
                needsRefresh = true
                finishFeedback(false, "Hardware capability changed during adjustment. Refresh before another write.")
                return
            }
            if (Number(record.current) === numeric) { discardDraft(id); continue }
            send({operation:"monitor_set",control:id,value:numeric}, id, numeric)
            return
        }
    }
    function requestSet(id, value) {
        var record = control(id)
        var numeric = Number(value)
        if (!writable(record) || !validValue(record, numeric)) return false
        setDraft(id, numeric)
        if (record.kind === "enum") {
            if (Number(record.current) === numeric) { discardDraft(id); return false }
            return send({operation:"monitor_set",control:id,value:numeric}, id, numeric)
        }
        if (pendingRequest !== "" && pendingControl === id && Number(pendingValue) === numeric) {
            removeQueued(id)
            return true
        }
        if (pendingRequest === "" && Number(record.current) === numeric) {
            removeQueued(id)
            discardDraft(id)
            dispatchQueued()
            return false
        }
        var next = Object.assign({}, queuedValues)
        next[id] = numeric
        queuedValues = next
        if (queuedControls.indexOf(id) < 0) queuedControls = queuedControls.concat([id])
        dispatchQueued()
        return !needsRefresh
    }
    function editNumber(id, invoker) {
        var record = control(id)
        if (!writable(record) || pendingRequest !== "" || queuedControls.length > 0) return
        activity.noteUserActivity()
        keypad.returnFocusItem = invoker || null
        keypadControl = id
        keypad.title = String(record.label).toUpperCase() + "  ·  0–" + record.maximum
        keypad.value = String(currentDraft(record))
        keypad.error = ""
    }
    function finishFeedback(success, message) {
        deadline.stop()
        var completedControl = pendingControl
        pendingRequest = ""
        pendingControl = ""
        pendingValue = null
        acknowledged = false
        feedbackSuccess = success
        feedback = message
        if (!success) {
            clearQueued()
            drafts = ({})
        } else {
            if (queuedValues[completedControl] === undefined) discardDraft(completedControl)
            dispatchQueued()
        }
    }
    function reconcile() {
        var sampled = Number(monitor.refreshed_at_ms || 0)
        if (pendingRequest !== "" && acknowledged && sampled > pendingObservation) {
            if (pendingControl === "") {
                needsRefresh = false
                finishFeedback(monitor.available === true, monitor.available === true ? "Hardware capabilities and current values refreshed" : String(monitor.reason || "Monitor discovery unavailable"))
            } else {
                var record = control(pendingControl)
                if (record.supported === true && Number(record.current) === Number(pendingValue)) {
                    needsRefresh = false
                    finishFeedback(true, "Verified on hardware: " + record.label + " = " + record.current + (record.maximum !== null ? " / " + record.maximum : ""))
                } else {
                    needsRefresh = true
                    finishFeedback(false, "Hardware readback differs from the requested value. Refresh before another write.")
                }
            }
        }
        observedAt = sampled
    }
    onMonitorChanged: reconcile()
    onLiveChanged: {
        if (!live && (pendingRequest !== "" || queuedControls.length > 0)) {
            needsRefresh = true
            finishFeedback(false, "Hardware connection or identity changed. Queued adjustments were discarded; refresh before another write.")
        }
    }
    Connections {
        target: root.store
        function onActionResultReceived(result) {
            if (!root.pendingRequest || String(result.request_id || "") !== root.pendingRequest) return
            if (result.ok !== true) {
                root.needsRefresh = true
                root.finishFeedback(false, String(result.message || "Monitor command failed") + " · Refresh hardware before trying again.")
            } else {
                root.acknowledged = true
                root.reconcile()
            }
        }
    }
    Timer {
        id: adjustmentTimer
        objectName: "monitorAdjustmentTimer"
        interval: root.adjustmentInterval
        onTriggered: root.dispatchQueued()
    }
    Timer {
        id: deadline
        objectName: "monitorWriteDeadline"
        interval: 45000
        onTriggered: {
            root.needsRefresh = true
            root.finishFeedback(false, "No confirmed hardware response. Refresh current values before another write; the command will not be resent.")
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.open
        onTriggered: root.clockTick += 1
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(root.theme.canvas, 0.94)
        MouseArea { anchors.fill: parent }
    }
    DashboardCard {
        id: panel
        enabled: root.keypadControl === ""
        objectName: "monitorSettingsCard"
        anchors.centerIn: parent
        width: parent.width - 48
        height: parent.height - 28
        theme: root.theme
        border.color: root.theme.accent
        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            Row {
                width: parent.width
                height: 52
                spacing: 14
                Column {
                    width: parent.width - 490
                    spacing: 4
                    Text {
                        text: "MONITOR // HARDWARE SETTINGS"
                        textFormat: Text.PlainText
                        color: root.theme.textPrimary
                        font.family: "monospace"
                        font.pixelSize: 25
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: root.previewMode ? "SYNTHETIC PREVIEW · HARDWARE WRITES DISABLED" : root.live ? "EXACT EDGE IDENTITY VERIFIED · DIRECT DDC CONTROL" : String(root.monitor.reason || "Hardware discovery has not completed")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: root.live ? root.theme.accent : root.theme.needsHelp
                        font.pixelSize: 15
                    }
                }
                DashboardButton {
                    objectName: "monitorRefreshButton"
                    Keys.forwardTo: [root]
                    theme: root.theme
                    width: 300
                    height: 48
                    label: root.pendingRequest !== "" ? "HARDWARE BUSY" : "REFRESH HARDWARE"
                    enabled: root.canRefresh
                    onClicked: root.refresh()
                }
                DashboardButton {
                    id: closeButton
                    Keys.forwardTo: [root]
                    objectName: "monitorCloseButton"
                    theme: root.theme
                    width: 160
                    height: 48
                    label: "CLOSE"
                    enabled: root.keypadControl === ""
                    onClicked: { root.activity.noteUserActivity(); root.closeRequested() }
                }
            }
            Row {
                width: parent.width
                height: parent.height - 110
                spacing: 14
                DashboardCard {
                    theme: root.theme
                    width: 440
                    height: parent.height
                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 8
                        Text { text: "DEVICE IDENTITY"; textFormat: Text.PlainText; color: root.theme.magenta; font.family: "monospace"; font.pixelSize: 19 }
                        Text { width: parent.width; text: String(root.monitor.model || "XENEON EDGE · NOT DISCOVERED"); textFormat: Text.PlainText; color: root.theme.textPrimary; font.pixelSize: 24; wrapMode: Text.WordWrap }
                        Text { width: parent.width; text: "OUTPUT  " + String(root.monitor.connector || "—") + "\nSERIAL  " + String(root.monitor.serial || "—") + "\nDDC BUS " + (root.monitor.i2c_bus === null || root.monitor.i2c_bus === undefined ? "—" : root.monitor.i2c_bus); textFormat: Text.PlainText; color: root.theme.textMuted; font.family: "monospace"; font.pixelSize: 17; lineHeight: 1.2 }
                        Text { width: parent.width; text: "EDID\n" + String(root.monitor.edid_sha256 || "Identity unavailable"); textFormat: Text.PlainText; color: root.theme.textMuted; font.family: "monospace"; font.pixelSize: 13; wrapMode: Text.WrapAnywhere }
                        Rectangle { width: parent.width; height: 1; color: root.theme.borderStrong }
                        Text { text: "DISPLAY / TOUCH · READ ONLY"; textFormat: Text.PlainText; color: root.theme.accent; font.family: "monospace"; font.pixelSize: 17 }
                        Text {
                            width: parent.width
                            text: {
                                var d = root.monitor.display
                                var t = root.monitor.touch
                                return (d ? d.width + " × " + d.height + "  @  " + Number(d.refresh_hz).toFixed(2) + " Hz\nScale " + d.scale + "  ·  transform " + d.transform : "Display mode unavailable") + "\n\n" + (t ? "Touch " + (t.connected ? "CONNECTED" : "ABSENT") + "\n" + String(t.device || "—") : "Touch status unavailable")
                            }
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 16
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: { root.clockTick; return root.monitor.refreshed_at_ms ? (root.monitor.available ? "Read " : "Checked ") + Math.max(0, Math.floor((Date.now() - Number(root.monitor.refreshed_at_ms)) / 1000)) + "s ago" : "No hardware check yet" }
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.pixelSize: 15
                        }
                    }
                }
                Column {
                    id: controlsColumn
                    width: parent.width - 454
                    height: parent.height
                    spacing: 10
                    readonly property real cardWidth: (width - 20) / 3
                    Row {
                        spacing: 10
                        Repeater {
                            model: root.pictureControls
                            MonitorControl {
                                required property string modelData
                                keyboardScope: root
                                objectName: "monitorControl_" + modelData
                                width: controlsColumn.cardWidth
                                height: 144
                                theme: root.theme
                                control: root.control(modelData)
                                draft: root.currentDraft(control)
                                writable: root.writable(control)
                                pending: root.pendingRequest !== "" && root.pendingControl === modelData
                                queued: root.queuedValues[modelData] !== undefined
                                numberEnabled: writable && root.pendingRequest === "" && root.queuedControls.length === 0
                                onDraftEdited: function(value) { root.requestSet(modelData, value) }
                                onValueReleased: function(value) { root.requestSet(modelData, value) }
                                onNumberRequested: function(invoker) { root.editNumber(modelData, invoker) }
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: root.rgbControls
                            MonitorControl {
                                required property string modelData
                                keyboardScope: root
                                objectName: "monitorControl_" + modelData
                                width: controlsColumn.cardWidth
                                height: 144
                                theme: root.theme
                                control: root.control(modelData)
                                draft: root.currentDraft(control)
                                writable: root.writable(control)
                                pending: root.pendingRequest !== "" && root.pendingControl === modelData
                                queued: root.queuedValues[modelData] !== undefined
                                numberEnabled: writable && root.pendingRequest === "" && root.queuedControls.length === 0
                                onDraftEdited: function(value) { root.requestSet(modelData, value) }
                                onValueReleased: function(value) { root.requestSet(modelData, value) }
                                onNumberRequested: function(invoker) { root.editNumber(modelData, invoker) }
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        MonitorControl {
                            keyboardScope: root
                            objectName: "monitorControl_sharpness"
                            width: controlsColumn.cardWidth
                            height: 170
                            theme: root.theme
                            control: root.control("sharpness", "Sharpness · advanced")
                            draft: root.currentDraft(control)
                            writable: root.writable(control)
                            pending: root.pendingRequest !== "" && root.pendingControl === "sharpness"
                            queued: root.queuedValues.sharpness !== undefined
                            numberEnabled: writable && root.pendingRequest === "" && root.queuedControls.length === 0
                            onDraftEdited: function(value) { root.requestSet("sharpness", value) }
                            onValueReleased: function(value) { root.requestSet("sharpness", value) }
                            onNumberRequested: function(invoker) { root.editNumber("sharpness", invoker) }
                        }
                        DashboardCard {
                            objectName: "monitorColorPresets"
                            theme: root.theme
                            width: controlsColumn.cardWidth * 2 + 10
                            height: 170
                            Column {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10
                                Text {
                                    width: parent.width
                                    text: "COLOR PRESET · " + (((root.preset.choices || []).filter(function(choice) { return Number(choice.value) === Number(root.preset.current) })[0] || {}).label || "UNKNOWN")
                                    textFormat: Text.PlainText
                                    color: root.theme.textPrimary
                                    font.family: "monospace"
                                    font.pixelSize: 18
                                    visible: root.preset.supported === true
                                }
                                Text {
                                    width: parent.width
                                    text: String(root.preset.reason || "Color presets are not exposed by this monitor")
                                    textFormat: Text.PlainText
                                    color: root.theme.textMuted
                                    font.pixelSize: 17
                                    wrapMode: Text.WordWrap
                                    visible: root.preset.supported !== true
                                }
                                Flickable {
                                    id: presetList
                                    width: parent.width
                                    height: 104
                                    contentHeight: presetGrid.height
                                    clip: true
                                    interactive: contentHeight > height
                                    visible: root.preset.supported === true
                                    Grid {
                                        id: presetGrid
                                        width: parent.width
                                        columns: 4
                                        spacing: 8
                                        Repeater {
                                            model: root.preset.choices || []
                                            DashboardButton {
                                                required property var modelData
                                                objectName: "monitorPreset_" + modelData.value
                                                Keys.forwardTo: [root]
                                                onActiveFocusChanged: {
                                                    if (!activeFocus) return
                                                    if (y < presetList.contentY)
                                                        presetList.contentY = y
                                                    else if (y + height > presetList.contentY + presetList.height)
                                                        presetList.contentY = y + height - presetList.height
                                                }
                                                theme: root.theme
                                                width: (presetGrid.width - 24) / 4
                                                height: 44
                                                label: String(modelData.label)
                                                selected: Number(root.preset.current) === Number(modelData.value)
                                                enabled: root.writable(root.preset)
                                                onClicked: root.requestSet("color_preset", modelData.value)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text {
                width: parent.width
                height: 38
                text: root.feedback || "Hardware values use the monitor’s actual ranges. Unsupported controls remain disabled."
                textFormat: Text.PlainText
                color: root.pendingRequest !== "" ? root.theme.accent : root.feedbackSuccess ? root.theme.success : root.needsRefresh ? root.theme.needsHelp : root.theme.textMuted
                font.pixelSize: 18
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
            }
        }
    }
    DashboardNumericPad {
        id: keypad
        objectName: "monitorNumericPad"
        anchors.fill: parent
        theme: root.theme
        open: root.keypadControl !== ""
        integerOnly: true
        fallbackFocusItem: closeButton
        onCancelled: root.keypadControl = ""
        onAccepted: function(value) {
            var id = root.keypadControl
            var record = root.control(id)
            var number = Number(value)
            if (!Number.isFinite(number) || Math.floor(number) !== number || number < 0 || number > Number(record.maximum)) {
                error = "Enter a whole number from 0 through " + record.maximum
                return
            }
            root.keypadControl = ""
            root.setDraft(id, number)
            root.requestSet(id, number)
        }
    }
}
