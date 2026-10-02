import QtQuick
import QtTest
import "../state"

TestCase {
    id: testCase
    name: "DashboardStoreSafety"

    PortalStore { id: dashboardStore }
    PortalBridge { id: bridge; store: dashboardStore; enabled: false; previewMode: true }
    SignalSpy { id: commands; target: bridge; signalName: "commandEmitted" }
    SignalSpy { id: rejections; target: bridge; signalName: "commandRejected" }

    function init() {
        dashboardStore.reset()
        commands.clear()
        rejections.clear()
    }

    function snapshot(generated) {
        return {
            "schema_version": 1, "type": "snapshot", "daemon_epoch": "dashboard-test",
            "sequence": 7, "generated_at_ms": generated, "connection": "connected",
            "sessions": [], "agents": [], "voice": {"state": "unavailable"}, "health": {},
            "omarchy": {"audio": {"available": true, "volume_percent": 25}, "theme": "Original", "dnd": false},
            "trading": {
                "connection": "connected", "broker_connected": true, "execution_enabled": true,
                "accounts": [{"id": "18446744073709551615", "label": "Demo", "can_trade": true, "balance": 50000}],
                "positions": [{"account_id": "18446744073709551615", "symbol": "NQZ6", "quantity": 1}],
                "orders": [{"id": "18446744073709551614", "account_id": "18446744073709551615", "symbol": "NQZ6"}],
                "fills": [{"id": "18446744073709551613", "account_id": "18446744073709551615", "symbol": "NQZ6"}],
                "quotes": []
            }
        }
    }

    function test_equalSequenceNewerObservationUpdatesBothDashboards() {
        verify(dashboardStore.ingestEnvelope(snapshot(1000)))
        var newer = snapshot(1001)
        newer.omarchy.audio.volume_percent = 65
        newer.omarchy.theme = "Updated"
        newer.omarchy.dnd = true
        newer.trading.accounts[0].balance = 50012.5
        newer.trading.positions = []
        newer.trading.orders = []
        verify(dashboardStore.ingestEnvelope(newer))
        compare(dashboardStore.sequence, 7)
        compare(dashboardStore.omarchy.audio.volume_percent, 65)
        compare(dashboardStore.omarchy.theme, "Updated")
        compare(dashboardStore.omarchy.dnd, true)
        compare(dashboardStore.trading.accounts[0].balance, 50012.5)
        compare(dashboardStore.trading.positions.length, 0)
        compare(dashboardStore.trading.orders.length, 0)
        verify(!dashboardStore.ingestEnvelope(snapshot(999)))
        compare(dashboardStore.omarchy.theme, "Updated")
    }

    function test_opaqueTradingHandlesRemainExactStrings() {
        verify(dashboardStore.ingestEnvelope(snapshot(1000)))
        compare(dashboardStore.trading.accounts[0].id, "18446744073709551615")
        compare(dashboardStore.trading.positions[0].account_id, "18446744073709551615")
        compare(dashboardStore.trading.orders[0].id, "18446744073709551614")
        compare(dashboardStore.trading.fills[0].id, "18446744073709551613")
        var unsafe = snapshot(1001)
        unsafe.trading.accounts[0].id = 9007199254740992
        unsafe.trading.orders[0].account_id = 9007199254740992
        verify(dashboardStore.ingestEnvelope(unsafe))
        compare(dashboardStore.trading.accounts[0].id, "")
        compare(dashboardStore.trading.orders[0].account_id, "")
    }

    function test_capabilitiesDefaultFalseAndBrokerDisconnectDisarmsExecution() {
        verify(dashboardStore.ingestEnvelope(snapshot(1000)))
        compare(dashboardStore.trading.supports_close, false)
        compare(dashboardStore.trading.supports_reverse, false)
        compare(dashboardStore.trading.positions[0].can_close, false)
        var disconnected = snapshot(1001)
        disconnected.trading.broker_connected = false
        disconnected.trading.supports_close = true
        verify(dashboardStore.ingestEnvelope(disconnected))
        compare(dashboardStore.trading.execution_enabled, false)
        var stale = snapshot(1002)
        stale.trading.connection = "stale"
        verify(dashboardStore.ingestEnvelope(stale))
        compare(dashboardStore.trading.execution_enabled, false)
    }

    function test_previewBridgeBlocksDesktopAndTradingControlDispatch() {
        verify(dashboardStore.ingestEnvelope(snapshot(1000)))
        compare(bridge.omarchyAction({"operation": "volume", "percent": 55}), "")
        compare(bridge.tradingAction({"action": "cancel_all", "account_id": "18446744073709551615"}), "")
        compare(commands.count, 0)
        compare(rejections.count, 2)
        compare(dashboardStore.pendingRequestOrder.length, 0)
        compare(bridge.bridgeProcess.running, false)
    }
}
