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
            { "label": "devices", "argv": ["/usr/bin/nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"] },
            // The same status helper the current network panel reads, for the
            // interface kind, address, and speed.
            {
                "label": "status",
                "argv": ["/usr/share/omarchy/bin/omarchy-network-status", "--verbose"]
            },
            // Wireless identity and strength. Only the connected network's row is
            // ever kept; the list of visible networks is not retained.
            {
                "label": "wifi",
                "argv": ["/usr/bin/nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "device", "wifi", "list"]
            }
        ]
    }

    // Detail beyond the connection name: the interface kind, its address, and
    // the wireless strength when this host is on wireless at all.
    readonly property string interfaceKind: snapshot.interfaceKind || ""
    readonly property string address: snapshot.address || ""
    readonly property bool wireless: interfaceKind === "wifi"
    readonly property int signal: snapshot.signal === null || snapshot.signal === undefined
        ? -1
        : snapshot.signal

    // Four bars, derived from the measured strength. -1 means no measurement.
    readonly property int signalBars: signal < 0
        ? 0
        : (signal >= 75 ? 4 : signal >= 55 ? 3 : signal >= 30 ? 2 : 1)

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

        var status = null
        if (root.probeSucceeded(results, "status"))
            status = Parse.parseNetworkStatus(root.probeText(results, "status"))

        var wifi = null
        if (root.probeSucceeded(results, "wifi"))
            wifi = Parse.parseWifiActive(root.probeText(results, "wifi"))

        var interfaceKind = status !== null && status.type !== undefined
            ? String(status.type)
            : detail.primaryType
        // An interface the status helper calls ethernet is wired, whatever
        // NetworkManager's own type column happened to say.
        if (interfaceKind === "ethernet")
            interfaceKind = "wired"

        root.publish({
            "connected": true,
            "device": detail.primaryDevice === "" ? route : detail.primaryDevice,
            "kind": detail.primaryType,
            "interfaceKind": interfaceKind,
            "address": status !== null && status.ip !== undefined ? String(status.ip) : "",
            "signal": wifi === null ? null : wifi.signal,
            "ssid": wifi === null ? "" : wifi.ssid,
            "connection": detail.primaryConnection,
            "connectedCount": detail.connectedCount,
            "wirelessConnected": detail.wirelessConnected,
            "wirelessTotal": detail.wirelessTotal
        })
    }
}