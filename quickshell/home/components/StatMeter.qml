pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design
import "../state/ThemePalette.js" as ThemePalette

// One measured quantity: a percentage, a temperature, or a capacity figure.
//
// The level is expressed as a filled arc and a number, not as a traffic-light
// colour. That is deliberate and it is also required here: this host's active
// Omarchy theme is monochrome, so a red/amber/green ramp would collapse into
// three indistinguishable greys. The theme's semantic roles are used for the
// one thing they are still good for here, which is the accent that marks a
// high reading, and even that is mixed from the live palette.
Item {
    id: root

    required property var theme

    // "load" | "temperature" | "capacity"
    property string kind: "load"

    property real percent: -1
    property real celsius: -1
    property string capacityLabel: ""

    // A second line under the reading. Capacity figures are split across two
    // lines here precisely so a used/total pair can never be truncated to an
    // ellipsis in a narrow column.
    property string capacityDetail: ""

    property string heading: ""

    property string detail: ""
    // Reduced motion is honoured by the meter settling on its final width with
    // no animation at all, rather than by animating a shorter distance.
    property bool reducedMotion: false

    readonly property bool hasReading: root.kind === "temperature"
        ? root.celsius >= 0
        : root.kind === "capacity"
            ? root.capacityLabel !== ""
            : root.percent >= 0

    readonly property real fraction: root.kind === "temperature"
        ? Math.max(0, Math.min(1, root.celsius / 100))
        : root.kind === "capacity"
            ? Math.max(0, Math.min(1, root.percent / 100))
            : Math.max(0, Math.min(1, root.percent / 100))

    // The reading is emphasised past this level. In a monochrome theme this
    // shows as weight and brightness rather than as a hue change.
    readonly property bool elevatedReading: root.fraction >= 0.75

    readonly property color valueColor: !root.hasReading
        ? String(root.theme.textMuted)
        : ThemePalette.ensureContrast(
            root.elevatedReading ? String(root.theme.textPrimary) : String(root.theme.textSecondary),
            String(root.theme.surface),
            7
        )

    readonly property color fillColor: !root.hasReading
        ? Qt.alpha(String(root.theme.textMuted), 0.25)
        : Qt.alpha(String(root.theme.textPrimary), root.elevatedReading ? 0.95 : 0.7)

    readonly property color trackColor: Qt.alpha(String(root.theme.textMuted), 0.28)

    readonly property string valueLabel: root.kind === "temperature"
        ? (root.celsius >= 0 ? Math.round(root.celsius) + "°" : "—")
        : root.kind === "capacity"
            ? root.capacityLabel
            : (root.percent >= 0 ? Math.round(root.percent) + "%" : "—")

    // The trailing line: the capacity total, the load average, or whatever the
    // source says about why there is no reading.
    readonly property string subLabel: root.capacityDetail !== ""
        ? root.capacityDetail
        : root.detail

    implicitWidth: 96
    implicitHeight: Design.type.metric.lineHeight
        + Design.type.caption.lineHeight * 2
        + 12

    // The heading. Uppercase and tracked, which is how a hardware block is
    // labelled in system UI: quiet enough to scan past, present enough to
    // identify the device at a glance.
    Text {
        id: headingText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        text: root.heading.toUpperCase()
        color: String(root.theme.textMuted)
        font.family: Design.fontFamily
        font.pixelSize: Design.type.caption.size
        font.weight: Design.type.caption.weight
        font.letterSpacing: 0.9
        elide: Text.ElideRight
    }

    // The reading, set in the metric step of the type scale.
    Text {
        id: valueText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headingText.bottom
        anchors.topMargin: 1

        text: root.valueLabel
        color: root.valueColor
        font.family: Design.fontFamily
        font.pixelSize: Design.type.metric.size
        font.weight: Design.type.metric.weight
        font.letterSpacing: Design.type.metric.tracking
        elide: Text.ElideRight
    }

    // The meter itself: a continuous capsule track with a filled portion. The
    // animation between samples is short and linear so a changing number reads
    // as a measurement settling, not as a bouncing decoration.
    Squircle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 5
        corner: 2.5
        fillColor: root.trackColor
    }

    Squircle {
        id: bar
        anchors.left: track.left
        anchors.verticalCenter: track.verticalCenter
        height: track.height
        width: root.hasReading
            ? Math.max(track.height, track.width * root.fraction)
            : 0
        corner: 2.5
        fillColor: root.fillColor

        Behavior on width {
            enabled: !root.reducedMotion
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }
    }

    // An unavailable reading keeps its heading so the device is still named,
    // and shows an em dash for the value, which is how system UI marks a
    // missing measurement.
    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: valueText.bottom
        anchors.topMargin: 1
        visible: root.subLabel !== ""
        text: root.subLabel
        color: String(root.theme.textMuted)
        font.family: Design.fontFamily
        font.pixelSize: Design.type.caption.size
        font.weight: 400
        font.letterSpacing: 0.2
        elide: Text.ElideRight
    }
}