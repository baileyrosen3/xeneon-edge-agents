import QtQuick
import "../state/ThemePalette.js" as ThemePalette

Item {
    id: root

    property var usage: ({"providers": []})
    property var theme: ThemePalette.fallback
    property var agents: []
    property var sessions: []
    property string managerLabel: "HERDR"
    property bool reducedMotion: false
    property bool expanded: false
    property int clockTick: 0

    readonly property var providerIds: ["claude", "codex", "opencode"]

    function provider(id) {
        var providers = usage !== null
                && usage !== undefined
                && Array.isArray(usage.providers)
            ? usage.providers
            : []
        for (var index = 0; index < providers.length; index += 1) {
            if (String(providers[index].id || "") === id)
                return providers[index]
        }
        return {
            "id": id,
            "label": id === "opencode" ? "OpenCode"
                : id.charAt(0).toUpperCase() + id.slice(1),
            "kind": id === "opencode" ? "local_budget" : "quota",
            "available": false,
            "stale": true,
            "primary": null,
            "secondary": null,
            "model": ""
        }
    }

    function percent(window) {
        if (window === null)
            return 0
        return Math.max(
            0,
            Math.min(100, Math.round(Number(window.utilization || 0) * 100))
        )
    }

    function resetLabel(window) {
        clockTick
        if (window === null || Number(window.reset_at_ms || 0) <= 0)
            return "NO RESET"
        var remaining = Math.max(
            0,
            Math.floor((Number(window.reset_at_ms) - Date.now()) / 60000)
        )
        if (remaining >= 1440)
            return "RESET " + Math.floor(remaining / 1440) + "D "
                + Math.floor((remaining % 1440) / 60) + "H"
        if (remaining >= 60)
            return "RESET " + Math.floor(remaining / 60) + "H "
                + (remaining % 60) + "M"
        return "RESET " + remaining + "M"
    }

    function countLabel(count, singular, plural) {
        return count + " " + (count === 1 ? singular : plural)
    }

    function fleetSummary() {
        return countLabel(agents.length, "AGENT", "AGENTS")
            + " · " + countLabel(sessions.length, "SESSION", "SESSIONS")
    }

    function focusedSummary() {
        var focused = 0
        for (var index = 0; index < agents.length; index += 1) {
            if (agents[index].focused === true)
                focused += 1
        }
        return focused > 0
            ? focused + " FOCUSED"
            : "NO FOCUSED AGENT"
    }

    function formatTokens(value) {
        var count = Math.max(0, Number(value || 0))
        if (count >= 1000000000)
            return (count / 1000000000).toFixed(
                count >= 10000000000 ? 1 : 2
            ) + "B"
        if (count >= 1000000)
            return (count / 1000000).toFixed(
                count >= 100000000 ? 0 : count >= 10000000 ? 1 : 2
            ) + "M"
        if (count >= 1000)
            return (count / 1000).toFixed(count >= 100000 ? 0 : 1) + "K"
        return Math.floor(count).toString()
    }

    function activitySummary(provider) {
        var today = Math.max(0, Number(provider.today_tokens || 0))
        var rate = Math.max(0, Number(provider.tokens_per_hour || 0))
        var fields = []
        if (today > 0)
            fields.push("TODAY " + formatTokens(today))
        if (rate > 0)
            fields.push("RATE " + formatTokens(rate) + "/H")
        if (fields.length > 0)
            return fields.join(" · ")
        if (String(provider.model || "") !== "")
            return String(provider.model).toUpperCase()
        return provider.available
            ? "NO RECENT TOKEN ACTIVITY"
            : "CAPACITY UNAVAILABLE"
    }

    function updatedLabel(provider) {
        clockTick
        var updated = Number(provider.last_updated_ms || 0)
        if (updated <= 0)
            return "UPDATE UNKNOWN"
        var minutes = Math.max(
            0,
            Math.floor((Date.now() - updated) / 60000)
        )
        if (minutes < 1)
            return "UPDATED NOW"
        if (minutes < 60)
            return "UPDATED " + minutes + "M AGO"
        if (minutes < 1440)
            return "UPDATED " + Math.floor(minutes / 60) + "H AGO"
        return "UPDATED " + Math.floor(minutes / 1440) + "D AGO"
    }

    function providerStatus(provider) {
        if (!provider.available) {
            if (provider.status === "rejected")
                return "LIMIT REACHED"
            if (provider.status === "blocked")
                return "BLOCKED"
            if (provider.source === "unknown")
                return "UNTRUSTED"
            return "NO DATA"
        }
        if (provider.stale)
            return "STALE"
        if (provider.status === "allowed_warning")
            return "WARNING"
        return "LIVE"
    }

    function providerDetail(provider) {
        var plan = String(provider.plan || "").trim()
        if (plan !== "")
            return plan.toUpperCase()
        return provider.kind === "local_budget"
            ? "LOCAL BUDGET"
            : "PROVIDER QUOTA"
    }

    function unavailableDetail(provider) {
        var status = providerStatus(provider)
        if (status === "UNTRUSTED")
            return "Source is untrusted.\nUsage values are not shown."
        if (status === "LIMIT REACHED")
            return "Provider limit reached.\nNo usable capacity reading."
        if (status === "BLOCKED")
            return "Provider access is blocked.\nNo usable capacity reading."
        return "No usable capacity reading.\nUpdate age is shown below."
    }

    function statusColor(provider, accent) {
        var state = providerStatus(provider)
        if (state === "LIVE")
            return accent
        if (state === "WARNING" || state === "STALE")
            return theme.needsHelp
        if (state === "NO DATA")
            return theme.textMuted
        return theme.orange
    }

    function readableColor(color) {
        return ThemePalette.ensureContrast(
            String(color),
            String(theme.surface),
            4.5
        )
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.clockTick += 1
    }

    component UsageLine: Item {
        property var usageWindow: null
        property string providerId: ""
        property string windowRole: ""
        property bool providerAvailable: false
        property color accent: root.theme.accent
        property bool reducedMotion: false

        visible: usageWindow !== null
        width: parent ? parent.width : 0
        height: visible ? (root.expanded ? 58 : 18) : 0

        Item {
            anchors.fill: parent

            Text {
                id: windowLabel

                objectName: "usageLabel_" + providerId + "_" + windowRole
                width: root.expanded
                    ? Math.max(0, parent.width - 90 - 224 - 24)
                    : Math.max(128, Math.ceil(implicitWidth) + 2)
                y: root.expanded ? 0 : (parent.height - height) / 2
                text: usageWindow === null
                    ? ""
                    : String(usageWindow.label || "USAGE").toUpperCase()
                textFormat: Text.PlainText
                color: root.theme.textSecondary
                elide: Text.ElideRight
                font {
                    family: "monospace"
                    pixelSize: root.expanded ? 26 : 10
                    weight: Font.DemiBold
                    letterSpacing: 0.4
                }
            }

            Rectangle {
                id: usageBar

                x: root.expanded ? 0 : windowLabel.width + 8
                y: root.expanded ? 40 : (parent.height - height) / 2
                width: root.expanded ? parent.width : Math.max(
                    60,
                    parent.width - windowLabel.width - 42 - 112 - 24
                )
                height: root.expanded ? 10 : 6
                radius: height / 2
                color: root.theme.surfaceRaised

                Rectangle {
                    width: parent.width * (
                        providerAvailable
                            ? root.percent(usageWindow) / 100
                            : 0
                    )
                    height: parent.height
                    radius: parent.radius
                    color: accent

                    Behavior on width {
                        NumberAnimation {
                            duration: reducedMotion ? 0 : 280
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            Text {
                x: root.expanded ? parent.width - width - 224 - 12
                    : usageBar.x + usageBar.width + 8
                y: root.expanded ? 0 : (parent.height - height) / 2
                width: root.expanded ? 90 : 42
                text: providerAvailable
                    ? root.percent(usageWindow) + "%"
                    : "—"
                textFormat: Text.PlainText
                color: providerAvailable
                    ? root.readableColor(accent)
                    : root.theme.textMuted
                horizontalAlignment: Text.AlignRight
                font {
                    family: "monospace"
                    pixelSize: root.expanded ? 28 : 11
                    weight: Font.Bold
                }
            }

            Text {
                x: root.expanded ? parent.width - width
                    : usageBar.x + usageBar.width + 8 + 42 + 8
                y: root.expanded ? 4 : (parent.height - height) / 2
                width: root.expanded ? 224 : 112
                text: root.resetLabel(usageWindow)
                textFormat: Text.PlainText
                color: root.theme.textMuted
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                font {
                    family: "monospace"
                    pixelSize: root.expanded ? 22 : 9
                    letterSpacing: 0.3
                }
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: 14

        Rectangle {
            visible: !root.expanded
            width: 286
            height: parent.height
            radius: 16
            color: root.theme.surface
            border.width: 1
            border.color: root.theme.border

            Column {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 22
                }
                spacing: 4

                Text {
                    objectName: "fleetTitle"
                    text: root.managerLabel + " FLEET"
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font {
                        family: "monospace"
                        pixelSize: 17
                        weight: Font.Bold
                        letterSpacing: 1.1
                    }
                }

                Text {
                    text: root.fleetSummary()
                    textFormat: Text.PlainText
                    color: root.theme.textMuted
                    font {
                        family: "monospace"
                        pixelSize: 10
                        letterSpacing: 0.6
                    }
                }

                Text {
                    text: root.focusedSummary()
                    textFormat: Text.PlainText
                    color: root.theme.textSecondary
                    font {
                        family: "monospace"
                        pixelSize: 9
                        letterSpacing: 0.6
                    }
                }
            }
        }

        Repeater {
            model: root.providerIds

            Rectangle {
                required property string modelData
                readonly property var provider: root.provider(modelData)
                readonly property var primaryUsage:
                    provider.primary === undefined ? null : provider.primary
                readonly property var secondaryUsage:
                    provider.secondary === undefined ? null : provider.secondary
                readonly property int primaryPercent: root.percent(primaryUsage)
                readonly property int secondaryPercent:
                    root.percent(secondaryUsage)
                readonly property string statusLabel:
                    root.providerStatus(provider)
                readonly property string activityLabel:
                    root.activitySummary(provider)
                readonly property color accent: modelData === "claude"
                    ? root.theme.orange
                    : modelData === "codex"
                        ? root.theme.green
                        : root.theme.magenta

                objectName: "usageCard_" + modelData
                width: root.expanded ? (root.width - 28) / 3
                    : (root.width - 286 - 42) / 3
                height: parent.height
                radius: 16
                color: root.theme.surface
                border.width: 1
                border.color: provider.available
                    ? Qt.alpha(accent, provider.stale ? 0.34 : 0.62)
                    : root.theme.border

                Item {
                    id: providerHeader

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: root.expanded ? 24 : 18
                        rightMargin: root.expanded ? 24 : 18
                        topMargin: root.expanded ? 18 : 10
                    }
                    height: root.expanded ? 80 : 22

                    Text {
                        id: providerName

                        width: root.expanded
                            ? Math.max(0, parent.width - statusText.width - 16)
                            : Math.min(132, implicitWidth)
                        text: String(parent.parent.provider.label || "").toUpperCase()
                        textFormat: Text.PlainText
                        color: root.theme.textPrimary
                        elide: Text.ElideRight
                        font {
                            family: "monospace"
                            pixelSize: root.expanded ? 34 : 14
                            weight: Font.Bold
                            letterSpacing: 0.7
                        }
                    }

                    Text {
                        x: root.expanded ? 0 : providerName.width + 9
                        y: root.expanded ? 48 : (parent.height - height) / 2
                        width: root.expanded ? parent.width : Math.max(
                            60,
                            parent.width - statusText.width - x - 9
                        )
                        text: root.providerDetail(parent.parent.provider)
                        textFormat: Text.PlainText
                        color: root.theme.textMuted
                        elide: Text.ElideRight
                        font {
                            family: "monospace"
                            pixelSize: root.expanded ? 24 : 9
                            letterSpacing: 0.4
                        }
                    }

                    Text {
                        id: statusText

                        x: parent.width - width
                        y: root.expanded ? 3 : (parent.height - height) / 2
                        text: parent.parent.statusLabel
                        textFormat: Text.PlainText
                        color: root.readableColor(
                            root.statusColor(
                                parent.parent.provider,
                                parent.parent.accent
                            )
                        )
                        font {
                            family: "monospace"
                            pixelSize: root.expanded ? 30 : 9
                            weight: Font.Bold
                            letterSpacing: 0.6
                        }
                    }
                }

                Column {
                    visible: !root.expanded || parent.provider.available
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: providerHeader.bottom
                        leftMargin: root.expanded ? 24 : 18
                        rightMargin: root.expanded ? 24 : 18
                        topMargin: root.expanded ? 12 : 4
                    }
                    spacing: root.expanded ? 12 : 3

                    UsageLine {
                        width: parent.width
                        providerId: parent.parent.modelData
                        windowRole: "primary"
                        usageWindow: parent.parent.primaryUsage
                        providerAvailable: parent.parent.provider.available
                        accent: parent.parent.accent
                        reducedMotion: root.reducedMotion
                    }

                    UsageLine {
                        width: parent.width
                        providerId: parent.parent.modelData
                        windowRole: "secondary"
                        usageWindow: parent.parent.secondaryUsage
                        providerAvailable: parent.parent.provider.available
                        accent: parent.parent.accent
                        reducedMotion: root.reducedMotion
                    }
                }

                Column {
                    visible: root.expanded && (!parent.provider.available
                        || (parent.primaryUsage === null
                            && parent.secondaryUsage === null))
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: providerHeader.bottom
                        leftMargin: 24
                        rightMargin: 24
                        topMargin: 24
                    }
                    spacing: 12

                    Text {
                        width: parent.width
                        text: parent.parent.provider.available
                            ? "NO CAPACITY WINDOWS"
                            : "CAPACITY UNAVAILABLE"
                        textFormat: Text.PlainText
                        color: root.readableColor(root.theme.textPrimary)
                        elide: Text.ElideRight
                        font {
                            family: "monospace"
                            pixelSize: 30
                            weight: Font.DemiBold
                        }
                    }

                    Text {
                        width: parent.width
                        text: parent.parent.provider.available
                            ? "No usage windows were reported."
                            : root.unavailableDetail(parent.parent.provider)
                        textFormat: Text.PlainText
                        color: root.readableColor(root.theme.textSecondary)
                        wrapMode: Text.WordWrap
                        font {
                            family: "monospace"
                            pixelSize: 24
                        }
                    }
                }

                Item {
                    id: providerFooter

                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: root.expanded ? 24 : 18
                        rightMargin: root.expanded ? 24 : 18
                        bottomMargin: root.expanded ? 18 : 9
                    }
                    height: root.expanded ? 62
                        : Math.max(activityText.implicitHeight, updateText.implicitHeight)

                    Text {
                        id: activityText

                        width: root.expanded ? parent.width : parent.width * 0.58
                        text: parent.parent.activityLabel
                        textFormat: Text.PlainText
                        color: root.theme.textSecondary
                        elide: Text.ElideRight
                        font {
                            family: "monospace"
                            pixelSize: root.expanded ? 24 : 9
                            weight: Font.DemiBold
                            letterSpacing: 0.3
                        }
                    }

                    Text {
                        id: updateText

                        x: root.expanded ? 0 : activityText.width + 10
                        y: root.expanded ? 34 : 0
                        width: root.expanded ? parent.width
                            : parent.width - activityText.width - 10
                        text: root.updatedLabel(parent.parent.provider)
                        textFormat: Text.PlainText
                        color: root.theme.textMuted
                        elide: Text.ElideRight
                        horizontalAlignment: root.expanded
                            ? Text.AlignLeft : Text.AlignRight
                        font {
                            family: "monospace"
                            pixelSize: root.expanded ? 24 : 9
                            letterSpacing: 0.3
                        }
                    }
                }
            }
        }
    }
}
