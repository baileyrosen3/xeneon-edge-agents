import QtQml
import "SourceParse.js" as Parse

// Local wall-clock time. This source owns no external tool: it reads the
// system clock directly and ticks once a second so the strip stays honest.
// Every rendered field is derived from a single `epochMs` sample, so the clock
// and the date can never disagree within one tick.
QtObject {
    id: root

    function sourceId() {
        return "clock"
    }
    property bool active: true
    property bool showSeconds: false
    property int sampleCount: 0

    readonly property int epochMs: snapshot.epochMs || 0
    readonly property bool available: snapshot.available === true
    readonly property date now: new Date(epochMs)

    readonly property string clock: available
        ? (showSeconds
            ? Parse.formatClockWithSeconds(now)
            : Parse.formatClock(now))
        : "--:--"

    readonly property string meridiem: available && now.getHours() >= 12 ? "PM" : "AM"
    readonly property string dateText: available ? Parse.formatDate(now) : ""

    property var snapshot: ({
        "available": false,
        "detail": "Waiting for the first tick",
        "updatedMs": 0,
        "epochMs": 0
    })

    property Timer tick: Timer {
        interval: 1000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    function sample() {
        var current = new Date()
        sampleCount += 1
        snapshot = {
            "available": true,
            "detail": "",
            "updatedMs": Date.now(),
            "epochMs": current.getTime()
        }
    }
}