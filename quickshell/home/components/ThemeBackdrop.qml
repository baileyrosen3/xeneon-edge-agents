pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import "Design.js" as Design
import "../state/ThemePalette.js" as ThemePalette

// The plane behind every card.
//
// This is deliberately the quietest element on the surface. It carries no
// structural pattern at all: no grid, no rules, no scanlines, no horizon glow,
// no particles, no bloom. A repeating rule field reads as an instrument panel
// and competes with the content floating above it, so there is none here.
//
// Instead the plane is a single smooth field derived from the live Omarchy
// palette. When the active theme publishes a wallpaper — Omarchy themes carry a
// `background` entry — that image is used, heavily de-emphasised, desaturated
// toward the theme, and vignetted so it reads as depth rather than as a picture
// anyone is meant to look at. When there is no wallpaper, the field is a pure
// palette gradient. Either way the structure is identical: a calm plane that
// recedes.
Item {
    id: root

    required property var theme
    property bool reducedMotion: false

    readonly property bool light: String(theme.mode) === "light"

    // Omarchy themes do publish a wallpaper at `<themeRoot>/background`. This
    // theme's is a regular dot field: rendered as anything sharper than a faint
    // smudge it reads as a repeating rule pattern, which is precisely the
    // structural noise this plane must not carry. It is therefore not used at
    // all, and the field is a pure palette gradient. `XENEON_HOME_WALLPAPER`
    // exists for a host whose wallpaper is a real image, and is still subject
    // to the same heavy de-emphasis.
    readonly property string wallpaperPath: {
        var override = String(Quickshell.env("XENEON_HOME_WALLPAPER") || "")
        return override
    }

    readonly property bool wallpaperReady: wallpaperSource.status === Image.Ready
        && wallpaperSource.sourceSize.width > 0

    // Three theme-derived stops. A monochrome theme still separates them,
    // because the lift is a luminance move rather than a hue move.
    readonly property color fieldTop: ThemePalette.mixColors(
        String(theme.canvas),
        String(theme.lighterBackground),
        light ? 0.40 : 0.30
    )
    readonly property color fieldMiddle: ThemePalette.mixColors(
        String(theme.canvas),
        String(theme.lighterBackground),
        light ? 0.16 : 0.12
    )
    readonly property color fieldBottom: ThemePalette.mixColors(
        String(theme.canvas),
        String(theme.darkBackground),
        light ? 0.04 : 0.10
    )

    Image {
        id: wallpaperSource
        anchors.fill: parent
        visible: false
        source: root.wallpaperPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
    }

    Rectangle {
        anchors.fill: parent
        visible: root.wallpaperReady
        color: "transparent"
        opacity: 0.10
        gradient: Gradient {
            GradientStop { position: 0.0; color: String(root.theme.lighterBackground) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // One gradient veil, from the palette, painting over whatever is beneath.
    // It is what pushes the wallpaper well toward the theme, so the image
    // supplies depth and composition without supplying a colour the palette
    // does not name.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.fieldTop }
            GradientStop { position: 0.58; color: root.fieldMiddle }
            GradientStop { position: 1.0; color: root.fieldBottom }
        }
    }

    // A vignette. This is the only shape the plane has, and it exists so the
    // corners recede and the middle cards sit forward. It is a smooth radial
    // falloff with no edge, so it reads as light rather than as a frame.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.62; color: "transparent" }
            GradientStop {
                position: 1.0
                // One smooth falloff to the corners. This is the only shape the
                // plane has, and it is what makes the middle cards sit forward.
                color: Qt.rgba(0, 0, 0, root.light ? 0.10 : 0.34)
            }
        }
    }

}
