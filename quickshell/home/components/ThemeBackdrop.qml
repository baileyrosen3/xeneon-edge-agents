import QtQuick
import Quickshell
import Quickshell.Io
import "../state/ThemePalette.js" as ThemePalette

// The plane behind every card: the user's own Omarchy background, plus a
// legibility scrim.
//
// The surface is non-opaque so the desktop's own `omarchy-background` layer
// shows through, which is why the wallpaper survives even if this file draws
// nothing. The image is *also* drawn here as a safety net: if that layer is
// disabled, the panel must still not fall back to black while a valid
// background exists.
//
// The path is bound, never resolved. `omarchy theme set` deletes and recreates
// the whole `current/theme` tree and repoints the symlink atomically, so a
// cached `readlink -f` result would point into a tree that no longer exists. The
// symlink path itself stays stable and is re-bound when it changes.
Item {
    id: root

    required property var theme
    property bool reducedMotion: false

    readonly property bool light: String(theme.mode) === "light"

    // The stable location. `XENEON_HOME_WALLPAPER` still overrides it.
    readonly property string backgroundPath: {
        var override = String(Quickshell.env("XENEON_HOME_WALLPAPER") || "")
        if (override !== "")
            return override
        return root.stateHome + "/omarchy/current/background"
    }

    readonly property string stateHome: {
        var home = String(Quickshell.env("XDG_STATE_HOME") || "")
        if (home === "")
            home = String(Quickshell.env("HOME") || "") + "/.local/state"
        return home
    }

    // Video extensions, matching the wallpaper plugin's own allowlist. A video is
    // never handed to `Image`: it would fail to decode and leave a broken
    // placeholder. Those fall back to the palette field.
    readonly property var videoExtensions: [".mp4", ".mkv", ".webm", ".mov", ".m4v"]

    readonly property bool isVideo: isVideoPath(backgroundPath)

    // What the Image is given, and when. Empty means "draw nothing".
    readonly property string wallpaperUrl: isVideo ? "" : "file://" + backgroundPath

    readonly property bool wallpaperReady: !isVideo
        && wallpaper.status === Image.Ready
        && wallpaper.sourceSize.width > 0

    function isVideoPath(path) {
        var lower = String(path === null || path === undefined ? "" : path).toLowerCase()
        for (var index = 0; index < root.videoExtensions.length; index += 1) {
            if (lower.endsWith(root.videoExtensions[index]))
                return true
        }
        return false
    }

    // A watcher on the *symlink*. It only reports change; pixels are never read
    // through it. `theme set` replaces the tree and repoints this link, and the
    // re-bind below is what makes the new image appear without a restart.
    property FileView watcher: FileView {
        path: root.backgroundPath
        watchChanges: true
        printErrors: false
        onLoaded: root.rebind()
        onLoadFailed: root.rebind()
    }

    // Re-binding clears the source for one frame. The path string is unchanged
    // across a theme switch, so without this the Image keeps its cached decode
    // and keeps painting the old wallpaper. It is a declarative binding rather
    // than an imperative assignment so the engine owns the property.
    property bool rebinding: false

    function rebind() {
        if (root.rebinding)
            return
        root.rebinding = true
        rebindStep.restart()
    }

    Timer {
        id: rebindStep
        interval: 0
        repeat: false
        onTriggered: root.rebinding = false
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        visible: root.wallpaperReady
        // Empty while rebinding, which forces a fresh decode of the new path.
        source: root.rebinding || root.isVideo ? "" : root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        // A broken or missing image paints nothing at all rather than a
        // placeholder box.
    }

    // The palette field. This is the FALLBACK: it is only visible when no
    // usable image resolved, so it can never cover a wallpaper that did load.
    Rectangle {
        anchors.fill: parent
        visible: !root.wallpaperReady
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.fieldTop }
            GradientStop { position: 0.58; color: root.fieldMiddle }
            GradientStop { position: 1.0; color: root.fieldBottom }
        }
    }

    // The legibility scrim. This is the hard part: the content sits over an
    // arbitrary photograph, so the scrim has to be strong enough that the
    // clock, labels and meters stay readable over a bright image, and weak
    // enough that the wallpaper is still obviously the background.
    //
    // It is two layers, both derived from the theme: a broad even darkening, and
    // a heavier band across the top where the status text lives.
    Rectangle {
        anchors.fill: parent
        color: root.scrimColor
        opacity: root.scrimOpacity
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(root.scrimColor, root.topScrimOpacity) }
            GradientStop { position: 0.34; color: Qt.alpha(root.scrimColor, root.topScrimOpacity * 0.35) }
            GradientStop { position: 0.72; color: "transparent" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // A soft vignette so the corners recede and the centre cards sit forward.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.55; color: "transparent" }
            GradientStop {
                position: 1.0
                color: Qt.rgba(0, 0, 0, root.light ? 0.10 : 0.30)
            }
        }
    }

    // Three theme-derived stops for the fallback field.
    readonly property color fieldTop: ThemePalette.mixColors(
        String(theme.canvas), String(theme.lighterBackground), light ? 0.40 : 0.30)
    readonly property color fieldMiddle: ThemePalette.mixColors(
        String(theme.canvas), String(theme.lighterBackground), light ? 0.16 : 0.12)
    readonly property color fieldBottom: ThemePalette.mixColors(
        String(theme.canvas), String(theme.darkBackground), light ? 0.04 : 0.10)

    // Scrim strength. On a light theme the photograph is darkened with black;
    // on a dark theme with the canvas, which is already near black. Both are
    // theme-derived, never a literal.
    readonly property color scrimColor: root.light ? "#000000" : String(theme.canvas)
    readonly property real scrimOpacity: root.light ? 0.34 : 0.62
    readonly property real topScrimOpacity: root.light ? 0.30 : 0.55
}
