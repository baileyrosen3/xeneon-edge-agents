pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design

// The desktop status-notifier tray, shown as a run of small icon wells.
//
// Each well activates by tray item id through the dispatcher, which resolves it
// against the ids the tray has already published. The surface never calls an
// item method by name and never accepts an id the tray did not publish.
Item {
    id: root

    required property var theme
    required property var dispatcher

    required property var tray

    property bool reducedMotion: false

    // A long tray is truncated rather than allowed to push the strip wider. The
    // count in the tooltip says how many are hidden, so nothing is silently
    // dropped.
    readonly property int maximumWells: 4

    readonly property var visibleEntries: root.tray.entries.slice(0, root.maximumWells)
    readonly property int hiddenCount: root.tray.entries.length - root.visibleEntries.length

    implicitHeight: height
    implicitWidth: wells.implicitWidth + 10
    height: 32

    GlassMaterial {
        anchors.fill: parent
        theme: root.theme
        elevation: 0
        corner: Design.radius.pill
    }

    Row {
        id: wells
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: root.visibleEntries

            delegate: Item {
                id: well
                required property var modelData
                required property int index

                width: 20
                height: 20

                // Activation goes by tray item id through the dispatcher, which
                // resolves it against the ids the tray currently publishes.
                function activateWell() {
                    root.activate(index)
                }

                Accessible.role: Accessible.Button
                Accessible.name: modelData.tooltipTitle === ""
                    ? modelData.title
                    : modelData.tooltipTitle
                Accessible.onPressAction: well.activateWell()

                function trigger() {
                    root.activate(index)
                }

                MouseArea {
                    id: press
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onClicked: well.activateWell()
                }

                HoverHandler {
                    id: hover
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Qt.alpha(
                        String(root.theme.textPrimary),
                        press.pressed ? 0.22 : hover.hovered ? 0.14 : 0.07
                    )
                }

                // The well shows the item's initial rather than shipping a
                // third-party icon theme. The title's first grapheme is real
                // data from the tray, and the tray will not claim more.
                Text {
                    anchors.centerIn: parent
                    text: root.initialFor(well.modelData)
                    color: String(root.theme.textSecondary)
                    font.family: Design.fontFamily
                    font.pixelSize: Design.type.caption.size
                    font.weight: 600
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hiddenCount > 0
            text: "+" + root.hiddenCount
            color: String(root.theme.textMuted)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.caption.size
            font.weight: 600
        }
    }

    function activate(index) {
        var entry = root.visibleEntries[index]
        if (entry === undefined)
            return
        root.dispatcher.dispatch("tray.activate", entry.id)
    }

    function initialFor(entry) {
        if (entry === undefined || entry === null)
            return ""
        var text = String(
            entry.tooltipTitle === "" ? entry.title : entry.tooltipTitle
        ).trim()
        if (text === "")
            return "•"
        return text.slice(0, 1).toUpperCase()
    }
}