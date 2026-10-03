import QtQuick
import QtCore
import Quickshell
import "components"
import "state"
import "state/ScreenIdentity.js" as ScreenIdentity

// A standalone Quickshell configuration for a home dashboard: a wide, short
// strip that mirrors the desktop's own menu bar as system UI.
//
// It is completely independent of the agent command center that also lives in
// this repository. Nothing here reads, writes, or imports the portal store, the
// agent protocol, or the bridge, and the two configurations can run at the same
// time without sharing state.
//
// Three modes:
//
//   preview  XENEON_HOME_PREVIEW=1 opens a 1280x360 FloatingWindow so the
//            surface can be captured offscreen. No screen identity is consulted
//            and no layer surface is created.
//   captured XENEON_HOME_PREVIEW=1 plus XENEON_HOME_SHOT=<path> and an optional
//            XENEON_HOME_PREVIEW_SIZE=<WxH> writes a PNG and exits.
//   live     Binds a layer surface to exactly one screen, matched by explicit
//            serial, model, and output identity. Incomplete or ambiguous
//            identity creates no surface at all and logs why.
ShellRoot {
    id: root

    // QSettings will not open without an application identity. These bindings
    // are evaluated while this root object is constructed, which is before any
    // Settings object anywhere in the configuration exists. The Settings
    // location stays explicit, so this only has to exist.
    property string applicationName: Qt.application.name = "xeneon-home-dashboard"
    property string applicationOrganization: Qt.application.organization = "xeneon"
    property string applicationDomain: Qt.application.domain = "home.xeneon.local"


    property bool fatalExitRequested: false
    property bool previewClosing: false

    // ---------------------------------------------------------------- modes

    readonly property bool previewMode:
        String(Quickshell.env("XENEON_HOME_PREVIEW") || "") === "1"

    readonly property bool reducedMotion:
        String(Quickshell.env("XENEON_HOME_REDUCED_MOTION") || "") === "1"
        || preferences.reduceMotion

    // Optional capture target. The preview harness writes a PNG here and exits,
    // which is how the screenshots in docs/home-dashboard.md are produced.
    readonly property string shotPath:
        String(Quickshell.env("XENEON_HOME_SHOT") || "")

    readonly property bool captureMode: root.previewMode && root.shotPath !== ""

    // The preview size, validated as a bounded WxH pair so a malformed value
    // falls back to the reference size instead of producing a broken window.
    readonly property size previewSize: (function() {
        var requested = String(Quickshell.env("XENEON_HOME_PREVIEW_SIZE") || "")
        var match = requested.match(/^([0-9]{3,4})x([0-9]{2,4})$/)
        if (match === null)
            return Qt.size(1280, 360)
        var width = Math.max(640, Math.min(3840, Number(match[1])))
        var height = Math.max(180, Math.min(720, Number(match[2])))
        return Qt.size(width, height)
    })()

    // ------------------------------------------------------- screen identity

    // The live surface binds only to a screen whose serial, model, and output
    // name all match exactly. Any missing component, or more than one match,
    // produces no surface and a log line. There is deliberately no fallback to
    // the primary display.
    readonly property string targetSerial:
        String(Quickshell.env("XENEON_HOME_SERIAL") || "")
    readonly property string targetModel:
        String(Quickshell.env("XENEON_HOME_MODEL") || "")
    readonly property string targetOutput:
        String(Quickshell.env("XENEON_HOME_OUTPUT") || "")

    readonly property var matchingScreens: screensMatchingIdentity()

    // Exactly one match or nothing. Several matches are as unusable as none.
    readonly property var targetScreens: (function() {
        var target = ScreenIdentity.targetScreen(
            Quickshell.screens,
            root.identity()
        )
        return target === null ? [] : [target]
    })()

    // The gate itself lives in ScreenIdentity.js so it can be executed and
    // tested offline. An unsatisfiable gate in this file rendered perfectly in
    // preview and could never bind live.
    function identity() {
        return {
            "output": root.targetOutput,
            "model": root.targetModel,
            "serial": root.targetSerial
        }
    }

    function identityConfigured() {
        return ScreenIdentity.identityConfigured(root.identity())
    }

    function screensMatchingIdentity() {
        var matches = ScreenIdentity.matchingScreens(
            Quickshell.screens,
            root.identity()
        )
        var reason = ScreenIdentity.refusalReason(
            Quickshell.screens,
            root.identity()
        )
        if (reason !== "")
            root.logIdentity("no surface: " + reason)
        return matches
    }

    function screenMatches(screen) {
        return ScreenIdentity.screenMatches(screen, root.identity())
    }

    function logIdentity(message) {
        console.warn("xeneon-home[identity] " + message)
    }

    // ----------------------------------------------------------------- state

    Scope {
        id: runtime

        HomeSettings {
            id: preferences
        }

        OmarchyTheme {
            id: sourceTheme
        }

        MappedTheme {
            id: homeTheme
            sourceTheme: sourceTheme
            preferences: preferences
        }

        ActionDispatcher {
            id: dispatcher
            hyprland: hyprland
            media: media
            tray: tray
        }

        IconResolver {
            id: icons
        }

        KeyboardSource {
            id: keyboard
        }

        StorageSource {
            id: storage
        }

        UpdateSource {
            id: updates
        }

        AgentUsageSource {
            id: agentsUsage
        }

        ClipboardSource {
            id: clipboard
        }

        NotificationSource {
            id: notifications
        }

        ClockSource {
            id: clock
        }

        HyprlandSource {
            id: hyprland
        }

        MediaSource {
            id: media
        }

        CpuSource {
            id: cpu
        }

        GpuSource {
            id: gpu
        }

        MemorySource {
            id: memory
        }

        AudioSource {
            id: audio
        }

        NetworkSource {
            id: network
        }

        BluetoothSource {
            id: bluetooth
        }

        PowerSource {
            id: power
        }

        TraySource {
            id: tray
        }

        IndicatorSource {
            id: indicators
        }

        // One presence probe per declared action, so a tile that cannot launch
        // on this host says so instead of failing silently on tap. The
        // dispatcher seeds its availability map at construction, so this only
        // has to correct it.
        Component.onCompleted: dispatcher.probeAll()
    }

    // ------------------------------------------------------------ live layer

    // The live layer surface, created only when exactly one screen has been
    // verified. There is no default case here: zero matches or several matches
    // both create nothing at all, which is the whole fail-closed rule.
    Loader {
        id: livePanel
        active: !root.previewMode && root.targetScreens.length === 1
        asynchronous: false
        visible: active
        source: active ? "components/HomePanel.qml" : ""

        // The context is applied once the item exists, which is the only point at
        // which a Loader can be configured.
        // The screen and the source context are injected once the panel exists,
        // which is the only point at which a Loader can be configured. Both are
        // built on the root, where every source is in scope.
        onLoaded: {
            livePanel.item.modelData = root.targetScreens[0]
            livePanel.item.context = root.sourcesContext()
            livePanel.item.reducedMotion = root.reducedMotion
        }
    }

    // ---------------------------------------------------------- preview window

    FloatingWindow {
        id: previewWindow

        visible: root.previewMode
        title: "XENEON Home Dashboard Preview"
        implicitWidth: root.previewSize.width
        implicitHeight: root.previewSize.height
        minimumSize: Qt.size(640, 180)
        color: homeTheme.canvas
        surfaceFormat.opaque: true

        onClosed: {
            root.previewClosing = true
            if (root.previewMode && !root.fatalExitRequested)
                Qt.quit()
        }

        onResourcesLost: {
            if (root.previewMode && !root.previewClosing) {
                root.fatalExitRequested = true
                Qt.exit(1)
            }
        }

        HomeSurface {
            id: previewSurface
            anchors.fill: parent

            theme: homeTheme
            settings: preferences
            dispatcher: dispatcher
            icons: icons
            clock: clock
            hyprland: hyprland
            media: media
            cpu: cpu
            gpu: gpu
            memory: memory
            audio: audio
            network: network
            bluetooth: bluetooth
            power: power
            tray: tray
            indicators: indicators
            keyboard: keyboard
            storage: storage
            updates: updates
            agentsUsage: agentsUsage
            clipboard: clipboard
            notifications: notifications
            reducedMotion: root.reducedMotion
        }

        // Capture waits for the sources to have real samples before grabbing,
        // so a screenshot shows data rather than the initial unavailable frame.
        Timer {
            id: shotDelay

            running: root.captureMode
            interval: 4200
            repeat: false
            onTriggered: root.captureShot()
        }
    }

    // Renders the preview surface to a PNG and exits. The path comes from the
    // harness environment, never from anything a user can reach.
    // The single object a live panel is handed. Assembled on the root so every
    // source is in scope, and so the panel cannot end up reading a different
    // instance of one than the preview does.
    function sourcesContext() {
        return {
            "theme": homeTheme,
            "settings": preferences,
            "dispatcher": dispatcher,
            "icons": icons,
            "clock": clock,
            "hyprland": hyprland,
            "media": media,
            "cpu": cpu,
            "gpu": gpu,
            "memory": memory,
            "audio": audio,
            "network": network,
            "bluetooth": bluetooth,
            "power": power,
            "tray": tray,
            "indicators": indicators,
            "keyboard": keyboard,
            "storage": storage,
            "updates": updates,
            "agentsUsage": agentsUsage,
            "clipboard": clipboard,
            "notifications": notifications
        }
    }

    function captureShot() {
        if (!root.captureMode)
            return

        var surface = previewSurface
        surface.grabToImage(function(result) {
            var saved = result.saveToFile(root.shotPath)
            console.log("xeneon-home[shot] " + (saved ? "wrote " : "failed to write ")
                    + root.shotPath
                    + " at " + root.previewSize.width + "x" + root.previewSize.height
            )
            root.fatalExitRequested = true
            if (saved)
                Qt.exit(0)
            else
                Qt.exit(1)
        })
    }
}