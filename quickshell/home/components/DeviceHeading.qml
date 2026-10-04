import QtQuick
import "Design.js" as Design

// A device name. Small and quiet: it identifies the group without competing
// with the values beside it. Extends Text, so the caption is set via `text`.
Text {
    id: root
    required property var theme

    color: String(root.theme.textMuted)
    font.family: Design.fontFamily
    font.pixelSize: Design.type.caption.size
    font.weight: 700
    font.letterSpacing: 0.9
    elide: Text.ElideRight
    text: String(root.caption).toUpperCase()

    property string caption: ""
}
