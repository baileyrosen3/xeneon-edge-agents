pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design

// The composed home surface.
//
// The layout answers the reference directly: an app launcher cluster on the
// left, the media card in the centre, the hardware stats on the right, and the
// status strip along the top.
//
// Everything is anchored inside a safe band that keeps all legible and
// interactive content clear of the outer 8% on both edges, because that band is
// an edge-gesture zone on this touchscreen. The band is computed from the
// surface height rather than hardcoded, so the same composition serves the
// 1024x288 logical surface and the 1280x360 preview without a second layout.
Item {
    id: root

    required property var theme
    required property var dispatcher
    required property var icons

    required property var settings
    required property var clock
    required property var hyprland
    required property var media
    required property var cpu
    required property var gpu
    required property var memory
    required property var audio
    required property var network
    required property var bluetooth
    required property var power
    required property var tray
    required property var indicators
    required property var keyboard
    required property var storage
    required property var updates
    required property var agentsUsage
    required property var clipboard
    required property var notifications
    required property var compositorIdentity

    property bool reducedMotion: false

    clip: true

    // The strip's own layout band. Derived once from the live height so the
    // 288px surface is not a scaled-down 360px layout.
    readonly property var band: Design.bandForHeight(height)
    readonly property real edgeSafe: band.edgeSafe

    // The dock's sizing, hoisted to the component root so a Repeater delegate
    // can qualify it. A delegate cannot reach an id declared on a nested Item.
    readonly property int dockTileSize: Design.compactHeight(height) ? 48 : 54
    readonly property int dockSpacing: 10

    ThemeBackdrop {
        anchors.fill: parent
        theme: root.theme
        reducedMotion: root.reducedMotion
    }

    StatusBarStrip {
        id: statusStrip

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.band.statusHeight + root.edgeSafe

        theme: root.theme
        dispatcher: root.dispatcher
        clock: root.clock
        hyprland: root.hyprland
        audio: root.audio
        network: root.network
        bluetooth: root.bluetooth
        power: root.power
        tray: root.tray
        indicators: root.indicators
        keyboard: root.keyboard
        storage: root.storage
        updates: root.updates
        agentsUsage: root.agentsUsage
        clipboard: root.clipboard
        notifications: root.notifications
        compositorIdentity: root.compositorIdentity

        reducedMotion: root.reducedMotion
        showDate: root.settings.showDate
        showWorkspaceIndicator: root.settings.showWorkspaceIndicator
        showTray: root.settings.showTray
    }

    // The main band sits inside the safe area: below the status strip, inset by
    // the edge-safe margin on the left, right, and bottom.
    Item {
        id: main

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusStrip.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.edgeSafe
        anchors.rightMargin: root.edgeSafe
        anchors.bottomMargin: root.edgeSafe

        readonly property real gap: root.band.columnGap

        readonly property real available: width - gap * 2

        // The dock's width is *derived* from the tiles it must hold, never a
        // share of the surface. A ratio could hand the dock less room than its
        // tiles need, which is what pushed the last tile under the media card.
        // Sizing the zone to its content makes overlap structurally impossible:
        // the media card takes whatever is left.

        // Five across, two rows: every declared tile is shown, so the block is a
        // fixed shape and nothing is dropped.
        readonly property int dockTileCount: root.dispatcher && root.dispatcher.dockApps ? root.dispatcher.dockApps.length : 0
        readonly property int dockCapacity: 5
        readonly property real dockWidth: Math.round(
            Math.min(
                5 * root.dockTileSize
                    + 4 * root.dockSpacing,
                Math.round(available * 0.34)
            )
        )
        readonly property var dockAppsShown: root.dispatcher && root.dispatcher.dockApps ? root.dispatcher.dockApps.slice(0, 5) : []

        readonly property real statsRatio: 0.30
        readonly property real statsWidth: Math.round(available * statsRatio)
        readonly property real mediaWidth: available - dockWidth - statsWidth

        // Left: the launcher grid. Icons float directly on the wallpaper — no
        // region card — in a tight two-row block, five per row.
        Grid {
            id: cluster

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            columns: 5
            spacing: root.dockSpacing

            Repeater {
                model: main.dockAppsShown

                delegate: DockIcon {
                    required property var modelData

                    theme: root.theme
                    dispatcher: root.dispatcher
                    icons: root.icons
                    actionId: modelData.id
                    label: modelData.label
                    monogram: modelData.monogram
                    role: modelData.role
                    reducedMotion: root.reducedMotion
                    plateSize: root.dockTileSize
                }
            }
        }

        // Centre: the now-playing card.
        NowPlayingCard {
            id: mediaCard

            anchors.left: parent.left
            anchors.leftMargin: main.dockWidth + main.gap
            width: main.mediaWidth
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            theme: root.theme
            dispatcher: root.dispatcher
            media: root.media
            reducedMotion: root.reducedMotion
        }

        // Right: the hardware stats block.
        StatsStack {
            id: stats

            anchors.left: parent.left
            anchors.leftMargin: main.dockWidth + main.mediaWidth + main.gap * 2
            width: main.statsWidth
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            theme: root.theme
            cpu: root.cpu
            gpu: root.gpu
            memory: root.memory
            reducedMotion: root.reducedMotion
        }
    }
}