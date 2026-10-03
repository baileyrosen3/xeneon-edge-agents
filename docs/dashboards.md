# Nine touch presets

The portal keeps the existing visual theme and agent interface, with a
**left-edge slide-out sidebar**. Tap the edge grip or drag it to the right to
open; tap a preset to switch pages and close the sidebar. Drag the grip left,
tap the backdrop, or use Escape in a keyboard-focusable preview to dismiss it.
The selected preset persists across portal restarts.

| Preset | Page |
|---|---|
| 1 | Agent Dashboard — existing agents and Omarchy controls |
| 2 | Trading Dashboard — existing Riptide console |
| 3 | Desktop Controls — PC health and quick actions |
| 4 | System Details — storage, processes, and network |
| 5 | Audio / Display — audio outputs and monitor access |
| 6 | Theme / Power — Omarchy themes and power profiles |
| 7 | AI Usage — provider capacity and fleet status |
| 8 | Agent Radar — live agent constellation |
| 9 | Palette Settings — agent-state color mappings |

Agent and trading screens remain mounted, so agent pagination and ticket
drafts survive switching. The desktop presets share one control instance and
its pending results. The desktop shortcuts on the agent dashboard's control
panel select presets 4–6 directly instead of opening a second local drawer, so
one destination has one navigation path. Unavailable projections stay
explicit.

Agent-card pagination continues within the combined dashboard, with ten cards
per page and explicit Previous/Next controls. Each card gives its display name
the full card width on up to two lines at the existing title size, so numeric
or otherwise distinguishing suffixes stay readable. Only the edge grip owns the
sidebar drag; page controls and scrolling lists keep their own gestures. Pages
cannot receive input while the sidebar is open, dragging, or settling. Reduced
motion snaps the drawer to its destination.

Preset rows, the Monitor entry, and agent pagination controls are sized for
shallow touch surfaces and scroll when the list is taller than the drawer; a
scroll indicator appears whenever a preset is out of view. Storage rows are
informational, not buttons.

## Keyboard and modal behavior

The installed portal window holds no keyboard focus, so this section describes
keyboard-operable behavior in focusable previews and assistive-technology
activation. Shared buttons accept Enter and Space once per press, show a focus
border, and expose their accessible name, state, and press action.

The sidebar retains focus while open and restores it to the edge grip on close.
The Monitor overlay, palette pane, Riptide selector, confirmation, and amendment
dialogs each take focus on open, contain Tab and Backtab, dismiss on Escape,
and restore the invoker's focus on close. Continuous monitor sliders accept
arrow, Home, and End keys against the discovered integer range. Palette role
cells are radio buttons with roving arrow-key selection. Agent motion
reduction stays a reversible user preference; only an externally forced value
disables the control.

## Pending actions

A desktop action that is dispatched but never answered — transport loss, a
daemon restart, or the response deadline — is not silently unlocked. The
shared desktop control reports an unknown outcome, blocks further desktop
actions, and requires the user to review current desktop state and press
**REVIEWED · RESUME** once a newer snapshot arrives. The action is never
replayed automatically.

A trading `pending` acknowledgement is not fulfillment. Local execution stays
locked across page and modal transitions until a strictly newer broker
observation arrives; the request is never resent. A lost or timed-out outcome
keeps its existing explicit review-and-resume path.

The Rust daemon owns data collection and actions. Quickshell presents bounded
snapshots and sends typed requests; it does not execute arbitrary shell commands
or create broker sessions.

## Omarchy

The control dashboard combines the existing PC health readings with desktop
controls: audio volume/mute, microphone mute, output selection, media playback,
Do Not Disturb, keep-awake, nightlight, capture, lock, themes, and power profiles.
Storage usage and a bounded process list provide PC context. Optional services
and readings have unavailable states.

Omarchy controls use the existing host command interfaces through an allowlist
in `crates/xeneon-agent-core/src/omarchy.rs`. A request such as
`{"operation":"volume","percent":55}` has fixed fields and bounded values.
Unknown operations and extra fields are rejected before dispatch.

## Monitor hardware settings

The **Monitor** button sits in the sidebar's **bottom-right corner**, available
from all nine presets, and opens the same hardware settings overlay. Opening
Monitor closes the sidebar; the underlying pages and sidebar cannot receive
input while the overlay is visible. Closing settings restores the selected
preset. Device identity, DDC bus, EDID digest, and available display/touch status
are shown alongside the picture controls. Display resolution, rotation, and
touch mapping are read-only.

Controls are discovered against the commissioned EDGE identity and confirmed
with successful DDC reads. Continuous controls use the monitor's actual integer
range; they do not assume percentages. Brightness, contrast, RGB gain, sharpness,
and advertised color presets can appear as writable capabilities. Unsupported
controls remain visible with their reason. The EDGE tested here exposes no
independent DDC backlight control, so that row stays disabled. Dashboard dimming
is a software overlay and is not a hardware backlight setting.

Dragging a hardware slider immediately shows its selected target and starts a
live adjustment. The confirmed hardware value stays visible separately. At most
one command is in flight, with one replaceable target per continuous control;
unique controls are served in order and sends are spaced at least 100 ms apart.
Releasing retains the final target without duplicating an in-flight or confirmed
value. Closing the menu lets already-entered targets finish. Presets and refresh
wait until adjustments finish. Tapping a reported value opens the integer touch
keypad with an Apply button when the hardware is idle.

