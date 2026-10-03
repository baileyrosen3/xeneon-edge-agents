import QtQml
import Quickshell
import Quickshell.Services.UPower

// Battery state through UPower, the same service the Omarchy power panel uses.
// A desktop with no battery reports unavailable rather than a full charge,
// because "no battery" and "fully charged" must not look the same.
QtObject {
    id: root

    function sourceId() {
        return "power"
    }

    readonly property var devices: UPower.devices ? UPower.devices.values : []
    readonly property var displayDevice: UPower.displayDevice ? UPower.displayDevice : null
    readonly property bool onBattery: UPower.onBattery === true

    readonly property bool available: snapshot.available === true
    readonly property int percent: available ? Number(snapshot.percent) : -1
    readonly property bool charging: available && snapshot.charging === true
    readonly property string state: available ? String(snapshot.state || "") : ""
    readonly property string model: available ? String(snapshot.model || "") : ""

    // A compact charge glyph: filled bars for the coarse level, and a bolt
    // while the pack is charging. Glyphs come from the theme's font, so they
    // inherit the active palette instead of hardcoding a colour.
    readonly property int bars: !available || percent < 0
        ? 0
        : (percent >= 90 ? 4 : percent >= 65 ? 3 : percent >= 40 ? 2 : percent >= 15 ? 1 : 0)

    property var snapshot: ({
        "available": false,
        "detail": "Waiting for UPower",
        "updatedMs": 0
    })

    // The power service publishes no aggregate change signal, so the snapshot is
    // rebuilt on a timer that samples the same module. Reading the service
    // rather than spawning anything keeps this cheap and truthful.
    property Timer upowerChangesTimer: Timer {
        interval: 4000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.rebuild()
    }

    Component.onCompleted: root.rebuild()

    function isPack(entry) {
        if (entry === null || entry === undefined)
            return false
        if (entry.isPresent !== true)
            return false
        // A pack publishes either energy (a real battery) or a charge
        // percentage (a wireless-controller style device).
        return (Number(entry.energy || 0) > 0 && Number(entry.energyCapacity || 0) > 0)
            || (Number(entry.percentage || 0) > 0)
    }

    function rebuild() {
        var pack = null
        for (var index = 0; index < root.devices.length; index += 1) {
            if (root.isPack(root.devices[index])) {
                pack = root.devices[index]
                break
            }
        }

        if (pack === null) {
            root.publishUnavailable("This machine reports no battery")
            return
        }

        var percentage = Number(pack.percentage)
        if (!Number.isFinite(percentage) || percentage < 0) {
            root.publishUnavailable("UPower reported no charge level")
            return
        }

        root.publish({
            "percent": Math.round(Math.max(0, Math.min(100, percentage))),
            "charging": root.onBattery === false && Number(pack.energyRate || 0) < 0
                ? false
                : (Number(pack.energyRate || 0) !== 0),
            "state": String(pack.state || ""),
            "model": String(pack.model || "")
        })
    }

    function publish(fields) {
        snapshot = Object.assign({
            "available": true,
            "detail": "",
            "updatedMs": Date.now()
        }, fields === undefined || fields === null ? ({}) : fields)
    }

    function publishUnavailable(detail) {
        snapshot = {
            "available": false,
            "detail": String(detail === undefined || detail === null ? "" : detail),
            "updatedMs": Date.now()
        }
    }
}