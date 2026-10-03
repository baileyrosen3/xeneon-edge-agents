import QtQml
import Quickshell
import Quickshell.Services.SystemTray

// The desktop status-notifier tray. Activation goes back through the action
// dispatcher by item id, so the strip never calls an item method by name.
QtObject {
    id: root

    function sourceId() {
        return "tray"
    }

    readonly property var items: SystemTray.items ? SystemTray.items.values : []
    readonly property bool available: items.length > 0

    // A tray entry needs a stable id to be activatable. An item with neither
    // an id nor a title cannot be activated and is not published.
    readonly property var entries: publishableEntries()
    readonly property int count: entries.length

    property string hiddenTitles: "Sunshine,_ZjR5N746J,tether,chrome_status_icon_1"

    // Titles the user has chosen to keep out of the strip, matching the active
    // bar's hidden list in ~/.config/omarchy/shell.json.
    readonly property var hidden: hiddenTitles.toLowerCase().split(",").map(function(value) {
        return value.trim()
    })

    // The tray service publishes no aggregate change signal, so the entry list is
    // resampled on a timer. Reading the service rather than spawning
    // anything keeps this cheap and truthful.
    property Timer trayChangesTimer: Timer {
        interval: 2500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.logChanged()
    }

    function isHidden(entry) {
        var title = String(entry.tooltipTitle || entry.title || "").toLowerCase()
        return root.hidden.indexOf(title) !== -1
    }

    function publishableEntries() {
        var published = []
        for (var index = 0; index < root.items.length; index += 1) {
            var item = root.items[index]
            if (item === null || item === undefined)
                continue
            if (root.isHidden(item))
                continue
            if (String(item.id || "") === "" && String(item.tooltipTitle || item.title || "") === "")
                continue
            published.push({
                "id": String(item.id || ""),
                "title": String(item.title || ""),
                "tooltipTitle": String(item.tooltipTitle || ""),
                "tooltipDescription": String(item.tooltipDescription || ""),
                "status": String(item.status || ""),
                "category": String(item.category || "")
            })
        }
        return published
    }

    function logChanged() {
        console.log("xeneon-home[tray] " + root.entries.length + " tray entries"
        )
    }
}