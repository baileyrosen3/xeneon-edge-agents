import QtQuick
import QtTest
import "../components"
import "../state/ThemePalette.js" as ThemePalette

TestCase {
    id: testCase
    name: "Dashboards"
    width: 2560
    height: 720
    visible: true
    when: windowShown
    QtObject {
        id: store
        signal actionResultReceived(var result)
        signal noticeReceived(var notice)
        property var agents: []
        property var agentOrder: ({
                available: true,
                mode: "grouped"
            })
        property var backend: ({
                mode: "herdr",
                switchable: true
            })
        property var sessions: []
        property var usage: ({
                providers: []
            })
        property var micro: ({
                connected: false,
                charging: false
            })
        property var voice: ({
                available: false,
                state: "unavailable"
            })
        property var health: ({})
        property var connection: ({
                state: "connected",
                detail: ""
            })
        property var omarchy: ({
                audio: {
                    available: true,
                    volume_percent: 55,
                    muted: false,
                    microphone_muted: true,
                    outputs: []
                },
                media: {
                    available: true,
                    title: "Midnight City",
                    artist: "M83",
                    playback_status: "playing"
                },
                dnd: false,
                keepawake: true,
                nightlight: false,
                recording: false,
                themes: ["Tokyo Night"],
                power_profiles: ["balanced"],
                storage: [],
                processes: []
            })
        property var trading: ({})
        property string transportDetail: ""
        property string protocolError: ""
        property bool freshSnapshotRequired: false
        property double sequence: 1
        property double generatedAtMs: 1
        function surfaceState() {
            return agents.length ? "ready" : "empty";
        }
    }
    QtObject {
        id: bridge
        signal commandRejected(string reason)
        signal commandEmitted(var command)
        property bool ready: true
        property int tradingRequests: 0
        property int desktopRequests: 0
        property var lastTrading: ({})
        function restoreFocus() {
            return "focus";
        }
        function openAgent(id) {
            return id;
        }
        function approveAgent() {
            return "approve";
        }
        function interruptAgent() {
            return "interrupt";
        }
        function openChatGptDesktop() {
            return "chatgpt";
        }
        function openClaudeDesktop() {
            return "claude";
        }
        function startVoice() {
            return "voice";
        }
        function stopVoice() {
            return "stop";
        }
        function cancelVoice() {
            return "cancel";
        }
        function setAgentOrder() {
            return "order";
        }
        function setAgentBackend() {
            return "backend";
        }
        function omarchyAction(payload) {
            desktopRequests += 1;
            return "omarchy-" + desktopRequests;
        }
        function tradingAction(payload) {
            tradingRequests += 1;
            lastTrading = payload;
            return "trading-" + tradingRequests;
        }
    }
    QtObject {
        id: activity
        property bool ambientMode: false
        function noteUserActivity() {
            ambientMode = false;
        }
    }
    QtObject {
        id: preferences
        property bool reduceMotion: true
        property bool dimmed: false
        property int dashboardIndex: 0
        function sync() {
        }
    }
    DashboardView {
        id: dashboards
        anchors.fill: parent
        store: store
        bridge: bridge
        activity: activity
        preferences: preferences
        theme: ThemePalette.fallback
        reducedMotion: true
    }

    function snapshot() {
        return {
            schema_version: 1,
            revision: 5,
            sampled_at_ms: Date.now(),
            connection: "connected",
            broker_connected: true,
            execution_enabled: true,
            supports_brackets: true,
            supports_flatten: true,
            supports_close: true,
            supports_reverse: true,
            accounts: [
                {
                    id: "exact-live-account",
                    label: "LIVE account",
                    account_type: "live",
                    can_trade: true,
                    balance: 50321.55,
                    open_pnl: 215.0,
                    closed_pnl: 90,
                    loss_limit: 2500,
                    min_account_balance: 48000
                }
            ],
            positions: [
                {
                    account_id: "exact-live-account",
                    symbol: "MESZ6",
                    quantity: 2,
                    can_close: true,
                    average_price: 5800.25,
                    open_pnl: 215
                }
            ],
            orders: [
                {
                    id: "stop-1",
                    account_id: "exact-live-account",
                    symbol: "MESZ6",
                    quantity: 2,
                    filled_quantity: 0,
                    side: "sell",
                    order_type: "stop_market",
                    stop_price: 5798.25,
                    status: "working"
                }
            ],
            fills: [
                {
                    id: "fill-1",
                    account_id: "exact-live-account",
                    symbol: "MESZ6",
                    quantity: 2,
                    side: "buy",
                    price: 5800.25,
                    time_ms: Date.now(),
                    pnl: 25,
                    fees: 1.24
                }
            ],
            quotes: [
                {
                    symbol: "MESZ6",
                    bid: 5801.25,
                    ask: 5801.5,
                    last: 5801.25,
                    tick_size: 0.25,
                    dollars_per_point: 5,
                    updated_at_ms: Date.now()
                },
                {
                    symbol: "MNQZ6",
                    bid: 21400.25,
                    ask: 21400.5,
                    last: 21400.5,
                    tick_size: 0.25,
                    dollars_per_point: 2,
                    updated_at_ms: Date.now()
                }
            ]
        };
    }
    function initTestCase() {
        // The runner reuses its window between files; pointer targets need this surface's size.
        Window.window.width = width;
        Window.window.height = height;
        Window.window.requestActivate();
        wait(0);
    }
    function init() {
        store.trading = snapshot();
        store.freshSnapshotRequired = false;
        store.health = {
            cpu: {
                available: true,
                value: 32
            },
            gpu: {
                available: true,
                value: 18
            },
            memory: {
                available: true,
                value: 44
            },
            cpu_temperature: {
                available: true,
                value: 59
            },
            gpu_temperature: {
                available: true,
                value: 48
            },
            network_down: {
                available: true,
                value: 2540800
            }
        };
        store.agents = [];
        for (var i = 0; i < 12; ++i)
            store.agents.push({
                id: "agent-" + i,
                display_name: "Agent " + (i + 1),
                agent: "codex",
                status: i % 3 === 0 ? "working" : "idle",
                review_ready: i === 2,
                focused: i === 0,
                observed_for_seconds: 100,
                workspace: "Omarchy",
                repository: "xeneon-edge-agents",
                worktree: "",
                actions: {
                    open: true,
                    zoom: true,
                    approve: i === 2 ? {
                        capability_id: "approve-2"
                    } : null,
                    interrupt: i === 0 ? {
                        capability_id: "interrupt-0"
                    } : null
                }
            });
        store.agents = store.agents.slice();
        bridge.ready = true;
        store.generatedAtMs = Date.now();
        bridge.tradingRequests = 0;
        bridge.desktopRequests = 0;
        preferences.reduceMotion = true;
        dashboards.reducedMotion = true;
        dashboards.monitorSettingsOpen = false;
        dashboards.sidebarOpen = false;
        var omarchy = findChild(dashboards, "omarchyControlPanel");
        omarchy.pendingRequest = "";
        omarchy.unknownOutcome = false;
        omarchy.unknownAtMs = 0;
        dashboards.previewMode = false;
        dashboards.selectDashboard(0);
        var trading = findChild(dashboards, "riptideDashboard");
        trading.unknownOutcome = false;
        trading.unknownAtMs = 0;
        trading.confirmationIsReview = false;
        trading.quantity = 1;
        trading.pendingRequest = "";
        trading.pendingAtMs = 0;
        trading.awaitingBroker = false;
        trading.keypadField = "";
        trading.confirmationOpen = false;
        trading.editingOrder = null;
        trading.orderType = "market";
        trading.price = "";
        trading.brackets = false;
        wait(0);
    }
    function test_motionPreferenceRemainsReversible() {
        dashboards.reducedMotion = false;
        preferences.reduceMotion = false;
        var agents = findChild(dashboards, "combinedAgentPortal");
        verify(agents.toggleMotionReduction());
        compare(preferences.reduceMotion, true);
        verify(agents.toggleMotionReduction());
        compare(preferences.reduceMotion, false);
        preferences.reduceMotion = true;
        verify(agents.toggleMotionReduction());
        compare(preferences.reduceMotion, false);
        dashboards.reducedMotion = true;
        verify(!agents.toggleMotionReduction());
        compare(preferences.reduceMotion, false);
    }
    function test_pendingBrokerAcknowledgementKeepsLocalExecutionLocked() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        var oldObservation = store.trading.sampled_at_ms;
        verify(trading.submit("buy", false));
        store.actionResultReceived({
            request_id: "trading-1",
            ok: true,
            code: "trading_pending",
            message: "Awaiting broker projection"
        });
        verify(!trading.canExecute);
        verify(!trading.submit("buy", false));
        dashboards.selectDashboard(5);
        dashboards.selectDashboard(1);
        store.trading = Object.assign({}, store.trading, {
            sampled_at_ms: oldObservation
        });
        verify(!trading.canExecute);
        compare(bridge.tradingRequests, 1);
        store.trading = Object.assign({}, store.trading, {
            sampled_at_ms: Date.now() + 1
        });
        tryCompare(trading, "canExecute", true);
        verify(!trading.feedbackSuccess);
        compare(bridge.tradingRequests, 1);
    }
    function test_lostDesktopResultRequiresFreshExplicitReview() {
        dashboards.selectDashboard(2);
        var omarchy = findChild(dashboards, "omarchyControlPanel");
        verify(omarchy.request({operation: "dnd"}));
        bridge.ready = false;
        store.freshSnapshotRequired = true;
        bridge.ready = true;
        store.freshSnapshotRequired = false;
        verify(!omarchy.request({operation: "dnd"}));
        var review = findChild(omarchy, "desktopReviewOutcome");
        verify(review !== null);
        verify(!review.enabled);
        store.generatedAtMs += 1;
        tryCompare(review, "enabled", true);
        mouseClick(review, review.width / 2, review.height / 2);
        compare(bridge.desktopRequests, 1);
        verify(omarchy.request({operation: "volume", percent: 60}));
        compare(bridge.desktopRequests, 2);
    }
    function test_keyboardMonitorExitRestoresSidebarFocus() {
        var handle = findChild(dashboards, "sidebarHandle");
        handle.forceActiveFocus(Qt.TabFocusReason);
        keyClick(Qt.Key_Space);
        tryCompare(dashboards, "sidebarOpen", true);
        keyClick(Qt.Key_End);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Space);
        tryCompare(dashboards, "monitorSettingsOpen", true);
        var monitor = findChild(dashboards, "monitorSettings");
        tryCompare(findChild(monitor, "monitorCloseButton"), "activeFocus", true);
        keyClick(Qt.Key_Tab);
        verify(monitor.activeFocus);
        keyClick(Qt.Key_Escape);
        tryCompare(dashboards, "monitorSettingsOpen", false);
        tryCompare(handle, "activeFocus", true);
        compare(bridge.desktopRequests, 0);
    }
    function test_navigationPreservesTradingDraftAcrossAllPresets() {
        var trading = findChild(dashboards, "riptideDashboard");
        trading.quantity = 15;
        trading.price = "5800.25";
        trading.orderType = "limit";
        for (var index = 0; index < 9; ++index)
            verify(dashboards.selectDashboard(index));
        dashboards.selectDashboard(1);
        compare(trading.quantity, 15);
        compare(trading.price, "5800.25");
        compare(trading.orderType, "limit");
    }
    function test_desktopShortcutsSharePresetNavigationWithoutReplayingActions() {
        var omarchy = findChild(dashboards, "omarchyControlPanel");
        verify(omarchy.request({operation: "dnd"}));
        for (var index = 3; index <= 5; ++index) {
            dashboards.selectDashboard(0);
            var shortcut = findChild(omarchy, "omarchyPreset_" + index);
            mouseClick(shortcut, shortcut.width / 2, shortcut.height / 2);
            tryCompare(dashboards, "dashboardIndex", index);
            verify(findChild(omarchy, "omarchyDetailPage").visible);
            compare(bridge.desktopRequests, 1);
            verify(!omarchy.request({operation: "dnd"}));
        }
        dashboards.selectDashboard(2);
        verify(!findChild(omarchy, "omarchyDetailPage").visible);
    }
    function test_sidebarSelectsAllNinePresetsAndPersistsSelection() {
        var handle = findChild(dashboards, "sidebarHandle");
        var pages = findChild(dashboards, "dashboardPages");
        var omarchy = findChild(dashboards, "omarchyControlPanel");
        var trading = findChild(dashboards, "riptideDashboard");
        for (var index = 0; index < 9; ++index) {
            mouseClick(handle, handle.width / 2, handle.height / 2);
            tryCompare(dashboards, "sidebarOpen", true);
            verify(!pages.enabled);
            tryCompare(findChild(dashboards, "dashboardSidebar"), "controlsEnabled", true);
            var button = findChild(dashboards, "presetButton_" + index);
            var list = findChild(dashboards, "sidebarPresetList");
            function settle() {
                for (var tick = 0; tick < 100; ++tick) {
                    if (!list.moving && !list.flicking)
                        return true;
                    wait(20);
                }
                return false;
            }
            var direction = 0;
            for (var scroll = 0; scroll < 40; ++scroll) {
                verify(settle());
                if (button.y >= list.contentY && button.y + button.height <= list.contentY + list.height)
                    break;
                if (direction === 0)
                    direction = button.y < list.contentY ? 120 : -120;
                var before = list.contentY;
                mouseWheel(list, list.width / 2, list.height / 2, 0, direction);
                wait(40);
                if (list.contentY === before)
                    direction = -direction;
            }
            verify(settle());
            mouseClick(button, button.width / 2, button.height / 2);
            tryCompare(dashboards, "dashboardIndex", index);
            tryCompare(dashboards, "sidebarOpen", false);
            tryCompare(pages, "enabled", true);
            compare(preferences.dashboardIndex, index);
            compare(trading.visible, index === 1);
            compare(omarchy.visible, index === 0 || index >= 2 && index <= 5);
        }
    }
    function dragSidebar(handle, distance) {
        var start = handle.mapToItem(dashboards, handle.width / 2, handle.height / 2);
        mousePress(dashboards, start.x, start.y);
        for (var step = 1; step <= 8; ++step)
            mouseMove(dashboards, start.x + distance * step / 8, start.y, 20);
        mouseRelease(dashboards, start.x + distance, start.y);
    }
    function test_edgeDragOpensClosesAndRestoresBinding() {
        var handle = findChild(dashboards, "sidebarHandle");
        var sidebar = findChild(dashboards, "dashboardSidebar");
        var drawer = findChild(dashboards, "sidebarDrawer");
        for (var repetition = 0; repetition < 2; ++repetition) {
            dragSidebar(handle, 420);
            tryCompare(dashboards, "sidebarOpen", true);
            tryCompare(drawer, "x", 0);
            dragSidebar(handle, -420);
            tryCompare(dashboards, "sidebarOpen", false);
            tryCompare(drawer, "x", -drawer.width);
            tryCompare(sidebar, "blocking", false);
        }
        mouseClick(handle, handle.width / 2, handle.height / 2);
        tryCompare(drawer, "x", 0);
        var backdrop = findChild(dashboards, "sidebarBackdrop");
        mouseClick(backdrop, backdrop.width - 100, backdrop.height / 2);
        tryCompare(drawer, "x", -drawer.width);
    }
    function test_sidebarEscapeAndInvalidSelectionCannotNavigate() {
        var handle = findChild(dashboards, "sidebarHandle");
        mouseClick(handle, handle.width / 2, handle.height / 2);
        tryCompare(dashboards, "sidebarOpen", true);
        keyClick(Qt.Key_Escape);
        tryCompare(dashboards, "sidebarOpen", false);
        dashboards.selectDashboard(8);
        var invalid = [-1, 9, 1.5, NaN, "1", undefined, null];
        for (var index = 0; index < invalid.length; ++index) {
            verify(!dashboards.selectDashboard(invalid[index]));
            compare(dashboards.dashboardIndex, 8);
            compare(preferences.dashboardIndex, 8);
        }
    }
    function test_drawerBlocksActionsUntilClosingAnimationFinishes() {
        dashboards.reducedMotion = false;
        preferences.reduceMotion = false;
        dashboards.selectDashboard(1);
        var pages = findChild(dashboards, "dashboardPages");
        var sidebar = findChild(dashboards, "dashboardSidebar");
        var trading = findChild(dashboards, "riptideDashboard");
        var handle = findChild(dashboards, "sidebarHandle");
        mouseClick(handle, handle.width / 2, handle.height / 2);
        tryCompare(dashboards, "sidebarOpen", true);
        verify(!trading.submit("buy", false));
        wait(300);
        dashboards.sidebarOpen = false;
        verify(!pages.enabled);
        verify(!trading.submit("buy", false));
        tryCompare(sidebar, "blocking", false);
        verify(pages.enabled);
        compare(bridge.tradingRequests, 0);
        dashboards.reducedMotion = true;
    }
    function test_staleQuoteBlocksOrderEntry() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        var stale = snapshot();
        stale.quotes[0].updated_at_ms = Date.now() - 30000;
        store.trading = stale;
        verify(!trading.canPlace);
        verify(!trading.submit("buy", false));
        compare(bridge.tradingRequests, 0);
    }
    function test_unknownOutcomeRequiresExplicitFreshReviewWithoutResend() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        verify(trading.submit("buy", false));
        store.actionResultReceived({
            request_id: "trading-1",
            ok: false,
            code: "trading_unknown",
            message: "Transport response lost"
        });
        verify(trading.unknownOutcome);
        verify(!trading.canExecute);
        verify(!trading.reviewOutcome());
        var currentSnapshot = snapshot();
        currentSnapshot.sampled_at_ms = Date.now() + 1;
        store.trading = currentSnapshot;
        verify(trading.reviewOutcome());
        compare(bridge.tradingRequests, 1);
        verify(trading.resumeReviewed());
        compare(trading.pendingRequest, "");
        verify(!trading.unknownOutcome);
        compare(bridge.tradingRequests, 1);
        verify(!trading.resumeReviewed());
    }
    function test_trailingStopRequiresTickAlignedInitialStop() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        trading.orderType = "trailing_stop";
        trading.stopPrice = "";
        verify(!trading.submit("sell", false));
        trading.stopPrice = "5800.25";
        verify(trading.submit("sell", false));
        compare(bridge.lastTrading.stop_price, 5800.25);
        compare(bridge.lastTrading.trail_ticks, 8);
    }
    function test_decimalTickMetadataAvoidsFloatNoise() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        var decimal = snapshot();
        decimal.quotes[0].tick_size = 0.009999999776482582;
        store.trading = decimal;
        trading.orderType = "limit";
        trading.price = "100.001";
        verify(!trading.submit("buy", false));
        trading.price = "100.00";
        verify(trading.submit("buy", false));
        compare(bridge.lastTrading.price, 100);
        store.actionResultReceived({
            request_id: "trading-1",
            ok: true,
            code: "confirmed",
            message: "Entry confirmed"
        });
        trading.price = "100.01";
        verify(trading.submit("buy", false));
        compare(bridge.lastTrading.price, 100.01);
    }
    function test_compactAgentPaginationIsVisibleAndClickable() {
        dashboards.selectDashboard(0)
        var agents = findChild(dashboards, "combinedAgentPortal")
        compare(agents.pageCount, 2)
        var dots = findChild(agents, "pageDots")
        verify(dots.visible)
        var next = findChild(agents, "agentNextPage")
        var previous = findChild(agents, "agentPreviousPage")
        verify(next.visible)
        verify(next.enabled)
        mouseClick(next, next.width / 2, next.height / 2)
        tryCompare(agents, "currentPage", 1)
        var eleventh = findChild(agents, "agentCard_1_0")
        verify(eleventh !== null)
        compare(eleventh.agent.display_name, "Agent 11")
        mouseClick(previous, previous.width / 2, previous.height / 2)
        tryCompare(agents, "currentPage", 0)
    }
    function test_previewBlocksBothActionFamilies() {
        dashboards.previewMode = true;
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        var omarchy = findChild(dashboards, "omarchyControlPanel");
        verify(!trading.submit("buy", false));
        verify(!omarchy.request({
            operation: "lock"
        }));
        compare(bridge.tradingRequests, 0);
        compare(bridge.desktopRequests, 0);
    }

    function test_monitorFooterIsGlobalAndModalBlocksNavigation() {
        var handle = findChild(dashboards, "sidebarHandle");
        var button = findChild(dashboards, "globalMonitorButton");
        var drawer = findChild(dashboards, "sidebarDrawer");
        var sidebar = findChild(dashboards, "dashboardSidebar");
        var pages = findChild(dashboards, "dashboardPages");
        for (var index = 0; index < 9; ++index) {
            dashboards.selectDashboard(index);
            mouseClick(handle, handle.width / 2, handle.height / 2);
            tryCompare(dashboards, "sidebarOpen", true);
            var corner = button.mapToItem(drawer, button.width, button.height);
            verify(corner.x > drawer.width - 40 && corner.x <= drawer.width);
            verify(corner.y > drawer.height - 40 && corner.y <= drawer.height);
            mouseClick(button, button.width / 2, button.height / 2);
            tryCompare(dashboards, "monitorSettingsOpen", true);
            verify(!sidebar.enabled);
            verify(!pages.enabled);
            verify(!dashboards.selectDashboard((index + 1) % 9));
            compare(dashboards.dashboardIndex, index);
            dashboards.monitorSettingsOpen = false;
            tryCompare(sidebar, "enabled", true);
        }
        compare(bridge.desktopRequests, 0);
    }
    function test_orderSubmissionIsExactAndNeverRepeatedWhilePending() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        verify(trading.submit("buy", false));
        compare(bridge.lastTrading.account_id, "exact-live-account");
        compare(bridge.lastTrading.symbol, "MESZ6");
        compare(bridge.lastTrading.order_type, "market");
        verify(!trading.submit("buy", false));
        compare(bridge.tradingRequests, 1);
        store.actionResultReceived({
            request_id: "trading-1",
            ok: false,
            code: "outcome_unknown",
            message: "Reconciliation pending"
        });
        compare(trading.pendingRequest, "trading-1");
        verify(!trading.feedbackSuccess);
        verify(!trading.submit("buy", false));
        compare(bridge.tradingRequests, 1);
        store.trading = Object.assign({}, store.trading, {
            execution_enabled: false
        });
        verify(!trading.submit("buy", false));
    }
    function test_tickValidationAndProtectionCapability() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        trading.orderType = "limit";
        trading.price = "5801.13";
        verify(!trading.submit("sell", false));
        compare(bridge.tradingRequests, 0);
        trading.price = "5801.25";
        trading.brackets = true;
        store.trading = Object.assign({}, store.trading, {
            supports_brackets: false
        });
        verify(!trading.submit("sell", false));
        compare(bridge.tradingRequests, 0);
        trading.brackets = false;
        verify(trading.submit("sell", false));
        compare(bridge.lastTrading.price, 5801.25);
    }
    function test_keypadAndConfirmationBlockTicket() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        trading.openKeypad("quantity", "QUANTITY", 1, true);
        verify(!trading.canExecute);
        trading.applyNumber("0");
        compare(trading.quantity, 1);
        compare(trading.keypadField, "quantity");
        trading.applyNumber("5");
        compare(trading.quantity, 5);
        compare(trading.keypadField, "");
        trading.confirm("FLATTEN", "Confirm", {
            action: "flatten",
            account_id: "exact-live-account"
        });
        verify(trading.confirmationOpen);
        verify(!trading.canExecute);
        verify(!trading.submit("buy", false));
        compare(bridge.tradingRequests, 0);
    }
}
