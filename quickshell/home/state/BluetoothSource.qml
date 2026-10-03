import QtQml
import "SourceParse.js" as Parse

// Bluetooth controller power and the set of connected devices.
SourceBase {
    id: root

    // The uniform snapshot contract every source publishes, so the UI reads
    // one shape regardless of which tool backs it.
    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "bluetooth"
    }

    function intervalMs() {
        return 6000
    }

    function probeList() {
        return [
            { "label": "controller", "argv": ["/usr/bin/bluetoothctl", "show"] },
            { "label": "devices", "argv": ["/usr/bin/bluetoothctl", "devices", "Connected"] }
        ]
    }

    readonly property bool powered: snapshot.powered === true
    readonly property string adapterName: snapshot.adapterName || ""
    readonly property var devices: snapshot.devices || []
    readonly property int deviceCount: devices.length

    function ingest(results) {
        var controller = null
        if (root.probeSucceeded(results, "controller"))
            controller = Parse.parseBluetoothController(root.probeText(results, "controller"))

        if (controller === null) {
            root.publishUnavailable("No Bluetooth adapter is present")
            return
        }

        var devices = []
        if (root.probeSucceeded(results, "devices"))
            devices = Parse.parseBluetoothDevices(root.probeText(results, "devices"))

        root.publish({
            "powered": controller.powered,
            "adapterName": controller.name,
            "devices": devices
        })
    }
}