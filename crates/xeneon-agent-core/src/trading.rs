//! Bounded direct gateway client. Broker credentials and broker sessions stay
//! on the Riptide server; the portal only receives the Edge projection.

use std::{
    env,
    fs::File,
    io::{BufRead, BufReader, Read},
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use futures_util::{SinkExt, StreamExt};
use reqwest::{Client, Url};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, watch};
use tokio_tungstenite::tungstenite::{
    Message, client::IntoClientRequest, http::HeaderValue, protocol::WebSocketConfig,
};
use uuid::Uuid;

const MAX_BODY: usize = 512 * 1024;
const MAX_CREDENTIAL_BYTES: u64 = 64 * 1024;
const STALE_AFTER: Duration = Duration::from_secs(20);
const RECONCILE_EVERY: Duration = Duration::from_secs(10);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(8);

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct TradingConfig {
    pub enabled: bool,
    pub server_url: Option<String>,
    /// Only DATA_SERVER_URL and DATA_SERVER_TOKEN are interpreted. No values
    /// are imported into the process environment, and broker keys are ignored.
    pub credentials_file: Option<PathBuf>,
    pub execution_enabled: bool,
}

impl TradingConfig {
    pub fn validate(&self) -> anyhow::Result<()> {
        if self.execution_enabled && !self.enabled {
            anyhow::bail!("Trading execution requires the gateway adapter to be enabled");
        }
        if let Some(url) = &self.server_url {
            validate_url(url).map_err(anyhow::Error::msg)?;
        }
        if self
            .credentials_file
            .as_ref()
            .is_some_and(|path| !path.is_absolute())
        {
            anyhow::bail!("Trading credentials_file must be an absolute path");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TradingConnection {
    #[default]
    Disabled,
    Unconfigured,
    Connecting,
    Connected,
    Stale,
    Offline,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TradingSide {
    Buy,
    Sell,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TradingOrderType {
    Market,
    Limit,
    StopMarket,
    StopLimit,
    TrailingStop,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TradingAccount {
    pub id: String,
    pub label: String,
    #[serde(default)]
    pub account_type: String,
    #[serde(default)]
    pub can_trade: bool,
    pub balance: Option<f64>,
    pub open_pnl: Option<f64>,
    pub closed_pnl: Option<f64>,
    pub loss_limit: Option<f64>,
    pub min_account_balance: Option<f64>,
    pub auto_liquidate_threshold: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TradingPosition {
    pub account_id: String,
    pub symbol: String,
    pub quantity: i64,
    pub average_price: Option<f64>,
    pub open_pnl: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TradingOrder {
    pub id: String,
    pub account_id: String,
    pub symbol: String,
    pub side: TradingSide,
    pub quantity: u32,
    pub filled_quantity: u32,
    pub order_type: TradingOrderType,
    pub price: Option<f64>,
    pub stop_price: Option<f64>,
    pub status: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TradingFill {
    pub id: String,
    pub account_id: String,
    pub symbol: String,
    pub side: TradingSide,
    pub quantity: u32,
    pub price: Option<f64>,
    pub pnl: Option<f64>,
    pub fees: Option<f64>,
    pub time_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TradingQuote {
    pub symbol: String,
    pub bid: Option<f64>,
    pub ask: Option<f64>,
    pub last: Option<f64>,
    pub tick_size: Option<f64>,
    pub dollars_per_point: Option<f64>,
    #[serde(default)]
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TradingSnapshot {
    pub schema_version: u32,
    pub revision: u64,
    pub sampled_at_ms: u64,
    pub connection: TradingConnection,
    #[serde(default)]
    pub broker_connected: bool,
    #[serde(default)]
    pub execution_enabled: bool,
    #[serde(default)]
    pub supports_brackets: bool,
    #[serde(default)]
    pub supports_flatten: bool,
    pub message: Option<String>,
    #[serde(default)]
    pub accounts: Vec<TradingAccount>,
    #[serde(default)]
    pub positions: Vec<TradingPosition>,
    #[serde(default)]
    pub orders: Vec<TradingOrder>,
    #[serde(default)]
    pub fills: Vec<TradingFill>,
    #[serde(default)]
    pub quotes: Vec<TradingQuote>,
}

impl Default for TradingSnapshot {
    fn default() -> Self {
        Self {
            schema_version: 1,
            revision: 0,
            sampled_at_ms: 0,
            connection: TradingConnection::Disabled,
            broker_connected: false,
            execution_enabled: false,
            supports_brackets: false,
            supports_flatten: false,
            message: None,
            accounts: Vec::new(),
            positions: Vec::new(),
            orders: Vec::new(),
            fills: Vec::new(),
            quotes: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub enum TradingRequest {
    Place {
        account_id: String,
        symbol: String,
        side: TradingSide,
        quantity: u32,
        order_type: TradingOrderType,
        price: Option<f64>,
        stop_price: Option<f64>,
        trail_ticks: Option<u32>,
        sl_ticks: Option<u32>,
        tp_ticks: Option<u32>,
    },
    Modify {
        account_id: String,
        order_id: String,
        quantity: Option<u32>,
        price: Option<f64>,
        stop_price: Option<f64>,
    },
    Cancel {
        account_id: String,
        order_id: String,
    },
    Close {
        account_id: String,
        symbol: String,
    },
    Reverse {
        account_id: String,
        symbol: String,
    },
    CancelAll {
        account_id: String,
    },
    Flatten {
        account_id: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TradingCommandState {
    Confirmed,
    Rejected,
    Pending,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TradingCommandResult {
    pub command_id: String,
    pub state: TradingCommandState,
    pub message: String,
}

impl TradingCommandResult {
    pub fn confirmed(&self) -> bool {
        self.state == TradingCommandState::Confirmed
    }
}

struct Endpoint {
    base: Url,
    // This type deliberately has no Debug or Serialize implementation.
    token: String,
}

struct TradingState {
    snapshot: TradingSnapshot,
    observed_at: Option<Instant>,
    stream_connected: bool,
    stream_observed_at: Option<Instant>,
    // Prevent accidental local redispatch even if callers reuse an ID. Never
    // evict IDs during a daemon lifetime; fail closed at the bounded limit.
    submitted: std::collections::HashSet<Uuid>,
}

#[derive(Clone)]
pub struct TradingController {
    config: TradingConfig,
    endpoint: Option<Arc<Endpoint>>,
    client: Option<Client>,
    state: Arc<Mutex<TradingState>>,
}

impl TradingController {
    pub fn new(config: TradingConfig) -> Self {
        let mut snapshot = TradingSnapshot::default();
        let endpoint = if !config.enabled {
            None
        } else if config.validate().is_err() {
            snapshot.connection = TradingConnection::Unconfigured;
            snapshot.message = Some("Trading gateway configuration is invalid".into());
            None
        } else {
            match load_endpoint(&config) {
                Ok(endpoint) => {
                    snapshot.connection = TradingConnection::Connecting;
                    Some(Arc::new(endpoint))
                }
                Err(message) => {
                    snapshot.connection = TradingConnection::Unconfigured;
                    snapshot.message = Some(message.into());
                    None
                }
            }
        };
        let client = Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .connect_timeout(Duration::from_secs(4))
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .build()
            .ok();
        Self {
            config,
            endpoint,
            client,
            state: Arc::new(Mutex::new(TradingState {
                snapshot,
                observed_at: None,
                stream_connected: false,
                stream_observed_at: None,
                submitted: Default::default(),
            })),
        }
    }

    /// Complete REST reconciliation. REST alone never arms execution; a live
    /// authenticated stream must also be present.
    pub async fn sample(&self) -> TradingSnapshot {
        let (Some(endpoint), Some(client)) = (&self.endpoint, &self.client) else {
            return self.current().await;
        };
        let result = async {
            let url = endpoint.base.join("api/edge/snapshot").map_err(|_| ())?;
            let response = client
                .get(url)
                .bearer_auth(&endpoint.token)
                .send()
                .await
                .map_err(|_| ())?;
            if !response.status().is_success() {
                return Err(());
            }
            let body = bounded_body(response).await?;
            let snapshot = parse_snapshot(&body)?;
            self.accept(snapshot).await
        }
        .await;
        if result.is_err() {
            self.fail("Gateway reconciliation unavailable").await;
        }
        self.current().await
    }

    pub async fn snapshot(&self) -> TradingSnapshot {
        self.current().await
    }

    /// Runs independently from health/agent sampling. The watch channel always
    /// carries a full replacement projection, including empty collections.
    pub async fn run(&self, updates: watch::Sender<TradingSnapshot>) {
        updates.send_replace(self.sample().await);
        let Some(endpoint) = &self.endpoint else {
            return;
        };
        loop {
            if updates.is_closed() {
                return;
            }
            let mut url = match endpoint.base.join("api/edge/ws") {
                Ok(url) => url,
                Err(_) => return,
            };
            let scheme = if url.scheme() == "https" { "wss" } else { "ws" };
            if url.set_scheme(scheme).is_err() {
                return;
            }
            let Ok(mut request) = url.as_str().into_client_request() else {
                return;
            };
            let Ok(mut bearer) = HeaderValue::from_str(&format!("Bearer {}", endpoint.token))
            else {
                return;
            };
            bearer.set_sensitive(true);
            request.headers_mut().insert("Authorization", bearer);
            let config = WebSocketConfig::default()
                .max_message_size(Some(MAX_BODY))
                .max_frame_size(Some(MAX_BODY));
            let connected = tokio::time::timeout(
                REQUEST_TIMEOUT,
                tokio_tungstenite::connect_async_with_config(request, Some(config), false),
            )
            .await;
            if let Ok(Ok((mut socket, _))) = connected {
                self.state.lock().await.stream_connected = true;
                let mut reconcile = tokio::time::interval(RECONCILE_EVERY);
                reconcile.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                let mut expiry = tokio::time::interval(Duration::from_secs(1));
                loop {
                    tokio::select! {
                        _ = updates.closed() => { let _ = socket.close(None).await; return; }
                        _ = reconcile.tick() => { updates.send_replace(self.sample().await); }
                        _ = expiry.tick() => { updates.send_replace(self.current().await); }
                        frame = socket.next() => {
                            match frame {
                                Some(Ok(Message::Text(text))) => {
                                    let accepted = match parse_snapshot(text.as_bytes()) {
                                        Ok(snapshot) => {
                                            let sampled_at_ms = snapshot.sampled_at_ms;
                                            let result = self.accept(snapshot).await;
                                            let mut state = self.state.lock().await;
                                            if result.is_ok() && sampled_at_ms >= state.snapshot.sampled_at_ms
                                                && now_ms().saturating_sub(sampled_at_ms) <= STALE_AFTER.as_millis() as u64
                                            { state.stream_observed_at = Some(Instant::now()); }
                                            result
                                        },
                                        Err(()) => Err(()),
                                    };
                                    if accepted.is_err() { break; }
                                    updates.send_replace(self.current().await);
                                }
                                Some(Ok(Message::Ping(bytes))) => {
                                    if socket.send(Message::Pong(bytes)).await.is_err() { break; }
                                }
                                Some(Ok(Message::Pong(_))) => {},
                                _ => break,
                            }
                        }
                    }
                }
            }
            {
                let mut state = self.state.lock().await;
                state.stream_connected = false;
                state.stream_observed_at = None;
            }
            self.fail("Gateway stream disconnected").await;
            updates.send_replace(self.current().await);
            tokio::select! {
                _ = updates.closed() => return,
                _ = tokio::time::sleep(Duration::from_secs(2)) => {},
            }
            updates.send_replace(self.sample().await);
        }
    }

    /// One transport submission per UUID. A timeout or ambiguous broker result
    /// remains unknown/pending, is reconciled, and is never automatically sent
    /// again. The server must independently enforce the same idempotency key.
    pub async fn perform(
        &self,
        request: &TradingRequest,
        command_id: &str,
    ) -> TradingCommandResult {
        let rejected = |message: &str| TradingCommandResult {
            command_id: command_id.into(),
            state: TradingCommandState::Rejected,
            message: message.into(),
        };
        let Ok(id) = Uuid::parse_str(command_id) else {
            return rejected("Invalid command ID");
        };
        if id.get_version_num() != 4 {
            return rejected("Command ID must be a random UUID v4");
        }
        let (Some(endpoint), Some(client)) = (&self.endpoint, &self.client) else {
            return rejected("Trading gateway is not configured");
        };
        let snapshot = self.current().await;
        if !snapshot.execution_enabled || !self.config.execution_enabled {
            return rejected("Trading is disabled or the gateway state is stale");
        }
        if let Err(message) = validate_request(request, &snapshot) {
            return rejected(message);
        }
        {
            let mut state = self.state.lock().await;
            if state.submitted.len() >= 4096 {
                return rejected("Command ledger capacity reached; execution disabled");
            }
            if !state.submitted.insert(id) {
                return rejected("Command ID already submitted; reconcile its outcome");
            }
        }
        let envelope = serde_json::json!({
            "command_id": command_id,
            "expected_revision": snapshot.revision,
            "request": request,
        });
        let outcome = async {
            let url = endpoint.base.join("api/edge/commands").map_err(|_| ())?;
            let response = client
                .post(url)
                .bearer_auth(&endpoint.token)
                .json(&envelope)
                .send()
                .await
                .map_err(|_| ())?;
            let success_status = response.status().is_success();
            let body = bounded_body(response).await?;
            let mut outcome: TradingCommandResult =
                serde_json::from_slice(&body).map_err(|_| ())?;
            if outcome.command_id != command_id
                || outcome.message.len() > 512
                || (!success_status && outcome.state != TradingCommandState::Rejected)
            {
                return Err(());
            }
            outcome.message = outcome.message.replace(&endpoint.token, "[redacted]");
            Ok(outcome)
        }
        .await;
        let result = outcome.unwrap_or_else(|()| TradingCommandResult {
            command_id: command_id.into(),
            state: TradingCommandState::Unknown,
            message: "Outcome unconfirmed; inspect reconciled orders before another action".into(),
        });
        // Any submitted action invalidates the current arming state until a
        // complete post-command observation is received.
        self.fail("Reconciling submitted command").await;
        result
    }

    async fn accept(&self, mut snapshot: TradingSnapshot) -> Result<(), ()> {
        let mut state = self.state.lock().await;
        // Revisions are opaque hashes of execution state, compared only for
        // equality by the server. Ordering uses the server observation clock.
        // Never refresh expiry with an older response from a REST/WS race.
        if snapshot.sampled_at_ms < state.snapshot.sampled_at_ms {
            return Ok(());
        }
        if let (Some(endpoint), Some(message)) = (&self.endpoint, &mut snapshot.message) {
            *message = message.replace(&endpoint.token, "[redacted]");
        }
        snapshot.execution_enabled &= self.config.execution_enabled;
        state.snapshot = snapshot;
        state.observed_at = Some(Instant::now());
        Ok(())
    }

    async fn current(&self) -> TradingSnapshot {
        let state = self.state.lock().await;
        let mut snapshot = state.snapshot.clone();
        if state
            .observed_at
            .is_some_and(|at| at.elapsed() > STALE_AFTER)
            || state
                .stream_observed_at
                .is_some_and(|at| state.stream_connected && at.elapsed() > STALE_AFTER)
            || (snapshot.sampled_at_ms > 0
                && now_ms().saturating_sub(snapshot.sampled_at_ms) > STALE_AFTER.as_millis() as u64)
        {
            snapshot.connection = TradingConnection::Stale;
            snapshot.message = Some("Gateway data is stale".into());
        }
        snapshot.execution_enabled &= state.stream_connected
            && state
                .stream_observed_at
                .is_some_and(|at| at.elapsed() <= STALE_AFTER)
            && snapshot.connection == TradingConnection::Connected
            && snapshot.broker_connected
            && state.observed_at.is_some()
            && state.submitted.len() < 4096;
        snapshot
    }

    async fn fail(&self, message: &str) {
        let mut state = self.state.lock().await;
        state.snapshot.connection = if state.observed_at.is_some() {
            TradingConnection::Stale
        } else {
            TradingConnection::Offline
        };
        state.snapshot.execution_enabled = false;
        state.snapshot.message = Some(message.into());
    }
}

fn default_credentials_path() -> Option<PathBuf> {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .map(|directory| directory.join("riptide/.env"))
}

fn load_endpoint(config: &TradingConfig) -> Result<Endpoint, &'static str> {
    let path = config
        .credentials_file
        .clone()
        .or_else(default_credentials_path)
        .ok_or("Gateway credentials file is not configured")?;
    let file = File::open(path).map_err(|_| "Gateway credentials file is unavailable")?;
    let metadata = file
        .metadata()
        .map_err(|_| "Gateway credentials file is unavailable")?;
    if !metadata.is_file() || metadata.len() > MAX_CREDENTIAL_BYTES {
        return Err("Gateway credentials must be a regular file");
    }
    let mut url = None;
    let mut token = None;
    // Read bounded lines, extracting just the two gateway fields. Never load
    // dotenv into the environment or retain unrelated broker key values.
    for line in BufReader::new(file.take(MAX_CREDENTIAL_BYTES + 1)).lines() {
        let line = line.map_err(|_| "Gateway credentials file cannot be read")?;
        let line = line.trim().strip_prefix("export ").unwrap_or(line.trim());
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if !matches!(key.trim(), "DATA_SERVER_URL" | "DATA_SERVER_TOKEN") {
            continue;
        }
        let value = value.trim();
        let value = if value.len() >= 2
            && ((value.starts_with('"') && value.ends_with('"'))
                || (value.starts_with('\'') && value.ends_with('\'')))
        {
            &value[1..value.len() - 1]
        } else {
            value
        };
        match key.trim() {
            "DATA_SERVER_URL" => url = Some(value.to_owned()),
            "DATA_SERVER_TOKEN" => token = Some(value.to_owned()),
            _ => {}
        }
    }
    let url = config
        .server_url
        .as_deref()
        .or(url.as_deref())
        .ok_or("Gateway URL is not configured")?;
    let mut base = validate_url(url)?;
    if !base.path().ends_with('/') {
        base.set_path(&format!("{}/", base.path()));
    }
    let token = token
        .filter(|token| {
            !token.is_empty() && token.len() <= 4096 && !token.chars().any(char::is_control)
        })
        .ok_or("Gateway token is not configured")?;
    Ok(Endpoint { base, token })
}

fn validate_url(value: &str) -> Result<Url, &'static str> {
    let url = Url::parse(value).map_err(|_| "Gateway URL is invalid")?;
    let loopback_test = cfg!(test)
        && url.scheme() == "http"
        && url.host_str().is_some_and(|host| {
            host == "localhost"
                || host
                    .trim_matches(['[', ']'])
                    .parse::<std::net::IpAddr>()
                    .is_ok_and(|ip| ip.is_loopback())
        });
    if (url.scheme() != "https" && !loopback_test)
        || url.host().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err("Gateway requires HTTPS without URL credentials or query strings");
    }
    Ok(url)
}

async fn bounded_body(mut response: reqwest::Response) -> Result<Vec<u8>, ()> {
    if response
        .content_length()
        .is_some_and(|n| n > MAX_BODY as u64)
    {
        return Err(());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| ())? {
        if bytes.len().saturating_add(chunk.len()) > MAX_BODY {
            return Err(());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value.trim() == value
        && !value.chars().any(char::is_control)
}

fn valid_symbol(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 32
        && value.bytes().all(|byte| {
            byte.is_ascii_uppercase()
                || byte.is_ascii_digit()
                || matches!(byte, b'.' | b'-' | b'_' | b'/')
        })
}

fn parse_snapshot(body: &[u8]) -> Result<TradingSnapshot, ()> {
    if body.len() > MAX_BODY {
        return Err(());
    }
    let snapshot: TradingSnapshot = serde_json::from_slice(body).map_err(|_| ())?;
    if snapshot.schema_version != 1
        || snapshot.accounts.len() > 128
        || snapshot.positions.len() > 256
        || snapshot.orders.len() > 512
        || snapshot.fills.len() > 256
        || snapshot.quotes.len() > 128
        || snapshot
            .message
            .as_ref()
            .is_some_and(|text| text.len() > 512)
        || snapshot.sampled_at_ms == 0
        || snapshot.sampled_at_ms > now_ms().saturating_add(5_000)
        || snapshot
            .accounts
            .iter()
            .any(|a| !valid_id(&a.id) || a.label.len() > 128 || a.account_type.len() > 64)
        || snapshot
            .positions
            .iter()
            .any(|p| !valid_id(&p.account_id) || !valid_symbol(&p.symbol))
        || snapshot.orders.iter().any(|o| {
            !valid_id(&o.id)
                || !valid_id(&o.account_id)
                || !valid_symbol(&o.symbol)
                || o.status.len() > 64
        })
        || snapshot
            .fills
            .iter()
            .any(|f| !valid_id(&f.id) || !valid_id(&f.account_id) || !valid_symbol(&f.symbol))
        || snapshot.quotes.iter().any(|q| !valid_symbol(&q.symbol))
    {
        return Err(());
    }
    Ok(snapshot)
}

fn validate_request(
    request: &TradingRequest,
    snapshot: &TradingSnapshot,
) -> Result<(), &'static str> {
    let account_id = match request {
        TradingRequest::Place { account_id, .. }
        | TradingRequest::Modify { account_id, .. }
        | TradingRequest::Cancel { account_id, .. }
        | TradingRequest::Close { account_id, .. }
        | TradingRequest::Reverse { account_id, .. }
        | TradingRequest::CancelAll { account_id }
        | TradingRequest::Flatten { account_id } => account_id,
    };
    if !valid_id(account_id)
        || !snapshot
            .accounts
            .iter()
            .any(|a| a.id == *account_id && a.can_trade)
    {
        return Err("Selected account is unavailable for trading");
    }
    let valid_quantity = |quantity: u32| quantity > 0 && quantity <= 10_000;
    let valid_price =
        |price: Option<f64>| price.is_none_or(|price| price.is_finite() && price > 0.0);
    match request {
        TradingRequest::Place {
            symbol,
            quantity,
            order_type,
            price,
            stop_price,
            trail_ticks,
            sl_ticks,
            tp_ticks,
            ..
        } => {
            if !valid_symbol(symbol)
                || !valid_quantity(*quantity)
                || !valid_price(*price)
                || !valid_price(*stop_price)
            {
                return Err("Order symbol, quantity, or price is invalid");
            }
            if matches!(
                order_type,
                TradingOrderType::Limit | TradingOrderType::StopLimit
            ) && price.is_none()
                || matches!(
                    order_type,
                    TradingOrderType::StopMarket | TradingOrderType::StopLimit
                ) && stop_price.is_none()
                || *order_type == TradingOrderType::TrailingStop && trail_ticks.is_none()
                || [trail_ticks, sl_ticks, tp_ticks]
                    .iter()
                    .any(|ticks| ticks.is_some_and(|ticks| !valid_quantity(ticks)))
            {
                return Err("Required order price or tick offset is missing or invalid");
            }
            if (sl_ticks.is_some() || tp_ticks.is_some()) && !snapshot.supports_brackets {
                return Err("Server-managed brackets are unavailable");
            }
            if (sl_ticks.is_some() || tp_ticks.is_some())
                && (sl_ticks.is_none()
                    || tp_ticks.is_none()
                    || !matches!(
                        order_type,
                        TradingOrderType::Market | TradingOrderType::Limit
                    ))
            {
                return Err(
                    "Server brackets require both stop and target offsets on market or limit orders",
                );
            }
        }
        TradingRequest::Modify {
            order_id,
            quantity,
            price,
            stop_price,
            ..
        } => {
            if !valid_id(order_id)
                || quantity.is_some_and(|q| !valid_quantity(q))
                || !valid_price(*price)
                || !valid_price(*stop_price)
                || (quantity.is_none() && price.is_none() && stop_price.is_none())
            {
                return Err("Order modification is invalid");
            }
            if !snapshot
                .orders
                .iter()
                .any(|o| o.id == *order_id && o.account_id == *account_id)
            {
                return Err("Selected order is no longer in the current snapshot");
            }
        }
        TradingRequest::Cancel { order_id, .. } => {
            if !valid_id(order_id)
                || !snapshot
                    .orders
                    .iter()
                    .any(|o| o.id == *order_id && o.account_id == *account_id)
            {
                return Err("Selected order is no longer in the current snapshot");
            }
        }
        TradingRequest::Close { symbol, .. } | TradingRequest::Reverse { symbol, .. } => {
            if !valid_symbol(symbol)
                || !snapshot
                    .positions
                    .iter()
                    .any(|p| p.account_id == *account_id && p.symbol == *symbol && p.quantity != 0)
            {
                return Err("Selected position is no longer in the current snapshot");
            }
            if !snapshot.supports_flatten {
                return Err("Server-managed position actions are unavailable");
            }
        }
        TradingRequest::Flatten { .. } => {
            if !snapshot.supports_flatten {
                return Err("Server-managed flatten is unavailable");
            }
        }
        TradingRequest::CancelAll { .. } => {}
    }
    Ok(())
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(u64::MAX as u128) as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };

    fn fixture() -> TradingSnapshot {
        TradingSnapshot {
            revision: 42,
            sampled_at_ms: now_ms(),
            connection: TradingConnection::Connected,
            broker_connected: true,
            execution_enabled: true,
            accounts: vec![TradingAccount {
                id: "18446744073709551615".into(),
                label: "Demo account".into(),
                account_type: "simulation".into(),
                can_trade: true,
                balance: Some(50_000.0),
                open_pnl: Some(12.5),
                closed_pnl: None,
                loss_limit: None,
                min_account_balance: None,
                auto_liquidate_threshold: None,
            }],
            ..Default::default()
        }
    }

    fn place() -> TradingRequest {
        TradingRequest::Place {
            account_id: "18446744073709551615".into(),
            symbol: "NQZ6".into(),
            side: TradingSide::Buy,
            quantity: 1,
            order_type: TradingOrderType::Market,
            price: None,
            stop_price: None,
            trail_ticks: None,
            sl_ticks: None,
            tp_ticks: None,
        }
    }

    async fn arm(client: &TradingController) {
        let mut state = client.state.lock().await;
        state.stream_connected = true;
        state.stream_observed_at = Some(Instant::now());
    }

    fn controller(url: String) -> (TradingController, tempfile::NamedTempFile) {
        let credentials = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(
            credentials.path(),
            "DATA_SERVER_TOKEN=test-token\nRITHMIC_PASSWORD=ignored-secret\n",
        )
        .unwrap();
        (
            TradingController::new(TradingConfig {
                enabled: true,
                execution_enabled: true,
                server_url: Some(url),
                credentials_file: Some(credentials.path().to_owned()),
            }),
            credentials,
        )
    }

    #[test]
    fn default_is_disabled_and_never_needs_credentials() {
        let config = TradingConfig::default();
        assert!(!config.enabled && !config.execution_enabled);
        let client = TradingController::new(config);
        assert!(client.endpoint.is_none());
    }

    #[test]
    fn transport_rejects_insecure_remote_urls_and_embedded_credentials() {
        for url in [
            "http://example.com",
            "http://127.0.0.1.evil.test",
            "ftp://example.com",
            "https://user:password@example.com",
            "https://example.com/?token=secret",
            "https://example.com/#secret",
        ] {
            assert!(validate_url(url).is_err());
        }
        assert!(validate_url("https://example.com").is_ok());
        assert!(validate_url("http://127.0.0.1:1234").is_ok());
        assert!(validate_url("http://[::1]:1234").is_ok());
    }

    #[test]
    fn snapshot_preserves_opaque_account_handles_and_rejects_numbers() {
        let encoded = serde_json::to_vec(&fixture()).unwrap();
        let parsed = parse_snapshot(&encoded).unwrap();
        assert_eq!(parsed.accounts[0].id, "18446744073709551615");
        let mut value = serde_json::to_value(parsed).unwrap();
        value["accounts"][0]["id"] = serde_json::json!(9007199254740993_u64);
        assert!(parse_snapshot(&serde_json::to_vec(&value).unwrap()).is_err());
    }

    #[test]
    fn snapshot_rejects_unsupported_schema_oversize_and_future_clock() {
        let mut snapshot = fixture();
        snapshot.schema_version = 2;
        assert!(parse_snapshot(&serde_json::to_vec(&snapshot).unwrap()).is_err());
        snapshot.schema_version = 1;
        snapshot.sampled_at_ms = now_ms() + 60_000;
        assert!(parse_snapshot(&serde_json::to_vec(&snapshot).unwrap()).is_err());
        assert!(parse_snapshot(&vec![b' '; MAX_BODY + 1]).is_err());
        snapshot.sampled_at_ms = now_ms();
        snapshot.accounts = vec![snapshot.accounts[0].clone(); 129];
        assert!(parse_snapshot(&serde_json::to_vec(&snapshot).unwrap()).is_err());
    }

    #[test]
    fn requests_are_typed_and_fail_closed_for_invalid_or_unowned_inputs() {
        let snapshot = fixture();
        assert!(validate_request(&place(), &snapshot).is_ok());
        let mut value = serde_json::to_value(place()).unwrap();
        value["account_id"] = serde_json::json!("another-account");
        let request = serde_json::from_value(value.clone()).unwrap();
        assert!(validate_request(&request, &snapshot).is_err());
        value["account_id"] = serde_json::json!(snapshot.accounts[0].id);
        value["quantity"] = serde_json::json!(0);
        assert!(
            validate_request(&serde_json::from_value(value.clone()).unwrap(), &snapshot).is_err()
        );
        value["quantity"] = serde_json::json!(1);
        value["symbol"] = serde_json::json!("NQZ6;sh");
        assert!(
            validate_request(&serde_json::from_value(value.clone()).unwrap(), &snapshot).is_err()
        );
        value["symbol"] = serde_json::json!("NQZ6");
        value["sl_ticks"] = serde_json::json!(10);
        assert!(
            validate_request(&serde_json::from_value(value.clone()).unwrap(), &snapshot).is_err()
        );
        value["shell"] = serde_json::json!("anything");
        assert!(serde_json::from_value::<TradingRequest>(value).is_err());
    }

    #[tokio::test]
    async fn stream_disconnect_clock_age_and_broker_disconnect_disarm_execution() {
        let (client, _credentials) = controller("http://127.0.0.1:1234".into());
        client.accept(fixture()).await.unwrap();
        assert!(!client.snapshot().await.execution_enabled);
        arm(&client).await;
        assert!(client.snapshot().await.execution_enabled);
        client.state.lock().await.observed_at =
            Some(Instant::now() - STALE_AFTER - Duration::from_secs(1));
        assert_eq!(client.snapshot().await.connection, TradingConnection::Stale);
        assert!(!client.snapshot().await.execution_enabled);
        let mut snapshot = fixture();
        snapshot.broker_connected = false;
        client.accept(snapshot).await.unwrap();
        assert!(!client.snapshot().await.execution_enabled);
        client.state.lock().await.snapshot.sampled_at_ms = now_ms() - 30_000;
        assert!(!client.snapshot().await.execution_enabled);
    }

    #[tokio::test]
    async fn complete_snapshots_clear_orders_and_older_observations_never_replace_newer_data() {
        let (client, _credentials) = controller("http://127.0.0.1:1234".into());
        let mut snapshot = fixture();
        snapshot.orders.push(TradingOrder {
            id: "order-1".into(),
            account_id: snapshot.accounts[0].id.clone(),
            symbol: "NQZ6".into(),
            side: TradingSide::Buy,
            quantity: 1,
            filled_quantity: 0,
            order_type: TradingOrderType::Limit,
            price: Some(20_000.0),
            stop_price: None,
            status: "working".into(),
        });
        let initial_time = snapshot.sampled_at_ms;
        client.accept(snapshot).await.unwrap();
        assert_eq!(client.snapshot().await.orders.len(), 1);
        let mut cleared = fixture();
        cleared.revision = 1; // opaque hash may decrease
        cleared.sampled_at_ms = initial_time + 1;
        client.accept(cleared).await.unwrap();
        assert!(client.snapshot().await.orders.is_empty());
        let mut old = fixture();
        old.sampled_at_ms = initial_time;
        old.accounts.clear();
        client.accept(old).await.unwrap();
        assert_eq!(client.snapshot().await.accounts.len(), 1);
    }

    async fn read_http(stream: &mut tokio::net::TcpStream) -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut buffer = [0; 4096];
        loop {
            let size = stream.read(&mut buffer).await.unwrap();
            if size == 0 {
                break;
            }
            bytes.extend_from_slice(&buffer[..size]);
            if let Some(end) = bytes.windows(4).position(|s| s == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&bytes[..end]).to_lowercase();
                let content_length = headers
                    .lines()
                    .find_map(|line| {
                        line.strip_prefix("content-length:")?
                            .trim()
                            .parse::<usize>()
                            .ok()
                    })
                    .unwrap_or(0);
                if bytes.len() >= end + 4 + content_length {
                    break;
                }
            }
        }
        bytes
    }

    async fn respond(stream: &mut tokio::net::TcpStream, status: &str, body: &[u8]) {
        let header = format!(
            "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            body.len()
        );
        stream.write_all(header.as_bytes()).await.unwrap();
        stream.write_all(body).await.unwrap();
    }

    #[tokio::test]
    async fn rest_uses_bearer_header_and_does_not_follow_redirects() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let (client, _credentials) =
            controller(format!("http://{}", listener.local_addr().unwrap()));
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let request = read_http(&mut stream).await;
            let text = String::from_utf8_lossy(&request).to_lowercase();
            assert!(text.starts_with("get /api/edge/snapshot "));
            assert!(text.contains("authorization: bearer test-token"));
            assert!(!text.contains("ignored-secret"));
            let response = format!(
                "HTTP/1.1 302 Found\r\nLocation: http://{}/stolen\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                listener.local_addr().unwrap()
            );
            stream.write_all(response.as_bytes()).await.unwrap();
            assert!(
                tokio::time::timeout(Duration::from_millis(150), listener.accept())
                    .await
                    .is_err()
            );
        });
        assert_eq!(client.sample().await.connection, TradingConnection::Offline);
        server.await.unwrap();
    }

    #[tokio::test]
    async fn mutation_timeout_has_one_submission_and_never_claims_success() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let (mut client, _credentials) =
            controller(format!("http://{}", listener.local_addr().unwrap()));
        client.client = Some(
            Client::builder()
                .timeout(Duration::from_millis(100))
                .retry(reqwest::retry::never())
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .unwrap(),
        );
        client.accept(fixture()).await.unwrap();
        arm(&client).await;
        let hits = Arc::new(AtomicUsize::new(0));
        let server_hits = hits.clone();
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let bytes = read_http(&mut stream).await;
            server_hits.fetch_add(1, Ordering::SeqCst);
            let start = bytes.windows(4).position(|s| s == b"\r\n\r\n").unwrap() + 4;
            let envelope: serde_json::Value = serde_json::from_slice(&bytes[start..]).unwrap();
            assert_eq!(envelope["request"]["account_id"], "18446744073709551615");
            assert_eq!(envelope["expected_revision"], 42);
            tokio::time::sleep(Duration::from_millis(200)).await;
            assert!(
                tokio::time::timeout(Duration::from_millis(100), listener.accept())
                    .await
                    .is_err()
            );
        });
        let command_id = Uuid::new_v4().to_string();
        let outcome = client.perform(&place(), &command_id).await;
        assert_eq!(outcome.state, TradingCommandState::Unknown);
        assert!(!outcome.confirmed());
        client.accept(fixture()).await.unwrap();
        let repeated = client.perform(&place(), &command_id).await;
        assert_eq!(repeated.state, TradingCommandState::Rejected);
        assert!(repeated.message.contains("already submitted"));
        server.await.unwrap();
        assert_eq!(hits.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn pending_outcome_is_not_success_and_messages_redact_token() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let (client, _credentials) =
            controller(format!("http://{}", listener.local_addr().unwrap()));
        client.accept(fixture()).await.unwrap();
        arm(&client).await;
        let command_id = Uuid::new_v4().to_string();
        let response_id = command_id.clone();
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            read_http(&mut stream).await;
            respond(
                &mut stream,
                "200 OK",
                &serde_json::to_vec(&TradingCommandResult {
                    command_id: response_id,
                    state: TradingCommandState::Pending,
                    message: "waiting test-token".into(),
                })
                .unwrap(),
            )
            .await;
        });
        let result = client.perform(&place(), &command_id).await;
        assert_eq!(result.state, TradingCommandState::Pending);
        assert!(!result.confirmed());
        assert!(!result.message.contains("test-token"));
        assert!(!client.snapshot().await.execution_enabled);
        server.await.unwrap();
    }

    #[tokio::test]
    #[allow(clippy::result_large_err)] // tungstenite's handshake callback requires this error type
    async fn websocket_uses_header_auth_and_disconnect_disarms_execution() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let (client, _credentials) =
            controller(format!("http://{}", listener.local_addr().unwrap()));
        let (release, released) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            // Complete REST bootstrap, followed by authenticated WS upgrade.
            let (mut rest, _) = listener.accept().await.unwrap();
            read_http(&mut rest).await;
            respond(
                &mut rest,
                "200 OK",
                &serde_json::to_vec(&fixture()).unwrap(),
            )
            .await;
            let (stream, _) = listener.accept().await.unwrap();
            let mut socket = tokio_tungstenite::accept_hdr_async(
                stream,
                |request: &tokio_tungstenite::tungstenite::handshake::server::Request, response| {
                    assert_eq!(request.uri().path(), "/api/edge/ws");
                    assert_eq!(
                        request.headers().get("authorization").unwrap(),
                        "Bearer test-token"
                    );
                    assert!(request.uri().query().is_none());
                    Ok(response)
                },
            )
            .await
            .unwrap();
            let (start_stream, stream_started) = tokio::sync::oneshot::channel();
            let stream_task = tokio::spawn(async move {
                stream_started.await.unwrap();
                socket
                    .send(Message::Text(
                        serde_json::to_string(&fixture()).unwrap().into(),
                    ))
                    .await
                    .unwrap();
                let _ = released.await;
                socket.close(None).await.unwrap();
            });
            // The independent stream loop also reconciles a complete REST
            // snapshot immediately after its successful connection.
            let (mut rest, _) = listener.accept().await.unwrap();
            read_http(&mut rest).await;
            respond(
                &mut rest,
                "200 OK",
                &serde_json::to_vec(&fixture()).unwrap(),
            )
            .await;
            start_stream.send(()).unwrap();
            stream_task.await.unwrap();
        });
        let (updates, mut receiver) = watch::channel(TradingSnapshot::default());
        let running = client.clone();
        let task = tokio::spawn(async move { running.run(updates).await });
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                receiver.changed().await.unwrap();
                if receiver.borrow().execution_enabled {
                    break;
                }
            }
        })
        .await
        .unwrap();
        release.send(()).unwrap();
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                receiver.changed().await.unwrap();
                if receiver.borrow().connection == TradingConnection::Stale {
                    assert!(!receiver.borrow().execution_enabled);
                    break;
                }
            }
        })
        .await
        .unwrap();
        drop(receiver);
        tokio::time::timeout(Duration::from_secs(1), task)
            .await
            .unwrap()
            .unwrap();
        server.await.unwrap();
    }
}
