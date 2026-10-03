pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design
import "../state/ThemePalette.js" as ThemePalette
import "Squircle.qml" as SquircleShape

// One measured quantity, laid out as one tight unit:
//
//   HEADING        what is being measured, uppercase and tracked
//   VALUE          the reading itself, in the metric step of the type scale
//   SUBLINE        the trailing context: a total, an average, or why there is
//                  no reading
//   ▬▬▬▬▬▬▬▬       the meter, immediately under the value it belongs to
//
// The meter is anchored to the value, never to the bottom of a stretched
// parent. That is what keeps a reading and its own bar visually attached
// instead of drifting apart inside a column.
Item {
    id: root

    required property var theme

    // "load" | "temperature" | "capacity"
    property string kind: "load"

    property real percent: -1
    property real celsius: -1
    property string capacityLabel: ""

    // A second line under the reading. Capacity figures are split across two
    // lines here so a used/total pair can never be truncated in a narrow
    // column.
    property string capacityDetail: ""

    // A third line, used only to explain an absent reading.
    property string detail: ""

    property string heading: ""

    property bool reducedMotion: false

    // Compact mode is chosen from the height the column actually has. It drops
    // the trailing line and steps the value down one size, so every meter still
    // fits inside the band instead of the last one being clipped.
    property bool compact: false

    // Whether a measurement actually exists. This is derived from the numbers
    // alone: an em dash is how a missing reading is *rendered*, never a reading
    // in itself, so the bar and the value can never disagree.
    readonly property bool hasReading: root.kind === "temperature"
        ? root.celsius >= 0
        : root.percent >= 0

    readonly property real fraction: root.kind === "temperature"
        ? Math.max(0, Math.min(1, root.celsius / 100))
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

    // The trailing line: the capacity total, or the reason there is no reading.
    readonly property string subLabel: root.capacityDetail !== ""
        ? root.capacityDetail
        : (!root.hasReading ? root.detail : "")

    implicitWidth: 96
    implicitHeight: column.implicitHeight

    // One column, sized to its own content. The meter is the last child, so it
    // always sits directly beneath the value rather than at the far edge of
    // whatever height the column was given.
    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: root.compact ? 2 : 3

        Text {
            id: headingText
            width: parent.width
            text: root.heading.toUpperCase()
            color: String(root.theme.textMuted)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.caption.size
            font.weight: Design.type.caption.weight
            font.letterSpacing: 0.9
            elide: Text.ElideRight
        }

        Text {
            id: valueText
            width: parent.width
            text: root.valueLabel
            color: root.valueColor
            font.family: Design.fontFamily
            font.pixelSize: root.compact ? 16 : Design.type.metric.size
            font.weight: Design.type.metric.weight
            font.letterSpacing: Design.type.metric.tracking
            elide: Text.ElideRight
        }

        Text {
            id: subText
            width: parent.width
            visible: root.subLabel !== "" && !root.compact
            text: root.subLabel
            color: String(root.theme.textMuted)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.caption.size
            font.weight: 400
            font.letterSpacing: 0.2
            elide: Text.ElideRight
        }

        // The meter: a continuous capsule track with a filled portion, wrapped
        // in an Item because a Column child cannot anchor to a sibling.
        Item {
            id: track
            width: parent.width
            height: root.compact ? 4 : 5

            Squircle {
                id: trackFill
                anchors.fill: parent
                corner: 2.5
                fillColor: root.trackColor
            }

            Squircle {
                id: bar
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: root.hasReading
                    ? Math.max(parent.height, parent.width * root.fraction)
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
        }
    }
}