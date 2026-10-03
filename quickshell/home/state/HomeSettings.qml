import QtQml
import QtCore
import Quickshell

// QSettings requires an application identity before it will open. This runs
// when this file is loaded, which is before the Settings object below is
// constructed. The Settings location stays explicit, so the identity
// only has to exist rather than name anything real.
// MVP preferences, persisted through Qt Settings in the user's runtime state
// directory. The location is overridable so the preview harness can be pointed
// at a throwaway file and never touches the installed configuration.
QtObject {
    id: root

    // The location is explicit and overridable, so the preference file lands
    // exactly where the harness asks and nowhere else.
    readonly property string settingsPath: {
        var configured = String(Quickshell.env("XENEON_HOME_SETTINGS_PATH") || "")
        if (configured !== "")
            return configured
        var runtimeDirectory = String(Quickshell.env("XDG_RUNTIME_DIR") || "")
        return runtimeDirectory === ""
            ? "/dev/null"
            : runtimeDirectory + "/xeneon-home-settings.ini"
    }

    // QSettings refuses to open without an application identity. It is set
    // here, in the root object of this file, which is constructed before the
    // Settings object below. The explicit `location` still decides where the
    // file lives, so the identity only has to exist, not be meaningful.
    property var store: Settings {
        id: settings
        location: root.settingsPath
        category: "home"
        property bool reduceMotion: false
        property bool showSeconds: false
        property bool showDate: true
        property bool showWorkspaceIndicator: true
        property bool showTray: true
        property bool showStats: true
        property string metricsStyle: "meter"
    }

    readonly property bool reduceMotion: settings.reduceMotion
    readonly property bool showSeconds: settings.showSeconds
    readonly property bool showDate: settings.showDate
    readonly property bool showWorkspaceIndicator: settings.showWorkspaceIndicator
    readonly property bool showTray: settings.showTray
    readonly property bool showStats: settings.showStats
    readonly property string metricsStyle: settings.metricsStyle

    function setReduceMotion(value) {
        settings.reduceMotion = value === true
    }

    function setShowSeconds(value) {
        settings.showSeconds = value === true
    }

    function setShowDate(value) {
        settings.showDate = value === true
    }

    function setShowWorkspaceIndicator(value) {
        settings.showWorkspaceIndicator = value === true
    }

    function setShowTray(value) {
        settings.showTray = value === true
    }

    function setShowStats(value) {
        settings.showStats = value === true
    }

    function setMetricsStyle(value) {
        var requested = String(value === null || value === undefined ? "" : value)
        settings.metricsStyle = requested === "bar" ? "bar" : "meter"
    }
}