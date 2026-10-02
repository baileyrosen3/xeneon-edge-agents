# Two touch dashboards

The portal keeps the existing visual theme and agent interface, with two
full-size destinations: **Omarchy + Agents** and **Riptide**. Tap either label
or drag the fixed two-position slider at the bottom to switch. Both screens
remain mounted so ticket drafts survive switching. Agent-card pagination
continues within the combined dashboard, with ten cards per page and explicit
Previous/Next controls. Controls and scrolling lists own their touch gestures.

The Rust daemon owns data collection and actions. Quickshell presents bounded
snapshots and sends typed requests; it does not execute arbitrary shell commands
or create broker sessions.

## Omarchy

The control dashboard combines the existing PC health readings with desktop
controls: audio volume/mute, microphone mute, output selection, media playback,
Do Not Disturb, keep-awake, nightlight, capture, lock, themes, and power profiles.
Storage usage and a bounded process list provide PC context. Optional services
and readings have unavailable states. The current EDGE brightness capability is
disabled when exact hardware identity and restoration have not been verified.

Omarchy controls use the existing host command interfaces through an allowlist
in `crates/xeneon-agent-core/src/omarchy.rs`. A request such as
`{"operation":"volume","percent":55}` has fixed fields and bounded values.
Unknown operations and extra fields are rejected before dispatch.

## Agents

The existing Herdr/T3 Code roster, attention states, usage displays, voice
dictation, manager selection, and permitted focus actions remain available.
Agent authority stays with the selected manager. Dashboard actions cannot
target an agent or borrow an approval/interrupt capability.

## Riptide

The trading dashboard connects **directly to the authenticated Riptide gateway**.
The desktop Riptide app does not need to be running. Broker credentials and the
Rithmic Order Plant session remain on the gateway; the EDGE uses only the gateway
URL and bearer token. Tokens are never included in QML snapshots or notices.

The native EDGE API is:

| Endpoint | Purpose |
|---|---|
| `GET /api/edge/snapshot` | Complete private JSON projection for the authenticated user |
| `WSS /api/edge/ws` | Complete replacement snapshots, including empty collections |
| `POST /api/edge/commands` | Typed, account-scoped request with a UUID command ID and expected revision |

The snapshot schema version is `1`. Its fields are `revision`, `sampled_at_ms`,
`connection`, `broker_connected`, `execution_enabled`, `supports_brackets`,
`supports_close`, `supports_reverse`, `supports_flatten`, `message`, `accounts`,
`positions`, `orders`, `fills`, and `quotes`. Account/order/fill handles are exact
strings, including handles larger than JavaScript's safe integer range.

Accounts include display label/type, trade permission, balance/PnL, and available
risk thresholds. Positions include exact contract symbol, signed quantity, and
average price, and an explicit `can_close` flag. Orders include side, type,
quantity/fills, prices, and status.
Quotes include available bid/ask/last, tick size, point value, and update time.
Fills are realized fill records; they are not reconstructed round-trip trades.

Supported request variants are `place`, `modify`, `cancel`, `close`, `reverse`,
`cancel_all`, and `flatten`. Their availability is governed by the server
capabilities and local execution setting. Close, reverse, and flatten have
independent capabilities; absent flags default to false. The current gateway
implementation keeps Close, Reverse, and Flatten disabled until complete broker
order/position enumeration and exit sequencing are proven. A future server can
expose native Close only for an explicitly eligible position with `can_close=true`.

Every request contains an opaque `account_id`. Place uses an exact `symbol`,
`side`, `quantity`, `order_type`, and applicable `price`, `stop_price`, or
`trail_ticks`. Native next-order brackets require both `sl_ticks` and `tp_ticks`
on Market or Limit entries. Modify/cancel use an exact `order_id`; close/reverse
use the exact position symbol. `cancel_all` and `flatten` are account-wide.

