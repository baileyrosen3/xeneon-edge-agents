import QtQml
import "SourceParse.js" as Parse

// Network state from the default route and NetworkManager. The default route
// comes from /proc/net/route, which needs no external tool and no elevated
// privilege, so connectivity is still reported when NetworkManager is absent.
SourceBase {
    id: root

    // The uniform snapshot contract every source publishes, so the UI reads
    // one shape regardless of which tool backs it.
    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "network"
    }

    function intervalMs() {
        return 4000
    }

    function probeList() {
        return [
            { "label": "route", "argv": ["/usr/bin/cat", "/proc/net/route"] },
            { "label": "devices", "argv": ["/usr/bin/nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"] }
        ]
    }

    readonly property bool connected: snapshot.connected === true
    readonly property string kind: snapshot.kind || ""
    readonly property string connection: snapshot.connection || ""
    readonly property string device: snapshot.device || ""
    readonly property int connectedCount: snapshot.connectedCount || 0

    function ingest(results) {
        var route = ""
        if (root.probeSucceeded(results, "route"))
            route = Parse.parseDefaultRoute(root.probeText(results, "route"))

        if (route === "") {
            root.publishUnavailable("No default route is published")
            return
        }

        var detail = Parse.parseNetworkDevices(
            root.probeSucceeded(results, "devices")
                ? root.probeText(results, "devices")
                : "",
            route
        )

        root.publish({
            "connected": true,
            "device": detail.primaryDevice === "" ? route : detail.primaryDevice,
            "kind": detail.primaryType,
            "connection": detail.primaryConnection,
            "connectedCount": detail.connectedCount,
            "wirelessConnected": detail.wirelessConnected,
            "wirelessTotal": detail.wirelessTotal
        })
    }
}