pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "."
import "Design.js" as Design
import "../state/ThemePalette.js" as ThemePalette

// The one translucent material every card, chip, and pill in this surface
// uses.
//
// Real vibrancy on Wayland needs a blurred view of whatever is behind the
// window, which a layer-shell surface cannot sample. Rather than fake a
// screenshot of a blur, this builds the same read from three layers that need
// no backdrop access and cost no per-frame render pass:
//
//   1. a fill lifted off the theme's raised surface,
//   2. a top-edge sheen suggesting light catching the surface,
//   3. a hairline border and exactly one soft shadow.
//
// Every colour is produced by ThemePalette mixing live theme roles, so the
// material stays correct in a light palette and a monochrome one alike.
Item {
    id: root

    // The theme mapping this surface reads. Required, so a card can never
    // render against a missing palette.
    required property var theme

    // 0 is a flat inset, 1 is a raised card, 2 is a floating control.
    property int elevation: 1

    property real corner: Design.radius.card
    property real pressed: 0

    readonly property bool light: String(theme.mode) === "light"

    readonly property var step: stepFor(elevation)

    function stepFor(level) {
        // A material is a DARK translucent plane on a dark theme, not a light
        // one: the fill is the theme's own background lifted a little toward its
        // lighterBackground, at a low alpha. On a light theme the same steps
        // invert, lifting toward white the way a light-mode material does.
        //
        // `fill` stays low on purpose. The depth on this surface comes from
        // layering a dark plane, a hairline rim, and a sheen, not from pushing
        // opacity toward the foreground and turning cards into pale slabs.
        var steps = [
            { "fill": 0.30, "sheen": 0.05, "rim": 0.10, "shadow": 0.30 },
            { "fill": 0.42, "sheen": 0.07, "rim": 0.14, "shadow": 0.42 },
            { "fill": 0.54, "sheen": 0.09, "rim": 0.18, "shadow": 0.52 }
        ]
        return steps[Math.max(0, Math.min(steps.length - 1, level))]
    }

    // Mixed through the palette so the result stays inside the theme's gamut
    // and follows its contrast rules instead of this file's own arithmetic.
    readonly property color planeColor: root.light
        ? ThemePalette.mixColors(
            String(theme.surfaceRaised),
            "#ffffff",
            0.55
        )
        : ThemePalette.mixColors(
            String(theme.background),
            String(theme.lighterBackground),
            0.62
        )

    readonly property color sheenColor: root.light
        ? "#ffffff"
        : ThemePalette.mixColors(
            String(theme.lighterBackground),
            String(theme.foreground),
            0.45
        )

    // The rim is a low-alpha foreground hairline: a light edge on a dark card,
    // a dark edge on a light one, which is how a material separates from what
    // is behind it without a drawn border.
    readonly property color rimColor: root.light
        ? ThemePalette.mixColors(
            String(theme.background),
            String(theme.foreground),
            0.22
        )
        : ThemePalette.mixColors(
            String(theme.lighterBackground),
            String(theme.foreground),
            0.30
        )

    implicitWidth: 0
    implicitHeight: 0

    // Exactly one shadow, wide and faint, offset a couple of pixels. A stack
    // of hard drop shadows is what makes a panel look cheap.
    MultiEffect {
        anchors.fill: parent
        anchors.margins: -8
        visible: root.step.shadow > 0
        enabled: visible

        shadowEnabled: true
        shadowBlur: 1.0
        shadowScale: 1.0
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 2
        shadowColor: Qt.rgba(0, 0, 0, root.step.shadow)

        source: content
    }

    Item {
        id: content
        anchors.fill: parent

        // The base plane: a dark translucent fill on a dark theme, derived from
        // the theme's own background rather than pushed toward white.
        Squircle {
            anchors.fill: parent
            corner: root.corner
            fillColor: Qt.alpha(root.planeColor, root.step.fill)
        }

        // The sheen is a short gradient pinned to the top edge. It is what makes
        // the surface read as a material catching light rather than as a
        // rectangle with a fill colour, and it follows the same continuous
        // outline as the fill because it is the same path.
        Squircle {
            anchors.fill: parent
            corner: root.corner
            fillGradient: LinearGradient {
                GradientStop {
                    position: 0.0
                    color: Qt.alpha(root.sheenColor, root.step.sheen)
                }
                GradientStop {
                    position: 0.42
                    color: Qt.alpha(root.sheenColor, 0)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.alpha(root.sheenColor, 0)
                }
            }
        }

        // A pressed control loses sheen and gains the theme's pressed surface,
        // which is the one place a card is allowed to look solid.
        Squircle {
            anchors.fill: parent
            corner: root.corner
            fillColor: Qt.alpha(String(root.theme.surfacePressed), root.pressed * 0.7)
            visible: root.pressed > 0
        }

        // The rim: a one-pixel low-alpha foreground hairline. On a dark theme
        // this is a light edge that separates the card from the plane behind
        // it, which is the whole job.
        Squircle {
            anchors.fill: parent
            corner: root.corner
            fillColor: "transparent"
            strokeColor: Qt.alpha(root.rimColor, root.step.rim + root.pressed * 0.25)
            strokeWidth: 1
        }
    }
}