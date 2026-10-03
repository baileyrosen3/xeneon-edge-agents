import QtQml
import Quickshell
import Quickshell.Io
import "SourceParse.js" as Parse

// Resolves a real application icon path for a desktop entry's `Icon` key.
//
// Quickshell's `iconPath` consults the running theme's icon directories. That
// is the correct first choice and is used whenever it answers. It returns an
// empty string when the theme does not carry the icon, so this falls back to
// walking the standard hicolor directories directly, which is the same lookup a
// desktop environment performs.
//
// Only an icon *name* from a fixed desktop entry is ever resolved, and the
// result is an existing file path. Nothing here executes anything or accepts a
// path from a caller.
QtObject {
    id: root

    // Absolute directories searched in order, mirroring the icon theme spec's
    // preference order. Larger icons are tried first because a 256px icon
    // downscales far better than a 16px one upscales on this panel.
    readonly property var searchPaths: [
        { "dir": "/usr/share/icons/hicolor/scalable/apps", "exts": ["svg", "png"] },
        { "dir": "/usr/share/icons/hicolor/256x256/apps", "exts": ["png", "svg"] },
        { "dir": "/usr/share/icons/hicolor/128x128/apps", "exts": ["png", "svg"] },
        { "dir": "/usr/share/pixmaps", "exts": ["png", "svg", "xpm"] }
    ]

    // Resolved paths, keyed by icon name. Reassigned on every hit so a binding
    // on a resolved icon re-evaluates.
    property var resolved: ({})

    // The theme's answers, seeded synchronously at start-up.
    property var themedPaths: ({})

    // Icons the theme could not answer for, waiting on the filesystem walk.
    property var walkQueue: []

    // A single in-flight probe. One FileView is enough because resolution is
    // a walk, not a fan-out.
    property string pendingIcon: ""
    property string pendingName: ""
    property int pendingIndex: 0

    property FileView probe: FileView {
        preload: false
        blockLoading: true
        printErrors: false
        path: ""
        onLoaded: root.recordProbe(true)
        onLoadFailed: root.recordProbe(false)
    }

    // Pure read: never starts a walk, never writes. A binding on this result can
    // therefore only be invalidated by the walk pipeline, never by evaluating
    // itself, which is what keeps a dock tile out of a binding loop.
    //
    // `themedPaths` is seeded synchronously for every allowlisted entry, so the
    // common case resolves on the first frame with no walk at all.
    function pathFor(iconName) {
        var name = String(iconName === null || iconName === undefined ? "" : iconName).trim()
        if (name === "")
            return ""
        if (Object.prototype.hasOwnProperty.call(root.resolved, name))
            return String(root.resolved[name])
        return String(root.themedPaths[name] === undefined ? "" : root.themedPaths[name])
    }

    // One synchronous sweep of the theme lookup for every entry the dock draws.
    // Anything the theme cannot answer for is queued for the filesystem walk.
    function resolveAll() {
        var themed = ({})
        var queue = []
        var entries = root.entryIcons
        for (var key in entries) {
            if (!Object.prototype.hasOwnProperty.call(entries, key))
                continue
            var name = String(entries[key])
            if (name === "")
                continue
            var path = Quickshell.iconPath(name, true)
            if (String(path || "") !== "")
                themed[name] = String(path)
            else
                queue.push(name)
        }
        root.themedPaths = themed
        root.walkQueue = queue
        root.walkNext()
    }

    // Walks one queued icon at a time, one candidate file at a time.
    function walkNext() {
        if (root.pendingName !== "" || root.walkQueue.length === 0)
            return
        var name = String(root.walkQueue[0])
        var entry = root.searchPaths[0]
        if (entry === undefined)
            return
        root.tryExtension(entry, 0, 0, name)
    }

    function tryExtension(entry, offset, index, name) {
        if (offset >= entry.exts.length) {
            if (index + 1 >= root.searchPaths.length)
                root.dequeue(name)
            else
                root.tryExtension(root.searchPaths[index + 1], 0, index + 1, name)
            return
        }
        root.pendingIcon = entry.dir + "/" + name + "." + entry.exts[offset]
        root.pendingName = name
        root.pendingIndex = index
        root.probe.path = root.pendingIcon
    }

    function recordProbe(found) {
        var candidate = root.pendingIcon
        var name = root.pendingName
        var index = root.pendingIndex
        root.pendingIcon = ""
        root.pendingName = ""

        if (found) {
            var updated = Object.assign({}, root.resolved)
            updated[name] = candidate
            root.resolved = updated
            root.dequeue(name)
            return
        }

        var entry = root.searchPaths[index]
        if (entry === undefined) {
            root.dequeue(name)
            return
        }
        root.tryExtension(entry, 1, index, name)
    }

    // An icon with no installed file is simply absent; it falls back to the
    // monogram. The queue moves on rather than retrying forever.
    function dequeue(name) {
        root.walkQueue = root.walkQueue.filter(function(entry) {
            return String(entry) !== String(name)
        })
        root.walkNext()
    }

    // The `Icon=` key each allowlisted launcher actually publishes, read from
    // the installed desktop files. These are confirmed names, not guesses.
    readonly property var entryIcons: ({
        "launch.terminal": "foot",
        "launch.browser": "chromium",
        "launch.files": "org.gnome.Nautilus",
        "launch.spotify": "spotify-client",
        "launch.terminal_alt": "foot"
    })

    function iconFor(actionId) {
        return root.pathFor(root.entryIcons[String(actionId)])
    }

    Component.onCompleted: root.resolveAll()
}