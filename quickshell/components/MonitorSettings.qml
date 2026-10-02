pragma ComponentBehavior: Bound
import QtQuick

Item {
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
    readonly property bool canRefresh: bridge.ready && !store.freshSnapshotRequired && !previewMode && pendingRequest === "" && keypadControl === ""
    property string pendingRequest: ""
    property string pendingControl: ""
    property var pendingValue: null
    property double pendingObservation: 0
    property bool acknowledged: false
    property bool needsRefresh: false
    property string feedback: ""
    property bool feedbackSuccess: false
    property var drafts: ({})
    property double observedAt: 0
    property string keypadControl: ""
    property int clockTick: 0
    readonly property var pictureControls: ["brightness", "backlight", "contrast"]
    readonly property var rgbControls: ["red_gain", "green_gain", "blue_gain"]
    readonly property var preset: control("color_preset", "Color preset")
    visible: open || opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 160 } }
    z: 200

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
        return live && !needsRefresh && pendingRequest === "" && keypadControl === "" && record.supported === true && record.writable === true
    }
    function send(payload, id, value) {
        activity.noteUserActivity()
        var requestId = bridge.omarchyAction(payload)
        if (!requestId) {
            feedback = "Could not send command. Check the daemon connection."
            feedbackSuccess = false
            return false
        }
        pendingRequest = String(requestId)
        pendingControl = id
        pendingValue = value
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
    function requestSet(id, value) {
        var record = control(id)
        var numeric = Number(value)
        if (!writable(record) || !Number.isFinite(numeric) || Math.floor(numeric) !== numeric) return false
        if (record.kind === "enum") {
            if (!(record.choices || []).some(function(choice) { return Number(choice.value) === numeric })) return false
        } else if (record.current === null || record.maximum === null || numeric < 0 || numeric > Number(record.maximum)) return false
        if (Number(record.current) === numeric) { drafts = ({}); return false }
        return send({operation:"monitor_set",control:id,value:numeric}, id, numeric)
    }
    function editNumber(id) {
        var record = control(id)
        if (!writable(record)) return
        activity.noteUserActivity()
        keypadControl = id
        keypad.title = String(record.label).toUpperCase() + "  ·  0–" + record.maximum
        keypad.value = String(currentDraft(record))
        keypad.error = ""
    }
    function finishFeedback(success, message) {
        deadline.stop()
        pendingRequest = ""
        pendingControl = ""
        pendingValue = null
        acknowledged = false
        feedbackSuccess = success
        feedback = message
        drafts = ({})
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
                        text: root.previewMode ? "SYNTHETIC PREVIEW · HARDWARE WRITES DISABLED" : root.live ? "EXACT EDGE IDENTITY VERIFIED · DIRECT DDC CONTROL" : String(root.monitor.reason || "Hardware discovery has not completed")
                        textFormat: Text.PlainText
                        color: root.live ? root.theme.accent : root.theme.needsHelp
                        font.pixelSize: 15
                    }
                }
                DashboardButton {
                    objectName: "monitorRefreshButton"
                    theme: root.theme
                    width: 300
                    height: 48
                    label: root.pendingRequest !== "" ? "HARDWARE BUSY" : "REFRESH HARDWARE"
                    enabled: root.canRefresh
                    onClicked: root.refresh()
                }
                DashboardButton {
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
                            text: { root.clockTick; return root.monitor.refreshed_at_ms ? "Read " + Math.max(0, Math.floor((Date.now() - Number(root.monitor.refreshed_at_ms)) / 1000)) + "s ago" : "No successful hardware observation yet" }
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
                                objectName: "monitorControl_" + modelData
                                width: controlsColumn.cardWidth
                                height: 144
                                theme: root.theme
                                control: root.control(modelData)
                                draft: root.currentDraft(control)
                                writable: root.writable(control)
                                pending: root.pendingRequest !== "" && root.pendingControl === modelData
                                onDraftEdited: function(value) { root.setDraft(modelData, value) }
                                onValueReleased: function(value) { root.requestSet(modelData, value) }
                                onNumberRequested: root.editNumber(modelData)
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: root.rgbControls
                            MonitorControl {
                                required property string modelData
                                objectName: "monitorControl_" + modelData
                                width: controlsColumn.cardWidth
                                height: 144
                                theme: root.theme
                                control: root.control(modelData)
                                draft: root.currentDraft(control)
                                writable: root.writable(control)
                                pending: root.pendingRequest !== "" && root.pendingControl === modelData
                                onDraftEdited: function(value) { root.setDraft(modelData, value) }
                                onValueReleased: function(value) { root.requestSet(modelData, value) }
                                onNumberRequested: root.editNumber(modelData)
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        MonitorControl {
                            objectName: "monitorControl_sharpness"
                            width: controlsColumn.cardWidth
                            height: 170
                            theme: root.theme
                            control: root.control("sharpness", "Sharpness · advanced")
                            draft: root.currentDraft(control)
                            writable: root.writable(control)
                            pending: root.pendingRequest !== "" && root.pendingControl === "sharpness"
                            onDraftEdited: function(value) { root.setDraft("sharpness", value) }
                            onValueReleased: function(value) { root.requestSet("sharpness", value) }
                            onNumberRequested: root.editNumber("sharpness")
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
