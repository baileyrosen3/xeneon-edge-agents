import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

// The live layer surface.
//
// This window covers exactly one already-verified screen. It is a plain
// layer-shell overlay with no keyboard focus and no exclusive zone, so it can
// never steal input from the desktop it is drawing over. The surface is only
// ever created from `ShellRoot`'s single-match screen list, so there is no code
// path here that can fall back to the primary display.
PanelWindow {
    id: root

    // Injected by the loader: the verified screen this surface covers.
    property var modelData: null

    // The verified screen and the single context object holding every source.
    // Both are set by the loader once this panel exists.
    property var context: null

    // Reduced motion reaches the real surface, not just the preview.
    property bool reducedMotion: false


    // `screen` is only ever set to an already-verified screen, and the window
    // stays hidden until that has happened. A null screen would resolve to the
    // primary display, which is precisely what the identity rule forbids.
    screen: root.modelData === null ? undefined : root.modelData
    visible: root.modelData !== null
    color: root.context.theme.canvas
    surfaceFormat.opaque: true
    focusable: false
    mask: null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // No exclusion zone and no keyboard focus: the strip reports information
    // and accepts taps, and nothing more.
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "xeneon-home-dashboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    HomeSurface {
        anchors.fill: parent

        theme: root.context.theme
        settings: root.context.settings
        dispatcher: root.context.dispatcher
        icons: root.context.icons
        clock: root.context.clock
        hyprland: root.context.hyprland
        media: root.context.media
        cpu: root.context.cpu
        gpu: root.context.gpu
        memory: root.context.memory
        audio: root.context.audio
        network: root.context.network
        bluetooth: root.context.bluetooth
        power: root.context.power
        tray: root.context.tray
        indicators: root.context.indicators
        keyboard: root.context.keyboard
        storage: root.context.storage
        updates: root.context.updates
        agentsUsage: root.context.agentsUsage
        clipboard: root.context.clipboard
        notifications: root.context.notifications
        compositorIdentity: root.context.compositorIdentity
        reducedMotion: root.reducedMotion
    }
}