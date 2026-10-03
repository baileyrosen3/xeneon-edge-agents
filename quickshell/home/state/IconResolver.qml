import QtQuick
import Quickshell
import Quickshell.Io

// Resolves the real application icon for each allowlisted launcher.
//
// Quickshell's `iconPath` consults the running theme and is tried first. When
// the theme cannot answer, the standard hicolor directories are listed once
// each with a fixed `ls` argv and the wanted names are matched against those
// listings in JavaScript.
//
// Listing a directory rather than probing one file per candidate is deliberate:
// probing relies on a miss being reported, and a missing-file read that never
// reports leaves the walk stalled forever. A listing always arrives, so the
// resolution is deterministic and always terminates.
//
// Nothing here executes anything, and no name comes from a caller: the set of
// icons is the fixed table at the bottom of this file.
QtObject {
    id: root

    // Absolute directories in preference order. Larger icons come first because
    // a 256px icon downscales far better than a 16px one upscales on this
    // panel.
    readonly property var searchPaths: [
        "/usr/share/icons/hicolor/scalable/apps",
        "/usr/share/icons/hicolor/256x256/apps",
        "/usr/share/icons/hicolor/128x128/apps",
        "/usr/share/icons/hicolor/64x64/apps",
        "/usr/share/icons/hicolor/48x48/apps",
        "/usr/share/icons/hicolor/32x32/apps",
        "/usr/share/pixmaps"
    ]

    readonly property var preferredExtensions: ["svg", "png", "xpm"]

    // The `Icon=` key each allowlisted launcher publishes, read from the
    // installed desktop files rather than guessed.
    readonly property var entryIcons: ({
        "launch.terminal": "foot",
        "launch.browser": "chromium",
        "launch.files": "org.gnome.Nautilus",
        "launch.spotify": "spotify-client",
        "launch.terminal_alt": "foot"
    })

    // Directory listings, keyed by directory. Each is appended in turn and
    // merged into `resolved` as it arrives.
    property var listings: ({})

    // Icon name -> resolved absolute path. Reassigned on every merge so a
    // binding on a resolved icon re-evaluates when its file is finally found.
    property var resolved: ({})

    // Paths the running theme already answered for, gathered synchronously at
    // start-up so the common case is correct on the very first frame.
    property var themedPaths: ({})

    property int directoryIndex: 0
    property bool listing: false

    // A pure read. It never starts work and never writes, so a binding on this
    // result can only be invalidated by the listing pipeline, never by
    // evaluating itself.
    function pathFor(iconName) {
        var name = String(iconName === null || iconName === undefined ? "" : iconName).trim()
        if (name === "")
            return ""
        if (Object.prototype.hasOwnProperty.call(root.resolved, name))
            return String(root.resolved[name])
        return String(root.themedPaths[name] === undefined ? "" : root.themedPaths[name])
    }

    function iconFor(actionId) {
        return root.pathFor(root.entryIcons[String(actionId)])
    }

    // Gathers the theme's answers, then begins listing directories.
    function resolveAll() {
        var themed = ({})
        for (var key in root.entryIcons) {
            if (!Object.prototype.hasOwnProperty.call(root.entryIcons, key))
                continue
            var name = String(root.entryIcons[key])
            if (name === "")
                continue
            var path = Quickshell.iconPath(name, true)
            if (String(path || "") !== "")
                themed[name] = String(path)
        }
        root.themedPaths = themed
        root.listNext()
    }

    // Bounds one listing, so a hung mount can never stall resolution forever.
    property Timer listingWatchdog: Timer {
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.listing)
                root.settle(false, true)
        }
    }

    // The single exit for one listing, so the watchdog and the exit handler
    // cannot both advance the directory index.
    function settle(found, timedOut) {
        if (!root.listing)
            return
        root.listing = false
        root.listingWatchdog.stop()
        root.directoryIndex += 1
        if (found === true)
            root.merge(root.pendingDirectory, root.listingLines)
        root.listingLines = []
        root.listNext()
    }

    function listNext() {
        if (root.listing || root.directoryIndex >= root.searchPaths.length)
            return
        var directory = String(root.searchPaths[root.directoryIndex])
        root.pendingDirectory = directory
        root.listing = true
        root.listingLines = []
        directoryProbe.command = ["/usr/bin/ls", directory]
        directoryProbe.running = true
    }

    property string pendingDirectory: ""

    property Process directoryProbe: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                root.listingLines.push(String(line === undefined || line === null ? "" : line))
            }
        }
        // Both the exit handler and the watchdog route through `settle`, so the
        // directory index advances exactly once per listing.
        onStarted: root.listingWatchdog.restart()
        onExited: function(exitCode) {
            root.settle(Number(exitCode) === 0)
        }
    }

    property var listingLines: []

    // Folds one directory listing into the resolved map. Names still missing are
    // carried forward, so the first directory that supplies a size wins.
    function merge(directory, lines) {
        var updated = Object.assign({}, root.resolved)
        var wanted = {}
        for (var key in root.entryIcons) {
            if (!Object.prototype.hasOwnProperty.call(root.entryIcons, key))
                continue
            wanted[String(root.entryIcons[key])] = true
        }

        for (var index = 0; index < lines.length; index += 1) {
            var fileName = String(lines[index]).trim()
            if (fileName === "")
                continue
            var dot = fileName.lastIndexOf(".")
            if (dot < 1)
                continue
            var base = fileName.slice(0, dot)
            var extension = fileName.slice(dot + 1).toLowerCase()
            if (!Object.prototype.hasOwnProperty.call(wanted, base))
                continue
            if (root.preferredExtensions.indexOf(extension) === -1)
                continue
            // Keep an existing answer from a higher-preference directory.
            if (Object.prototype.hasOwnProperty.call(updated, base))
                continue
            updated[base] = directory + "/" + fileName
        }

        if (Object.keys(updated).length !== Object.keys(root.resolved).length)
            root.resolved = updated
    }

    Component.onCompleted: root.resolveAll()
}