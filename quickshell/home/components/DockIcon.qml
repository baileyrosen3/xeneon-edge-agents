pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design
import "../state/ThemePalette.js" as ThemePalette

// One app-launcher tile: a glass plate with a monogram, a caption, press and
// hover feedback, and spring motion.
//
// The tile never names a command. It carries an allowlisted action id and calls
// the dispatcher, so the launch path here is identical to the one a menu row
// would use. When the dispatcher's one-off presence probe reports the target is
// not installed, the tile renders a real unavailable state instead of
// pretending to launch.
Item {
    id: root

    required property var theme
    required property var dispatcher
    required property var icons

    property string actionId: ""
    property string label: ""
    property string monogram: ""

    // A theme role name, not a colour. The tile resolves it against the live
    // palette, so a monochrome theme stays monochrome.
    property string role: "accent"

    property bool reducedMotion: false
    property bool enabledTile: true
    property bool showLabel: true

    signal activated(string actionId)

    // The tile's edge length. The cluster passes the size it computed for this
    // surface, so a tile always fits inside its own zone at any width.
    property int plateSize: Design.compactHeight(height) ? 52 : 62
    readonly property int captionHeight: Design.type.caption.size + 5
    readonly property int captionGap: 3
    readonly property bool available: dispatcher.isAvailable(actionId)

    // The resolved icon path, or an empty string when this host has none for
    // the entry. An empty string is what shows the monogram fallback.
    readonly property string iconPath: root.icons.iconFor(root.actionId)

    // A resolved path is not a decoded image. The monogram shows unless the
    // Image actually rendered, so a format this host cannot decode degrades to
    // the placeholder rather than to an empty tile.
    readonly property bool iconRendered: iconImage.status === Image.Ready
        && iconImage.sourceSize.width > 0

    // A caption is drawn only when no icon could be decoded; the name is always
    // still exposed through Accessible.
    readonly property bool needsCaption: !root.iconRendered

    readonly property real pressScale: press.pressed && enabledTile
        ? Design.motion.pressScale
        : 1
    readonly property real hoverScale: hover.hovered && enabledTile
        ? Design.motion.hoverScale
        : 1

    implicitWidth: plateSize
    implicitHeight: plateSize + (needsCaption ? captionGap + captionHeight : 0)

    // A role the theme does not publish falls back to the accent, so a tile can
    // never render a blank plate.
    readonly property color accent: roleColor()

    function roleColor() {
        var name = String(role || "accent")
        var value = theme[name]
        if (value === undefined || value === null || String(value) === "")
            return String(theme.accent)
        return String(value)
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.available ? "" : "Not installed"
    Accessible.onPressAction: root.trigger()

    function trigger() {
        if (!root.enabledTile || !root.available)
            return
        root.activated(root.actionId)
        dispatcher.dispatch(root.actionId)
    }

    MouseArea {
        id: press
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledTile
        acceptedButtons: Qt.LeftButton
        onClicked: root.trigger()
    }

    HoverHandler {
        id: hover
        enabled: root.enabledTile
    }

    // The plate and its caption scale as one, so a spring never separates the
    // icon from its label.
    Item {
        id: body
        width: root.plateSize
        height: root.plateSize + (root.showLabel ? root.captionGap + root.captionHeight : 0)

        scale: root.pressScale * root.hoverScale
        Behavior on scale {
            enabled: !root.reducedMotion
            NumberAnimation {
                duration: Design.motion.springDurationMs
                easing.type: Easing.OutCubic
            }
        }

        // The glass plate is exactly plateSize; the caption hangs below it
        // rather than inside, so the rounded shape never has to fight the text.
        GlassMaterial {
            id: plate
            width: root.plateSize
            height: root.plateSize
            theme: root.theme
            elevation: hover.hovered && root.enabledTile ? 2 : 1
            corner: Design.radius.card - 4
        }

        // A monogram rather than a shipped brand glyph: this surface ships no
        // third-party artwork, and a monogram set in the theme's own face is
        // what keeps the dock reading as system UI rather than as a launcher.
        Squircle {
            id: iconPlate
            anchors.centerIn: plate
            width: 36
            height: 36
            corner: Design.radius.card - 9
            fillColor: Qt.alpha(root.accent, root.theme.mode === "light" ? 0.16 : 0.24)
            strokeColor: Qt.alpha(root.accent, 0.5)
            strokeWidth: 1
        }

        Image {
            id: iconImage
            anchors.centerIn: iconPlate
            width: iconPlate.width * 0.72
            height: iconPlate.height * 0.72
            visible: root.iconPath !== ""
            source: root.iconPath
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: true
        }

        Text {
            anchors.centerIn: iconPlate
            visible: !root.iconRendered
            text: root.monogram
            color: ThemePalette.ensureContrast(
                root.accent,
                String(root.theme.surface),
                4.5
            )
            font.family: Design.fontFamily
            font.pixelSize: Design.type.headline.size - 1
            font.weight: Design.type.headline.weight
            font.letterSpacing: Design.type.headline.tracking
        }

        // An unavailable tile is struck with a hairline. That is a truthful
        // state, not a control that looks disabled but still dispatches.
        Rectangle {
            anchors.horizontalCenter: plate.horizontalCenter
            y: plate.y + plate.height / 2
            width: plate.width * 0.46
            height: 1
            color: Qt.alpha(String(root.theme.textMuted), 0.9)
            visible: !root.available
        }

        Text {
            anchors.top: plate.bottom
            anchors.topMargin: root.captionGap
            visible: root.needsCaption
            anchors.horizontalCenter: plate.horizontalCenter
            width: plate.width + 22
            height: root.captionHeight

            text: root.label
            color: !root.available
                ? String(root.theme.textMuted)
                : String(root.theme.textSecondary)
            font.family: Design.fontFamily
            font.pixelSize: Design.type.caption.size
            font.weight: Design.type.caption.weight
            font.letterSpacing: Design.type.caption.tracking
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}