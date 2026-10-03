import QtQml
import Quickshell
import Quickshell.Io
import "SourceParse.js" as Parse

// Desktop indicator state: do-not-disturb, stay-awake, nightlight, and whether
// a system update is waiting. Each reads the same `omarchy toggle <name>
// --status` probe the packaged bar indicators are built on, so the strip and
// the bar can never disagree about what is enabled.
SourceBase {
    id: root

    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "indicators"
    }

    function intervalMs() {
        return 8000
    }

    function probeList() {
        return [
            { "label": "idle", "argv": ["/usr/bin/omarchy", "toggle", "idle", "--status"] },
            { "label": "nightlight", "argv": ["/usr/bin/omarchy", "toggle", "nightlight", "--status"] },
            { "label": "updates", "argv": ["/usr/bin/omarchy-update-available"] }
        ]
    }

    // DND is owned by the notifications service rather than a toggle flag, so
    // it is read from the same JSON file that service writes.
    property var notificationsState: null
    property FileView notifications: FileView {
        path: root.notificationsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.readNotifications(root.notifications.text())
        onLoadFailed: root.readNotifications("")
    }

    readonly property string notificationsPath: {
        var home = String(Quickshell.env("HOME") || "")
        return home === "" ? "" : home + "/.local/state/omarchy/notifications.json"
    }

    readonly property bool doNotDisturb: notificationsState !== null
        && notificationsState.dnd === true
    readonly property bool dndAvailable: notificationsState !== null
    readonly property bool stayAwake: snapshot.stayAwake === true
    readonly property bool nightlight: snapshot.nightlight === true
    readonly property bool updatesAvailable: snapshot.updatesAvailable === true
    readonly property string updateDetail: snapshot.updateDetail || ""
    readonly property string nightlightDetail: snapshot.nightlightDetail || ""

    function readNotifications(text) {
        var state = Parse.parseJsonObject(text)
        notificationsState = state === null ? null : ({ "dnd": state.dnd === true })
    }

    // `omarchy toggle idle --status` reports whether idle locking is enabled;
    // the flag file it consults is the stay-awake marker, so the surface shows
    // stay-awake as the inverse.
    function parseIdleStatus(text) {
        var state = Parse.parseJsonObject(text)
        if (state === null)
            return null
        if (state.enabled === true)
            return false
        if (state.enabled === false)
            return true
        return null
    }

    function parseNightlightStatus(text) {
        var state = Parse.parseJsonObject(text)
        if (state === null)
            return null
        if (state.enabled === true)
            return true
        if (state.enabled === false)
            return false
        return null
    }

    // The update helper prints a sentence, not a code. A non-empty sentence
    // that is not the up-to-date phrasing means an update is waiting.
    function parseUpdateStatus(text) {
        var message = String(text || "").trim()
        if (message === "")
            return null
        if (message.indexOf("up to date") !== -1)
            return { "available": false, "detail": message }
        return { "available": true, "detail": message }
    }

    function ingest(results) {
        var stayAwake = null
        if (root.probeSucceeded(results, "idle"))
            stayAwake = root.parseIdleStatus(root.probeText(results, "idle"))

        var nightlight = null
        var nightlightDetail = ""
        if (root.probeSucceeded(results, "nightlight")) {
            nightlight = root.parseNightlightStatus(root.probeText(results, "nightlight"))
            var state = Parse.parseJsonObject(root.probeText(results, "nightlight"))
            if (state !== null && state.temperature !== null && state.temperature !== undefined)
                nightlightDetail = String(state.temperature)
        }

        var updates = null
        var updateDetail = ""
        if (root.probeSucceeded(results, "updates")) {
            updates = root.parseUpdateStatus(root.probeText(results, "updates"))
            if (updates !== null)
                updateDetail = updates.detail
        }

        if (stayAwake === null && nightlight === null && updates === null) {
            root.publishUnavailable("No Omarchy indicator reported a status")
            return
        }

        root.publish({
            "stayAwake": stayAwake,
            "nightlight": nightlight,
            "nightlightDetail": nightlightDetail,
            "updatesAvailable": updates !== null && updates.available,
            "updateDetail": updateDetail
        })
    }
}