The daemon attaches a stable UUID v5 derived from its epoch and portal request
ID, plus the current revision. Revisions are opaque equality tokens, not
increasing sequence numbers. Full snapshots are ordered by observation time.
The client reconciles via REST every ten seconds and requires a fresh live
stream before enabling execution. Old/disconnected data disables actions.

Commands have no automatic transport retry. A confirmed broker observation can
produce success. `pending` is acknowledged but remains visibly unconfirmed
until a fresh broker update; execution is disarmed while that update is awaited.
An `unknown` outcome keeps the ticket locked until the user explicitly reviews
current orders/positions and uses Review & resume. That control never resends
the prior command. The server
must persist the per-user command intent before submission and deduplicate the
UUID across reconnects and restarts. The client also prevents concurrent local
commands and repeated IDs during its lifetime.

## Existing-server compatibility

Only an exact `404` from `/api/edge/snapshot` enables a **read-only** compatibility
view using authenticated `GET /api/rithmic/accounts`, `/positions`, and `/orders`.
Authorization failures, malformed responses, and other errors do not fall back.
The compatibility view preserves integer IDs as strings and polls every ten
seconds; it detects an upgraded EDGE endpoint on the next reconciliation.

The legacy routes expose caches without authoritative live Order Plant
liveness. The view reports gateway reachability while marking broker connection
unverified. Execution and all command capabilities stay disabled, with a server
upgrade message. Quotes and fills stay empty when unavailable. No order mutation
is sent through a legacy endpoint.

## Configuration and customization

`config/xeneon-edge-agents/config.toml.example` contains a disabled-by-default
`[trading]` section. `enabled` permits gateway observation;
`execution_enabled` is a separate local opt-in and still requires server-side
execution permission and capabilities. Use HTTPS and an absolute
`credentials_file` containing only `DATA_SERVER_URL` and `DATA_SERVER_TOKEN`.
Keep it mode `0600`, outside Git. The URL can also be set with `server_url`.

The source customization points are:

| Location | Responsibility |
|---|---|
| `quickshell/components/DashboardView.qml` | Combined dashboard composition and two-screen routing |
| `quickshell/components/DashboardSwitcher.qml` | Fixed bottom drag/tap slider |
| `quickshell/components/PortalView.qml` | Existing agent interface, actions, and pagination |
| `quickshell/components/OmarchyControls.qml` | Desktop dashboard content |
| `quickshell/components/RiptideDashboard.qml` | Trading layout, ticket, and review flow |
| `quickshell/state/PortalStore.qml` | Bounded UI normalization and full replacement state |
| `quickshell/state/PortalBridge.qml` | Typed transport and preview restrictions |
| `quickshell/state/CommandBuilder.qml` | Command envelope construction |
| `crates/xeneon-agent-core/src/omarchy.rs` | Host collectors and allowed desktop operations |
| `crates/xeneon-agent-core/src/trading.rs` | Gateway transport, normalization, and execution gates |

Preview mode blocks real desktop and trading controls. It is suitable for
layout/theme work with deterministic fixtures. Installed QML is copied from the
source tree, so source edits require reinstall/relaunch to update production.
Physical EDGE touch, output identity, hotplug, and broker SIM commissioning are
separate from fixture validation. A preview is not evidence of live execution.

## Validation

The focused Rust tests cover typed parameter boundaries, malformed requests
rejected before action controllers, a real daemon Unix socket staying alive with
trading disabled, exact account IDs, independent capabilities, reconciliation,
and local HTTP/WebSocket mocks. Decimal tick metadata promoted from `f32` must
not reject valid decimal prices; the gateway performs authoritative price-grid
validation.

`quickshell/tests/tst_dashboard_store_safety.qml` covers equal-sequence newer
snapshots refreshing both dashboards, exact opaque handles, disconnected/stale
execution states, and preview actions producing no real control dispatch.
The Qt test runner uses an inert I/O double for the actual bridge component;
no daemon/process is started by that test. Runtime socket tests separately
exercise the real Rust transport.

Run `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`,
and `tests/run-qml-tests`. Installer/Lua checks and physical hardware checks
remain part of the repository commissioning workflow.
