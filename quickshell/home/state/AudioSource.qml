import QtQml
import "SourceParse.js" as Parse

// Default-sink volume and mute state from PulseAudio, the same values the
// Omarchy audio panel reads and the same executable the allowlisted volume
// actions dispatch through.
SourceBase {
    id: root

    // The uniform snapshot contract every source publishes, so the UI reads
    // one shape regardless of which tool backs it.
    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "audio"
    }

    function intervalMs() {
        return 2500
    }

    function probeList() {
        return [
            { "label": "volume", "argv": ["/usr/bin/pactl", "get-sink-volume", "@DEFAULT_SINK@"] },
            { "label": "mute", "argv": ["/usr/bin/pactl", "get-sink-mute", "@DEFAULT_SINK@"] }
        ]
    }

    readonly property real percent: snapshot.percent === null || snapshot.percent === undefined
        ? -1
        : snapshot.percent
    readonly property bool muted: snapshot.muted === true

    function ingest(results) {
        var volume = null
        if (root.probeSucceeded(results, "volume"))
            volume = Parse.parseSinkVolume(root.probeText(results, "volume"))

        var mute = null
        if (root.probeSucceeded(results, "mute"))
            mute = Parse.parseSinkMute(root.probeText(results, "mute"))

        if (volume === null && mute === null) {
            root.publishUnavailable("PulseAudio reported no default sink")
            return
        }

        root.publish({
            "percent": volume === null ? null : volume.percent,
            "muted": mute !== null && mute.muted
        })
    }
}