.pragma library

// The single allowlist table for every action this surface can perform.
//
// Presentation code never supplies a command, an argument string, or a
// keystroke. It supplies a typed identifier plus a small number of typed
// parameters. Each identifier resolves here to a fixed argv whose executable
// and argument shape are decided in code. A `parameter` descriptor declares how
// the one permitted substitution is validated before it reaches argv; any
// value that fails validation is rejected and never formatted into a command.
//
// Three parameter kinds exist and no others:
//   none      no substitution is permitted
//   workspace a bounded integer workspace id
//   window    a window address that must already appear in the most recent
//             HyprlandSource snapshot
//   position  a bounded non-negative millisecond media position
//
// `checked` marks an entry whose executable must be probed once per process
// with a fixed `probe` argv; an entry that is not present on the host reports
// unavailable rather than reporting zero.

var workspaceMinimum = 1
var workspaceMaximum = 20

var actions = {
    "launch.terminal": {
        "kind": "launch",
        "detached": true,
        "label": "Terminal",
        "command": ["/usr/bin/foot"]
    },
    "launch.files": {
        "kind": "launch",
        "detached": true,
        "label": "Files",
        "command": ["/usr/bin/nautilus"]
    },
    "launch.browser": {
        "kind": "launch",
        "detached": true,
        "label": "Browser",
        "command": ["/usr/bin/chromium"]
    },
    "launch.spotify": {
        "kind": "launch",
        "detached": true,
        "label": "Spotify",
        "command": ["/usr/bin/spotify"]
    },
    "launch.terminal_alt": {
        "kind": "launch",
        "detached": true,
        "label": "Alt Terminal",
        "command": ["/usr/bin/foot", "-T", "xterm-256color"]
    },

    "workspace.focus": {
        "kind": "workspace",
        "label": "Focus workspace",
        "command": ["/usr/bin/hyprctl", "dispatch", "workspace", "0"],
        "parameter": "workspace"
    },
    "window.focus": {
        "kind": "workspace",
        "label": "Focus window",
        "command": ["/usr/bin/hyprctl", "dispatch", "focuswindow", "address:0x0"],
        "parameter": "window"
    },

    "media.toggle": {
        "kind": "media",
        "label": "Play or pause",
        "handler": "togglePlaying"
    },
    "media.play": {
        "kind": "media",
        "label": "Play",
        "handler": "play"
    },
    "media.pause": {
        "kind": "media",
        "label": "Pause",
        "handler": "pause"
    },
    "media.next": {
        "kind": "media",
        "label": "Next track",
        "handler": "next"
    },
    "media.previous": {
        "kind": "media",
        "label": "Previous track",
        "handler": "previous"
    },
    "media.seek": {
        "kind": "media",
        "label": "Seek",
        "handler": "seek",
        "parameter": "position"
    },

    "audio.mute": {
        "kind": "audio",
        "label": "Mute",
        "command": ["/usr/bin/pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"],
        "checked": true
    },
    "audio.volume_up": {
        "kind": "audio",
        "label": "Volume up",
        "command": ["/usr/bin/pactl", "set-sink-volume", "@DEFAULT_SINK@", "+5%"],
        "checked": true
    },
    "audio.volume_down": {
        "kind": "audio",
        "label": "Volume down",
        "command": ["/usr/bin/pactl", "set-sink-volume", "@DEFAULT_SINK@", "-5%"],
        "checked": true
    },

    "toggle.idle": {
        "kind": "desktop",
        "label": "Stay awake",
        "command": ["/usr/bin/omarchy", "toggle", "idle", "toggle"],
        "checked": true,
        "probe": ["/usr/bin/omarchy", "toggle", "idle", "--status"]
    },
    "toggle.notification_silencing": {
        "kind": "desktop",
        "label": "Do not disturb",
        "command": ["/usr/bin/omarchy", "toggle", "notification", "silencing"],
        "checked": true,
        "probe": ["/usr/bin/omarchy", "toggle", "notification", "silencing", "--status"]
    },
    "toggle.nightlight": {
        "kind": "desktop",
        "label": "Nightlight",
        "command": ["/usr/bin/omarchy", "toggle", "nightlight", "toggle"],
        "checked": true,
        "probe": ["/usr/bin/omarchy", "toggle", "nightlight", "--status"]
    }
}

// Tray activation is a fourth action kind. There is no command for it: the
// dispatcher resolves a typed `tray.*` identifier against the current tray
// snapshot and calls the status-notifier item's own activate method. The
// parameter must match an id the tray has already published, so a caller
// cannot name an item that is not present.
var trayActions = {
    "tray.activate": { "label": "Activate tray item", "method": "activate" },
    "tray.secondary": { "label": "Secondary tray action", "method": "secondaryActivate" }
}

var trayActionIds = Object.keys(trayActions).sort()

function validTrayMethod(name) {
    var text = String(name === null || name === undefined ? "" : name)
    return text === "activate" || text === "secondaryActivate" ? text : null
}

// The one tray method name table the dispatcher may reach.
function planTray(actionId, itemId, context) {
    if (!Object.prototype.hasOwnProperty.call(trayActions, String(actionId || "")))
        return { "error": "Tray action is not allowlisted" }

    var method = validTrayMethod(trayActions[String(actionId)].method)
    if (method === null)
        return { "error": "Tray method is not allowlisted" }

    var wanted = String(itemId === null || itemId === undefined ? "" : itemId)
    var entries = context === null || context === undefined ? [] : (context.entries || [])
    for (var index = 0; index < entries.length; index += 1) {
        if (String(entries[index].id) === wanted && wanted !== "")
            return { "method": method, "id": wanted }
    }
    return { "error": "Tray item is not in the current snapshot" }
}

