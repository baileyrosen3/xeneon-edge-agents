pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    required property var store
    required property var bridge
    required property var activity
    required property var preferences
    required property var theme
    property var sourceTheme: theme
    property bool reducedMotion: false
    property bool previewMode: false
    property bool restoreVoiceFocus: false
    property bool previewMicroOpen: false
    property string hostName: "LOCAL"
    // Leave room for the rail without reducing compact agent-card readability.
    readonly property int agentControlsWidth: 704
    readonly property var presets: [
        {label: "AGENT DASHBOARD", detail: "Agents + desktop controls"},
        {label: "TRADING DASHBOARD", detail: "Riptide accounts + order ticket"},
        {label: "DESKTOP CONTROLS", detail: "PC health + quick actions"},
        {label: "SYSTEM DETAILS", detail: "Storage + processes + network"},
        {label: "AUDIO / DISPLAY", detail: "Audio outputs + monitor access"},
        {label: "THEME / POWER", detail: "Omarchy themes + power profiles"},
        {label: "AI USAGE", detail: "Provider capacity + fleet status"},
        {label: "AGENT RADAR", detail: "Live agent constellation"},
        {label: "PALETTE SETTINGS", detail: "Agent-state color mappings"}
    ]
    property int dashboardIndex: validIndex(preferences.dashboardIndex)
        ? preferences.dashboardIndex : 0
    property bool sidebarOpen: false
    property bool monitorSettingsOpen: false
    property Item monitorReturnFocus: null
    property bool monitorFocusPending: false
    readonly property bool effectiveReducedMotion: reducedMotion || preferences.reduceMotion === true

    function validIndex(index) {
        return Number.isInteger(index) && index >= 0 && index < presets.length;
    }
    function selectDashboard(index) {
        if (!validIndex(index) || monitorSettingsOpen)
            return false;
        dashboardIndex = index;
        sidebarOpen = false;
        activity.noteUserActivity();
        if (preferences.dashboardIndex !== undefined) {
            preferences.dashboardIndex = dashboardIndex;
            if (typeof preferences.sync === "function")
                preferences.sync();
        }
        return true;
    }
    function openMonitor() {
        activity.noteUserActivity();
        monitorSettingsOpen = true;
    }
    onMonitorSettingsOpenChanged: {
        if (monitorSettingsOpen) {
            monitorReturnFocus = root.Window.window ? root.Window.window.activeFocusItem : null;
            monitorFocusPending = true;
            sidebarOpen = false;
        }
    }
    function restoreMonitorFocus() {
        if (!monitorFocusPending || monitorSettingsOpen || monitorSettings.visible)
            return;
        if (monitorReturnFocus && monitorReturnFocus.enabled && monitorReturnFocus.visible)
            monitorReturnFocus.forceActiveFocus(Qt.OtherFocusReason);
        else
            sidebar.restoreFocus();
        monitorReturnFocus = null;
        monitorFocusPending = false;
    }

    clip: true
    Rectangle {
        anchors.fill: parent
        color: root.theme.canvas
    }
    Item {
        id: dashboards
        objectName: "dashboardPages"
        x: Math.min(64, root.width)
        width: Math.max(0, root.width - x)
        height: root.height
        enabled: !sidebar.blocking && !monitorSettings.visible

        Item {
            objectName: "omarchyAgentDashboard"
            anchors.fill: parent
            visible: root.dashboardIndex === 0
            enabled: visible
            PortalView {
                id: agents
                objectName: "combinedAgentPortal"
                width: Math.max(0, parent.width - root.agentControlsWidth)
                height: parent.height
                store: root.store
                bridge: root.bridge
                activity: root.activity
                preferences: root.preferences
                theme: root.theme
                sourceTheme: root.sourceTheme
                reducedMotion: root.reducedMotion || root.dashboardIndex !== 0
                previewMode: root.previewMode
                restoreVoiceFocus: root.restoreVoiceFocus
                previewMicroOpen: root.previewMicroOpen
                hostName: root.hostName
                compactLayout: true
            }
            Rectangle {
                x: agents.width
                width: 1
                height: parent.height
                color: root.theme.borderStrong
            }
        }
        OmarchyControls {
            id: omarchyControls
            objectName: "omarchyControlPanel"
            x: root.dashboardIndex === 0 ? dashboards.width - width
                : (dashboards.width - width) / 2
            width: root.dashboardIndex === 0 ? root.agentControlsWidth : 1200
            height: parent.height
            visible: root.dashboardIndex === 0
                || root.dashboardIndex >= 2 && root.dashboardIndex <= 5
            enabled: visible
            preset: root.dashboardIndex === 3 ? "system"
                : root.dashboardIndex === 4 ? "audio"
                : root.dashboardIndex === 5 ? "desktop" : "overview"
            store: root.store
            bridge: root.bridge
            activity: root.activity
            theme: root.theme
            previewMode: root.previewMode
            onMonitorRequested: root.openMonitor()
            onPresetRequested: function(index) { root.selectDashboard(index); }
        }
        RiptideDashboard {
            objectName: "riptideDashboard"
            anchors.fill: parent
            visible: root.dashboardIndex === 1
            enabled: visible
            store: root.store
            bridge: root.bridge
            activity: root.activity
            theme: root.theme
            previewMode: root.previewMode
        }
        Item {
            objectName: "aiUsageDashboard"
            anchors.fill: parent
            visible: root.dashboardIndex === 6
            enabled: visible
            Column {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 96)
                spacing: 24
                Text {
                    text: "AI USAGE // PROVIDER CAPACITY  ·  " + root.store.agents.length + " AGENTS"
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font.family: "monospace"
                    font.pixelSize: 32
                    font.weight: Font.Bold
                }
                AiUsageDock {
                    objectName: "presetAiUsage"
                    width: parent.width
                    height: 360
                    expanded: true
                    usage: root.store.usage
                    agents: root.store.agents
                    sessions: root.store.sessions
                    managerLabel: String((root.store.backend || {}).mode) === "t3code"
                        ? "T3 CODE" : "HERDR"
                    theme: root.theme
                    reducedMotion: root.effectiveReducedMotion || root.dashboardIndex !== 6
                }
                Text {
                    width: parent.width
                    text: "Read-only provider projections · unavailable and stale readings remain explicit."
                    textFormat: Text.PlainText
                    color: root.theme.textMuted
                    font.family: "monospace"
                    font.pixelSize: 22
                    wrapMode: Text.WordWrap
                }
            }
        }
        Item {
            id: radarPage
            objectName: "agentRadarDashboard"
            anchors.fill: parent
            visible: root.dashboardIndex === 7
            enabled: visible
            AmbientView {
                anchors.fill: parent
                active: radarPage.visible
                radarMode: true
                agents: root.store.agents
                health: root.store.health
                voice: root.store.voice
                connectionState: String(root.store.connection.state || "reconnecting")
                theme: root.theme
                reducedMotion: root.effectiveReducedMotion || !radarPage.visible
                onWakeRequested: root.selectDashboard(0)
            }
        }
        Item {
            objectName: "paletteDashboard"
            anchors.fill: parent
            visible: root.dashboardIndex === 8
            enabled: visible
            PaletteSettingsPane {
                anchors.centerIn: parent
                open: root.dashboardIndex === 8
                preferences: root.preferences
                sourceTheme: root.sourceTheme
                theme: root.theme
                onCloseRequested: root.selectDashboard(0)
                onInteractionOccurred: root.activity.noteUserActivity()
            }
        }
    }
    DashboardSidebar {
        id: sidebar
        objectName: "dashboardSidebar"
        anchors.fill: parent
        theme: root.theme
        presets: root.presets
        currentIndex: root.dashboardIndex
        open: root.sidebarOpen
        reducedMotion: root.effectiveReducedMotion
        monitorBusy: monitorSettings.pendingRequest !== ""
        visible: !monitorSettings.visible
        enabled: visible
        onOpenRequested: function (value) {
            root.sidebarOpen = value;
        }
        onSelected: function (index) {
            root.selectDashboard(index);
        }
        onMonitorRequested: root.openMonitor()
        onInteractionOccurred: root.activity.noteUserActivity()
    }
    MonitorSettings {
        id: monitorSettings
        objectName: "monitorSettings"
        anchors.fill: parent
        store: root.store
        bridge: root.bridge
        activity: root.activity
        theme: root.theme
        previewMode: root.previewMode
        reducedMotion: root.effectiveReducedMotion
        open: root.monitorSettingsOpen
        onCloseRequested: root.monitorSettingsOpen = false
        onVisibleChanged: {
            if (!visible)
                Qt.callLater(root.restoreMonitorFocus);
        }
    }
}
