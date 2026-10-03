import QtQml
import Quickshell
import Quickshell.Io

// Pending-notification count, plus the reminder count, as two integers.
//
// No notification body, summary, app name, or action is ever read. The history
// directory is only counted, and a reminder record is reduced to its count by
// its own tool before it reaches this source.
//
// The count respects do-not-disturb: when DND is on, nothing is pending for the
// user, so the pill is suppressed rather than contradicting the state it sits
// next to.
QtObject {
    id: root

    property string sourceId: "notifications"

    property var snapshot: ({
        "available": false,
        "detail": "Waiting for the first sample",
        "updatedMs": 0
    })

    readonly property bool available: snapshot.available === true

    // True only when something is actually pending and DND is not silencing it.
    readonly property bool pending: available
        && snapshot.doNotDisturb !== true
        && ((snapshot.notificationCount || 0) + (snapshot.reminderCount || 0)) > 0

    readonly property int notificationCount: available
        ? (snapshot.notificationCount || 0)
        : -1
    readonly property int reminderCount: available
        ? (snapshot.reminderCount || 0)
        : -1

    property int countedNotifications: 0
    property int countedReminders: 0
    readonly property bool suppressedByDnd: available && snapshot.doNotDisturb === true

    readonly property string historyDirectory: {
        var stateHome = String(Quickshell.env("XDG_STATE_HOME") || "")
        if (stateHome === "")
            stateHome = String(Quickshell.env("HOME") || "") + "/.local/state"
        return stateHome + "/omarchy/notifications/history"
    }

    readonly property string notificationsStatePath: {
        var stateHome = String(Quickshell.env("XDG_STATE_HOME") || "")
        if (stateHome === "")
            stateHome = String(Quickshell.env("HOME") || "") + "/.local/state"
        return stateHome + "/omarchy/notifications.json"
    }

    // The DND flag the indicator service publishes. Read as a file; never written.
    property var doNotDisturb: false
    property FileView dndState: FileView {
        path: root.notificationsStatePath
        watchChanges: true
        printErrors: false
        onLoaded: root.readDnd(root.dndState.text())
    }

    function readDnd(text) {
        var match = String(text || "").match(/"dnd"\\s*:\\s*(true|false)/)
        root.doNotDisturb = match !== null && match[1] === "true"
    }

    // Counting files never reads their contents.
    property Process historyCount: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                var text = String(line === undefined || line === null ? "" : line).trim()
                var number = Number(text)
                if (Number.isFinite(number))
                    root.countedNotifications = number
            }
        }
        onExited: function(exitCode) {
            root.historyCount.running = false
            root.historyWatchdog.stop()
            root.readReminders()
        }
    }

    property Timer historyWatchdog: Timer {
        interval: 6000
        repeat: false
        onTriggered: {
            if (root.historyCount.running)
                root.historyCount.running = false
            root.readReminders()
        }
    }

    // The reminder tool reduces its own record to JSON; only the count is kept.
    property Process reminders: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                root.reminderText = String(line === undefined || line === null ? "" : line)
            }
        }
        onExited: function(exitCode) {
            root.reminders.running = false
            root.reminderWatchdog.stop()
            root.finish(Number(exitCode))
        }
    }

    property string reminderText: ""

    property Timer reminderWatchdog: Timer {
        interval: 6000
        repeat: false
        onTriggered: {
            if (root.reminders.running)
                root.reminders.running = false
            root.finish(-1)
        }
    }

    property Timer poll: Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    property bool sampling: false

    function sample() {
        if (root.sampling)
            return
        root.sampling = true
        root.reminderText = ""
        root.historyCount.command = [
            "/usr/bin/find", root.historyDirectory,
            "-maxdepth", "1", "-name", "*.json"
        ]
        root.historyCount.running = true
        root.historyWatchdog.restart()
    }

    function readReminders() {
        if (root.reminders.running)
            return
        root.reminders.command = ["/usr/bin/omarchy", "reminder", "show", "--json"]
        root.reminders.running = true
        root.reminderWatchdog.restart()
    }

    function finish(exitCode) {
        root.sampling = false
        var reminders = 0
        if (exitCode === 0) {
            var match = String(root.reminderText || "").match(/"count"\\s*:\\s*([0-9]+)/)
            if (match !== null)
                reminders = Number(match[1])
        }
        root.countedReminders = reminders
        root.snapshot = {
            "available": true,
            "detail": "",
            "updatedMs": Date.now(),
            "notificationCount": root.countedNotifications,
            "reminderCount": reminders,
            "doNotDisturb": root.doNotDisturb
        }
    }
}
