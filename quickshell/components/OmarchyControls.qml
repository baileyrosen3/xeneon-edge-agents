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
    property string feedback: ""
    property bool drawerOpen: false
    property string drawerTab: "system"
    property real headerActionWidth: 0
    signal monitorRequested
    property var histories: ({})
    property int clockTick: 0
    readonly property var metrics: [
        {
            key: "cpu",
            label: "CPU",
            unit: "%",
            color: theme.blue
        },
        {
            key: "gpu",
            label: "GPU",
            unit: "%",
            color: theme.magenta
        },
        {
            key: "memory",
            label: "MEMORY",
            unit: "%",
            color: theme.cyan
        },
        {
            key: "cpu_temperature",
            label: "CPU TEMP",
            unit: "°C",
            color: theme.orange
        },
        {
            key: "gpu_temperature",
            label: "GPU TEMP",
            unit: "°C",
            color: theme.yellow
        },
        {
            key: "network_down",
            label: "NETWORK ↓",
            unit: "",
            color: theme.green
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
        activity.noteUserActivity();
        if (!actionable || pendingRequest !== "" || typeof bridge.omarchyAction !== "function")
            return false;
        var id = bridge.omarchyAction(payload);
        if (!id) {
            feedback = "Action unavailable";
            return false;
        }
        pendingRequest = String(id);
        feedback = "Applying…";
        return true;
    }
    function showDrawer(tab) {
        activity.noteUserActivity();
        drawerTab = tab;
        drawerOpen = true;
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
            root.feedback = result.ok === true ? "Applied" : String(result.message || result.code || "Action failed");
        }
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
        Row {
            width: parent.width
            height: 38
            Text {
                width: parent.width - 220 - root.headerActionWidth
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
                    required property var modelData
                    theme: root.theme
                    width: (root.width - 56) / 3
                    height: 86
                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        Text {
                            text: modelData.label
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                        Text {
                            text: root.metricLabel(modelData.key, modelData.unit)
                            textFormat: Text.PlainText
                            color: root.metric(modelData.key) === null ? root.theme.textMuted : root.theme.textPrimary
                            font.family: "monospace"
                            font.pixelSize: 25
                            font.weight: Font.DemiBold
                        }
                    }
                    Canvas {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 12
                        property var values: root.histories[modelData.key] || []
                        onValuesChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            if (values.length < 2)
                                return;
                            var maxValue = modelData.key.indexOf("network_") === 0 ? Math.max(1, ...values) : 100;
                            ctx.strokeStyle = String(modelData.color);
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
                        drawer: "system"
                    },
                    {
                        label: "AUDIO / DISPLAY",
                        drawer: "audio"
                    },
                    {
                        label: "THEME / POWER",
                        drawer: "desktop"
                    }
                ]
                DashboardButton {
                    required property var modelData
                    theme: root.theme
                    width: (root.width - 52) / 3
                    height: 48
                    label: modelData.label
                    selected: modelData.active === true
                    enabled: modelData.drawer !== undefined || (root.actionable && root.pendingRequest === "")
                    onClicked: {
                        if (modelData.drawer !== undefined)
                            root.showDrawer(modelData.drawer);
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
            height: 20
            text: root.previewMode ? "PREVIEW  ·  desktop actions disabled" : root.feedback || String(root.model.detail || "Native desktop controls")
            textFormat: Text.PlainText
            color: root.previewMode ? root.theme.needsHelp : root.theme.textMuted
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }
    Item {
        anchors.fill: parent
        visible: root.drawerOpen
        z: 50
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(root.theme.canvas, 0.94)
            TapHandler {}
        }
        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14
            Row {
                width: parent.width
                spacing: 12
                Text {
                    width: parent.width - 132
                    height: 48
                    text: root.drawerTab === "system" ? "SYSTEM DETAILS" : root.drawerTab === "audio" ? "AUDIO / DISPLAY" : "THEME / POWER"
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font.family: "monospace"
                    font.pixelSize: 22
                    verticalAlignment: Text.AlignVCenter
                }
                DashboardButton {
                    theme: root.theme
                    width: 120
                    label: "CLOSE"
                    onClicked: root.drawerOpen = false
                }
            }
            Flickable {
                width: parent.width
                height: root.height - 110
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
                        visible: root.drawerTab === "system"
                        Text {
                            text: "STORAGE"
                            textFormat: Text.PlainText
                            color: root.theme.accent
                            font.family: "monospace"
                            font.pixelSize: 18
                        }
                        Repeater {
                            model: root.model.storage || []
                            DashboardButton {
                                required property var modelData
                                theme: root.theme
                                width: drawerContent.width
                                height: 66
                                label: String(modelData.mount || "/")
                                detail: root.bytes(modelData.available_bytes) + " FREE / " + root.bytes(modelData.total_bytes) + "  ·  " + Number(modelData.used_percent || 0).toFixed(0) + "% USED"
                            }
                        }
                        Text {
                            text: "TOP CPU PROCESSES"
                            textFormat: Text.PlainText
                            color: root.theme.accent
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
                        visible: root.drawerTab === "audio"
                        Text {
                            text: "AUDIO OUTPUT"
                            textFormat: Text.PlainText
                            color: root.theme.accent
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
                            onClicked: { root.drawerOpen = false; root.monitorRequested() }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.drawerTab === "desktop"
                        Text {
                            text: "POWER PROFILE"
                            textFormat: Text.PlainText
                            color: root.theme.accent
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
                            text: "OMARCHY THEME"
                            textFormat: Text.PlainText
                            color: root.theme.accent
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
        }
    }
}
