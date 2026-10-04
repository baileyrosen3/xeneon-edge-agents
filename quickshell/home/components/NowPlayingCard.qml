import QtQuick
import "Design.js" as Design
import "../state/SourceParse.js" as Parse
import "../state/ThemePalette.js" as ThemePalette
import "TransportButton.qml"

// The media block: square artwork on the left, and to its right the track
// title on one ellipsised line, a thin scrubber with the elapsed time beneath
// it, and a row of transport buttons.
//
// There is no card behind this. It occupies the same footprint whether a track
// is playing or not, so an idle player never turns into a large empty panel.
Item {
    id: root

    required property var theme
    required property var dispatcher
    required property var media

    property bool reducedMotion: false

    readonly property bool available: media.available

    readonly property int artworkSize: Design.compactHeight(root.height) ? 58 : 68
    readonly property int controlSize: 30
    readonly property int primaryControlSize: 36

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        // Square rounded artwork.
        Squircle {
            id: artworkFrame
            width: root.artworkSize
            height: root.artworkSize
            corner: Design.radius.artwork
            fillColor: Qt.alpha(String(root.theme.surfacePressed), 0.55)
            strokeColor: Qt.alpha(String(root.theme.border), 0.7)
            strokeWidth: 1

            Image {
                id: artwork
                anchors.fill: parent
                anchors.margins: 1
                visible: root.media.artUrl !== "" && status === Image.Ready
                        && sourceSize.width > 0
                source: root.localArtUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }

            // The placeholder only when nothing decodable was published.
            Text {
                anchors.centerIn: parent
                visible: !artwork.visible
                text: root.media.artUrl === "" ? root.playerMonogram : ""
                color: String(root.theme.textSecondary)
                font.family: Design.fontFamily
                font.pixelSize: Design.type.metric.size - 4
                font.weight: 600
            }
        }

        Column {
            id: meta
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(60, root.width - root.artworkSize - 14)
            spacing: 3

            Text {
                width: parent.width
                text: root.media.title
                color: String(root.theme.textPrimary)
                font.family: Design.fontFamily
                font.pixelSize: Design.type.title.size
                font.weight: Design.type.title.weight
                font.letterSpacing: Design.type.title.tracking
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                visible: root.media.artist !== ""
                text: root.media.artist
                color: String(root.theme.textSecondary)
                font.family: Design.fontFamily
                font.pixelSize: Design.type.subheadline.size
                font.weight: Design.type.subheadline.weight
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Scrubber, with the elapsed time right-aligned beneath it.
            Item {
                width: parent.width
                height: 16

                Rectangle {
                    id: track
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 3
                    radius: 1.5
                    color: Qt.alpha(String(root.theme.textMuted), 0.4)
                }

                Rectangle {
                    anchors.left: track.left
                    anchors.verticalCenter: track.verticalCenter
                    height: track.height
                    width: root.media.lengthSeconds > 0
                        ? Math.max(0, Math.min(track.width, track.width * root.media.progress))
                        : 0
                    radius: 1.5
                    color: String(root.theme.textPrimary)
                    opacity: 0.9
                }

                Text {
                    anchors.top: track.bottom
                    anchors.topMargin: 3
                    anchors.left: parent.left
                    text: Parse.formatDuration(root.media.positionSeconds)
                    color: String(root.theme.textMuted)
                    font.family: Design.monospaceFamily
                    font.pixelSize: Design.type.mono.size
                }

                Text {
                    anchors.top: track.bottom
                    anchors.topMargin: 3
                    anchors.right: parent.right
                    text: "-" + Parse.formatDuration(
                        Math.max(0, root.media.lengthSeconds - Math.max(0, root.media.positionSeconds)))
                    color: String(root.theme.textMuted)
                    font.family: Design.monospaceFamily
                    font.pixelSize: Design.type.mono.size
                }

                MouseArea {
                    id: scrubber
                    anchors.fill: parent
                    enabled: root.media.canSeek && root.media.lengthSeconds > 0
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                    function positionAt(point) {
                        var fraction = (point.x - track.x) / Math.max(1, track.width)
                        return Math.max(0, Math.min(1, fraction)) * root.media.lengthSeconds
                    }

                    onPressed: function(point) {
                        if (root.media.canSeek)
                            root.dispatcher.dispatch("media.seek", positionAt(point))
                    }

                    onPositionChanged: function(point) {
                        if (pressed && root.media.canSeek)
                            root.dispatcher.dispatch("media.seek", positionAt(point))
                    }
                }
            }

            Row {
                spacing: 8

                TransportButton {
                    theme: root.theme
                    dispatcher: root.dispatcher
                    reducedMotion: root.reducedMotion
                    size: root.controlSize
                    glyph: "◀◀"
                    label: "Previous track"
                    actionId: "media.previous"
                    controlEnabled: root.media.canPrevious
                }

                TransportButton {
                    theme: root.theme
                    dispatcher: root.dispatcher
                    reducedMotion: root.reducedMotion
                    size: root.primaryControlSize
                    glyph: root.media.playing ? "❚❚" : "▶"
                    label: root.media.playing ? "Pause" : "Play"
                    actionId: "media.toggle"
                    controlEnabled: root.media.canToggle
                    primary: true
                }

                TransportButton {
                    theme: root.theme
                    dispatcher: root.dispatcher
                    reducedMotion: root.reducedMotion
                    size: root.controlSize
                    glyph: "▶▶"
                    label: "Next track"
                    actionId: "media.next"
                    controlEnabled: root.media.canNext
                }
            }
        }
    }

    // Artwork is accepted only from the local filesystem: a remote URL would
    // tell a third party which track is playing.
    readonly property string localArtUrl: localOnly(root.media.artUrl)

    function localOnly(artUrl) {
        var text = String(artUrl === null || artUrl === undefined ? "" : artUrl).trim()
        if (text === "")
            return ""
        if (text.indexOf("file://") === 0)
            return text
        if (text.charAt(0) === "/" && /^[A-Za-z0-9._\-\/ ]*$/.test(text))
            return text
        return ""
    }

    readonly property string playerMonogram: monogramFor(root.media.playerName)

    function monogramFor(name) {
        var text = String(name === null || name === undefined ? "" : name).trim()
        if (text === "")
            return ""
        var letters = String(text.replace(/[^A-Za-z0-9]/g, ""))
        if (letters.length === 0)
            return String(text.slice(0, 2)).toUpperCase()
        if (letters.length === 1)
            return letters.toUpperCase()
        return String(letters[0] + letters[1]).toUpperCase()
    }
}
