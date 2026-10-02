pragma ComponentBehavior: Bound
import QtQuick

DashboardCard {
    id: root
    required property var control
    property real draft: 0
    property bool writable: false
    property bool pending: false
    property bool queued: false
    property bool numberEnabled: writable
    readonly property bool targetVisible: hasValue && (pending || queued || draft !== Number(control.current))
    readonly property bool hasValue: control.supported === true && control.current !== null && control.current !== undefined && control.maximum !== null && control.maximum !== undefined && Number(control.maximum) > 0
    signal draftEdited(int value)
    signal valueReleased(int value)
    signal numberRequested
    Text {
        x: 16
        y: 19
        width: parent.width - 170
        text: String(root.control.label || root.control.id).toUpperCase()
        textFormat: Text.PlainText
        font.family: "monospace"
        font.pixelSize: 19
        font.weight: Font.DemiBold
        color: root.theme.textPrimary
        elide: Text.ElideRight
    }
    DashboardButton {
        objectName: "monitorNumeric_" + String(root.control.id)
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 10
        width: 136
        height: 44
        theme: root.theme
        label: root.targetVisible ? "SET " + root.draft : root.hasValue ? root.control.current + " / " + root.control.maximum : "—"
        detail: root.targetVisible ? "READ " + root.control.current + "/" + root.control.maximum : root.hasValue ? "READ VALUE" : "UNAVAILABLE"
        enabled: root.numberEnabled
        opacity: root.hasValue ? 1 : 0.42
        selected: root.targetVisible
        onClicked: root.numberRequested()
    }
    Text {
        x: 16
        y: 61
        width: parent.width - 32
        text: root.queued ? "Latest target " + root.draft + " · waiting for hardware" : root.pending ? "Applying live · waiting for hardware readback" : !root.hasValue || !root.control.writable ? String(root.control.reason || "Not exposed by this monitor") : "Raw units 0–" + root.control.maximum + "  ·  adjusts while dragging"
        textFormat: Text.PlainText
        font.pixelSize: 15
        color: root.pending || root.queued ? root.theme.accent : root.theme.textMuted
        wrapMode: Text.WordWrap
    }
    MonitorSlider {
        objectName: "monitorSlider_" + String(root.control.id)
        x: 16
        y: 90
        width: parent.width - 32
        height: 48
        theme: root.theme
        value: root.draft
        maximum: root.hasValue ? Number(root.control.maximum) : 1
        visible: root.hasValue
        enabled: root.writable
        opacity: enabled ? 1 : 0.32
        onEdited: function(value) { root.draftEdited(value) }
        onReleased: function(value) { root.valueReleased(value) }
    }
}
