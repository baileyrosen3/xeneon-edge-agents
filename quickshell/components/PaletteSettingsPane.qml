import QtQuick
import QtQuick.Window
import "../state/ThemePalette.js" as ThemePalette

Rectangle {
    id: root

    property bool open: false
    property var preferences
    property var sourceTheme: ThemePalette.fallback
    property var theme: ThemePalette.fallback
    property Item returnFocusItem: null

    signal closeRequested()
    signal interactionOccurred()

    readonly property var paletteRoles: ThemePalette.selectableRoles
    readonly property var mappingTargets: [
        {"id": "ready", "label": "READY", "fallback": "muted"},
        {"id": "success", "label": "SUCCESS", "fallback": "green"},
        {"id": "working", "label": "WORKING", "fallback": "blue"},
        {"id": "needsHelp", "label": "NEEDS HELP", "fallback": "yellow"},
        {
            "id": "reviewReady",
            "label": "REVIEW READY",
            "fallback": "green"
        },
        {"id": "error", "label": "ERROR", "fallback": "red"},
        {"id": "unknown", "label": "UNKNOWN", "fallback": "magenta"},
        {"id": "recording", "label": "RECORDING", "fallback": "green"},
        {"id": "processing", "label": "PROCESSING", "fallback": "cyan"}
    ]

    readonly property bool customized:
        storedSelectionFor("ready", "muted") !== "muted"
        || storedSelectionFor("success", "green") !== "green"
        || storedSelectionFor("working", "blue") !== "blue"
        || storedSelectionFor("needsHelp", "yellow") !== "yellow"
        || storedSelectionFor("reviewReady", "green") !== "green"
        || storedSelectionFor("error", "red") !== "red"
        || storedSelectionFor("unknown", "magenta") !== "magenta"
        || storedSelectionFor("recording", "green") !== "green"
        || storedSelectionFor("processing", "cyan") !== "cyan"

    function storedSelectionFor(target, fallbackRole) {
        if (preferences === null || preferences === undefined)
            return fallbackRole
        var value = preferences[target + "ColorRole"]
        if (value === undefined || value === null || String(value) === "")
            return fallbackRole
        return String(value).toLowerCase()
    }

    function selectionFor(target, fallbackRole) {
        if (preferences === null || preferences === undefined)
            return fallbackRole
        switch (target) {
        case "ready":
            return ThemePalette.selectableRole(
                preferences.readyColorRole, fallbackRole
            )
        case "success":
            return ThemePalette.selectableRole(
                preferences.successColorRole, fallbackRole
            )
        case "working":
            return ThemePalette.selectableRole(
                preferences.workingColorRole, fallbackRole
            )
        case "needsHelp":
            return ThemePalette.selectableRole(
                preferences.needsHelpColorRole, fallbackRole
            )
        case "reviewReady":
            return ThemePalette.selectableRole(
                preferences.reviewReadyColorRole, fallbackRole
            )
        case "error":
            return ThemePalette.selectableRole(
                preferences.errorColorRole, fallbackRole
            )
        case "unknown":
            return ThemePalette.selectableRole(
                preferences.unknownColorRole, fallbackRole
            )
        case "recording":
            return ThemePalette.selectableRole(
                preferences.recordingColorRole, fallbackRole
            )
        case "processing":
            return ThemePalette.selectableRole(
                preferences.processingColorRole, fallbackRole
            )
        default:
            return fallbackRole
        }
    }

    function setMapping(target, role) {
        if (preferences === null || preferences === undefined
                || ThemePalette.selectableRoles.indexOf(role) < 0)
            return false
        switch (target) {
        case "ready":
            preferences.readyColorRole = role
            break
        case "success":
            preferences.successColorRole = role
            break
        case "working":
            preferences.workingColorRole = role
            break
        case "needsHelp":
            preferences.needsHelpColorRole = role
            break
        case "reviewReady":
            preferences.reviewReadyColorRole = role
            break
        case "error":
            preferences.errorColorRole = role
            break
        case "unknown":
            preferences.unknownColorRole = role
            break
        case "recording":
            preferences.recordingColorRole = role
            break
        case "processing":
            preferences.processingColorRole = role
            break
        default:
            return false
        }
        if (typeof preferences.sync === "function")
            preferences.sync()
        root.interactionOccurred()
        return true
    }

    function resetMappings() {
        if (preferences === null || preferences === undefined)
            return false
        preferences.readyColorRole = "muted"
        preferences.successColorRole = "green"
        preferences.workingColorRole = "blue"
        preferences.needsHelpColorRole = "yellow"
        preferences.reviewReadyColorRole = "green"
        preferences.errorColorRole = "red"
        preferences.unknownColorRole = "magenta"
        preferences.recordingColorRole = "green"
        preferences.processingColorRole = "cyan"
        if (typeof preferences.sync === "function")
            preferences.sync()
        root.interactionOccurred()
        return true
    }

    function sourceColor(role) {
        return ThemePalette.roleColor(sourceTheme, role, "accent")
    }

    function visibleThemeName() {
        if (sourceTheme !== null && sourceTheme !== undefined
                && sourceTheme.themeName !== undefined) {
            var name = String(sourceTheme.themeName || "").trim()
            if (name !== "")
                return name.toUpperCase()
        }
        return "CURRENT OMARCHY THEME"
    }
    function focusTargets(item, targets) {
        if (!item.visible || !item.enabled) return
        if (item.activeFocusOnTab) targets.push(item)
        for (var i = 0; i < item.children.length; ++i)
            focusTargets(item.children[i], targets)
    }
    function moveFocus(backwards) {
        var targets = []
        focusTargets(root, targets)
        if (!targets.length) return
        var current = -1
        for (var i = 0; i < targets.length; ++i)
            if (targets[i].activeFocus) { current = i; break }
        var next = current < 0 ? (backwards ? targets.length - 1 : 0)
            : (current + (backwards ? -1 : 1) + targets.length) % targets.length
        targets[next].forceActiveFocus(backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason)
    }
    function acquireFocus() {
        if (!open || !visible || !enabled) return
        if (root.Window.window)
            returnFocusItem = root.Window.window.activeFocusItem
        closeButton.forceActiveFocus(Qt.OtherFocusReason)
    }
    onOpenChanged: {
        if (open) Qt.callLater(acquireFocus)
        else {
            var previous = returnFocusItem
            returnFocusItem = null
            Qt.callLater(function() {
                if (!root.open && previous && previous.visible && previous.enabled)
                    previous.forceActiveFocus(Qt.OtherFocusReason)
            })
        }
    }
    Component.onCompleted: { if (open) Qt.callLater(acquireFocus) }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (!root.open) return
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.moveFocus(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) !== 0)
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            event.accepted = true
            if (!event.isAutoRepeat) root.closeRequested()
        }
    }

    objectName: "paletteSettingsPane"
    width: 960
    height: 610
    radius: 20
    visible: root.open
    enabled: root.open
    color: theme.surface
    border.width: 2
    border.color: theme.borderStrong
    clip: true

    Accessible.role: Accessible.Grouping
    Accessible.ignored: !open
    Accessible.name: "XENEON palette mapping"
    Accessible.description:
        "Assign current Omarchy theme colors to agent application states"

    // Keep taps in blank pane space from reaching cards or ambient wake
    // handling beneath this overlay. Later children remain the topmost hit
    // targets for their own controls.
    Item {
        anchors.fill: parent

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
        }
    }

    Column {
        anchors {
            fill: parent
            margins: 18
        }
        spacing: 8

        Item {
            width: parent.width
            height: 44

            Column {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                spacing: 1

                Text {
                    text: "PALETTE MAPPING"
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font {
                        family: "monospace"
                        pixelSize: 18
                        weight: Font.Bold
                        letterSpacing: 1
                    }
                }

                Text {
                    text: "THEME // " + root.visibleThemeName()
                    textFormat: Text.PlainText
                    color: root.theme.textMuted
                    font {
                        family: "monospace"
                        pixelSize: 9
                        letterSpacing: 0.5
                    }
                }
            }

            DashboardButton {
                id: closeButton
                objectName: "paletteCloseButton"
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 48
                height: 44
                theme: root.theme
                label: "CLOSE"
                labelPixelSize: 9
                Keys.forwardTo: [root]
                Accessible.name: "Close palette mapping"
                onClicked: root.closeRequested()
            }
        }

        Item {
            width: parent.width
            height: 64

            Text {
                id: sourcePaletteLabel
                anchors {
                    left: parent.left
                    top: parent.top
                }
                text: "CURRENT THEME COLORS"
                textFormat: Text.PlainText
                color: root.theme.textSecondary
                font {
                    family: "monospace"
                    pixelSize: 10
                    weight: Font.DemiBold
                    letterSpacing: 0.6
                }
            }

            Row {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: sourcePaletteLabel.bottom
                    topMargin: 5
                }
                height: 48

                Repeater {
                    model: root.paletteRoles

                    Item {
                        required property string modelData
                        width: parent.width / root.paletteRoles.length
                        height: parent.height

                        Column {
                            anchors.centerIn: parent
                            spacing: 3

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 24
                                height: 24
                                radius: 12
                                color: root.sourceColor(parent.parent.modelData)
                                border.width: 1
                                border.color: root.theme.textSecondary
                            }

                            Text {
                                width: parent.parent.width - 4
                                text: parent.parent.modelData.toUpperCase()
                                textFormat: Text.PlainText
                                color: root.theme.textMuted
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                font {
                                    family: "monospace"
                                    pixelSize: 9
                                    weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }
        }

        Flickable {
            id: mappingList
            width: parent.width
            height: Math.max(44, parent.height - 176)
            contentWidth: width
            contentHeight: mappingColumn.height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            clip: true

            Column {
                id: mappingColumn
                width: mappingList.width

                Repeater {
                    model: root.mappingTargets

                    Item {
                        id: mappingRow
                        required property var modelData
                        width: parent.width
                        height: 44
                        Accessible.role: Accessible.Grouping
                        Accessible.name: modelData.label + " color"

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            width: 160
                            text: mappingRow.modelData.label
                            textFormat: Text.PlainText
                            color: root.theme.textPrimary
                            elide: Text.ElideRight
                            font {
                                family: "monospace"
                                pixelSize: 11
                                weight: Font.Bold
                                letterSpacing: 0.5
                            }
                        }

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: 160
                            }
                            height: parent.height

                            Repeater {
                                id: roleButtons
                                model: root.paletteRoles

                                Rectangle {
                                    id: roleButton
                                    required property string modelData
                                    required property int index
                                    readonly property bool selected:
                                        root.selectionFor(
                                            mappingRow.modelData.id,
                                            mappingRow.modelData.fallback
                                        ) === modelData

                                    objectName: "paletteRole_"
                                        + mappingRow.modelData.id + "_"
                                        + modelData
                                    width: parent.width / root.paletteRoles.length
                                    height: parent.height
                                    radius: 10
                                    color: roleTap.pressed
                                        ? root.theme.surfacePressed
                                        : selected
                                            ? Qt.alpha(
                                                root.sourceColor(modelData),
                                                0.16
                                            )
                                            : "transparent"
                                    activeFocusOnTab: enabled && visible && selected
                                    border.width: activeFocus ? 3 : selected ? 2 : 0
                                    border.color: activeFocus ? root.theme.accent : root.theme.textPrimary
                                    Keys.forwardTo: [root]
                                    Keys.onPressed: function(event) {
                                        var next = index
                                        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                                            next = (index + roleButtons.count - 1) % roleButtons.count
                                        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                                            next = (index + 1) % roleButtons.count
                                        else if (event.key === Qt.Key_Home)
                                            next = 0
                                        else if (event.key === Qt.Key_End)
                                            next = roleButtons.count - 1
                                        else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            event.accepted = true
                                            if (!event.isAutoRepeat) activate()
                                            return
                                        } else return
                                        event.accepted = true
                                        var button = roleButtons.itemAt(next)
                                        if (button) button.activate()
                                    }
                                    onActiveFocusChanged: {
                                        if (!activeFocus) return
                                        if (mappingRow.y < mappingList.contentY)
                                            mappingList.contentY = mappingRow.y
                                        else if (mappingRow.y + mappingRow.height > mappingList.contentY + mappingList.height)
                                            mappingList.contentY = mappingRow.y + mappingRow.height - mappingList.height
                                    }

                                    function activate() {
                                        if (!enabled) return false
                                        forceActiveFocus(Qt.OtherFocusReason)
                                        return root.setMapping(mappingRow.modelData.id, modelData)
                                    }

                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: mappingRow.modelData.label
                                        + " uses " + modelData
                                    Accessible.checkable: true
                                    Accessible.checked: selected
                                    Accessible.focusable: enabled && visible
                                    Accessible.focused: activeFocus
                                    Accessible.onToggleAction: activate()
                                    Accessible.onPressAction: activate()

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: roleButton.selected ? 24 : 18
                                        height: width
                                        radius: width / 2
                                        color: root.sourceColor(roleButton.modelData)
                                        border.width: 1
                                        border.color: root.theme.textSecondary

                                        Text {
                                            anchors.centerIn: parent
                                            visible: roleButton.selected
                                            text: "✓"
                                            textFormat: Text.PlainText
                                            color: ThemePalette.ensureContrast(
                                                String(root.theme.textPrimary),
                                                String(root.sourceColor(
                                                    roleButton.modelData
                                                )),
                                                4.5
                                            )
                                            font {
                                                family: "monospace"
                                                pixelSize: 14
                                                weight: Font.Bold
                                            }
                                        }
                                    }

                                    TapHandler {
                                        id: roleTap
                                        gesturePolicy:
                                            TapHandler.ReleaseWithinBounds
                                        onTapped: roleButton.activate()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 44

            Text {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                width: parent.width - resetButton.width - 18
                text: "CHROME AND TEXT CONTRAST REMAIN AUTOMATIC"
                textFormat: Text.PlainText
                color: root.theme.textMuted
                elide: Text.ElideRight
                font {
                    family: "monospace"
                    pixelSize: 9
                    letterSpacing: 0.5
                }
            }

            DashboardButton {
                id: resetButton
                objectName: "paletteResetButton"
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 150
                height: 44
                theme: root.theme
                enabled: root.customized
                label: "RESET DEFAULTS"
                labelPixelSize: 9
                Keys.forwardTo: [root]
                Accessible.name: "Reset palette mappings"
                Accessible.description: "Restore the reviewed default roles"
                onClicked: {
                    root.resetMappings()
                    closeButton.forceActiveFocus(Qt.OtherFocusReason)
                }
            }
        }
    }
}
