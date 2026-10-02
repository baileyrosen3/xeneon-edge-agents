import QtQuick
import QtTest
import "../components"
import "../state/ThemePalette.js" as ThemePalette

TestCase {
    id: testCase
    name: "Dashboards"
    width: 2560
    height: 720
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
    Window {
        id: testWindow
        width: 2560
        height: 720
        visible: true
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
        bridge.tradingRequests = 0;
        bridge.desktopRequests = 0;
        dashboards.previewMode = false;
        dashboards.selectDashboard(0);
        var trading = findChild(dashboards, "riptideDashboard");
        trading.unknownOutcome = false;
        trading.unknownAtMs = 0;
        trading.confirmationIsReview = false;
        trading.quantity = 1;
        trading.pendingRequest = "";
        trading.keypadField = "";
        trading.confirmationOpen = false;
        trading.editingOrder = null;
        trading.orderType = "market";
        trading.price = "";
        trading.brackets = false;
        wait(0);
    }
    function test_switcher_preservesDraftAndAgentTargets() {
        var trading = findChild(dashboards, "riptideDashboard");
        var agents = findChild(dashboards, "combinedAgentPortal");
        compare(agents.pageSize, 10);
        verify(findChild(agents, "agentBackendToggle").height >= 44);
        verify(findChild(agents, "chatGptDesktopButton").height >= 44);
        var firstCard = findChild(agents, "agentCard_0_0");
        verify(firstCard.width >= 330);
        verify(firstCard.height >= 180);
        verify(firstCard.y + firstCard.height <= findChild(agents, "agentGrid_0").height + 0.5);
        trading.quantity = 15;
        trading.price = "5800.25";
        trading.orderType = "limit";
        dashboards.selectDashboard(1);
        compare(preferences.dashboardIndex, 1);
        dashboards.selectDashboard(0);
        dashboards.selectDashboard(1);
        compare(trading.quantity, 15);
        compare(trading.price, "5800.25");
        compare(trading.orderType, "limit");
        compare(findChild(dashboards, "dashboardSwitcher").currentIndex, 1);
    }
    function test_switcherDragAndLabels() {
        var thumb = findChild(dashboards, "dashboardSliderThumb");
        var track = findChild(dashboards, "dashboardSlider");
        mousePress(track, 64, 24);
        mouseMove(track, 130, 24, 20);
        mouseMove(track, 230, 24, 20);
        mouseMove(track, 350, 24, 20);
        mouseRelease(track, 350, 24);
        tryCompare(dashboards, "dashboardIndex", 1);
        mousePress(track, 350, 24);
        mouseMove(track, 270, 24, 20);
        mouseMove(track, 150, 24, 20);
        mouseMove(track, 64, 24, 20);
        mouseRelease(track, 64, 24);
        tryCompare(dashboards, "dashboardIndex", 0);
        var label = findChild(dashboards, "dashboardRiptideLabel");
        mouseClick(label, label.width / 2, label.height / 2);
        tryCompare(dashboards, "dashboardIndex", 1);
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
    function test_pendingAcknowledgementIsNotFulfillment() {
        dashboards.selectDashboard(1);
        var trading = findChild(dashboards, "riptideDashboard");
        verify(trading.submit("buy", false));
        store.trading = Object.assign({}, store.trading, {
            execution_enabled: false
        });
        store.actionResultReceived({
            request_id: "trading-1",
            ok: true,
            code: "trading_pending",
            message: "Awaiting broker projection"
        });
        compare(trading.pendingRequest, "");
        verify(!trading.feedbackSuccess);
        verify(!trading.canExecute);
        verify(trading.feedback.indexOf("AWAITING BROKER UPDATE") >= 0);
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
        verify(dots.width > 0)
        verify(dots.height >= 44)
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

    function test_monitorEntryIsGlobalAndModalPreservesSwitcher() {
        var button = findChild(dashboards, "globalMonitorButton")
        var switcher = findChild(dashboards, "dashboardSwitcher")
        var pages = findChild(dashboards, "dashboardPages")
        for (var i=0;i<2;++i) {
            dashboards.selectDashboard(i)
            mouseClick(button,button.width/2,button.height/2)
            verify(dashboards.monitorSettingsOpen)
            verify(switcher.visible)
            verify(!switcher.enabled)
            verify(!pages.enabled)
            dashboards.monitorSettingsOpen=false
            verify(switcher.enabled)
        }
        compare(bridge.desktopRequests,0)
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
    function test_renderScreenshots() {
        var done = false;
        dashboards.grabToImage(function (result) {
            result.saveToFile("/tmp/xeneon-dashboard-ui-omarchy.png");
            done = true;
        });
        tryVerify(function () {
            return done;
        });
        dashboards.selectDashboard(1);
        wait(100);
        done = false;
        dashboards.grabToImage(function (result) {
            result.saveToFile("/tmp/xeneon-dashboard-ui-riptide.png");
            done = true;
        });
        tryVerify(function () {
            return done;
        });
    }
}
