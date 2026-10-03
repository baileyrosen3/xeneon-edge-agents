pragma ComponentBehavior: Bound
import QtQuick
import "."
import "Design.js" as Design
import "../state/SourceParse.js" as Parse
import "../state/ThemePalette.js" as ThemePalette

// The centrepiece: artwork, title and artist, a scrubber, and transport
// controls, laid out the way a media card reads in system UI.
//
// Transport controls only enable when the active MPRIS player advertises the
// matching capability, so a disabled button means the player refused it, not
// that the UI forgot to wire it. Every button dispatches a typed action id
// through the dispatcher; no button ever names a method itself.
Item {
    id: root

    required property var theme
    required property var dispatcher
    required property var media

    property bool reducedMotion: false

    readonly property bool available: media.available
    readonly property color artSeed: String(theme.accent)

    // Layout constants, derived once so no card measures by eye.
    readonly property int artworkSize: 96
    readonly property int controlSize: 38
    readonly property int primaryControlSize: 46
    readonly property int innerPadding: 20

    GlassMaterial {
        anchors.fill: parent
        theme: root.theme
        elevation: 2
        corner: Design.radius.card
    }

    // The unavailable state. A host with no registered player shows a real
    // reason, not an empty card that reads as a paused track.
    Item {
        anchors.fill: parent
        visible: !root.available

        Column {
            anchors.centerIn: parent
            width: parent.width - root.innerPadding * 2
            spacing: 6

            Text {
                width: parent.width
                text: "No media playing"
                color: String(root.theme.textSecondary)
                font.family: Design.fontFamily
                font.pixelSize: Design.type.title.size
                font.weight: Design.type.title.weight
                font.letterSpacing: Design.type.title.tracking
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.media.snapshot.detail
                color: String(root.theme.textMuted)
                font.family: Design.fontFamily
                font.pixelSize: Design.type.subheadline.size
                font.weight: Design.type.subheadline.weight
                font.letterSpacing: Design.type.subheadline.tracking
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    // The playing state.
    Item {
        id: content
        anchors.fill: parent
        anchors.margins: root.innerPadding
        visible: root.available

        // A crossfade between the two states rather than a hard swap, so a
        // player appearing or disappearing does not flash the card.
        opacity: root.available ? 1 : 0
        Behavior on opacity {
            enabled: !root.reducedMotion
            NumberAnimation {
                duration: Design.motion.crossfadeMs
                easing.type: Easing.OutCubic
            }
        }

        // The header is a plain Item: its two halves are positioned by
        // anchors, because a Row cannot also position an anchored child.
        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.artworkSize

            // Artwork. A loaded MPRIS image when the player publishes one,
            // otherwise a squircle monogram tile. No placeholder artwork is
            // shipped, because inventing a cover would be fabricated data.
            Squircle {
                id: artworkFrame
                anchors.left: parent.left
                anchors.top: parent.top
                width: root.artworkSize
                height: root.artworkSize
                corner: Design.radius.artwork
                fillColor: Qt.alpha(String(root.theme.surfacePressed), 0.5)
                strokeColor: Qt.alpha(String(root.theme.border), 0.8)
                strokeWidth: 1

                Image {
                    id: artwork
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: status === Image.Ready && sourceSize.width > 0
                    source: root.localArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    clip: true
                }

                // The monogram fallback, shown when no artwork is published.
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    visible: artwork.status !== Image.Ready || artwork.sourceSize.width <= 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.playerMonogram
                        color: String(root.theme.textSecondary)
                        font.family: Design.fontFamily
                        font.pixelSize: Design.type.metric.size - 2
                        font.weight: Design.type.metric.weight
                        font.letterSpacing: Design.type.metric.tracking
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "ARTWORK"
                        color: String(root.theme.textMuted)
                        font.family: Design.fontFamily
                        font.pixelSize: 8
                        font.weight: 600
                        font.letterSpacing: 1.2
                    }
                }
            }

            Column {
                id: meta
                anchors.left: artworkFrame.right
                anchors.leftMargin: 14
                anchors.right: controls.left
                anchors.rightMargin: 16
                anchors.verticalCenter: artworkFrame.verticalCenter
                width: Math.max(40, parent.width - artworkFrame.width - controls.width - 46)
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
                }

                Text {
                    width: parent.width
                    text: root.media.artist
                    color: String(root.theme.textSecondary)
                    font.family: Design.fontFamily
                    font.pixelSize: Design.type.body.size
                    font.weight: Design.type.body.weight
                    font.letterSpacing: Design.type.body.tracking
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.subtitle
                    color: String(root.theme.textMuted)
                    font.family: Design.fontFamily
                    font.pixelSize: Design.type.subheadline.size
                    font.weight: Design.type.subheadline.weight
                    font.letterSpacing: Design.type.subheadline.tracking
                    elide: Text.ElideRight
                }
            }

            // The transport is a Row, so it is placed by its own anchor only
            // vertically and its width is derived from its contents.
            Row {
                id: controls
                anchors.top: parent.top
                anchors.topMargin: (artworkFrame.height - height) / 2
                anchors.right: parent.right
                spacing: 8

                TransportButton {
                    theme: root.theme
                    dispatcher: root.dispatcher
                    reducedMotion: root.reducedMotion
                    size: root.controlSize
                    glyph: "◀◀"
                    label: "Previous track"
                    actionId: "media.previous"
                    enabled: root.media.canPrevious
                }

                TransportButton {
                    theme: root.theme
                    dispatcher: root.dispatcher
                    reducedMotion: root.reducedMotion
                    size: root.primaryControlSize
                    glyph: root.media.playing ? "❚❚" : "▶"
                    label: root.media.playing ? "Pause" : "Play"
                    actionId: "media.toggle"
                    enabled: root.media.canToggle
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
                    enabled: root.media.canNext
                }
            }
        }

        // The scrubber spans the full card width below the header. It reads as
        // one continuous track with the elapsed and remaining time set into it,
        // which is how a media card presents position without a numeric field.
        Item {
            id: scrubTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 26

            readonly property bool interactive: root.media.canSeek
                && root.media.lengthSeconds > 0

            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -3
                height: 4
                radius: 2
                color: Qt.alpha(String(root.theme.textMuted), 0.32)
            }

            Rectangle {
                id: fill
                anchors.left: track.left
                anchors.verticalCenter: track.verticalCenter
                height: track.height
                width: track.width * root.media.progress
                radius: 2
                color: String(root.theme.textPrimary)
                opacity: 0.85
            }

            // The handle grows while scrubbing and rests small otherwise, which
            // keeps the resting layout quiet.
            Rectangle {
                id: handle
                visible: root.media.lengthSeconds > 0
                anchors.verticalCenter: track.verticalCenter
                x: track.x + track.width * root.media.progress - width / 2
                width: Design.motion.scrubHandleDiameter
                height: Design.motion.scrubHandleDiameter
                radius: width / 2
                color: String(root.theme.textPrimary)
                opacity: scrubArea.pressed || scrubArea.containsMouse ? 1 : 0.75

                scale: scrubArea.pressed || scrubArea.containsMouse ? 1.2 : 1
                Behavior on scale {
                    enabled: !root.reducedMotion
                    NumberAnimation {
                        duration: Design.motion.springDurationMs
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                id: scrubArea
                anchors.fill: parent
                enabled: root.media.lengthSeconds > 0
                hoverEnabled: true
                preventStealing: true
                cursorShape: root.media.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

                function positionSecondsAt(point) {
                    var fraction = (point.x - track.x) / Math.max(1, track.width)
                    fraction = Math.max(0, Math.min(1, fraction))
                    return fraction * root.media.lengthSeconds
                }

                onPressed: function(point) {
                    if (!root.media.canSeek)
                        return
                    root.dispatcher.dispatch("media.seek", positionSecondsAt(point))
                }

                onPositionChanged: function(point) {
                    if (pressed && root.media.canSeek)
                        root.dispatcher.dispatch("media.seek", positionSecondsAt(point))
                }
            }

            Text {
                anchors.left: track.left
                anchors.top: track.bottom
                anchors.topMargin: 5
                text: Parse.formatDuration(root.media.positionSeconds)
                color: String(root.theme.textMuted)
                font.family: Design.monospaceFamily
                font.pixelSize: Design.type.mono.size
                font.weight: Design.type.mono.weight
                font.letterSpacing: Design.type.mono.tracking
            }

            Text {
                anchors.right: track.right
                anchors.top: track.bottom
                anchors.topMargin: 5
                text: "-" + Parse.formatDuration(
                    Math.max(0, root.media.lengthSeconds - Math.max(0, root.media.positionSeconds))
                )
                color: String(root.theme.textMuted)
                font.family: Design.monospaceFamily
                font.pixelSize: Design.type.mono.size
                font.weight: Design.type.mono.weight
                font.letterSpacing: Design.type.mono.tracking
            }
        }
    }

    // Album and player identity under the title, joined so the subtitle is one
    // line rather than two competing ones.
    readonly property string subtitle: {
        if (root.media.album !== "")
            return root.media.playerName === ""
                ? root.media.album
                : root.media.album + " · " + root.media.playerName
        return root.media.playerName
    }

    // A two-letter mark derived from the player identity, used only as the
    // artwork placeholder's label.
    readonly property string playerMonogram: monogramFor(root.media.playerName)

    // Artwork is accepted only from the local filesystem. A player may publish
    // any URL it likes, and fetching a remote one would tell a third party which
    // track is playing. Anything that is not a file:// URL or an absolute local
    // path is refused and the monogram placeholder is shown instead.
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

    function monogramFor(name) {
        var text = String(name === null || name === undefined ? "" : name).trim()
        if (text === "")
            return "--"
        var letters = String(text.replace(/[^A-Za-z0-9]/g, ""))
        if (letters.length === 0)
            return String(text.slice(0, 2)).toUpperCase()
        if (letters.length === 1)
            return letters.toUpperCase()
        return String(letters[0] + letters[1]).toUpperCase()
    }
}