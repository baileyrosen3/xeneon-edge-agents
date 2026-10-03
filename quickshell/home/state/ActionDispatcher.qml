import QtQml
import Quickshell
import Quickshell.Io
import "HomeActions.js" as Allowlist

// The single typed action boundary for this surface.
//
// Presentation code calls `dispatch(actionId)` or
// `dispatch(actionId, parameter)` with an enum-like identifier. It never
// supplies a command, a command string, an argument, or a keystroke. The
// identifier is resolved in HomeActions.js to either a fixed argv or a fixed
// MPRIS method name, and only then is a process started or a player called.
//
// Every accepted and every refused dispatch is logged, so an unexpected action
// from the UI is always visible in the log rather than silently ignored.
QtObject {
    id: root

    // Sources the dispatcher needs in order to validate parameters against
    // current truth: the compositor's window list and the current track.
    property var hyprland: null
    property var media: null
    property var tray: null

    readonly property var allowlist: Allowlist.actions
    readonly property var actionIds: Allowlist.actionIds
    readonly property var dockApps: Allowlist.dockApps
    readonly property var trayActions: Allowlist.trayActions
    readonly property var trayActionIds: Allowlist.trayActionIds

    property int dispatchCount: 0
    property int refusedCount: 0
    property string lastAction: ""
    property string lastOutcome: ""

    signal dispatched(string actionId, bool accepted, string detail)
    signal commandStarted(string actionId, var argv)

    property Process runner: Process {
        running: false
        onExited: function(exitCode) {
            root.runner.running = false
            root.recordExit(Number(exitCode))
        }
    }

    property string runningAction: ""
    property var runningArgv: null

    // Every dispatch enters here.
    function dispatch(actionId, parameter) {
        var id = String(actionId === null || actionId === undefined ? "" : actionId)

        if (Allowlist.trayActionIds.indexOf(id) !== -1)
            return dispatchTray(id, parameter)

        if (!Allowlist.has(id))
            return refuse(id, "Action is not allowlisted")

        var result = Allowlist.plan(id, parameter, actionContext())
        if (result === null || (result.argv === undefined && result.method === undefined))
            return refuse(id, result === null ? "Action is not allowlisted" : String(result.error))

        if (result.method !== undefined)
            return dispatchMedia(id, String(result.method), result.parameter)

        return dispatchCommand(id, result.argv)
    }

    // Tray activation, resolved against the ids the tray currently publishes.
    function dispatchTray(actionId, itemId) {
        var result = Allowlist.planTray(actionId, itemId, trayContext())
        if (result.method === undefined)
            return refuse(actionId, String(result.error))

        var item = trayItemFor(result.id)
        if (item === null)
            return refuse(actionId, "Tray item is not in the current snapshot")

        try {
            if (result.method === "activate")
                item.activate(0, 0)
            else
                item.secondaryActivate(0, 0)
        } catch (error) {
            return refuse(actionId, "Tray item rejected the activation")
        }

        root.log("dispatch " + actionId + " -> tray." + result.method, true)
        return true
    }

    function trayItemFor(itemId) {
        if (root.tray === null || root.tray === undefined)
            return null
        for (var index = 0; index < root.tray.items.length; index += 1) {
            var item = root.tray.items[index]
            if (item !== null && item !== undefined && String(item.id || "") === String(itemId))
                return item
        }
        return null
    }

    // Context used only to validate parameters. Nothing from here is ever
    // concatenated into a command; it decides accept or refuse.
    function actionContext() {
        return {
            "windows": root.hyprland && root.hyprland.available
                ? root.hyprland.windowAddresses
                : [],
            "lengthSeconds": root.media && root.media.available
                ? root.media.lengthSeconds
                : -1
        }
    }

    function trayContext() {
        return {
            "entries": root.tray === null || root.tray === undefined
                ? []
                : root.tray.entries
        }
    }

    // Context used only to validate a parameter. Nothing from here is ever
    // concatenated into a command; it decides accept or refuse.
    function dispatchCommand(actionId, argv) {
        if (!Array.isArray(argv) || argv.length === 0)
            return refuse(actionId, "Resolved command is empty")

        if (!root.isAvailable(actionId))
            return refuse(actionId, executableName(actionId) + " is not installed")

        if (root.runner.running)
            return refuse(actionId, "Another action is already running")

        root.runningAction = actionId
        root.runningArgv = argv
        root.log("dispatch " + actionId + " -> " + argv.join(" "), true)
        commandStarted(actionId, argv)
        root.runner.command = argv
        root.runner.running = true
        return true
    }

    // A fixed MPRIS method name, resolved through the allowlist and called only
    // when the active player advertises the matching capability.
    function dispatchMedia(actionId, method, parameter) {
        var player = root.media && root.media.available ? root.media.player : null
        if (player === null)
            return refuse(actionId, "No MPRIS player is active")

        if (!root.playerAllows(player, method))
            return refuse(actionId, "Player does not allow " + method)

        try {
            if (method === "seek")
                player.seek(Number(parameter))
            else
                player[method]()
        } catch (error) {
            return refuse(actionId, "Player rejected " + method)
        }

        root.log("dispatch " + actionId + " -> mpris." + method, true)
        return true
    }

    function playerAllows(player, method) {
        if (method === "next")
            return player.canGoNext === true
        if (method === "previous")
            return player.canGoPrevious === true
        if (method === "play")
            return player.canPlay === true
        if (method === "pause")
            return player.canPause === true || (player.canTogglePlaying === true && player.isPlaying !== true)
        if (method === "togglePlaying")
            return player.canTogglePlaying === true
        if (method === "stop")
            return player.canStop === true
        if (method === "seek")
            return player.canSeek === true
        return false
    }

    // Presence is probed once per action id with `/usr/bin/test -x`, whose
    // only argument is an absolute path taken from the allowlist table. A tool
    // that is not installed is reported as unavailable rather than dispatched
    // and silently failing.
    property var presenceQueue: []
    property string probingAction: ""

    // A path the table declares but this host does not have. The dock reads
    // this so a tile can be shown disabled instead of pretending to launch.
    readonly property var unavailableActions: unavailableList()

    function unavailableList() {
        var missing = []
        for (var index = 0; index < root.actionIds.length; index += 1) {
            var id = root.actionIds[index]
            if (Object.prototype.hasOwnProperty.call(root.presence, id)
                    && root.presence[id] === false)
                missing.push(id)
        }
        return missing
    }

    // Deliberately not a property binding: the probe writes into the same map
    // it reads, so a binding here would be self-referential.
    // Presence is a writable property that is only ever written by the probe
    // pipeline, and it is always *reassigned* rather than mutated in place.
    // That is what makes a settled probe a normal notifiable change for every
    // tile that reads it, instead of a binding loop. It is seeded at
    // construction so the first frame is already correct.
    property var presence: ({
        "launch.terminal": true,
        "launch.files": true,
        "launch.browser": true,
        "launch.spotify": true,
        "launch.terminal_alt": true,
        "workspace.focus": true,
        "window.focus": true,
        "media.toggle": true,
        "media.play": true,
        "media.pause": true,
        "media.next": true,
        "media.previous": true,
        "media.seek": true,
        "audio.mute": true,
        "audio.volume_up": true,
        "audio.volume_down": true,
        "toggle.idle": true,
        "toggle.notification_silencing": true,
        "toggle.nightlight": true
    })

    // Whether an action's executable is installed. This is a *pure read*: it
    // never queues a probe and never writes. Every entry is seeded by
    // `probeAll` at start-up, so a binding on this result can only be
    // invalidated by the probe pipeline, never by evaluating itself.
    function isAvailable(actionId) {
        var id = String(actionId === null || actionId === undefined ? "" : actionId)
        return root.presence[id] === true
    }

    // Seeds one entry as available and queues its probe. Seeding is optimistic
    // because every table entry is an absolute path the target distribution
    // ships; a refusal is corrected the moment the probe exits. Only start-up
    // calls this, never a binding.
    function queueProbe(actionId) {
        var executable = Allowlist.executableFor(actionId)
        if (executable === "" || !/^\/[A-Za-z0-9._\/-]+$/.test(executable))
            return false

        if (!Object.prototype.hasOwnProperty.call(root.presence, actionId)) {
            var seeded = Object.assign({}, root.presence)
            seeded[actionId] = true
            root.presence = seeded
            root.presenceQueue.push(actionId)
            root.runNextProbe()
        }
        return true
    }

    function runNextProbe() {
        if (root.presenceRunner.running || root.presenceQueue.length === 0)
            return
        var actionId = root.presenceQueue[0]
        root.presenceQueue = root.presenceQueue.slice(1)
        root.probingAction = actionId
        root.presenceRunner.command = ["/usr/bin/test", "-x", Allowlist.executableFor(actionId)]
        root.presenceRunner.running = true
    }

    function finishProbe(exitCode) {
        var actionId = root.probingAction
        root.probingAction = ""
        if (actionId !== "") {
            // Reassigned rather than mutated in place, so every binding that
            // reads presence is notified once, after the write is complete.
            var updated = Object.assign({}, root.presence)
            updated[actionId] = Number(exitCode) === 0
            root.presence = updated
        }
        root.runNextProbe()
    }

    property Process presenceRunner: Process {
        running: false
        onExited: function(exitCode) {
            root.presenceRunner.running = false
            root.finishProbe(Number(exitCode))
        }
    }

    // Seeds and probes every declared action once at start-up, so the dock
    // renders a truthful available state from the first frame onward.
    function probeAll() {
        for (var index = 0; index < root.actionIds.length; index += 1)
            root.queueProbe(root.actionIds[index])
    }


    function recordExit(exitCode) {
        var actionId = root.runningAction
        root.runningAction = ""
        root.runningArgv = null
        if (actionId === "")
            return
        if (exitCode === 0)
            root.accept(actionId, "Command completed")
        else
            root.refuse(actionId, "Command exited with status " + exitCode)
    }

    function accept(actionId, detail) {
        dispatchCount += 1
        lastAction = actionId
        lastOutcome = detail
        dispatched(actionId, true, detail)
        log("accepted " + actionId + ": " + detail, true)
    }

    function refuse(actionId, detail) {
        refusedCount += 1
        lastAction = actionId
        lastOutcome = String(detail)
        dispatched(actionId, false, lastOutcome)
        log("refused " + actionId + ": " + lastOutcome, false)
        return false
    }

    function executableName(actionId) {
        var executable = Allowlist.executableFor(actionId)
        var parts = executable.split("/")
        return parts[parts.length - 1]
    }

    function labelFor(actionId) {
        return Allowlist.labelFor(actionId)
    }

    function log(message, accepted) {
        var line = "xeneon-home[action] " + String(message)
        if (accepted)
            console.log(line)
        else
            console.warn(line)
    }
}