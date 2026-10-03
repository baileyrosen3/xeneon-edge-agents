import QtQml
import "SourceParse.js" as Parse

// Workspaces, the focused monitor, the active window, and every window
// address the compositor currently publishes. Read with `hyprctl -j`, which is
// the same source the Omarchy bar's workspace plugin reads.
SourceBase {
    id: root

    // The uniform snapshot contract every source publishes, so the UI reads
    // one shape regardless of which tool backs it.
    readonly property bool available: snapshot.available === true

    function sourceId() {
        return "hyprland"
    }

    function intervalMs() {
        return 2000
    }

    function probeList() {
        return [
            { "label": "monitors", "argv": ["/usr/bin/hyprctl", "-j", "monitors"] },
            { "label": "workspaces", "argv": ["/usr/bin/hyprctl", "-j", "workspaces"] },
            { "label": "activewindow", "argv": ["/usr/bin/hyprctl", "-j", "activewindow"] },
            { "label": "clients", "argv": ["/usr/bin/hyprctl", "-j", "clients"] }
        ]
    }

    readonly property var workspaces: snapshot.workspaces || []
    readonly property var monitors: snapshot.monitors || []
    readonly property var windowAddresses: snapshot.windowAddresses || []
    readonly property var activeWindow: snapshot.activeWindow || null
    readonly property int focusedWorkspace: focusedMonitorActiveWorkspace(monitors)

    function focusedMonitorActiveWorkspace(list) {
        for (var index = 0; index < list.length; index += 1) {
            if (list[index].focused === true)
                return list[index].activeWorkspace
        }
        return -1
    }

    function ingest(results) {
        var monitors = null
        var workspaces = null
        var activeWindow = null
        var addresses = null
        var failures = []

        if (root.probeSucceeded(results, "monitors")) {
            monitors = Parse.parseMonitors(root.probeText(results, "monitors"))
            if (monitors === null)
                failures.push("monitors")
        } else {
            failures.push("monitors")
        }

        if (root.probeSucceeded(results, "workspaces")) {
            workspaces = Parse.parseWorkspaces(root.probeText(results, "workspaces"))
            if (workspaces === null)
                failures.push("workspaces")
        } else {
            failures.push("workspaces")
        }

        if (root.probeSucceeded(results, "activewindow")) {
            activeWindow = Parse.parseActiveWindow(root.probeText(results, "activewindow"))
            if (activeWindow === null || activeWindow.address === "")
                activeWindow = null
        }

        if (root.probeSucceeded(results, "clients"))
            addresses = Parse.parseClientAddresses(root.probeText(results, "clients"))
        if (addresses === null)
            addresses = activeWindow === null ? [] : [activeWindow.address]

        if (monitors === null || workspaces === null) {
            root.log(
                "monitors=" + (monitors === null ? "null" : "ok")
                + " workspaces=" + (workspaces === null ? "null" : "ok")
                + " failures=" + failures.join(",")
            )
            root.publishUnavailable(
                "hyprctl did not report " + failures.join(" and ")
            )
            return
        }

        root.publish({
            "monitors": monitors,
            "workspaces": workspaces,
            "activeWindow": activeWindow,
            "windowAddresses": addresses
        })
    }
}