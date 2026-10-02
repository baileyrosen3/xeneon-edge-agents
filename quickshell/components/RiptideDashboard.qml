pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    required property var store
    required property var bridge
    required property var activity
    required property var theme
    property bool previewMode: false
    readonly property var trading: store.trading || ({})
    readonly property var accounts: trading.accounts || []
    readonly property var quotes: trading.quotes || []
    property string selectedAccount: ""
    property string selectedSymbol: ""
    property string orderType: "market"
    property int quantity: 1
    property string price: ""
    property string stopPrice: ""
    property int trailTicks: 8
    property bool brackets: false
    property int slTicks: 8
    property int tpTicks: 16
    property string activityTab: "positions"
    property string pendingRequest: ""
    property bool unknownOutcome: false
    property double unknownAtMs: 0
    readonly property bool canReviewOutcome: unknownOutcome && pendingRequest !== "" && current && !previewMode && Number(trading.sampled_at_ms || 0) > unknownAtMs
    property string feedback: ""
    property bool feedbackSuccess: false
    property bool selectorOpen: false
    property string selectorKind: "symbol"
    property string keypadField: ""
    property bool confirmationOpen: false
    property string confirmationTitle: ""
    property bool confirmationIsReview: false
    property string confirmationDetail: ""
    property var confirmationPayload: ({})
    property var editingOrder: null
    property string editPrice: ""
    property string editQuantity: ""
    property int clockTick: 0
    readonly property var selectedAccountRecord: find(accounts, "id", selectedAccount) || ({})
    readonly property var quote: find(quotes, "symbol", selectedSymbol) || ({})
    readonly property bool current: trading.connection === "connected" && trading.broker_connected === true && !store.freshSnapshotRequired
    readonly property bool canExecute: current && !previewMode && bridge.ready && trading.execution_enabled === true && selectedAccountRecord.can_trade === true && pendingRequest === "" && !confirmationOpen && editingOrder === null && keypadField === "" && !selectorOpen
    readonly property bool quoteCurrent: {
        clockTick;
        return Number(quote.updated_at_ms || 0) > 0 && Date.now() - Number(quote.updated_at_ms) <= 10000;
    }
    readonly property bool canPlace: canExecute && quoteCurrent && tickSize > 0
    readonly property var positions: accountItems(trading.positions || [])
    readonly property var orders: accountItems(trading.orders || [])
    readonly property var fills: accountItems(trading.fills || [])
    readonly property var closedFills: fills.filter(function (fill) {
        return fill.pnl !== null && fill.pnl !== undefined;
    })
    readonly property real tickSize: Number(quote.tick_size || 0)
    readonly property real pointValue: Number(quote.dollars_per_point || 0)
    function find(items, field, value) {
        for (var i = 0; i < items.length; ++i)
            if (String(items[i][field]) === value)
                return items[i];
        return null;
    }
    function accountItems(items) {
        return items.filter(function (item) {
            return String(item.account_id) === root.selectedAccount;
        });
    }
    function money(value) {
        return value === null || value === undefined || !Number.isFinite(Number(value)) ? "—" : (Number(value) < 0 ? "−$" : "$") + Math.abs(Number(value)).toFixed(2);
    }
    function number(value) {
        return value === null || value === undefined || !Number.isFinite(Number(value)) ? "—" : Number(value).toFixed(tickSize > 0 && tickSize < 1 ? Math.min(6, Math.ceil(-Math.log(tickSize) / Math.LN10) + 1) : 2);
    }
    function initializeSelection() {
        if (selectedAccount === "" && accounts.length > 0)
            selectedAccount = String(accounts[0].id);
        if (selectedSymbol === "" && quotes.length > 0)
            selectedSymbol = String(quotes[0].symbol);
    }
    function working(order) {
        return !["filled", "cancelled", "canceled", "rejected", "expired"].includes(String(order.status || "").toLowerCase());
    }
    function protection(position) {
        var parts = [];
        for (var i = 0; i < orders.length; ++i) {
            var order = orders[i];
            if (order.symbol !== position.symbol || !working(order) || order.side === (position.quantity > 0 ? "buy" : "sell"))
                continue;
            var label = String(order.order_type).indexOf("stop") >= 0 ? "SL" : order.order_type === "limit" ? "TP" : "EXIT";
            parts.push(label + " " + number(order.stop_price !== null && order.stop_price !== undefined ? order.stop_price : order.price) + " ×" + order.quantity);
        }
        return parts.length ? parts.join("  ·  ") : "No working protection reported";
    }
    function tickAligned(value) {
        if (!Number.isFinite(value) || value <= 0 || tickSize <= 0)
            return false;
        return Math.abs(value / tickSize - Math.round(value / tickSize)) < 0.00001;
    }
    function payloadFor(side, join) {
        if (selectedSymbol === "" || !quote.symbol || quantity < 1 || quantity > 1000) {
            feedback = "Choose an available contract and quantity";
            return null;
        }
        var type = join ? "limit" : orderType;
        var orderPrice = join ? Number(side === "buy" ? quote.bid : quote.ask) : Number(price);
        var payload = {
            action: "place",
            account_id: selectedAccount,
            symbol: selectedSymbol,
            side: side,
            quantity: quantity,
            order_type: type
        };
        if (type === "limit") {
            if (!tickAligned(orderPrice)) {
                feedback = "Limit price must match the contract tick size";
                return null;
            }
            payload.price = orderPrice;
        }
        if (type === "stop_market") {
            if (!tickAligned(Number(stopPrice))) {
                feedback = "Stop price must match the contract tick size";
                return null;
            }
            payload.stop_price = Number(stopPrice);
        }
        if (type === "trailing_stop") {
            if (!tickAligned(Number(stopPrice))) {
                feedback = "Initial trailing stop must match the contract tick size";
                return null;
            }
            payload.stop_price = Number(stopPrice);
            payload.trail_ticks = trailTicks;
        }
        if (brackets) {
            if (!["market", "limit"].includes(type)) {
                feedback = "Brackets require a Market or Limit entry";
                return null;
            }
            if (trading.supports_brackets !== true) {
                feedback = "Server bracket execution is unavailable";
                return null;
            }
            payload.sl_ticks = slTicks;
            payload.tp_ticks = tpTicks;
        }
        return payload;
    }
    function request(payload) {
        activity.noteUserActivity();
        if (!current || previewMode || !bridge.ready || trading.execution_enabled !== true || selectedAccountRecord.can_trade !== true || pendingRequest !== "" || typeof bridge.tradingAction !== "function")
            return false;
        var requestId = bridge.tradingAction(payload);
        if (!requestId) {
            feedback = "Execution request unavailable";
            return false;
        }
        pendingRequest = String(requestId);
        unknownOutcome = false;
        unknownAtMs = 0;
        feedback = "SENDING  ·  Awaiting server acknowledgement";
        feedbackSuccess = false;
        outcomeTimer.restart();
        return true;
    }
    function submit(side, join) {
        if (!canPlace)
            return false;
        var payload = payloadFor(side, join);
        if (!payload)
            return false;
        return request(payload);
    }
    function confirm(title, detail, payload) {
        if (!canExecute)
            return;
        activity.noteUserActivity();
        confirmationIsReview = false;
        confirmationTitle = title;
        confirmationDetail = detail;
        confirmationPayload = payload;
        confirmationOpen = true;
    }
    function markUnknown(detail) {
        unknownOutcome = true;
        unknownAtMs = Date.now();
        feedbackSuccess = false;
        feedback = "OUTCOME UNKNOWN  ·  " + detail;
        outcomeTimer.stop();
    }
    function reviewOutcome() {
        if (!canReviewOutcome)
            return false;
        activity.noteUserActivity();
        activityTab = "orders";
        confirmationIsReview = true;
        confirmationTitle = "REVIEW EXECUTION OUTCOME";
        confirmationDetail = "Review current orders and positions in account " + selectedAccount + " before resuming. " + orders.filter(working).length + " working orders and " + positions.length + " positions are currently reported. The previous request will never be resent.";
        confirmationPayload = ({});
        confirmationOpen = true;
        return true;
    }
    function resumeReviewed() {
        if (!confirmationOpen || !confirmationIsReview || !canReviewOutcome)
            return false;
        activity.noteUserActivity();
        pendingRequest = "";
        unknownOutcome = false;
        unknownAtMs = 0;
        outcomeTimer.stop();
        confirmationOpen = false;
        confirmationIsReview = false;
        feedbackSuccess = false;
        feedback = "RESUMED AFTER REVIEW  ·  Previous request was not resent";
        return true;
    }
    function edit(order) {
        if (!canExecute || !working(order))
            return;
        activity.noteUserActivity();
        editingOrder = order;
        editPrice = String(order.order_type.indexOf("stop") >= 0 ? order.stop_price || "" : order.price || "");
        editQuantity = String(order.quantity);
    }
    function applyEdit() {
        if (editingOrder === null)
            return;
        var value = Number(editPrice);
        var orderQuote = find(quotes, "symbol", String(editingOrder.symbol)) || ({});
        var step = Number(orderQuote.tick_size || 0);
        var count = Number(editQuantity);
        if (!Number.isInteger(count) || count < 1 || count > 1000 || !Number.isFinite(value) || value <= 0 || step <= 0 || Math.abs(value / step - Math.round(value / step)) > 0.00001) {
            feedback = "Enter valid quantity and a tick-aligned price";
            return;
        }
        var payload = {
            action: "modify",
            account_id: selectedAccount,
            order_id: String(editingOrder.id),
            quantity: count
        };
        if (String(editingOrder.order_type).indexOf("stop") >= 0)
            payload.stop_price = value;
        else
            payload.price = value;
        if (request(payload))
            editingOrder = null;
    }
    function openKeypad(field, title, value, integerOnly) {
        activity.noteUserActivity();
        keypadField = field;
        keypad.title = title;
        keypad.value = String(value);
        keypad.integerOnly = integerOnly;
        keypad.error = "";
    }
    function applyNumber(value) {
        var n = Number(value);
        var field = keypadField;
        if (["quantity", "slTicks", "tpTicks", "trailTicks", "editQuantity"].includes(field) && (!Number.isInteger(n) || n < 1 || n > 1000)) {
            keypad.error = "Use a whole number from 1 to 1000";
            return;
        }
        if (["price", "stopPrice", "editPrice"].includes(field) && n <= 0) {
            keypad.error = "Price must be greater than zero";
            return;
        }
        if (["quantity", "slTicks", "tpTicks", "trailTicks"].includes(field))
            root[field] = n;
        else
            root[field] = value;
        keypadField = "";
    }
    Component.onCompleted: initializeSelection()
    Connections {
        target: root.store
        function onTradingChanged() {
            root.initializeSelection();
        }
        function onActionResultReceived(result) {
            if (String(result.request_id || "") !== root.pendingRequest || root.pendingRequest === "")
                return;
            var code = String(result.code || "");
            if (["trading_unknown", "outcome_unknown", "timeout", "execution_timeout"].includes(code)) {
                root.markUnknown(String(result.message || "Awaiting server reconciliation; order will not be resent"));
                return;
            }
            root.pendingRequest = "";
            root.unknownOutcome = false;
            root.unknownAtMs = 0;
            outcomeTimer.stop();
            var awaiting = ["trading_pending", "outcome_pending"].includes(code);
            root.feedbackSuccess = result.ok === true && !awaiting;
            root.feedback = (awaiting ? "ACKNOWLEDGED  ·  AWAITING BROKER UPDATE  ·  " : result.ok === true ? "SERVER ACKNOWLEDGED  ·  " : "ACTION RESULT  ·  ") + String(result.message || result.code || "");
        }
    }
    Timer {
        id: outcomeTimer
        interval: 15000
        onTriggered: root.markUnknown("Awaiting reconciliation; order will not be resent")
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: root.clockTick += 1
    }
    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12
        Row {
            width: parent.width
            height: 42
            Column {
                width: 580
                spacing: 3
                Text {
                    text: "RIPTIDE // TRADING CONSOLE"
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font.family: "monospace"
                    font.pixelSize: 27
                    font.weight: Font.Bold
                }
                Text {
                    text: root.previewMode ? "SYNTHETIC PREVIEW  ·  EXECUTION DISABLED" : "DIRECT VULTR CONNECTION"
                    textFormat: Text.PlainText
                    color: root.previewMode ? root.theme.needsHelp : root.theme.textMuted
                    font.family: "monospace"
                    font.pixelSize: 12
                }
            }
            Text {
                width: 700
                anchors.verticalCenter: parent.verticalCenter
                text: "SERVER " + String(root.trading.connection || "UNCONFIGURED").toUpperCase() + "  ·  RITHMIC " + (root.trading.broker_connected === true ? "CONNECTED" : "OFFLINE")
                textFormat: Text.PlainText
                color: root.current ? root.theme.success : root.theme.needsHelp
                font.family: "monospace"
                font.pixelSize: 18
            }
            Text {
                width: parent.width - 1280 - (root.unknownOutcome ? 292 : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    root.clockTick;
                    var age = Math.max(0, Math.floor((Date.now() - Number(root.trading.sampled_at_ms || 0)) / 1000));
                    return root.trading.sampled_at_ms ? "SNAPSHOT " + age + "s AGO  ·  " + (root.trading.execution_enabled === true ? "EXECUTION ENABLED" : "READ ONLY") : "Waiting for server configuration";
                }
                textFormat: Text.PlainText
                color: root.theme.textMuted
                font.family: "monospace"
                font.pixelSize: 15
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
            DashboardButton {
                objectName: "riptideReviewOutcome"
                theme: root.theme
                width: 280
                height: 44
                visible: root.unknownOutcome
                label: "REVIEW & RESUME"
                enabled: root.canReviewOutcome
                onClicked: root.reviewOutcome()
            }
        }
        Row {
            width: parent.width
            height: root.height - 112
            spacing: 14
            DashboardCard {
                theme: root.theme
                width: 480
                height: parent.height
                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12
                    Text {
                        text: "ACCOUNTS"
                        textFormat: Text.PlainText
                        color: root.theme.accent
                        font.family: "monospace"
                        font.pixelSize: 19
                        font.weight: Font.Bold
                    }
                    ListView {
                        width: parent.width
                        height: 150
                        model: root.accounts
                        spacing: 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: DashboardButton {
                            required property var modelData
                            theme: root.theme
                            width: ListView.view.width
                            height: 66
                            label: String(modelData.label || modelData.id)
                            detail: String(modelData.account_type || "UNKNOWN").toUpperCase() + "  ·  " + (modelData.can_trade === true ? "TRADING PERMITTED" : "READ ONLY")
                            selected: String(modelData.id) === root.selectedAccount
                            enabled: root.pendingRequest === "" && !root.confirmationOpen
                            onClicked: {
                                root.activity.noteUserActivity();
                                root.selectedAccount = String(modelData.id);
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.accounts.length === 0
                            text: "No accounts available"
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.pixelSize: 19
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: [
                                {
                                    label: "BALANCE",
                                    key: "balance"
                                },
                                {
                                    label: "UNREALIZED P&L",
                                    key: "open_pnl"
                                },
                                {
                                    label: "REALIZED P&L",
                                    key: "closed_pnl"
                                }
                            ]
                            Row {
                                required property var modelData
                                width: parent.width
                                height: 32
                                Text {
                                    width: 230
                                    text: modelData.label
                                    textFormat: Text.PlainText
                                    color: root.theme.textMuted
                                    font.family: "monospace"
                                    font.pixelSize: 15
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    width: parent.width - 230
                                    text: root.money(root.selectedAccountRecord[modelData.key])
                                    textFormat: Text.PlainText
                                    color: modelData.key.indexOf("pnl") >= 0 ? Number(root.selectedAccountRecord[modelData.key] || 0) < 0 ? root.theme.error : root.theme.success : root.theme.textPrimary
                                    font.family: "monospace"
                                    font.pixelSize: 24
                                    horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.theme.border
                    }
                    Text {
                        width: parent.width
                        text: "BROKER LIMITS\nLoss limit: " + root.money(root.selectedAccountRecord.loss_limit) + "\nMinimum balance: " + root.money(root.selectedAccountRecord.min_account_balance) + "\nLiquidation threshold: " + root.money(root.selectedAccountRecord.auto_liquidate_threshold)
                        textFormat: Text.PlainText
                        color: root.theme.textMuted
                        font.family: "monospace"
                        font.pixelSize: 15
                        lineHeight: 1.5
                    }
                    Row {
                        spacing: 10
                        DashboardButton {
                            theme: root.theme
                            width: 217
                            height: 52
                            label: "CANCEL ALL"
                            destructive: true
                            enabled: root.canExecute && root.orders.some(root.working)
                            onClicked: root.confirm("CANCEL ALL ORDERS", "Cancel every working order in " + root.selectedAccount + "? This includes protective exits.", {
                                action: "cancel_all",
                                account_id: root.selectedAccount
                            })
                        }
                        DashboardButton {
                            theme: root.theme
                            width: 217
                            height: 52
                            label: "FLATTEN ACCOUNT"
                            destructive: true
                            enabled: root.canExecute && root.trading.supports_flatten === true
                            onClicked: root.confirm("FLATTEN ACCOUNT", "Cancel working orders and close all positions in " + root.selectedAccount + "?", {
                                action: "flatten",
                                account_id: root.selectedAccount
                            })
                        }
                    }
                }
            }
            DashboardCard {
                theme: root.theme
                width: 900
                height: parent.height
                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12
                    Row {
                        width: parent.width
                        spacing: 12
                        Text {
                            width: 200
                            height: 48
                            text: "ORDER CARD"
                            textFormat: Text.PlainText
                            color: root.theme.accent
                            font.family: "monospace"
                            font.pixelSize: 19
                            font.weight: Font.Bold
                            verticalAlignment: Text.AlignVCenter
                        }
                        DashboardButton {
                            objectName: "riptideContractSelector"
                            theme: root.theme
                            width: parent.width - 212
                            label: root.selectedSymbol || "SELECT EXACT CONTRACT / EXPIRY"
                            detail: "Tap to select contract"
                            enabled: root.pendingRequest === ""
                            onClicked: {
                                root.activity.noteUserActivity();
                                root.selectorKind = "symbol";
                                root.selectorOpen = true;
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        height: 46
                        spacing: 12
                        Repeater {
                            model: [
                                {
                                    label: "BID",
                                    key: "bid"
                                },
                                {
                                    label: "LAST",
                                    key: "last"
                                },
                                {
                                    label: "ASK",
                                    key: "ask"
                                }
                            ]
                            Text {
                                required property var modelData
                                width: (parent.width - 24) / 3
                                text: modelData.label + "  " + root.number(root.quote[modelData.key])
                                textFormat: Text.PlainText
                                color: modelData.key === "last" ? root.theme.textPrimary : root.theme.textMuted
                                font.family: "monospace"
                                font.pixelSize: 25
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [
                                {
                                    label: "MARKET",
                                    type: "market"
                                },
                                {
                                    label: "LIMIT",
                                    type: "limit"
                                },
                                {
                                    label: "STOP",
                                    type: "stop_market"
                                },
                                {
                                    label: "TRAILING STOP",
                                    type: "trailing_stop"
                                }
                            ]
                            DashboardButton {
                                required property var modelData
                                theme: root.theme
                                width: 208
                                height: 48
                                label: modelData.label
                                selected: root.orderType === modelData.type
                                enabled: root.pendingRequest === ""
                                onClicked: {
                                    root.activity.noteUserActivity();
                                    root.orderType = modelData.type;
                                }
                            }
                        }
                    }
                    Row {
                        spacing: 10
                        DashboardButton {
                            theme: root.theme
                            width: 84
                            label: "−"
                            enabled: root.quantity > 1 && root.pendingRequest === ""
                            onClicked: {
                                root.activity.noteUserActivity();
                                root.quantity = Math.max(1, root.quantity - 1);
                            }
                        }
                        DashboardButton {
                            objectName: "riptideQuantity"
                            theme: root.theme
                            width: 148
                            label: "QTY " + root.quantity
                            enabled: root.pendingRequest === ""
                            onClicked: root.openKeypad("quantity", "ORDER QUANTITY", root.quantity, true)
                        }
                        DashboardButton {
                            theme: root.theme
                            width: 84
                            label: "+"
                            enabled: root.quantity < 1000 && root.pendingRequest === ""
                            onClicked: {
                                root.activity.noteUserActivity();
                                root.quantity += 1;
                            }
                        }
                        Repeater {
                            model: [1, 3, 5, 10, 15]
                            DashboardButton {
                                required property int modelData
                                theme: root.theme
                                width: 100
                                label: String(modelData)
                                selected: root.quantity === modelData
                                enabled: root.pendingRequest === ""
                                onClicked: {
                                    root.activity.noteUserActivity();
                                    root.quantity = modelData;
                                }
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        height: 48
                        spacing: 10
                        DashboardButton {
                            theme: root.theme
                            width: 420
                            label: root.orderType === "market" ? "MARKET EXECUTION" : root.orderType === "limit" ? "LIMIT " + (root.price || "SET PRICE") : root.orderType === "stop_market" ? "STOP " + (root.stopPrice || "SET PRICE") : "TRAIL " + root.trailTicks + " TICKS"
                            enabled: root.orderType !== "market" && root.pendingRequest === ""
                            onClicked: root.openKeypad(root.orderType === "limit" ? "price" : root.orderType === "stop_market" ? "stopPrice" : "trailTicks", root.orderType === "trailing_stop" ? "TRAIL DISTANCE IN TICKS" : "ORDER PRICE", root.orderType === "limit" ? root.price : root.orderType === "stop_market" ? root.stopPrice : root.trailTicks, root.orderType === "trailing_stop")
                        }
                        DashboardButton {
                            theme: root.theme
                            width: 434
                            height: 48
                            visible: root.orderType === "trailing_stop"
                            label: "INITIAL STOP " + (root.stopPrice || "SET PRICE")
                            detail: "Tick " + root.number(root.tickSize || null) + " · point " + root.money(root.pointValue || null)
                            enabled: root.pendingRequest === ""
                            onClicked: root.openKeypad("stopPrice", "INITIAL TRAILING STOP PRICE", root.stopPrice, false)
                        }
                        Text {
                            visible: root.orderType !== "trailing_stop"
                            width: parent.width - 430
                            height: 48
                            text: "TICK " + root.number(root.tickSize || null) + "  ·  POINT " + root.money(root.pointValue || null) + "\nSPREAD " + (root.quote.bid && root.quote.ask ? root.number(Number(root.quote.ask) - Number(root.quote.bid)) : "—")
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.family: "monospace"
                            font.pixelSize: 14
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.theme.border
                    }
                    Row {
                        spacing: 10
                        DashboardButton {
                            theme: root.theme
                            width: 268
                            label: "NEXT ORDER BRACKETS"
                            detail: root.trading.supports_brackets === true ? root.brackets ? "ON" : "OFF" : "SERVER SUPPORT UNAVAILABLE"
                            selected: root.brackets
                            enabled: root.trading.supports_brackets === true && ["market", "limit"].includes(root.orderType) && root.pendingRequest === ""
                            onClicked: {
                                root.activity.noteUserActivity();
                                root.brackets = !root.brackets;
                            }
                        }
                        DashboardButton {
                            theme: root.theme
                            width: 288
                            label: "SL " + root.slTicks + " TICKS"
                            enabled: root.brackets && root.pendingRequest === ""
                            onClicked: root.openKeypad("slTicks", "NEXT ORDER STOP LOSS TICKS", root.slTicks, true)
                        }
                        DashboardButton {
                            theme: root.theme
                            width: 288
                            label: "TP " + root.tpTicks + " TICKS"
                            enabled: root.brackets && root.pendingRequest === ""
                            onClicked: root.openKeypad("tpTicks", "NEXT ORDER TAKE PROFIT TICKS", root.tpTicks, true)
                        }
                    }
                    Text {
                        width: parent.width
                        text: root.brackets && root.tickSize > 0 && root.pointValue > 0 ? "EST. RISK " + root.money(root.quantity * root.slTicks * root.tickSize * root.pointValue) + "  ·  REWARD " + root.money(root.quantity * root.tpTicks * root.tickSize * root.pointValue) + "  ·  " + (root.tpTicks / root.slTicks).toFixed(2) + "R  ·  excludes fees/slippage" : "Next-order protection is separate from existing working SL / TP orders"
                        textFormat: Text.PlainText
                        color: root.theme.textMuted
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                    Row {
                        spacing: 12
                        DashboardButton {
                            objectName: "riptideBuy"
                            theme: root.theme
                            width: 420
                            height: 62
                            label: "BUY " + root.quantity
                            detail: root.selectedSymbol + " · " + root.orderType.toUpperCase()
                            accent: root.theme.success
                            selected: true
                            enabled: root.canPlace
                            onClicked: root.submit("buy", false)
                        }
                        DashboardButton {
                            objectName: "riptideSell"
                            theme: root.theme
                            width: 420
                            height: 62
                            label: "SELL " + root.quantity
                            detail: root.selectedSymbol + " · " + root.orderType.toUpperCase()
                            accent: root.theme.error
                            selected: true
                            enabled: root.canPlace
                            onClicked: root.submit("sell", false)
                        }
                    }
                    Row {
                        spacing: 12
                        DashboardButton {
                            theme: root.theme
                            width: 420
                            label: "JOIN BID " + root.number(root.quote.bid)
                            enabled: root.canPlace && root.quote.bid !== null && root.quote.bid !== undefined
                            onClicked: root.submit("buy", true)
                        }
                        DashboardButton {
                            theme: root.theme
                            width: 420
                            label: "JOIN ASK " + root.number(root.quote.ask)
                            enabled: root.canPlace && root.quote.ask !== null && root.quote.ask !== undefined
                            onClicked: root.submit("sell", true)
                        }
                    }
                }
            }
            DashboardCard {
                theme: root.theme
                width: parent.width - 1408
                height: parent.height
                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12
                    Row {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: [
                                {
                                    label: "POSITIONS",
                                    tab: "positions"
                                },
                                {
                                    label: "ORDERS",
                                    tab: "orders"
                                },
                                {
                                    label: "FILLS",
                                    tab: "fills"
                                },
                                {
                                    label: "CLOSED",
                                    tab: "closed"
                                }
                            ]
                            DashboardButton {
                                required property var modelData
                                theme: root.theme
                                width: (parent.width - 24) / 4
                                label: modelData.label
                                selected: root.activityTab === modelData.tab
                                onClicked: {
                                    root.activity.noteUserActivity();
                                    root.activityTab = modelData.tab;
                                }
                            }
                        }
                    }
                    ListView {
                        id: activityList
                        width: parent.width
                        height: parent.height - 65
                        spacing: 10
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.activityTab === "positions" ? root.positions : root.activityTab === "orders" ? root.orders : root.activityTab === "closed" ? root.closedFills : root.fills
                        delegate: DashboardCard {
                            id: activityCard
                            readonly property var record: modelData || ({})
                            required property var modelData
                            theme: root.theme
                            width: activityList.width
                            height: root.activityTab === "positions" ? 154 : root.activityTab === "orders" ? 124 : 94
                            color: root.theme.surfaceRaised
                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8
                                Row {
                                    width: parent.width
                                    Text {
                                        width: parent.width * 0.62
                                        text: String(activityCard.record.symbol) + "  ·  " + (root.activityTab === "positions" ? Number(activityCard.record.quantity) > 0 ? "LONG" : "SHORT" : String(activityCard.record.side || "").toUpperCase()) + " ×" + Math.abs(Number(activityCard.record.quantity))
                                        textFormat: Text.PlainText
                                        color: root.theme.textPrimary
                                        font.family: "monospace"
                                        font.pixelSize: 22
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width * 0.38
                                        text: root.activityTab === "positions" ? root.money(activityCard.record.open_pnl) : root.activityTab === "orders" ? String(activityCard.record.status || "UNKNOWN").toUpperCase() : root.money(activityCard.record.pnl)
                                        textFormat: Text.PlainText
                                        color: Number(activityCard.record.open_pnl || activityCard.record.pnl || 0) < 0 ? root.theme.error : root.theme.success
                                        font.family: "monospace"
                                        font.pixelSize: 20
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: root.activityTab === "positions" ? "ENTRY " + root.number(activityCard.record.average_price) + "  ·  LAST " + root.number((root.find(root.quotes, "symbol", String(activityCard.record.symbol)) || {}).last) : root.activityTab === "orders" ? String(activityCard.record.order_type).toUpperCase() + "  ·  PRICE " + root.number(activityCard.record.price) + "  ·  STOP " + root.number(activityCard.record.stop_price) + "  ·  FILLED " + activityCard.record.filled_quantity : "PRICE " + root.number(activityCard.record.price) + "  ·  " + Qt.formatDateTime(new Date(Number(activityCard.record.time_ms || 0)), "hh:mm:ss") + "  ·  FEES " + root.money(activityCard.record.fees)
                                    textFormat: Text.PlainText
                                    color: root.theme.textMuted
                                    font.family: "monospace"
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: root.activityTab === "positions"
                                    text: root.protection(activityCard.record)
                                    textFormat: Text.PlainText
                                    color: root.theme.needsHelp
                                    font.family: "monospace"
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                }
                                Row {
                                    width: parent.width
                                    spacing: 10
                                    visible: root.activityTab === "positions" || root.activityTab === "orders"
                                    DashboardButton {
                                        theme: root.theme
                                        width: (parent.width - 20) / 3
                                        height: 44
                                        label: root.activityTab === "positions" ? "VIEW SL / TP" : "MODIFY"
                                        enabled: root.activityTab === "positions" || (root.canExecute && root.working(activityCard.record) && ["limit", "stop_market", "stop_limit"].includes(String(activityCard.record.order_type)))
                                        onClicked: {
                                            if (root.activityTab === "positions") {
                                                root.activity.noteUserActivity();
                                                root.activityTab = "orders";
                                            } else
                                                root.edit(activityCard.record);
                                        }
                                    }
                                    DashboardButton {
                                        theme: root.theme
                                        width: (parent.width - 20) / 3
                                        height: 44
                                        label: root.activityTab === "positions" ? "CLOSE" : "CANCEL"
                                        destructive: true
                                        enabled: root.canExecute && (root.activityTab === "positions" ? root.trading.supports_flatten === true : root.working(activityCard.record))
                                        onClicked: root.confirm(root.activityTab === "positions" ? "CLOSE POSITION" : "CANCEL ORDER", String(activityCard.record.symbol) + "  ·  account " + root.selectedAccount, root.activityTab === "positions" ? {
                                            action: "close",
                                            account_id: root.selectedAccount,
                                            symbol: String(activityCard.record.symbol)
                                        } : {
                                            action: "cancel",
                                            account_id: root.selectedAccount,
                                            order_id: String(activityCard.record.id)
                                        })
                                    }
                                    DashboardButton {
                                        theme: root.theme
                                        width: (parent.width - 20) / 3
                                        height: 44
                                        label: "REVERSE"
                                        destructive: true
                                        visible: root.activityTab === "positions"
                                        enabled: root.canExecute && root.trading.supports_flatten === true
                                        onClicked: root.confirm("REVERSE POSITION", "Reverse " + String(activityCard.record.symbol) + " ×" + Math.abs(Number(activityCard.record.quantity)) + " in " + root.selectedAccount + "?", {
                                            action: "reverse",
                                            account_id: root.selectedAccount,
                                            symbol: String(activityCard.record.symbol)
                                        })
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: activityList.count === 0
                            text: root.activityTab === "closed" ? "No realized fills reported" : "No " + root.activityTab + " reported"
                            textFormat: Text.PlainText
                            color: root.theme.textMuted
                            font.pixelSize: 21
                        }
                    }
                }
            }
        }
        Row {
            width: parent.width
            height: 24
            spacing: 12
            Text {
                width: parent.width
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: root.feedback || String(root.trading.message || (root.current ? "Ready  ·  Choose account and contract" : "Trading unavailable until the authenticated Vultr feed is connected"))
                textFormat: Text.PlainText
                color: root.feedbackSuccess ? root.theme.success : root.theme.needsHelp
                font.family: "monospace"
                font.pixelSize: 16
                elide: Text.ElideRight
            }
        }
    }
    Item {
        anchors.fill: parent
        visible: root.selectorOpen
        z: 60
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(root.theme.canvas, 0.9)
            TapHandler {
                onTapped: root.selectorOpen = false
            }
        }
        DashboardCard {
            theme: root.theme
            anchors.centerIn: parent
            width: 760
            height: 560
            Column {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16
                Row {
                    spacing: 16
                    Text {
                        width: 550
                        height: 48
                        text: "EXACT CONTRACT / EXPIRY"
                        textFormat: Text.PlainText
                        color: root.theme.textPrimary
                        font.family: "monospace"
                        font.pixelSize: 24
                        verticalAlignment: Text.AlignVCenter
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 140
                        label: "CLOSE"
                        onClicked: root.selectorOpen = false
                    }
                }
                ListView {
                    width: parent.width
                    height: parent.height - 64
                    model: root.quotes
                    spacing: 10
                    clip: true
                    delegate: DashboardButton {
                        required property var modelData
                        theme: root.theme
                        width: ListView.view.width
                        height: 66
                        label: String(modelData.symbol)
                        detail: "LAST " + root.number(modelData.last) + "  ·  tick " + String(modelData.tick_size || "—")
                        selected: String(modelData.symbol) === root.selectedSymbol
                        onClicked: {
                            root.selectedSymbol = String(modelData.symbol);
                            root.selectorOpen = false;
                            root.price = "";
                            root.stopPrice = "";
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.quotes.length === 0
                        text: "Server has no contract quotes"
                        textFormat: Text.PlainText
                        color: root.theme.textMuted
                        font.pixelSize: 22
                    }
                }
            }
        }
    }
    Item {
        anchors.fill: parent
        visible: root.confirmationOpen
        z: 70
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(root.theme.canvas, 0.9)
            TapHandler {}
        }
        DashboardCard {
            theme: root.theme
            anchors.centerIn: parent
            width: 860
            height: root.confirmationIsReview ? 380 : 330
            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 22
                Text {
                    text: root.confirmationTitle
                    textFormat: Text.PlainText
                    color: root.theme.error
                    font.family: "monospace"
                    font.pixelSize: 27
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    height: root.confirmationIsReview ? 130 : 88
                    text: root.confirmationDetail
                    textFormat: Text.PlainText
                    color: root.theme.textPrimary
                    font.pixelSize: 23
                    wrapMode: Text.WordWrap
                }
                Text {
                    text: "ACCOUNT: " + root.selectedAccount + "  ·  " + String(root.selectedAccountRecord.account_type || "UNKNOWN").toUpperCase()
                    textFormat: Text.PlainText
                    color: root.theme.textMuted
                    font.family: "monospace"
                    font.pixelSize: 18
                }
                Row {
                    spacing: 16
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 58
                        label: "GO BACK"
                        onClicked: root.confirmationOpen = false
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 58
                        label: root.confirmationIsReview ? "I REVIEWED · RESUME" : "CONFIRM ACTION"
                        destructive: !root.confirmationIsReview
                        enabled: root.confirmationIsReview ? root.canReviewOutcome : root.current && !root.previewMode && root.trading.execution_enabled === true && root.pendingRequest === ""
                        onClicked: {
                            if (root.confirmationIsReview) {
                                root.resumeReviewed();
                                return;
                            }
                            var payload = root.confirmationPayload;
                            root.confirmationOpen = false;
                            root.request(payload);
                        }
                    }
                }
            }
        }
    }
    Item {
        anchors.fill: parent
        visible: root.editingOrder !== null
        z: 70
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(root.theme.canvas, 0.9)
            TapHandler {}
        }
        DashboardCard {
            theme: root.theme
            anchors.centerIn: parent
            width: 860
            height: 400
            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 18
                Text {
                    text: "EDIT WORKING ORDER"
                    textFormat: Text.PlainText
                    color: root.theme.accent
                    font.family: "monospace"
                    font.pixelSize: 27
                }
                Text {
                    width: parent.width
                    text: root.editingOrder === null ? "" : String(root.editingOrder.symbol) + "  ·  " + String(root.editingOrder.order_type).toUpperCase() + "  ·  " + String(root.editingOrder.id)
                    textFormat: Text.PlainText
                    color: root.theme.textMuted
                    font.family: "monospace"
                    font.pixelSize: 18
                    elide: Text.ElideRight
                }
                Row {
                    spacing: 16
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 60
                        label: "PRICE " + (root.editPrice || "SET")
                        onClicked: root.openKeypad("editPrice", "EXISTING EXIT / ORDER PRICE", root.editPrice, false)
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 60
                        label: "QUANTITY " + root.editQuantity
                        onClicked: root.openKeypad("editQuantity", "EXISTING ORDER QUANTITY", root.editQuantity, true)
                    }
                }
                Row {
                    spacing: 16
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 48
                        label: "PRICE − 1 TICK"
                        onClicked: {
                            var step = Number((root.find(root.quotes, "symbol", String(root.editingOrder.symbol)) || {}).tick_size || 0);
                            root.editPrice = String(Number(root.editPrice) - step);
                        }
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 48
                        label: "PRICE + 1 TICK"
                        onClicked: {
                            var step = Number((root.find(root.quotes, "symbol", String(root.editingOrder.symbol)) || {}).tick_size || 0);
                            root.editPrice = String(Number(root.editPrice) + step);
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: "This amends the selected working order. Next-order bracket settings stay separate."
                    textFormat: Text.PlainText
                    color: root.theme.textMuted
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                }
                Row {
                    spacing: 16
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 58
                        label: "CANCEL EDIT"
                        onClicked: root.editingOrder = null
                    }
                    DashboardButton {
                        theme: root.theme
                        width: 392
                        height: 58
                        label: "APPLY AMENDMENT"
                        selected: true
                        enabled: root.current && !root.previewMode && root.trading.execution_enabled === true && root.pendingRequest === "" && root.keypadField === ""
                        onClicked: root.applyEdit()
                    }
                }
            }
        }
    }
    DashboardNumericPad {
        id: keypad
        anchors.fill: parent
        theme: root.theme
        open: root.keypadField !== ""
        onAccepted: function (value) {
            root.applyNumber(value);
        }
        onCancelled: root.keypadField = ""
    }
}