// Fixed application tiles rendered by the dock. Every tile references an
// allowlisted launch identifier; the dock cannot name a command.
var dockApps = [
    { "id": "launch.terminal", "label": "Terminal", "monogram": "Tm", "role": "accent" },
    { "id": "launch.browser", "label": "Browser", "monogram": "Br", "role": "cyan" },
    { "id": "launch.files", "label": "Files", "monogram": "Fi", "role": "orange" },
    { "id": "launch.spotify", "label": "Spotify", "monogram": "Sp", "role": "green" },
    { "id": "launch.terminal_alt", "label": "Alt Shell", "monogram": "As", "role": "magenta" }
]

var actionIds = Object.keys(actions).sort()

function has(actionId) {
    return Object.prototype.hasOwnProperty.call(actions, String(actionId || ""))
}

function entry(actionId) {
    return has(actionId) ? actions[String(actionId)] : null
}

function labelFor(actionId) {
    var record = entry(actionId)
    return record === null ? "" : String(record.label || "")
}

// A bounded integer workspace id. Anything else is refused, so no workspace
// action can carry a caller-supplied string into argv.
function validWorkspace(value) {
    var number = Number(value)
    if (!Number.isFinite(number))
        return null
    if (!Number.isInteger(number))
        return null
    if (number < workspaceMinimum || number > workspaceMaximum)
        return null
    return String(number)
}

// A window address is only ever a lowercase hex token that the compositor has
// already published in the current snapshot. A caller cannot mint one.
var addressPattern = /^0x[0-9a-f]{1,16}$/

function validAddress(value) {
    var text = String(value === null || value === undefined ? "" : value)
    return addressPattern.test(text) ? text : null
}

// A media seek position in seconds. MPRIS seek offsets are seconds, and the
// bound is the current track length so a seek can never address past the end.
function validPositionSeconds(value, lengthSeconds) {
    var number = Number(value)
    if (!Number.isFinite(number) || number < 0)
        return null
    var length = Number(lengthSeconds)
    if (Number.isFinite(length) && length > 0 && number > length)
        return null
    return Math.round(number * 1000) / 1000
}

// The only MPRIS method names this surface may ever reach. A handler is
// resolved through this set before it is called on a player object, so no
// caller-named method can cross into the media service.
var mediaMethods = [
    "togglePlaying",
    "play",
    "pause",
    "stop",
    "next",
    "previous",
    "seek"
]

function validMediaMethod(name) {
    var text = String(name === null || name === undefined ? "" : name)
    return mediaMethods.indexOf(text) === -1 ? null : text
}

// Turns one typed identifier into a fully fixed plan. Returns an object with
// exactly one of `argv` or `method`, or `error` when the request is refused.
// Nothing else crosses the boundary: no raw command string, no keystroke, and
// no caller-named method.
function plan(actionId, parameter, context) {
    // Not named `entry`: that would shadow the lookup function above and make
    // every call throw.
    var record = entry(actionId)
    if (record === null)
        return { "error": "Action is not allowlisted" }

    var kind = String(record.kind || "")
    var parameterKind = String(record.parameter || "none")

    if (parameterKind !== "none" && (parameter === undefined || parameter === null))
        return { "error": "Action requires a parameter" }
    if (parameterKind === "none" && parameter !== undefined && parameter !== null)
        return { "error": "Action takes no parameter" }

    if (kind === "media") {
        var method = validMediaMethod(record.handler)
        if (method === null)
            return { "error": "Media method is not allowlisted" }

        if (method === "seek") {
            var seconds = validPositionSeconds(parameter, context.lengthSeconds)
            if (seconds === null)
                return { "error": "Seek position is outside the current track" }
            return { "method": method, "parameter": seconds }
        }

        return { "method": method }
    }

    var command = record.command
    if (!Array.isArray(command) || command.length === 0)
        return { "error": "Action has no fixed command" }

    var argv = command.slice()
    if (parameterKind === "workspace") {
        var workspace = validWorkspace(parameter)
        if (workspace === null)
            return { "error": "Workspace id is out of range" }
        argv[argv.length - 1] = workspace
    } else if (parameterKind === "window") {
        var address = validAddress(parameter)
        if (address === null)
            return { "error": "Window address is malformed" }
        if ((context.windows || []).indexOf(address) === -1)
            return { "error": "Window address is not in the current snapshot" }
        argv[argv.length - 1] = "address:" + address
    } else if (parameterKind !== "none") {
        return { "error": "Action parameter kind is unknown" }
    }

    return { "argv": argv }
}

// The fixed probe for an entry whose executable may be absent on this host.
// Presence is decided by a fixed argv, never by a caller-supplied path.
function probeFor(actionId) {
    var record = entry(actionId)
    if (record === null)
        return null
    if (record.checked !== true)
        return null
    var probe = record.probe
    return Array.isArray(probe) && probe.length > 0 ? probe.slice() : null
}

// The absolute executable path an allowlisted entry would run, used for the
// once-per-process presence probe and for the unavailable explanation.
function executableFor(actionId) {
    // Not named `entry`: that would shadow the lookup function above.
    var record = entry(actionId)
    if (record === null || !Array.isArray(record.command) || record.command.length === 0)
        return ""
    return String(record.command[0])
}