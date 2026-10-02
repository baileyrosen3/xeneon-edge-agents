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
    property int dashboardIndex: preferences.dashboardIndex === 1 ? 1 : 0
    property bool monitorSettingsOpen: false
    readonly property bool effectiveReducedMotion: reducedMotion || preferences.reduceMotion === true
    function selectDashboard(index) {
        dashboardIndex = index === 1 ? 1 : 0;
        activity.noteUserActivity();
        if (preferences.dashboardIndex !== undefined) {
            preferences.dashboardIndex = dashboardIndex;
            if (typeof preferences.sync === "function")
                preferences.sync();
        }
    }
    clip: true
    Rectangle {
        anchors.fill: parent
        color: root.theme.canvas
    }
    Item {
        id: dashboards
        objectName: "dashboardPages"
        width: root.width * 2
        height: root.height - switcher.height
        enabled: !root.monitorSettingsOpen
        x: -root.dashboardIndex * root.width
        Behavior on x {
            NumberAnimation {
                duration: root.effectiveReducedMotion ? 0 : 260
                easing.type: Easing.OutCubic
            }
        }
        Item {
            id: desktopDashboard
            objectName: "omarchyAgentDashboard"
            width: root.width
            height: parent.height
            enabled: root.dashboardIndex === 0
            PortalView {
                id: agents
                objectName: "combinedAgentPortal"
                width: desktopDashboard.width - 720
                height: parent.height
                store: root.store
                bridge: root.bridge
                activity: root.activity
                preferences: root.preferences
                theme: root.theme
                sourceTheme: root.sourceTheme
                reducedMotion: root.effectiveReducedMotion || root.dashboardIndex !== 0
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
            OmarchyControls {
                objectName: "omarchyControlPanel"
                anchors.right: parent.right
                width: 720
                height: parent.height
                store: root.store
                bridge: root.bridge
                activity: root.activity
                theme: root.theme
                previewMode: root.previewMode
                headerActionWidth: 194
                onMonitorRequested: root.monitorSettingsOpen = true
            }
        }
        RiptideDashboard {
            id: trading
            objectName: "riptideDashboard"
            x: root.width
            width: root.width
            height: parent.height
            enabled: root.dashboardIndex === 1
            store: root.store
            bridge: root.bridge
            activity: root.activity
            theme: root.theme
            previewMode: root.previewMode
            headerActionWidth: 194
        }
    }
    DashboardButton {
        objectName: "globalMonitorButton"
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: 14
        width: 180
        height: 44
        theme: root.theme
        label: monitorSettings.pendingRequest !== "" ? "MONITOR · BUSY" : "MONITOR"
        selected: root.monitorSettingsOpen
        enabled: !root.monitorSettingsOpen
        onClicked: {
            root.activity.noteUserActivity()
            root.monitorSettingsOpen = true
        }
    }
    DashboardSwitcher {
        id: switcher
        objectName: "dashboardSwitcher"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 64
        theme: root.theme
        currentIndex: root.dashboardIndex
        reducedMotion: root.effectiveReducedMotion
        enabled: !root.monitorSettingsOpen
        onSelected: function (index) {
            root.selectDashboard(index);
        }
    }
    MonitorSettings {
        id: monitorSettings
        objectName: "monitorSettings"
        anchors.fill: parent
        anchors.bottomMargin: switcher.height
        store: root.store
        bridge: root.bridge
        activity: root.activity
        theme: root.theme
        previewMode: root.previewMode
        reducedMotion: root.effectiveReducedMotion
        open: root.monitorSettingsOpen
        onCloseRequested: root.monitorSettingsOpen = false
    }
}
