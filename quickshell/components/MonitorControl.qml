pragma ComponentBehavior: Bound
import QtQuick

DashboardCard {
    id: root
    required property var control
    property real draft: 0
    property bool writable: false
    property bool pending: false
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
        label: root.hasValue ? root.control.current + " / " + root.control.maximum : "—"
        detail: root.pending ? "PENDING" : root.hasValue ? "READ VALUE" : "UNAVAILABLE"
        enabled: root.writable
        onClicked: root.numberRequested()
    }
    Text {
        x: 16
        y: 61
        width: parent.width - 32
        text: root.pending ? "Writing · waiting for hardware readback" : !root.hasValue || !root.control.writable ? String(root.control.reason || "Not exposed by this monitor") : root.draft !== Number(root.control.current) ? "SET " + root.draft + "  ·  release to apply" : "Raw units 0–" + root.control.maximum + "  ·  drag or tap value"
        textFormat: Text.PlainText
        font.pixelSize: 15
        color: root.pending ? root.theme.accent : root.theme.textMuted
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
