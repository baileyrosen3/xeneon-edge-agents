import QtQml
import "SourceParse.js" as Parse

// Whether a system update is waiting.
//
// One bit, conveyed one bit's worth. The helper exits 0 when an update is
// pending and non-zero when the tree is current, so the bit comes from the exit
// status rather than from parsing an English sentence.
//
// The update *action* is deliberately not implemented: on this surface it is a
// floating terminal, which the parity plan classifies NOT-PORTABLE.
SourceBase {
    id: root

    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "update"
    }

    // The current widget polls every six hours.
    function intervalMs() {
        return 21600000
    }

    function probeList() {
        return [
            { "label": "available", "argv": ["/usr/bin/omarchy-update-available"] }
        ]
    }

    readonly property bool updatePending: snapshot.pending === true
    readonly property string detail: snapshot.detail || ""

    function ingest(results) {
        if (results === null || results === undefined) {
            root.publishUnavailable("Update status was not collected")
            return
        }
        var entry = results.available
        if (entry === undefined || entry === null) {
            root.publishUnavailable("Update status probe did not run")
            return
        }
        // The exit status is the signal. The message is kept only as the pill's
        // accessible name, never parsed for meaning.
        var pending = Number(entry.code) === 0
        root.publish({
            "pending": pending,
            "detail": String(entry.text || "").trim()
        })
    }
}
