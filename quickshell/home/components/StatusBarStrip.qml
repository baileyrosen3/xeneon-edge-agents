pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design
import "../state/SourceParse.js" as Parse
import "../state/ThemePalette.js" as ThemePalette
import "WorkspaceIndicator.qml"

// The strip along the top: clock and date, the workspace indicator, and the
// status pills.
//
// Every pill reads a real source. A pill whose source is unavailable shows an
// explicit em-dash state and says why in its accessible name, rather than
// drawing a zero, a full bar, or an optimistic "connected".
Item {
    id: root

    required property var theme
    required property var dispatcher

    required property var clock
    required property var hyprland
    required property var audio
    required property var network
    required property var bluetooth
    required property var power
    required property var tray
    required property var indicators

    property bool reducedMotion: false
    property bool showDate: true
    property bool showWorkspaceIndicator: true
    property bool showTray: true

    readonly property int pillHeight: Design.compactHeight(height)
        ? 30
        : 34

    readonly property color labelColor: String(theme.textSecondary)
    readonly property color valueColor: String(theme.textPrimary)

    // Nothing interactive sits within 8% of the top edge, because that band is
    // an edge-gesture zone. The strip's content starts below it.
    readonly property real edgeSafe: Math.max(
        Design.metrics.edgeSafeMinimum,
        Math.round(height * Design.metrics.edgeSafeFraction)
    )

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.alpha(String(root.theme.border), 0.6)
        opacity: 0.7
    }

    // Clock and date, left-aligned. The clock is the large title of the strip:
    // it is the one number a user reads without aiming.
    Item {
        id: clockBlock
        anchors.left: parent.left
        anchors.leftMargin: root.edgeSafe
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.edgeSafe * 0.35
        height: clockText.implicitHeight
        width: clockRow.implicitWidth + (root.showDate ? dateText.implicitWidth + 14 : 0)

        Row {
            id: clockRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                id: clockText
                anchors.verticalCenter: parent.verticalCenter
                text: root.clock.available ? root.clock.clock : "--:--"
                color: root.valueColor
                font.family: Design.fontFamily
                font.pixelSize: Design.compactHeight(root.height)
                    ? Design.type.title.size
                    : Design.type.display.size
                font.weight: root.clock.showSeconds
                    ? 400
                    : Design.type.display.weight
                font.letterSpacing: root.clock.showSeconds
                    ? 0
                    : Design.type.display.tracking
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.clock.available && !root.clock.showSeconds
                text: root.clock.meridiem
                color: root.labelColor
                font.family: Design.fontFamily
                font.pixelSize: Design.type.subheadline.size
                font.weight: Design.type.subheadline.weight
                font.letterSpacing: 0.4
            }
        }

        Text {
            id: dateText
            visible: root.showDate && root.clock.available
            anchors.left: clockRow.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter

            text: root.clock.dateText
            color: root.labelColor
            font.family: Design.fontFamily
            font.pixelSize: Design.type.body.size
            font.weight: Design.type.body.weight
            font.letterSpacing: Design.type.body.tracking
        }
    }

    // Workspaces, centred. Dispatching a workspace uses the allowlisted action
    // with a bounded integer id, so a tap can never carry a string into argv.
    WorkspaceIndicator {
        id: workspaces
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.edgeSafe * 0.35
        visible: root.showWorkspaceIndicator
        theme: root.theme
        hyprland: root.hyprland
        dispatcher: root.dispatcher
        reducedMotion: root.reducedMotion
        height: root.pillHeight
    }

    // Status pills and the tray, right-aligned in one group so they read as a
    // single cluster rather than as scattered icons.
    Row {
        id: pills
        anchors.right: parent.right
        anchors.rightMargin: root.edgeSafe
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.edgeSafe * 0.35
        spacing: 7

        // Indicators first, because they are states the user toggles rather
        // than measurements they read.
        IndicatorPill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            actionId: "toggle.notification_silencing"
            glyph: root.indicators.dndAvailable && root.indicators.doNotDisturb ? "◐" : "○"
            label: "Do not disturb"
            state: !root.indicators.dndAvailable
                ? "unavailable"
                : root.indicators.doNotDisturb ? "active" : "idle"
            detail: !root.indicators.dndAvailable
                ? root.indicators.notificationsAvailable === false
                    ? "notifications state is unreadable"
                    : ""
                : ""
        }

        IndicatorPill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            actionId: "toggle.idle"
            glyph: root.indicators.stayAwake ? "☀" : "☾"
            label: "Stay awake"
            state: !root.indicators.snapshot.available
                ? "unavailable"
                : root.indicators.stayAwake ? "active" : "idle"
            detail: !root.indicators.snapshot.available
                ? root.indicators.snapshot.detail
                : ""
        }

        IndicatorPill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            actionId: "toggle.nightlight"
            glyph: "◐"
            label: "Nightlight"
            state: !root.indicators.snapshot.available
                ? "unavailable"
                : root.indicators.nightlight ? "active" : "idle"
            detail: !root.indicators.snapshot.available
                ? root.indicators.snapshot.detail
                : root.indicators.nightlightDetail
        }

        StatusPill {
            theme: root.theme
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            glyph: root.network.snapshot.available && root.network.connected ? "⌁" : "⌁"
            label: "Network"
            value: root.network.snapshot.available
                ? (root.network.connection === ""
                    ? root.network.device
                    : root.network.connection)
                : "—"
            state: !root.network.snapshot.available
                ? "unavailable"
                : root.network.connected ? "active" : "idle"
            detail: !root.network.snapshot.available
                ? root.network.snapshot.detail
                : root.network.connectedCount + " up"
        }

        VolumePill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            audio: root.audio
        }

        StatusPill {
            theme: root.theme
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            glyph: "ᛒ"
            label: "Bluetooth"
            value: root.bluetooth.snapshot.available && root.bluetooth.deviceCount > 0
                ? String(root.bluetooth.deviceCount)
                : "—"
            state: !root.bluetooth.snapshot.available
                ? "unavailable"
                : root.bluetooth.powered ? "active" : "idle"
            detail: !root.bluetooth.snapshot.available
                ? root.bluetooth.snapshot.detail
                : root.bluetooth.deviceCount + " paired"
        }

        StatusPill {
            theme: root.theme
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            glyph: root.power.available
                ? (root.power.charging ? "⚡" : root.batteryGlyph)
                : "▭"
            label: "Battery"
            value: root.power.available
                ? String(root.power.percent) + "%"
                : "—"
            state: !root.power.available ? "unavailable" : "idle"
            detail: !root.power.available ? root.power.snapshot.detail : "Battery"
        }

        // The desktop tray. Entries are activated by item id through the
        // dispatcher's tray action family, never by calling an item directly.
        TrayPill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            tray: root.tray
            visible: root.showTray && root.tray.entries.length > 0
        }
    }

    // A charge glyph from the theme's own glyph font, four bars plus a bolt
    // while charging. A desktop reports no battery, which is a different state
    // from a full one.
    readonly property string batteryGlyph: root.power.bars >= 4
        ? "████"
        : root.power.bars === 3
            ? "███░"
            : root.power.bars === 2
                ? "██░░"
                : root.power.bars === 1
                    ? "█░░░"
                    : "░░░░"
}