Presets use only advertised values and names; RGB availability follows the
backend's writable flags for the active preset. A write remains pending until a
successful result and a newer matching hardware readback arrive. An error,
timeout, disconnect, or identity change discards unissued targets and requires
an explicit hardware refresh before another write; the UI never replays them.

The typed operations are `monitor_refresh` and
`{"operation":"monitor_set","control":"contrast","value":50}`. The daemon
owns identity verification, capability discovery, range checks, serialization,
bounded DDC calls, and readback. The UI cannot select an arbitrary bus or VCP
code. Factory reset, input switching, power control, display-mode changes, and
touch calibration are not exposed by this panel.

The production portal also exposes the local UI-only IPC target
`xeneonMonitor`, with `openMonitor` and `closeMonitor`. It changes only the
visibility of this existing overlay. Select the production service's exact
Quickshell process using `quickshell ipc --pid PID call xeneonMonitor openMonitor`;
use `closeMonitor` to dismiss it. Preview windows do not register this target,
and it exposes no hardware mutation methods. The interface follows the
[Quickshell IPC handler documentation](https://quickshell.org/docs/v0.2.0/types/Quickshell.Io/IpcHandler/).

The `[monitor]` configuration separates observation (`enabled`) from writes
(`writes_enabled`). Writes default to false. `refresh_ms` sets the bounded
background observation interval, and optional `commissioning_file` selects the
exact identity record. This controller replaces the legacy commissioning
`[ddc].brightness_enabled` gate; enabling the new controller does not change that
record or touchscreen/display configuration. Hardware values and capability
availability are runtime data, not theme constants.

Optional `read_sleep_multiplier` is an explicit, host-tested read timing profile
from 0.25 through 1.0; omitted keeps native defaults. A complete normal probe
must establish the actual MCCS version before the faster initialization path is
used. That proof is tied to the freshly identified device and expires after
60 seconds without extension by fast reads. Range and RGB preset checks still
read the hardware for each write. Writes keep normal fixed timing, verification,
and independent readback; a failed operation invalidates the proof. Periodic
read-only probes yield to a queued slider write.

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
until a strictly newer broker observation arrives; the local execution
interlock stays engaged across page and modal transitions while that update is
awaited, and the acknowledged request is never resent.
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
| `quickshell/components/DashboardView.qml` | Nine-preset composition, routing, persistence, and modal boundaries |
| `quickshell/components/DashboardSidebar.qml` | Edge drag/tap drawer, preset selection, and bottom-right Monitor entry |
| `quickshell/components/PortalView.qml` | Existing agent interface, actions, and pagination |
| `quickshell/components/OmarchyControls.qml` | Desktop dashboard content |
| `quickshell/components/MonitorSettings.qml` | Global hardware overlay, pending/readback state, and touch keypad |
| `quickshell/components/MonitorControl.qml` | Capability-driven hardware value and slider card |
| `quickshell/components/MonitorSlider.qml` | Raw-unit touch slider with live target updates |
| `quickshell/components/RiptideDashboard.qml` | Trading layout, ticket, and review flow |
| `quickshell/state/PortalStore.qml` | Bounded UI normalization and full replacement state |
| `quickshell/state/PortalBridge.qml` | Typed transport and preview restrictions |
| `quickshell/state/CommandBuilder.qml` | Command envelope construction |
| `crates/xeneon-agent-core/src/omarchy.rs` | Host collectors and allowed desktop operations |
| `crates/xeneon-agent-core/src/monitor.rs` | Exact device discovery, DDC controls, and verified readback |
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

`quickshell/tests/tst_dashboards.qml` covers all nine pointer-selected presets
with scrolling, repeated edge drags, backdrop and Escape dismissal, bounded
selection, draft retention, desktop shortcuts that select the matching
presets without replaying a pending action, closing-animation action blocking,
reversible motion preference, keyboard Monitor entry with focus restoration,
recoverable pending trading acknowledgement, explicit lost-result review, and
global Monitor entry with modal navigation blocking.

`quickshell/tests/tst_dashboard_store_safety.qml` covers equal-sequence newer
snapshots refreshing both dashboards, exact opaque handles, disconnected/stale
execution states, and preview actions producing no real control dispatch.
The Qt test runner uses an inert I/O double for the actual bridge component;
no daemon/process is started by that test. Runtime socket tests separately
exercise the real Rust transport.

`quickshell/tests/tst_monitor_settings.qml` covers dynamic hardware ranges,
unsupported controls, leading/coalesced writes, fair final targets across
controls, closing during adjustment, disconnect/error queue cancellation,
snapshots during a drag,
readback/result ordering, explicit recovery after errors, integer keypad bounds,
and preview/stale/unverified actions producing no dispatch. Its exported image
is a synthetic fixture, not a live hardware acceptance test.

Run `cargo test --workspace`, `cargo clippy --workspace --all-targets -- -D warnings`,
and `tests/run-qml-tests`. Installer/Lua checks and physical hardware checks
remain part of the repository commissioning workflow.
