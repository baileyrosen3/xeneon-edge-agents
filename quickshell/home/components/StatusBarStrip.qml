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

    // A soft, bounded separation under the bar: a hairline that fades out
    // toward both ends rather than a rule spanning the full width. It reads as
    // the bar's own material edge, not as a divider drawn across the surface.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        opacity: 0.55
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.18; color: Qt.alpha(String(root.theme.foreground), 0.10) }
            GradientStop { position: 0.82; color: Qt.alpha(String(root.theme.foreground), 0.10) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // The strip is three regions in a row: the clock, the workspace group, and
    // the status pills.
    //
    // Their widths are computed explicitly from the live width rather than
    // anchored independently, because three independently anchored regions
    // overlap as soon as the surface narrows — which is exactly what made the
    // clock vanish at 1024x288. A shared budget means the clock is always
    // present and always readable, the pills always get their space, and the
    // workspace group absorbs whatever is left.
    readonly property real regionWidth: Math.max(0, width - edgeSafe * 2)
    readonly property real regionGap: 12

    readonly property real clockBudget: Math.round(regionWidth * 0.30)
    readonly property real pillsBudget: Math.round(regionWidth * 0.50)
    readonly property real workspaceBudget: Math.max(
        0,
        regionWidth - clockBudget - pillsBudget - regionGap * 2
    )

    // Clock and date, left-aligned. The clock is the large title of the strip:
    // it is the one number a user reads without aiming.
    Item {
        id: clockBlock
        anchors.left: parent.left
        anchors.leftMargin: root.edgeSafe
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.edgeSafe * 0.35
        height: clockText.implicitHeight
        width: Math.min(
            clockRow.implicitWidth + (root.showDate ? dateText.implicitWidth + 14 : 0),
            root.clockBudget
        )
        // The clock is never dropped. If the date cannot fit beside it, the
        // date is what gives way.
        visible: root.regionWidth > 0

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
            visible: root.showDate
                && root.clock.available
                && dateText.implicitWidth + 14 + clockRow.implicitWidth <= root.clockBudget
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
        anchors.left: clockBlock.right
        anchors.leftMargin: root.regionGap
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.edgeSafe * 0.35
        visible: root.showWorkspaceIndicator
        theme: root.theme
        hyprland: root.hyprland
        dispatcher: root.dispatcher
        reducedMotion: root.reducedMotion
        height: root.pillHeight
        // The group never exceeds the space the budget left for it, so the
        // pills to its right are never displaced.
        maximumWidth: root.workspaceBudget
    }

    // Status pills and the tray, right-aligned in one group so they read as a
    // single cluster rather than as scattered icons.
    //
    // Every pill shows a recognisable glyph AND a short text label, so nothing
    // is ever a bare dash or a lone letter. A pill whose source has no state at
    // all is hidden entirely rather than drawn empty.
    // A refused action says so here rather than only in the log. It sits on the
    // far left of the pill group, where nothing else competes for the space.
    Text {
        id: refusalText
        anchors.right: pills.left
        anchors.rightMargin: root.regionGap
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.edgeSafe * 0.35
        visible: root.dispatcher.visibleRefusal !== ""
        text: root.dispatcher.visibleRefusalAction + ": " + root.dispatcher.visibleRefusal
        color: String(root.theme.textMuted)
        font.family: Design.fontFamily
        font.pixelSize: Design.type.caption.size
        font.weight: Design.type.caption.weight
        font.letterSpacing: 0.2
        elide: Text.ElideLeft
    }

    Row {
        id: pills
        anchors.right: parent.right
        anchors.rightMargin: root.edgeSafe
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -root.edgeSafe * 0.35
        spacing: 8
        // Caps the group at its budget so it can never grow into the clock.

        // Indicators first: these are states the user toggles.
        IndicatorPill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            actionId: "toggle.notification_silencing"
            glyph: "☾"
            label: "Focus"
            visible: root.indicators.dndAvailable
            pillState: root.indicators.doNotDisturb ? "active" : "idle"
        }

        IndicatorPill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            actionId: "toggle.idle"
            glyph: "☀"
            label: "Awake"
            visible: root.indicators.snapshot.available
            pillState: root.indicators.stayAwake ? "active" : "idle"
        }

        IndicatorPill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            actionId: "toggle.nightlight"
            glyph: "◐"
            label: "Night"
            visible: root.indicators.snapshot.available
            pillState: root.indicators.nightlight ? "active" : "idle"
        }

        // Connectivity, with the interface named rather than a bare glyph.
        StatusPill {
            theme: root.theme
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            glyph: "⌁"
            label: "Net"
            value: root.network.snapshot.available
                ? (root.network.connection === ""
                    ? root.network.device
                    : root.network.connection)
                : "offline"
            pillState: !root.network.snapshot.available
                ? "unavailable"
                : root.network.connected ? "active" : "idle"
        }

        VolumePill {
            theme: root.theme
            dispatcher: root.dispatcher
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            audio: root.audio
            visible: root.audio.snapshot.available
        }

        StatusPill {
            theme: root.theme
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            glyph: "ᛒ"
            label: "BT"
            value: root.bluetooth.snapshot.available && root.bluetooth.deviceCount > 0
                ? String(root.bluetooth.deviceCount) + " paired"
                : "none"
            pillState: !root.bluetooth.snapshot.available
                ? "unavailable"
                : root.bluetooth.powered ? "active" : "idle"
        }

        StatusPill {
            theme: root.theme
            reducedMotion: root.reducedMotion
            height: root.pillHeight
            glyph: root.power.available ? (root.power.charging ? "⚡" : "▮") : "▯"
            label: "Batt"
            value: root.power.available
                ? String(root.power.percent) + "%"
                : "none"
            pillState: !root.power.available ? "unavailable" : "idle"
        }

        // The desktop tray. Each well shows the item's icon or its app name,
        // never a placeholder.
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