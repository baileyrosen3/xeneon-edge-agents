pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    required property var store
    required property var bridge
    required property var activity
    required property var theme
    property bool previewMode: false
    readonly property var model: store.omarchy || ({})
    readonly property var audio: model.audio || ({})
    readonly property var media: model.media || ({})
    readonly property var health: store.health || ({})
    readonly property bool actionable: !previewMode && bridge.ready && !store.freshSnapshotRequired
    property string pendingRequest: ""
    property bool unknownOutcome: false
    property double unknownAtMs: 0
    readonly property bool canReviewOutcome: visible && enabled && actionable && unknownOutcome
        && pendingRequest !== "" && Number(store.generatedAtMs || 0) > unknownAtMs
    onActionableChanged: {
        if (!actionable && pendingRequest !== "")
            markUnknown("Connection changed before the action result arrived.");
    }
    property string feedback: ""
    property string preset: "overview"
    readonly property bool embeddedPage: preset === "system" || preset === "audio" || preset === "desktop"
    readonly property string pageTab: preset
    function listAvailable(value) {
        return Array.isArray(value) && value.length > 0;
    }
    signal monitorRequested
    signal presetRequested(int index)
    // Presentation only; dispatch authority stays with the daemon.
    property var histories: ({})
    property int clockTick: 0
    readonly property var metrics: [
        {
            key: "cpu",
            label: "CPU",
            unit: "%",
            colorRole: "blue"
        },
        {
            key: "gpu",
            label: "GPU",
            unit: "%",
            colorRole: "magenta"
        },
        {
            key: "memory",
            label: "MEMORY",
            unit: "%",
            colorRole: "cyan"
        },
        {
            key: "cpu_temperature",
            label: "CPU TEMP",
            unit: "°C",
            colorRole: "orange"
        },
        {
            key: "gpu_temperature",
            label: "GPU TEMP",
            unit: "°C",
            colorRole: "yellow"
        },
        {
            key: "network_down",
            label: "NETWORK ↓",
            unit: "",
            colorRole: "green"
        }
    ]
    function metric(key) {
        var item = health[key];
        if (!item || item.available !== true || !Number.isFinite(Number(item.value)))
            return null;
        return Number(item.value);
    }
    function metricLabel(key, unit) {
        var value = metric(key);
        if (value === null)
            return "—";
        if (key.indexOf("network_") === 0)
            return value >= 1048576 ? (value / 1048576).toFixed(1) + " MB/s" : (value / 1024).toFixed(1) + " KB/s";
        return value.toFixed(0) + unit;
    }
    function recordHistory() {
        var next = Object.assign({}, histories);
        for (var i = 0; i < metrics.length; ++i) {
            var key = metrics[i].key;
            var value = metric(key);
            if (value === null)
                continue;
            var values = (next[key] || []).slice(-29);
            values.push(value);
            next[key] = values;
        }
        histories = next;
    }
    function request(payload) {
        if (!root.visible || !root.enabled)
            return false;
        activity.noteUserActivity();
        if (!actionable || pendingRequest !== "" || typeof bridge.omarchyAction !== "function")
            return false;
        var id = bridge.omarchyAction(payload);
        if (!id) {
            feedback = "Action unavailable";
            return false;
        }
        pendingRequest = String(id);
        unknownOutcome = false;
        unknownAtMs = 0;
        outcomeTimer.restart();
        feedback = "Applying…";
        return true;
    }
    function markUnknown(detail) {
        if (pendingRequest === "" || unknownOutcome)
            return;
        unknownOutcome = true;
        unknownAtMs = Number(store.generatedAtMs || 0);
        outcomeTimer.stop();
        feedback = "OUTCOME UNKNOWN  ·  " + detail + " Review current desktop state before resuming; the action will not be resent.";
    }
    function resumeReviewed() {
        if (!canReviewOutcome)
            return false;
        activity.noteUserActivity();
        pendingRequest = "";
        unknownOutcome = false;
        unknownAtMs = 0;
        feedback = "Resumed after review · previous action was not resent";
        return true;
    }
    function bytes(value) {
        var n = Number(value || 0);
        return n >= 1099511627776 ? (n / 1099511627776).toFixed(1) + " TB" : (n / 1073741824).toFixed(1) + " GB";
    }
    Component.onCompleted: recordHistory()
    Connections {
        target: root.store
        function onHealthChanged() {
            root.recordHistory();
        }
        function onActionResultReceived(result) {
            if (String(result.request_id || "") !== root.pendingRequest || root.pendingRequest === "")
                return;
            root.pendingRequest = "";
            root.unknownOutcome = false;
            root.unknownAtMs = 0;
            outcomeTimer.stop();
            root.feedback = result.ok === true ? "Applied" : String(result.message || result.code || "Action failed");
        }
    }
    Timer {
        id: outcomeTimer
        interval: 15000
        onTriggered: root.markUnknown("No response was received.")
    }
    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.clockTick += 1
    }
    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10
        visible: !root.embeddedPage
        Row {
            width: parent.width
            height: 38
            Text {
                width: parent.width - 220
                text: "OMARCHY // CONTROL"
                textFormat: Text.PlainText
                color: root.theme.textPrimary
                font.family: "monospace"
                font.pixelSize: 22
                font.weight: Font.Bold
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                width: 220
                text: {
                    root.clockTick;
                    return Qt.formatDateTime(new Date(), "ddd  hh:mm:ss");
                }
                textFormat: Text.PlainText
                color: root.theme.accent
                font.family: "monospace"
                font.pixelSize: 19
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Grid {
            width: parent.width
            columns: 3
            spacing: 10
            Repeater {
                model: root.metrics
                DashboardCard {
                    id: metricCard
                    required property var modelData
                    readonly property var definition: modelData || ({})
                    readonly property string metricKey: String(definition.key || "")
                    objectName: "omarchyMetric_" + metricKey
                    theme: root.theme
                    width: (root.width - 56) / 3
                    height: 86
                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        Text {
                            text: String(metricCard.definition.label || "")
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Text {
                            text: root.metricLabel(metricCard.metricKey, String(metricCard.definition.unit || ""))
                            textFormat: Text.PlainText
                            color: root.metric(metricCard.metricKey) === null ? root.theme.textMuted : root.theme.textPrimary
                            font.family: "monospace"
                            font.pixelSize: 25
                            font.weight: Font.DemiBold
                        }
                    }
                    Canvas {
                        objectName: "omarchyHistory_" + metricCard.metricKey
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 12
                        property var values: root.histories[metricCard.metricKey] || []
                        property color lineColor: root.theme[metricCard.definition.colorRole] || root.theme.accent
                        onValuesChanged: requestPaint()
                        onLineColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            if (values.length < 2)
                                return;
                            var maxValue = metricCard.metricKey.indexOf("network_") === 0 ? Math.max(1, ...values) : 100;
                            ctx.strokeStyle = String(lineColor);
                            ctx.lineWidth = 1.5;
                            ctx.beginPath();
                            for (var i = 0; i < values.length; ++i) {
                                var x = width * i / (values.length - 1);
                                var y = height - Math.min(1, values[i] / maxValue) * (height - 2);
                                if (i === 0)
                                    ctx.moveTo(x, y);
                                else
                                    ctx.lineTo(x, y);
                            }
                            ctx.stroke();
                        }
                    }
                }
            }
        }
        DashboardCard {
            theme: root.theme
            width: parent.width
            height: 92
            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                Row {
                    spacing: 10
                    Text {
                        width: 130
                        text: "AUDIO  " + (audio.volume_percent === undefined || audio.volume_percent === null ? "—" : audio.volume_percent + "%")
                        textFormat: Text.PlainText
                        color: root.theme.textPrimary
                        font.family: "monospace"
                        font.pixelSize: 17
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 100
                        height: 44
                        label: "−"
                        enabled: root.actionable && audio.available === true && root.pendingRequest === ""
                        onClicked: root.request({
                            operation: "volume",
                            percent: Math.max(0, Number(audio.volume_percent || 0) - 5)
                        })
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 100
                        height: 44
                        label: "+"
                        enabled: root.actionable && audio.available === true && root.pendingRequest === ""
                        onClicked: root.request({
                            operation: "volume",
                            percent: Math.min(100, Number(audio.volume_percent || 0) + 5)
                        })
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 130
                        height: 44
                        label: "SPEAKER"
                        selected: audio.muted === true
                        enabled: root.actionable && audio.available === true && root.pendingRequest === ""
                        onClicked: root.request({
                            operation: "mute",
                            muted: audio.muted !== true
                        })
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 130
                        height: 44
                        label: "MIC MUTE"
                        selected: audio.microphone_muted === true
                        enabled: root.actionable && audio.available === true && root.pendingRequest === ""
                        onClicked: root.request({
                            operation: "microphone_mute",
                            muted: audio.microphone_muted !== true
                        })
                    }
                }
                Text {
                    width: parent.width
                    text: audio.available === true ? "PIPEWIRE  ·  " + (audio.muted === true ? "SPEAKERS MUTED" : "SPEAKERS ON") + "  ·  " + (audio.microphone_muted === true ? "MIC MUTED" : "MIC ON") : "Audio status unavailable"
                    textFormat: Text.PlainText
                    color: root.theme.textMuted
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
            }
        }
        DashboardCard {
            theme: root.theme
            width: parent.width
            height: 80
            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                Column {
                    width: parent.width - 172
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        width: parent.width
                        text: String(media.title || "No active media")
                        textFormat: Text.PlainText
                        color: root.theme.textPrimary
                        font.pixelSize: 20
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: String(media.artist || media.identity || "MPRIS") + "  ·  " + String(media.playback_status || "UNAVAILABLE").toUpperCase()
                        textFormat: Text.PlainText
                        color: root.theme.textMuted
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
                Repeater {
                    model: [
                        {
                            label: "‹",
                            command: "previous"
                        },
                        {
                            label: "Ⅱ / ▷",
                            command: "play_pause"
                        },
                        {
                            label: "›",
                            command: "next"
                        }
                    ]
                    DashboardButton {
                        required property var modelData
                        theme: root.theme
                        width: 48
                        height: 52
                        label: modelData.label
                        enabled: root.actionable && media.available === true && root.pendingRequest === ""
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.request({
                            operation: "media",
                            command: modelData.command
                        })
                    }
                }
            }
        }
        Grid {
            width: parent.width
            columns: 3
            spacing: 8
            Repeater {
                model: [
                    {
                        label: "DO NOT DISTURB",
                        operation: "toggle_dnd",
                        active: root.model.dnd
                    },
                    {
                        label: "KEEP AWAKE",
                        operation: "toggle_keepawake",
                        active: root.model.keepawake
                    },
                    {
                        label: "NIGHTLIGHT",
                        operation: "toggle_nightlight",
                        active: root.model.nightlight
                    },
                    {
                        label: "SCREENSHOT",
                        operation: "screenshot"
                    },
                    {
                        label: root.model.recording === true ? "STOP RECORDING" : "RECORD SCREEN",
                        operation: root.model.recording === true ? "stop_recording" : "start_recording",
                        active: root.model.recording
                    },
                    {
                        label: "LOCK",
                        operation: "lock"
                    },
                    {
                        label: "SYSTEM DETAILS",
                        presetIndex: 3
                    },
                    {
                        label: "AUDIO / DISPLAY",
                        presetIndex: 4
                    },
                    {
                        label: "THEME / POWER",
                        presetIndex: 5
                    }
                ]
                DashboardButton {
                    required property var modelData
                    objectName: modelData.presetIndex !== undefined ? "omarchyPreset_" + modelData.presetIndex : ""
                    theme: root.theme
                    width: (root.width - 52) / 3
                    height: 48
                    label: modelData.label
                    selected: modelData.active === true
                    enabled: modelData.presetIndex !== undefined || (root.actionable && root.pendingRequest === "")
                    onClicked: {
                        if (modelData.presetIndex !== undefined)
                            root.presetRequested(modelData.presetIndex);
                        else
                            root.request({
                                operation: modelData.operation
                            });
                    }
                }
            }
        }
        Text {
            width: parent.width
            height: implicitHeight
            text: root.previewMode ? "PREVIEW  ·  desktop actions disabled" : root.feedback || String(root.model.detail || "Native desktop controls")
            textFormat: Text.PlainText
            color: root.previewMode ? root.theme.needsHelp : root.theme.textMuted
            font.pixelSize: root.unknownOutcome ? 18 : 13
            wrapMode: Text.WordWrap
        }
    }
    Item {
        objectName: "omarchyDetailPage"
        anchors.fill: parent
        visible: root.embeddedPage
        z: 50
        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14
            Row {
                width: parent.width
                spacing: 12
                Text {
                    width: parent.width
                    height: 48
                    text: root.pageTab === "system" ? "SYSTEM DETAILS" : root.pageTab === "audio" ? "AUDIO / DISPLAY" : "THEME / POWER"
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font.family: "monospace"
                    font.pixelSize: 32
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Flickable {
                width: parent.width
                height: parent.height - 144
                contentHeight: drawerContent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: drawerContent
                    width: parent.width
                    spacing: 12
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.pageTab === "system"
                        Text {
                            text: root.listAvailable(root.model.storage) ? "STORAGE" : "STORAGE  ·  UNAVAILABLE"
                            textFormat: Text.PlainText
                            color: root.listAvailable(root.model.storage) ? root.theme.accent : root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                        Repeater {
                            model: root.model.storage || []
                            DashboardCard {
                                required property var modelData
                                theme: root.theme
                                width: drawerContent.width
                                height: 82
                                Accessible.role: Accessible.StaticText
                                Accessible.name: String(modelData.mount || "/") + ", " + Number(modelData.used_percent || 0).toFixed(0) + " percent used"
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6
                                    Text { text: String(parent.parent.modelData.mount || "/"); textFormat: Text.PlainText; color: root.theme.textPrimary; font.pixelSize: 24 }
                                    Text { text: root.bytes(parent.parent.modelData.available_bytes) + " FREE / " + root.bytes(parent.parent.modelData.total_bytes) + "  ·  " + Number(parent.parent.modelData.used_percent || 0).toFixed(0) + "% USED"; textFormat: Text.PlainText; color: root.theme.textMuted; font.pixelSize: 18 }
                                }
                            }
                        }
                        Text {
                            text: root.listAvailable(root.model.processes) ? "TOP CPU PROCESSES" : "TOP CPU PROCESSES  ·  UNAVAILABLE"
                            textFormat: Text.PlainText
                            color: root.listAvailable(root.model.processes) ? root.theme.accent : root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                        Repeater {
                            model: root.model.processes || []
                            Text {
                                required property var modelData
                                width: drawerContent.width
                                text: String(modelData.name || "process") + "  ·  " + Number(modelData.cpu_percent || 0).toFixed(1) + "%"
                                textFormat: Text.PlainText
                                color: root.theme.textPrimary
                                font.family: "monospace"
                                font.pixelSize: 18
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            text: "NETWORK ↑  " + root.metricLabel("network_up", "")
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.pageTab === "audio"
                        Text {
                            text: root.listAvailable(root.audio.outputs) ? "AUDIO OUTPUT" : "AUDIO OUTPUT  ·  UNAVAILABLE"
                            textFormat: Text.PlainText
                            color: root.listAvailable(root.audio.outputs) ? root.theme.accent : root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                        Repeater {
                            model: root.audio.outputs || []
                            DashboardButton {
                                required property var modelData
                                theme: root.theme
                                width: drawerContent.width
                                height: 60
                                label: String(modelData.name || "Output")
                                selected: modelData.id === root.audio.default_output_id
                                enabled: root.actionable && root.pendingRequest === ""
                                onClicked: root.request({
                                    operation: "output",
                                    id: modelData.id
                                })
                            }
                        }
                        Text {
                            text: "MONITOR HARDWARE"
                            textFormat: Text.PlainText
                            color: root.theme.accent
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                        Text {
                            width: parent.width
                            text: String((root.model.monitor || {}).reason || "Picture controls and hardware capability discovery")
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.pixelSize: 18
                            wrapMode: Text.WordWrap
                        }
                        DashboardButton {
                            theme: root.theme
                            width: drawerContent.width
                            height: 52
                            label: "OPEN MONITOR SETTINGS"
                            enabled: root.enabled && root.visible
                            onClicked: {
                                root.monitorRequested();
                            }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.pageTab === "desktop"
                        Text {
                            text: root.listAvailable(root.model.power_profiles) ? "POWER PROFILE" : "POWER PROFILE  ·  UNAVAILABLE"
                            textFormat: Text.PlainText
                            color: root.listAvailable(root.model.power_profiles) ? root.theme.accent : root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                        Repeater {
                            model: root.model.power_profiles || []
                            DashboardButton {
                                required property string modelData
                                theme: root.theme
                                width: drawerContent.width
                                label: modelData.toUpperCase()
                                selected: modelData === root.model.power_profile
                                enabled: root.actionable && root.pendingRequest === ""
                                onClicked: root.request({
                                    operation: "set_power_profile",
                                    profile: modelData
                                })
                            }
                        }
                        Text {
                            text: root.listAvailable(root.model.themes) ? "OMARCHY THEME" : "OMARCHY THEME  ·  UNAVAILABLE"
                            textFormat: Text.PlainText
                            color: root.listAvailable(root.model.themes) ? root.theme.accent : root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                        Repeater {
                            model: root.model.themes || []
                            DashboardButton {
                                required property string modelData
                                theme: root.theme
                                width: drawerContent.width
                                label: modelData
                                selected: modelData === root.model.theme
                                enabled: root.actionable && root.pendingRequest === ""
                                onClicked: root.request({
                                    operation: "set_theme",
                                    name: modelData
                                })
                            }
                        }
                    }
                }
            }
                    Text {
                        width: parent.width
                        height: implicitHeight
                        text: root.previewMode ? "PREVIEW  ·  desktop actions disabled" : root.feedback || String(root.model.detail || "Native desktop controls")
                        textFormat: Text.PlainText
                        color: root.previewMode ? root.theme.needsHelp : root.theme.textMuted
                        font.pixelSize: 18
                        wrapMode: Text.WordWrap
                    }
        }
    }
    DashboardButton {
        objectName: "desktopReviewOutcome"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        width: Math.min(320, parent.width - 36)
        height: 64
        label: "REVIEWED · RESUME"
        visible: root.unknownOutcome
        enabled: root.canReviewOutcome
        theme: root.theme
        z: 60
        onClicked: root.resumeReviewed()
    }
}
