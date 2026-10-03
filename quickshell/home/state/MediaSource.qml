import QtQml
import Quickshell
import Quickshell.Services.Mpris

// Now playing, read through Quickshell's MPRIS service. This is the same path
// the Omarchy bar's media widget uses, and the only one that works on this
// host: there is no playerctl binary, and MPRIS is the protocol every desktop
// music player actually implements.
//
// The service pushes property changes, so this source holds no probe and no
// timer. Its snapshot is rebuilt whenever the player list or the active
// player's metadata changes. A host with no player reports unavailable with a
// reason rather than an empty card that looks like a paused track.
QtObject {
    id: root

    function sourceId() {
        return "media"
    }

    readonly property var players: Mpris.players ? Mpris.players.values : []
    readonly property var player: activePlayer()

    readonly property bool available: snapshot.available === true
    readonly property string title: available ? String(snapshot.title || "") : ""
    readonly property string artist: available ? String(snapshot.artist || "") : ""
    readonly property string album: available ? String(snapshot.album || "") : ""
    readonly property string artUrl: available ? String(snapshot.artUrl || "") : ""
    readonly property string playerName: available ? String(snapshot.playerName || "") : ""
    readonly property bool playing: available ? snapshot.playing === true : false

    // MPRIS reports both position and length in microseconds.
    readonly property double positionSeconds: available
        && Number(snapshot.positionSeconds) >= 0
        ? Number(snapshot.positionSeconds)
        : -1
    readonly property double lengthSeconds: available
        && Number(snapshot.lengthSeconds) > 0
        ? Number(snapshot.lengthSeconds)
        : -1
    readonly property real progress: lengthSeconds > 0 && positionSeconds >= 0
        ? Math.max(0, Math.min(1, positionSeconds / lengthSeconds))
        : 0

    readonly property bool canToggle: available ? snapshot.canToggle === true : false
    readonly property bool canNext: available ? snapshot.canNext === true : false
    readonly property bool canPrevious: available ? snapshot.canPrevious === true : false
    readonly property bool canSeek: available ? snapshot.canSeek === true : false

    property int sampleCount: 0

    property var snapshot: ({
        "available": false,
        "detail": "Waiting for the media service",
        "updatedMs": 0
    })

    // MPRIS position only advances while the player pushes updates, and a
    // paused player stops pushing entirely. This advances the displayed
    // position between updates and holds while paused.
    property Timer advance: Timer {
        interval: 500
        repeat: true
        running: root.available && root.playing
        onTriggered: root.tickPosition()
    }

    // The MPRIS service publishes no aggregate change signal, so the snapshot is
    // rebuilt on a short timer that samples the same module. Reading the
    // service rather than spawning anything keeps this cheap and truthful.
    property Timer playerListChangedTimer: Timer {
        interval: 700
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.rebuild()
    }

    property Connections trackChanged: Connections {
        target: root.player
        ignoreUnknownSignals: true

        function onTrackTitleChanged() {
            root.rebuild()
        }

        function onTrackArtistChanged() {
            root.rebuild()
        }

        function onTrackAlbumChanged() {
            root.rebuild()
        }

        function onTrackArtUrlChanged() {
            root.rebuild()
        }

        function onPositionChanged() {
            root.rebuild()
        }

        function onLengthChanged() {
            root.rebuild()
        }

        function onIsPlayingChanged() {
            root.rebuild()
        }

        function onCanTogglePlayingChanged() {
            root.rebuild()
        }

        function onCanGoNextChanged() {
            root.rebuild()
        }

        function onCanGoPreviousChanged() {
            root.rebuild()
        }

        function onCanSeekChanged() {
            root.rebuild()
        }
    }

    Component.onCompleted: root.rebuild()

    function playerKey(entry) {
        if (entry === null || entry === undefined)
            return ""
        return String(entry.dbusName || entry.desktopEntry || entry.identity || "")
    }

    function playerLabel(entry) {
        if (entry === null || entry === undefined)
            return ""
        var name = String(entry.dbusName || "")
            .replace(/^org\.mpris\.MediaPlayer2\./, "")
            .replace(/\.instance[0-9]+$/, "")
        return String(entry.desktopEntry || entry.identity || name)
    }

    function hasMetadata(entry) {
        if (entry === null || entry === undefined)
            return false
        return !!(entry.trackTitle || entry.trackArtist || entry.trackAlbum)
    }

    // Prefers a playing player with metadata, then a paused one, then anything
    // that at least identifies itself.
    function activePlayer() {
        var playing = null
        var paused = null
        var identified = null
        for (var index = 0; index < root.players.length; index += 1) {
            var entry = root.players[index]
            if (entry === null || entry === undefined)
                continue
            if (root.hasMetadata(entry)) {
                if (entry.isPlaying === true && playing === null)
                    playing = entry
                else if (paused === null)
                    paused = entry
            } else if (identified === null && root.playerLabel(entry) !== "") {
                identified = entry
            }
        }
        return playing !== null ? playing : (paused !== null ? paused : identified)
    }

    function rebuild() {
        var entry = root.player
        // With no player registered there is nothing that can have changed, so
        // the snapshot is left as it is rather than republished on every tick.
        if (entry === null || entry === undefined) {
            if (root.players.length === 0 && root.sampleCount > 0)
                return
            root.publishUnavailable(
                root.players.length === 0
                    ? "No MPRIS player is registered on this host"
                    : "MPRIS player exposes no track metadata"
            )
            return
        }

        if (!root.hasMetadata(entry)) {
            root.publishUnavailable("MPRIS player exposes no track metadata")
            return
        }

        root.publish({
            "title": String(entry.trackTitle || ""),
            "artist": String(entry.trackArtist || ""),
            "album": String(entry.trackAlbum || ""),
            "artUrl": String(entry.trackArtUrl || ""),
            "playerName": root.playerLabel(entry),
            "playing": entry.isPlaying === true,
            "positionSeconds": entry.positionSupported === true ? Number(entry.position) / 1000000 : -1,
            "lengthSeconds": entry.lengthSupported === true ? Number(entry.length) / 1000000 : -1,
            "canToggle": entry.canTogglePlaying === true || entry.canPlay === true || entry.canPause === true,
            "canNext": entry.canGoNext === true,
            "canPrevious": entry.canGoPrevious === true,
            "canSeek": entry.canSeek === true
        })
    }

    // Advances the local position between MPRIS pushes. A paused player stops
    // the timer, so the scrubber holds rather than drifting.
    function tickPosition() {
        if (root.lengthSeconds <= 0 || root.positionSeconds < 0)
            return
        var next = root.positionSeconds + 0.5
        if (next > root.lengthSeconds)
            next = root.lengthSeconds
        root.publish({
            "title": root.title,
            "artist": root.artist,
            "album": root.album,
            "artUrl": root.artUrl,
            "playerName": root.playerName,
            "playing": root.playing,
            "positionSeconds": next,
            "lengthSeconds": root.lengthSeconds,
            "canToggle": root.canToggle,
            "canNext": root.canNext,
            "canPrevious": root.canPrevious,
            "canSeek": root.canSeek
        })
    }

    function publish(fields) {
        sampleCount += 1
        snapshot = Object.assign({
            "available": true,
            "detail": "",
            "updatedMs": Date.now()
        }, fields === undefined || fields === null ? ({}) : fields)
    }

    function publishUnavailable(detail) {
        sampleCount += 1
        snapshot = {
            "available": false,
            "detail": String(detail === undefined || detail === null ? "" : detail),
            "updatedMs": Date.now()
        }
    }
}