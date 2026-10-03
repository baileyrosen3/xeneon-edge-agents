# Template: XENEON EDGE agent dashboard

Snapshot of the working Quickshell/QML agent command center as it exists in
this repository, documented as a reusable starting template. This file
describes the current code; it does not propose changes to it.

Repository: `spencerbull/xeneon-edge-agents` (remotes `origin`, `fork`).
Integration branch: `local/omarchy`. Commit that pins this state:
`0f74318c38f37f7df2ad5001ec969ce32bf286f1` ("Replace bottom switcher with
nine-preset slide-out sidebar"). The whole `quickshell/` tree is clean at that
commit.

## Contents

1. [What this template is and is not](#1-what-this-template-is-and-is-not)
2. [Hardware and surface constraints](#2-hardware-and-surface-constraints)
3. [Component map](#3-component-map)
4. [State model](#4-state-model)
5. [Design system](#5-design-system)
6. [Safety boundaries any reuse must preserve](#6-safety-boundaries-any-reuse-must-preserve)
7. [Verification](#7-verification)
8. [Extraction](#8-extraction)
9. [Known constraints and gaps](#9-known-constraints-and-gaps)

---

## 1. What this template is and is not

**It is** an agent/session command center for one physical surface: the Corsair
XENEON EDGE, a 2560x720 capacitive touch strip mounted on a desk, driven on
Omarchy (Arch + Hyprland) by a standalone Quickshell named configuration.
Its product job:

- show a roster of coding/agent sessions owned by exactly one agent manager
  (Herdr or T3 Code) with attention state, review-readiness, and safe triage
  actions;
- provide secondary read/act surfaces for AI provider capacity, host health,
  desktop controls, and monitor (DDC/CI) hardware settings;
- provide an "Ambient" agent-radar presentation for the long idle state.

Structure of the product surface: nine presets behind a left-edge slide-out
drawer (`quickshell/components/DashboardView.qml` `presets` array):

| # | Preset label | Backing component |
|---|---|---|
| 1 | `AGENT DASHBOARD` | `PortalView` + `OmarchyControls` side-by-side |
| 2 | `TRADING DASHBOARD` | `RiptideDashboard` |
| 3 | `DESKTOP CONTROLS` | `OmarchyControls` preset `overview` |
| 4 | `SYSTEM DETAILS` | `OmarchyControls` preset `system` |
| 5 | `AUDIO / DISPLAY` | `OmarchyControls` preset `audio` |
| 6 | `THEME / POWER` | `OmarchyControls` preset `desktop` |
| 7 | `AI USAGE` | `AiUsageDock` |
| 8 | `AGENT RADAR` | `AmbientView` with `radarMode: true` |
| 9 | `PALETTE SETTINGS` | `PaletteSettingsPane` |

The selection persists in the Quickshell `Settings` object
(`preferences.dashboardIndex`, category `display`).

**It is not**:

- a system menu bar. There is no top-bar/system-tray product here; the only
  system controls are pages *inside* this dashboard reached through the
  drawer.
- a home dashboard. A separate home dashboard product is being built in a
  different Quickshell configuration (`quickshell/home/`, written outside this
  repository). It shares no QML with this tree and is not described here. Do
  not merge the two configurations or their preferences files.
- not a general-purpose dashboard framework. Presets, agents, monitor
  capability discovery, and the agent manager concept are all hardcoded to this
  product.

Data flow is strictly one-directional for reads: a Rust daemon
(`xeneon-agentd`) owns all collection and all actions, exposes a `0600` Unix
socket speaking NDJSON schema v1, and Quickshell renders bounded snapshots and
emits typed commands. See `docs/architecture.md` for the trust boundary and
`docs/protocol.md` for the wire shapes.

---

## 2. Hardware and surface constraints

| Constraint | Value | Source |
|---|---|---|
| Panel physical resolution | 2560x720 | `README.md:8`, `TODO.md:770` |
| Panel logical resolution | 1024x288 at scale 2.5 (measured on the commissioned unit) | `TODO.md:770-771` |
| Design surface | 2560x720 logical design units, scaled by `Math.min(width/2560, height/720)` | `quickshell/components/PortalViewport.qml:19-24` |
| Preview window | `FloatingWindow` 1280x360, minimum 960x270, opaque | `quickshell/shell.qml:208-217` |
| Production window | `PanelWindow` anchored to all four edges, `ExclusionMode.Ignore`, `WlrLayer.Overlay`, namespace `xeneon-edge-agent-portal`, `WlrKeyboardFocus.None`, `focusable: false`, `mask: null` | `quickshell/PortalPanel.qml:24-41` |

Because the design surface is fixed at 2560x720 and scaled by 0.4 on the
logical panel, all layout constants in `components/*.qml` are **design pixels**,
not logical touch pixels. `TODO.md:770-771` states this explicitly: "design
dimensions are scaled by 0.4, not literal logical touch sizes."

**Screen identity is fail-closed.** `shell.qml` builds `matchingScreens` from
`Quickshell.screens` using `screenMatches()`, then `targetScreens =
matchingScreens.length === 1 ? matchingScreens : []`, and the `Variants` model
is `[]` in preview mode. Consequences:

- zero matching screens or more than one match → **no window is created at all**;
- there is no primary-display fallback in production code;
- the only primary-display path is an explicit preview window
  (`previewMode`/`livePreviewMode`), which `README.md:102-105` documents
  explicitly.

`screenMatches()` requires `identityConfigured()` (output + serial + model all
non-empty from `XENEON_EDGE_OUTPUT`, `XENEON_EDGE_SERIAL`, `XENEON_EDGE_MODEL`),
a non-empty `screen.name`, positive width/height, an exact `screen.model`
match, an exact `screen.name` match, and — only when Qt exposes it —
`screen.serialNumber === targetSerial`. The code comments note that Qt's
Wayland `QScreen` backend does not always expose EDID serials, which is why the
Hyprland-side reconciler verifies the serial before the service is activated.

**Edge-gesture safe areas**: there is no safe-area/inset abstraction in the QML
tree. The panel declares no exclusive zone (`ExclusionMode.Ignore`) and the
sidebar's edge handle is the only left-edge interactive strip
(`railWidth = Math.min(64, width)`). Gestures that reach the compositor's own
edge-swipe areas are handled entirely outside QML, in
`config/hypr/xeneon_edge_agents.lua.in` and the reconciler. Whether a specific
compositor gesture inset is reserved on this panel is **UNKNOWN** from the QML
source.

**Resource-loss recovery**: `PortalPanel` toggles `visible` off/on with a
bounded exponential backoff (`120ms * 2^n`, capped at `maximumRecoveryDelayMs =
2000`) plus a 1500ms watchdog and a 5000ms stability timer; more than two
recovery attempts calls `Qt.exit(1)`.

---

## 3. Component map

Line counts are from the working tree at `0f74318`.

### 3.1 Entry points

| File | Lines | Role | Public properties | Signals / public functions | Depends on |
|---|---|---|---|---|---|
| `quickshell/shell.qml` | 246 | `ShellRoot`. Reads env config, builds `Settings`, instantiates store/theme/activity/bridge, creates one `PortalPanel` per matching screen and the optional preview `FloatingWindow`. | `fatalExitRequested`, `previewClosing`, `previewMode`, `livePreviewMode`, `previewMicroOpen`, `previewWindowMode`, `reducedMotion`, `previewAmbientTimeoutMs`, `targetSerial`, `targetModel`, `targetOutput`, `hostName`, `settingsPath`, `fixtureName`, `matchingScreens`, `targetScreens` | `identityConfigured()`, `screenMatches(screen)` | `PortalViewport`, `PortalStore`, `OmarchyTheme`, `MappedTheme`, `ActivityController`, `PortalBridge` |
| `quickshell/PortalPanel.qml` | 122 | `PanelWindow` for the layer surface. Owns resource-loss recovery and the `xeneonMonitor` `IpcHandler`. | `modelData`, `store`, `bridge`, `activity`, `preferences`, `theme`, `sourceTheme` (all required), `reducedMotion`, `hostName`, `recoveryVisible`, `recoveryAttempts`, `awaitingRecovery`, `maximumRecoveryDelayMs` | `scheduleRecovery()`; IPC `xeneonMonitor.openMonitor()` / `closeMonitor()` | `PortalViewport` |

`Settings` schema (category `display`, file `XENEON_EDGE_SETTINGS_PATH`,
default `$XDG_RUNTIME_DIR/xeneon-edge-portal-settings.ini`, `/dev/null` when
unset): `reduceMotion: bool`, `dimmed: bool`, `dashboardIndex: int`,
`readyColorRole`, `successColorRole`, `workingColorRole`, `needsHelpColorRole`,
`reviewReadyColorRole`, `errorColorRole`, `unknownColorRole`,
`recordingColorRole`, `processingColorRole` (all `string`).

Environment variables read by `shell.qml`: `XENEON_EDGE_PREVIEW`,
`XENEON_EDGE_LIVE_PREVIEW`, `XENEON_EDGE_PREVIEW_MICRO_OPEN`,
`XENEON_EDGE_REDUCED_MOTION`, `XENEON_EDGE_AMBIENT_TIMEOUT_MS` (clamped to
1000..300000, default 60000), `XENEON_EDGE_SERIAL`, `XENEON_EDGE_MODEL`,
`XENEON_EDGE_OUTPUT`, `XENEON_EDGE_HOSTNAME`, `XENEON_EDGE_SETTINGS_PATH`,
`XENEON_EDGE_FIXTURE` (must match `/^[a-z0-9_-]+\.ndjson$/`). Theme root
override: `XENEON_EDGE_THEME_ROOT`.

### 3.2 Composition layer (`components/`)

| File | Lines | Role | Public properties / signals | Depends on |
|---|---|---|---|---|
| `PortalViewport.qml` | 59 | Fixes the 2560x720 design surface and letterboxes/scale-maps it into the window. | required `store, bridge, activity, preferences, theme`; `sourceTheme`, `reducedMotion`, `previewMode`, `restoreVoiceFocus`, `previewMicroOpen`, `hostName`; alias `monitorSettingsOpen` | `DashboardView` |
| `DashboardView.qml` | 266 | Nine-preset composition, routing, persistence, sidebar + Monitor modal boundary. | required `store, bridge, activity, preferences, theme`; `sourceTheme`, `reducedMotion`, `previewMode`, `restoreVoiceFocus`, `previewMicroOpen`, `hostName`, `dashboardIndex`, `sidebarOpen`, `monitorSettingsOpen`; readonly `agentControlsWidth` (704), `presets`, `effectiveReducedMotion`; `validIndex()`, `selectDashboard(index)`, `openMonitor()`, `restoreMonitorFocus()` | `DashboardSidebar`, `PortalView`, `AmbientView`, `RiptideDashboard`, `AiUsageDock`, `MonitorSettings`, `OmarchyControls`, `PaletteSettingsPane` |
| `DashboardSidebar.qml` | 396 | Left-edge `FocusScope`: `DragHandler` on the handle, `TapHandler`, `Flickable` preset list with scroll indicator, bottom-right `MONITOR` button, full keyboard model. | required `theme, presets`; `currentIndex`, `open`, `reducedMotion`, `monitorBusy`, `dragging`; readonly `blocking`, `railWidth` (≤64), `drawerWidth` (≤560), `controlsEnabled`; signals `openRequested(bool)`, `selected(int)`, `monitorRequested()`, `interactionOccurred()` | `DashboardButton` |
| `PortalView.qml` | 1335 | The agent command center: header, manager/order controls, desktop app buttons, 3x2 agent card grid with pagination, degraded banner, voice hold-to-talk, Micro drawer, palette pane, dimmer, perimeter halo, AmbientView overlay. | required `store, bridge, activity, preferences, theme`; `sourceTheme`, `reducedMotion`, `previewMode`, `restoreVoiceFocus`, `previewMicroOpen`, `compactLayout`, `hostName`; `pageSize` = `compactLayout ? 10 : 14`; `currentPage`, `microDrawerOpen`, `paletteSettingsOpen`, `controlCenterInteractive`; `agentAt()`, `selectPage()`, `requestDesktop()`, `requestAgentOrder()`, `requestAgentBackend()`, `toggleMotionReduction()`, `toggleDisplayDim()`, `togglePaletteSettings()` | `PortalBackground`, `AmbientRing`, `AmbientView`, `AgentCard`, `DashboardButton`, `AiUsageDock`, `PaletteSettingsPane`, `MicroDrawer`, `DesktopAppButton`, `VoiceControl`, `DisplaySettingsControls` |
| `AmbientView.qml` | 500 | The animated/radar agent constellation: staged entry (1350ms), exit (1000ms), orbit, trails, center label. | `active`, `theme`, `reducedMotion`, `radarMode`, `agents`, `health`, `voice`, `connectionState`, `revealProgress`, `orbitPhase`, `motionEnergy`, `exitShield`; readonly `entryDurationMs`=1350, `exitDurationMs`=1000, `nodeLimit`=14; signal `wakeRequested()` | `AmbientAgentNode`, `OrbitTrail` |
| `AmbientRing.qml` | 428 | Perimeter status bloom: one GPU-blurred halo (`perimeterHaloBloom`) plus two opposing clockwise runners (`perimeterHaloRunners`) with bounded trailing motes. `Shape`/`MultiEffect`, not Canvas. | `agents`, `theme`, `voice`, `connectionState`, `reducedMotion`, `suppressRunners`, `phase`; readonly `mode` = `PortalPalette.perimeterMode(agents)`, `runnerCount`=2, `runnerSpan`=0.105, `coreSpan`=0.012 | — |
| `AmbientAgentNode.qml` | 134 | One upright agent capsule on an ellipse. | required `agent`; `theme`, `centerX/Y`, `radiusX/Y`, `angleDegrees`, `reveal`, `reducedMotion`, `dense`, `glowPulse` | — |
| `OrbitTrail.qml` | 66 | Tapered after-image: `segmentCount`=8 nested arcs sharing one head, `headGapDegrees`=5, `sweepDegrees`=44. | `centerX/Y`, `radiusX/Y`, `angleDegrees`, `reveal`, `accent`, `sweepDegrees` | — |
| `AgentCard.qml` | 530 | One agent card: state accent blooms (`cardAccentBloom`, `cardActivityBloom`), full-card focus target, safe action row. | `agent`, `theme`, `reducedMotion`, `snapshotSequence`, `actionsEnabled`, `managerName`; signals `focusRequested(string agentId)`, `approveRequested(agentId, capabilityId, sequence)`, `interruptRequested(...)`, `interacted()` | `HoldControl` |
| `HoldControl.qml` | 182 | Guarded press-and-hold button. `TapHandler.longPressThreshold: 0.8` (800 ms). Pins agent id, capability id, and snapshot sequence at press; any change cancels. | `label`, `theme`, `accent`, `reducedMotion`, `completed`, `armed`, `targetAgentId`, `targetCapabilityId`, `targetSequence`, `heldAgentId`, `heldCapabilityId`, `heldSequence`; signals `confirmed(agentId, capabilityId, sequence)`, `cancelled()`, `interacted()`, `accessibleHoldRequested()` | — |
| `VoiceControl.qml` | 319 | Push-to-talk dictation control. | `voice`, `theme`, `reducedMotion`, `actionsEnabled`, `pressOwned`; signals `startRequested()`, `stopRequested()`, `cancelRequested()`, `interacted()` | — |
| `MicroDrawer.qml` | 416 | Read-only Codex Micro device/status drawer. | `opened`, `theme`, `reducedMotion`, `interactive`, `micro`, `agents`, `voice`; signals `closeRequested()`, `interacted()` | — |
| `DesktopAppButton.qml` | 76 | Fixed ChatGPT/Claude Desktop focus-or-launch button. | `label`, `detail`, `theme`, `accent`, `pending`; signal `triggered()`; `activate()` | — |
| `PortalBackground.qml` | 109 | Canvas gradient (canvas → surface at 0.54 → alpha accent/magenta at 1) plus dim slate/cyan grid geometry. | `theme`, `reducedMotion`, `ambientMode` | — |
| `AiUsageDock.qml` | 602 | Claude / Codex / OpenCode capacity, resets, plan, aggregate token activity. | `usage`, `theme`, `agents`, `sessions`, `managerLabel`, `reducedMotion`, `expanded`, `clockTick` | — |
| `OmarchyControls.qml` | 702 | Desktop panel: health metrics with history, audio, media, DND/keep-awake/nightlight/recording, themes, power, storage, processes. Presets `overview`/`system`/`audio`/`desktop`. | required `store, bridge, activity, theme`; `previewMode`, `preset`, `pendingRequest`, `unknownOutcome`, `canReviewOutcome`, `feedback`, `histories`, `clockTick`; signals `monitorRequested()`, `presetRequested(int index)` | `DashboardCard`, `DashboardButton` |
| `MonitorSettings.qml` | 570 | Global DDC/CI hardware overlay: identity, capability discovery, one-command-in-flight queue, readback, keypad. | required `store, bridge, activity, theme`; `open`, `previewMode`, `reducedMotion`, `pendingRequest`, `queuedControls`, `drafts`, `keypadControl`, `canRefresh`, `live`; readonly `monitor`, `adjustmentInterval`=100, `pictureControls`, `rgbControls`; signal `closeRequested()` | `DashboardCard`, `DashboardButton`, `DashboardNumericPad`, `MonitorControl` |
| `MonitorControl.qml` | 75 | One capability-driven hardware value/slider card. | required `control`; `draft`, `writable`, `pending`, `queued`, `numberEnabled`, `keyboardScope`; signals `draftEdited(int)`, `valueReleased(int)`, `numberRequested(Item invoker)` | `DashboardCard`, `DashboardButton`, `MonitorSlider` |
| `MonitorSlider.qml` | 106 | Raw-unit touch slider with `Accessible.Slider` interface (arrow/Home/End). | required `theme`; `value`, `maximum`, `accessibleName`, `dragging`; signals `edited(int)`, `released(int)` | — |
| `RiptideDashboard.qml` | 1350 | Trading view against the Riptide gateway: accounts, positions, orders, ticket, confirmation and review-and-resume modals. | required `store, bridge, activity, theme`; `previewMode`, `selectedAccount`, `selectedSymbol`, `orderType`, `quantity`, `price`, `stopPrice`, `trailTicks`, `brackets`, `slTicks`, `tpTicks`, `pendingRequest`, `awaitingBroker`, `unknownOutcome`, `canReviewOutcome`, `confirmationOpen`, `activeModal` | `DashboardCard`, `DashboardButton`, `DashboardNumericPad` |
| `PaletteSettingsPane.qml` | 590 | Maps nine XENEON semantic meanings onto allowlisted Omarchy palette roles; reset to defaults. | `open`, `preferences`, `sourceTheme`, `theme`, `returnFocusItem`; signals `closeRequested()`, `interactionOccurred()` | `DashboardButton` |
| `DashboardCard.qml` | 12 | Shared surface primitive: radius 20, `theme.surface`, 1px `theme.border`, `clip: true`. | required `theme` | — |
| `DashboardButton.qml` | 99 | Shared pressable: 12px radius, focus border, Enter/Space, `Accessible` name/state/press action. | required `theme`; `label`, `detail`, `labelPixelSize` (17), `detailPixelSize` (12), `keyboardPressed`, `accent`, `selected`, `destructive`; signal `clicked` | — |
| `DashboardNumericPad.qml` | 207 | Integer/decimal touch keypad dialog with focus trap, Escape cancel, `Accessible.Dialog`. | required `theme`; `open`, `title`, `value`, `integerOnly`, `signed`, `error`, `returnFocusItem`, `fallbackFocusItem`; signals `accepted(string value)`, `cancelled` | `DashboardCard`, `DashboardButton` |
| `DisplaySettingButton.qml` | 107 | Small toggle for the shared header settings row. | `label`, `stateLabel`, `theme`, `accent`, `checked`; signal `toggled()` | — |
| `DisplaySettingsControls.qml` | 70 | Upper-right MOTION / SCREEN / PALETTE group. | `motionReduced`, `dimmed`, `motionForced`, `paletteOpen`, `paletteCustom`, `theme`; signals `motionToggleRequested()`, `dimToggleRequested()`, `paletteToggleRequested()` | `DisplaySettingButton` |
| `PortalPalette.js` | 145 | JS library: `effectiveAgentState`, `agentColor`, `ambientMode`, `perimeterMode`, `ambientColor`, `ambientLabel`, `snakeDuration`, `haloDuration`. | — | — |

### 3.3 State layer (`state/`)

| File | Lines | Role | Public properties / signals |
|---|---|---|---|
| `PortalStore.qml` | 890 | `QtObject` view model + full-replacement normalization. See [§4](#4-state-model). | see §4 |
| `PortalBridge.qml` | 204 | NDJSON transport. Owns the `Process`, `SplitParser` on stdout/stderr, restart timer, and one typed method per action. | required `store`; `enabled`, `previewMode`, `fixturePath`; readonly `ready`; signals `commandEmitted(var)`, `commandRejected(string)`; methods `openAgent`, `zoomAgent`, `approveAgent`, `interruptAgent`, `restoreFocus`, `openChatGptDesktop`, `openClaudeDesktop`, `startVoice`, `stopVoice`, `cancelVoice`, `setAgentOrder`, `setAgentBackend`, `omarchyAction`, `tradingAction` |
| `CommandBuilder.qml` | 116 | Command envelope construction and allowlist enforcement. | readonly `allowedActions`; `requestCounter`, `lastError`; `build(action, agentId, capabilityId, pinnedSequence, parameters)` |
| `OmarchyTheme.qml` | 134 | `Scope` that watches `$XDG_STATE_HOME/omarchy/current/theme.name` and re-reads `theme/colors.toml`. | `themeRoot`, `themeNamePath`, `colorsPath`, `themeName`, `paletteLoaded`, `paletteGeneration`, `colorsReadPath`; 13 raw Omarchy roles + 11 derived chrome roles |
| `MappedTheme.qml` | 67 | Presentation-only layer resolving nine XENEON semantic roles against the live palette. | required `sourceTheme`, `preferences`; readonly `selectableRoles`, raw roles, chrome roles, and `ready/success/working/needsHelp/reviewReady/error/unknown/recording/processing` |
| `ThemePalette.js` | 241 | JS library: TOML-lite parse, allowlist, contrast math. | `fallback`, `selectableRoles`, `parse`, `roleColor`, `ensureContrast`, `contrastRatio`, `mixColors` |
| `ActivityController.qml` | 49 | Inactivity/ambient state machine, 500ms ticker. | `automatic`, `inactivityMs` (60000 production), `eventWakeMs` (15000), `lastUserActivityMs`, `eventWakeUntilMs`, `ambientMode`; `reset()`, `noteUserActivity()`, `noteEvent()`, `evaluate()` |

### 3.4 Fixtures and tests

`quickshell/fixtures/` holds 12 deterministic NDJSON snapshots used by preview
and by the Python fixture tests: `action_result.ndjson`, `agents.ndjson`,
`disconnected.ndjson`, `empty.ndjson`, `health.ndjson`, `home.ndjson`,
`snapshot.ndjson`, `t3code.ndjson`, `voice.ndjson`, `voice_error.ndjson`,
`voice_idle.ndjson`, `voice_processing.ndjson`.

`quickshell/tests/` holds 15 Qt TestCase QML files, 2 Python test modules, and
`mocks/Quickshell/Io/{Process.qml,SplitParser.qml,qmldir}` — an inert I/O
double used instead of the real bridge so Qt tests start no daemon.

Note: `quickshell/components/DashboardSwitcher.qml` **no longer exists in the
source tree**; commit `0f74318` deleted it (106 lines) when the sidebar
replaced it. `TODO.md:773` records that a stale copy still exists in the
*installed* user Quickshell config, which is a deployment concern, not a source
concern.

---

## 4. State model

### 4.1 `PortalStore.qml`

`PortalStore` is a `QtObject` holding a normalized view model, never the raw
wire envelope ("The UI consumes a small view model instead of holding the wire
envelope", comment at `PortalStore.qml:17`).

Properties:

| Property | Type | Default | Meaning |
|---|---|---|---|
| `schemaVersion` | int | `1` | only version accepted by `ingestEnvelope` |
| `sequence` / `daemonEpoch` / `generatedAtMs` | double / string / double | `-1` / `""` / `0` | snapshot ordering triple |
| `hasSnapshot`, `freshSnapshotRequired` | bool | `false` / `true` | freshness gate for every action |
| `transportState`, `transportDetail`, `protocolError` | string | `"starting"` / `""` / `""` | transport-level state |
| `connection` | var | `{state:"reconnecting", detail:"Waiting for xeneon-agentd"}` | `connected` \| `degraded` \| `reconnecting` \| `offline` |
| `sessions` | var[] | `[]` | `{name, state, version, protocol, last_sync_ms, message}`; state ∈ `connected\|stale\|incompatible\|offline` |
| `agents` | var[] | `[]` | normalized + sorted agent cards (below) |
| `agentOrder` | var | `{available:false, mode:"grouped"}` | `grouped` \| `priority` |
| `backend` | var | `{mode:"herdr", switchable:false}` | `herdr` \| `t3code` |
| `health` | var | `{}` | metrics + `status` (`healthy` \| `partial`) |
| `omarchy` | var | `{}` | audio/media/toggles/theme/storage/processes/edge_brightness/monitor |
| `trading` | var | `{connection:"disabled", execution_enabled:false, accounts:[], positions:[], orders:[], quotes:[], fills:[]}` | normalized gateway projection |
| `voice` | var | `{available:false, state:"unavailable", owned:false}` | `unavailable\|idle\|recording\|processing\|error` |
| `usage` | var | `{providers:[]}` | allowlisted `claude`/`codex`/`opencode` |
| `micro` | var | `{connected:false, firmware:"", battery:-1, charging:false, layer:-1, profile:-1, last_updated_ms:0}` | read-only device view |
| `lastActionResult`, `lastNotice`, `activitySignature` | var | `null`/`null`/`""` | last result/notice and semantic signature |
| `pendingRequestActions` (map), `pendingRequestOrder` (array) | var | `{}` / `[]` | in-flight request tracking, bounded at 128 entries |

Signals: `snapshotAccepted(var snapshot)`, `semanticActivityChanged(string signature)`,
`actionResultReceived(var result)`, `noticeReceived(var notice)`,
`protocolRejected(string reason)`.

Normalized agent shape (`normalizeAgent`, 890-line store, `normalizeAgent` at
line 189):

```
{ id, display_name, agent, status, workspace, repository, worktree,
  session, focused, launch_pending, review_ready, observed_for_seconds,
  source_order, state_change_seq,
  actions: { open: bool, zoom: bool, approve: capability|null,
             interrupt: capability|null } }
```

- `status` is coerced to one of `blocked|done|working|idle|unknown`
  (`allowedAgentStates`); anything else becomes `unknown`.
- `display_name` is capped at 56 chars, `workspace`/`repository` 96, `worktree`
  128, `session` 64.
- `review_ready` defaults to `status === "done"` when the field is absent, for
  legacy fixture compatibility.
- capabilities (`normalizeCapability`) require a non-empty `capability_id`, a
  `kind` equal to the expected action, `expires_at_ms >= 0`, and
  `expected_revision >= 0`; otherwise the capability is dropped (`null`).
- sorting: `grouped` → `source_order` then `id`; `priority` →
  `statePriority(state, review_ready)` then `state_change_seq` descending, then
  `source_order`, then `id`. `statePriority`: blocked 0, review-ready done/idle
  1, working 2, plain done/idle 3, unknown 4. When `agentOrder.available` is
  false the store sorts with `priority` anyway
  (`nextAgentOrder.available ? nextAgentOrder.mode : "priority"`).

Other normalization worth copying: `normalizeHealth` uses
`{available: bool, value: number|null, unit}` and never encodes "unavailable"
as zero; `normalizeUsage` drops any provider id outside
`["claude","codex","opencode"]` and clamps utilization to 0..1; `normalizeTrading`
requires `connection === "connected" && broker_connected === true` before
`execution_enabled` can be true, and keeps account/order/fill ids as opaque
strings via `opaqueId()` (128 chars) so handles larger than
`Number.MAX_SAFE_INTEGER` survive; `normalizeMonitor` allowlists exactly
`brightness, backlight, contrast, red_gain, green_gain, blue_gain, sharpness,
color_preset`, bounds `controls` to 16 rows and `choices` to 32, and validates
`display` geometry before exposing it.

### 4.2 Envelope handling

`ingestEnvelope` rejects non-objects, any `schema_version !== 1`, and any
`type` other than `snapshot`, `action_result`, `notice`.

`ingestSnapshot` requires `Array.isArray(agents)` and
`Array.isArray(sessions)`, a non-empty `daemon_epoch`, and `sequence >= 0`.
Ordering rules:

- different epoch → treated as a fresh snapshot (daemon restart);
- same epoch and `sequence < current` → dropped silently (`return false`);
- same epoch and `sequence === current` and older `generated_at_ms` → dropped;
- equal sequence, newer `generated_at_ms` → *partial* refresh: health, omarchy,
  trading, voice, usage, micro are replaced but agents/sessions/backend are
  kept (this is how host-health refreshes do not invalidate a guarded 800ms
  hold — `docs/architecture.md:130-132`);
- equal sequence, equal timestamp, `freshSnapshotRequired === false` → dropped;
- otherwise full replacement, recomputing `activitySignature`.

`semanticSignature(connection, agents, voice)` = `JSON.stringify` of
`[backend.mode, connection.state, voice.state, voice.owned, ...per agent
(id, status, review_ready)]`. `shell.qml` wires `semanticActivityChanged`,
`actionResultReceived`, and `noticeReceived` into
`ActivityController.noteEvent()`.

`action_result` normalization (`ingestActionResult`):

```
{ request_id, action, ok: bool, code, message(<=120 chars) }
```

`action` is recovered from `pendingRequestActions` via `takeTrackedAction`, so
the UI can render a result without trusting the wire for the action name.
Requires non-empty `request_id`, non-empty `code`, and a boolean `ok`.

`notice` normalization (`ingestNotice`):

```
{ level, code, message(<=120 chars) }
```

`surfaceState()` returns one of `disconnected | loading | disconnected |
degraded | empty | ready` for the header banner.

### 4.3 Transport: fixture vs live

`PortalBridge` runs exactly one `Process`:

```
previewMode == true  -> ["/usr/bin/tail", "-n", "+1", "-f", fixturePath]
previewMode == false -> ["xeneon-agentctl", "qml-bridge"]
```

- `stdinEnabled: !previewMode` — in preview the process has no stdin and no
  command is written anywhere.
- stdout `SplitParser.onRead` → `handleLine` → `JSON.parse` →
  `store.ingestEnvelope`. A parse failure calls `store.reject("Invalid NDJSON
  envelope")`.
- stderr `SplitParser.onRead` → `store.setTransportState("degraded", "Bridge
  reported a warning")`; the next accepted envelope restores the transport
  state.
- `onStarted` → `store.awaitFreshSnapshot("fixture"|"streaming", ...)`, which
  sets `freshSnapshotRequired = true`; every action is refused until a fresh
  snapshot arrives.
- `onExited` → `awaitFreshSnapshot("disconnected", ...)` plus a 1500ms restart
  timer.
- `ready` = `!store.freshSnapshotRequired && (previewMode || bridgeProcess.running)`.

In preview mode `sendBuilt` still builds, tracks, and emits the command
(`commandEmitted`) so tests can observe it, but never writes to a process.
`omarchyAction` and `tradingAction` reject outright in preview
("Desktop controls are disabled in preview", "Trading is disabled in preview");
`tradingAction` additionally requires `store.trading.execution_enabled === true`
and `connection === "connected"`.

### 4.4 Command envelopes and action authority

`CommandBuilder.allowedActions` (16 entries): `open`, `zoom`, `approve`,
`interrupt`, `restore_focus`, `chatgpt_desktop`, `claude_desktop`, `voice_start`,
`voice_stop`, `voice_cancel`, `order_grouped`, `order_priority`,
`backend_herdr`, `backend_t3code`, `omarchy`, `trading`.

Envelope:

```json
{ "schema_version": 1, "type": "command",
  "request_id": "xep-<Date.now()>-<counter>",
  "sequence": <int, must be >= 0>,
  "action": "<allowlisted>" }
```

plus optional `agent_id`, `capability_id`, `parameters`.

Structural rules enforced in `build()`:

- sequence must be finite and `>= 0` → otherwise "Command requires a valid
  snapshot sequence";
- the twelve "system" actions (`restore_focus`, the two desktop apps, three
  voice actions, two order actions, two backend actions, `omarchy`,
  `trading`) may **not** carry `agent_id` or `capability_id`;
- the other four require a non-empty `agent_id`;
- `approve`/`interrupt` require a non-empty `capability_id`;
- `open`/`zoom`/system actions must **not** carry a `capability_id`;
- `omarchy`/`trading` require an object `parameters`; all other actions must
  not carry `parameters`.

**Action authority rules (must survive reuse):**

1. QML cannot choose an executable, desktop entry, class, title, argument,
   binary, socket, path, or shell string. Desktop actions are two fixed
   identities only.
2. Approve/interrupt are capability-gated and single-use; the capability ID
   must be present in the *current* snapshot, is pinned at press time, and the
   hold is cancelled if the agent, capability, or sequence changes
   (`HoldControl.invalidateChangedTarget`).
3. Host commands have a 10s ceiling and are never retried; a failed or
   timed-out start may issue at most one distinct cancel cleanup attempt.
4. Commands carry the snapshot `sequence` as a stale gate (except voice, where
   ownership plus live Voxtype state is authoritative — `docs/protocol.md:194`).
5. Desktop actions that are dispatched but never answered lock the shared
   desktop control and require an explicit **REVIEWED · RESUME**; the action is
   never replayed (`docs/dashboards.md:57-64`).
6. A trading `pending` acknowledgement is not fulfillment: local execution stays
   locked until a strictly newer broker observation, and the request is never
   resent (`docs/dashboards.md:66-69`).
7. Monitor writes: at most one command in flight, one replaceable target per
   continuous control, sends spaced `>= 100ms` (`adjustmentInterval`), and a
   write stays pending until a successful result plus a newer matching
   readback. Errors/disconnects/identity changes discard unissued targets and
   require an explicit hardware refresh (`docs/dashboards.md:106-119`).

---

## 5. Design system

### 5.1 Color

Source of truth is Omarchy's live palette, read by `OmarchyTheme.qml` from
`$XDG_STATE_HOME/omarchy/current/theme.name` (stable beacon) and then
`$XDG_STATE_HOME/omarchy/current/theme/colors.toml`. Omarchy replaces the theme
directory atomically, so the QML watches `theme.name` and re-opens `colors.toml`
after a 40ms debounce; `colorsReadPath` is cleared before the debounce so an
in-flight `FileView` read cannot race the swap. `omarchy theme set` therefore
updates the portal without a restart.

`ThemePalette.js` parses only `key = "#rrggbb"` lines (`/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/`),
validates with `/^#[0-9A-Fa-f]{6}$/`, and maps a fixed key allowlist with
aliases: `background|bg`, `foreground|fg`, `muted|dark_foreground|dark_fg`,
`accent|blue`, `dark_background|dark_bg|darker_background|darker_bg`,
`lighter_background|lighter_bg`, plus `red/green/yellow/blue/magenta/cyan/orange`.
Everything absent or invalid falls back to `rawFallback` (fail-soft).

Semantic derivation (`semantic()`):

- light themes are translated to a dark adaptive command surface:
  `canvas = mix(foreground, #000000, 0.62)` when `mode === "light"`, else
  `background`; `surface = mix(canvas, accent, 0.06)` (light) or
  `mix(background, lighterBackground, 0.34)`; `surfaceRaised` uses weights
  0.12 / 0.68; `surfacePressed = mix(surfaceRaised, accent, 0.18)`.
- `textPrimary` is contrast-enforced to **7:1** against `surface`;
  `textMuted` to **4.5:1**; `textSecondary = ensureContrast(mix(textPrimary,
  textMuted, 0.34), surface, 4.5)`. `ensureContrast` mixes toward black or
  white (whichever has more contrast on the background) using a 12-iteration
  binary search, so semantic hues survive but legibility is guaranteed.
- `border = mix(muted, accent, 0.32)`, `borderStrong = mix(muted, accent, 0.68)`,
  `accentSecondary = cyan`.

The nine XENEON semantic roles are stored only as allowlisted Omarchy **role
names** in `Settings` (`ThemePalette.selectableRoles` = `accent, red, orange,
yellow, green, cyan, blue, magenta, muted`) and resolved at render time by
`MappedTheme`:

| Meaning | Preference key | Default role |
|---|---|---|
| Ready | `readyColorRole` | `muted` |
| Success | `successColorRole` | `green` |
| Working | `workingColorRole` | `blue` |
| Needs Help | `needsHelpColorRole` | `yellow` |
| Review Ready | `reviewReadyColorRole` | `green` |
| Error | `errorColorRole` | `red` |
| Unknown | `unknownColorRole` | `magenta` |
| Recording | `recordingColorRole` | `green` |
| Processing | `processingColorRole` | `cyan` |

An invalid or missing selection fails closed to the default role
(`selectableRole`). The palette editor cannot store arbitrary colors and cannot
change background/surface/text roles.

Agent color resolution (`components/PortalPalette.js` `effectiveAgentState`):
`blocked` and `working` pass through; `review_ready === true` → `review`;
`idle`/`done` → `idle`; else `unknown`. `agentColor` maps
working→`theme.working`, blocked→`theme.needsHelp`, review→`theme.reviewReady`,
idle→`theme.ready`, default→`theme.unknown`.

### 5.2 Typography

Uniform across the product: `font.family: "monospace"`, uppercase labels,
positive `letterSpacing` (0.5–1.4 for chrome), and `textFormat: Text.PlainText`
on essentially every label (a Python contract test, `test_all_portal_text_is_explicitly_plain`,
asserts this). Sizes in design pixels: sidebar drawer title 26, preset row 30,
sub-labels 18; page heading 32, body 22; card title at the existing compact
size with full card width across up to two lines; button label 17 by default,
30 for drawer rows.

### 5.3 Visual language

`PortalBackground.qml` is the whole surface: a vertical three-stop gradient
(`canvas` → `surface` at 0.54 → `alpha(magenta, 0.16)` in ambient mode or
`alpha(accent, 0.12)` otherwise) plus dim slate/cyan structural grid geometry.
The stated contract (`docs/concept-motion.md:29-41`) is "near-black navy
canvas with dim slate/cyan structural geometry", "narrow uppercase monospaced
display type with generous tracking", "bright ice/cyan system copy and
low-contrast blue-gray metadata".

Glow is achieved with `MultiEffect`/`Shape`, not Canvas (a Canvas prototype was
rejected for paint cost — `TODO.md:237-240`). Named glow objects:
`cardAccentBloom`, `cardActivityBloom` (AgentCard), `perimeterHaloBloom`,
`perimeterHaloRunners` (AmbientRing). `AmbientRing` has one shadowed halo plus
two opposing clockwise runners with six bounded trailing motes each, visible
only when `mode !== "off"`.

The dimmer (`displayDimmer`) is a software veil: black at `opacity 0.88` when
`preferences.dimmed`, `220ms` `OutCubic` otherwise. It is explicitly **not** a
hardware backlight change (`docs/dashboards.md:103-104`,
`docs/concept-motion.md:73-75`).

### 5.4 Motion and reduced motion

Ambient timings (`AmbientView.qml`): `entryDurationMs` 1350, `exitDurationMs`
1000, `nodeLimit` 14. `docs/concept-motion.md` and `design-qa.md` describe the
staged opaque crossfade, center-out ring expansion, delayed node reveal, a
2.8s quiet hold, and a gradual ramp into independent clockwise orbits. Sidebar
reveal is a 220ms `OutCubic` `Behavior on requestedReveal`.

Reduced motion is a two-input OR: the environment override
(`XENEON_EDGE_REDUCED_MOTION=1`, external/system) and the reversible user
preference (`preferences.reduceMotion`). `DashboardView.effectiveReducedMotion =
reducedMotion || preferences.reduceMotion === true`. When set:

- `PortalView.toggleMotionReduction()` refuses to toggle (the control is
  disabled but remains visible); only an externally forced value disables it
  (`docs/dashboards.md:54-55`);
- the sidebar drawer snaps (`revealAnimation.complete()` in
  `onReducedMotionChanged`, and animation `duration: 0`);
- `AmbientView` renders the final static constellation at fixed, evenly spaced
  positions, removes trails and the two perimeter runners, and disables
  continuous orbit (`docs/concept-motion.md:56-58`);
- `AmbientRing.suppressRunners` is forced true from `PortalView`;
- the ambient-to-control exit uses a frozen boost phase, a short forward coast,
  and a linear exit driver while preserving staged reveal windows;
- controls hidden mid-transition are removed from the accessibility tree and
  guarded with `enabled` checks (`controlCenterInteractive`), so an assistive
  press cannot fire a hidden action.

Idle policy: production 60s (`ActivityController.inactivityMs`); preview uses
`XENEON_EDGE_AMBIENT_TIMEOUT_MS` clamped to 1..300s. A daemon event arriving
during ambient holds the surface awake for a further `eventWakeMs` = 15000.

---

## 6. Safety boundaries any reuse must preserve

These are the repository's own rules (`AGENTS.md:10-26`,
`docs/architecture.md`, `docs/protocol.md`, `docs/commissioning.md`,
`README.md:257-261`). Any reuse of this template must carry them forward
unchanged.

1. **Never send arbitrary terminal text or keys from QML.** There is no
   method, key, text, shell-command, prompt, close, or server-control
   passthrough in the protocol.
2. **Never retry a non-idempotent agent action.** Commands have no automatic
   transport retry; inputs are never queued or replayed.
3. **Never show terminal or prompt contents on the portal.** Card names come
   from Herdr tab labels / T3 Code thread titles, never from prompt or terminal
   text; `docs/architecture.md:122-124`.
4. **T3 Code is a read-only projection boundary.** Never write T3 Code state;
   never read messages, activities, checkpoints, secrets, or provider
   payloads. Only bounded thread, session, turn, and project projections are
   inputs. Rows bounded at 512 candidates / 64 cards; a schema query failure
   reports the session `incompatible` rather than guessing.
5. **Never fall back to the primary display** when the XENEON identity is
   absent or ambiguous. Zero or multiple matching screens create no surface.
6. **Never apply a global touchscreen mapping** — this host also has an
   internal touchscreen; only the commissioned device is mapped.
7. **Never edit packaged Omarchy files under `/usr/share/omarchy`.** Installed
   files stay in user-owned XDG locations and installation must be reversible;
   Hyprland's `monitors.lua` ownership is untouched.
8. **No network listener in the daemon.** The transport is a mode-`0600` Unix
   socket inside a mode-`0700` systemd runtime directory; the daemon has no
   public port.
9. **Credentials and secrets never enter QML.** Gateway tokens stay in a mode
   `0600` `credentials_file` containing only `DATA_SERVER_URL` and
   `DATA_SERVER_TOKEN`; snapshots and notices never carry tokens.
10. **Absent is not zero.** Unavailable health/usage/monitor readings render as
    explicit unavailable states, never as a false zero or a guessed value.
11. **Preserve unrelated user changes** in the repository and in `~/.config`.
    The installer refuses or preserves modified files.

---

## 7. Verification

### 7.1 Commands

From the repository root (`just` targets in `justfile`):

| Gate | Command | Notes |
|---|---|---|
| Format | `cargo fmt --all -- --check` | `just fmt` |
| Rust tests | `cargo test --workspace` | `just rust` |
| Rust lint | `cargo clippy --workspace --all-targets -- -D warnings` | |
| Shell lint | `shellcheck scripts/*.sh scripts/preview tests/*.sh tests/run-integration-tests tests/run-qml-tests` | CI also lints `config/bin/*` |
| QML lint + contracts + Qt tests | `tests/run-qml-tests` | runs `qmllint` over `find quickshell -name '*.qml'`, then `python -m unittest discover -s quickshell/tests -p 'test_*.py' -v`, then `QT_QPA_PLATFORM=offscreen qmltestrunner -input quickshell/tests -import quickshell -import quickshell/state -import quickshell/tests/mocks -v1` |
| Integration | `tests/run-integration-tests` | runs `tests/startup_lifecycle_test.py`, `cargo build --workspace`, then `tests/install_integration.sh` with `XENEON_AGENTD_BIN` |
| Everything | `just check` = `fmt rust shell qml integration` + `git diff --check` | `mise exec -- just check` |
| Preview | `scripts/preview [fixture.ndjson] [--live] [--ambient-after N]` | `mise run preview` |

`tests/run-qml-tests` requires `qmllint` and `qmltestrunner` on `PATH` or at
`/usr/lib/qt6/bin/` (overridable with `QMLLINT` / `QMLTESTRUNNER`).
`tests/run-integration-tests` requires `luac` and `lua`.

CI (`.github/workflows/ci.yml`) runs three jobs: `rust` (fmt/test/clippy/
`git diff --check`), `integration-contracts` (shellcheck, JSON validation,
`python3 -m unittest discover -s quickshell/tests -p 'test_*.py' -v`,
`tests/run-integration-tests`), and `qml` (archlinux container, `pacman -S
quickshell qt6-declarative`, then `tests/run-qml-tests`).

Python contract tests (22 methods in `quickshell/tests/test_contract.py`) are
source-text assertions — they grep the QML for required substrings. Notable
ones for reuse: `test_production_output_matching_is_fail_closed`,
`test_panel_has_exact_layer_surface_contract`,
`test_one_bridge_process_and_explicit_preview_window`,
`test_commands_are_allowlisted_ndjson_without_raw_input`,
`test_hold_controls_are_800ms_and_drag_cancellable`,
`test_all_portal_text_is_explicitly_plain`,
`test_resource_loss_exits_after_bounded_recovery_budget`,
`test_omarchy_theme_reload_is_runtime_owned_and_chrome_is_bound`.
6 fixture tests live in `quickshell/tests/test_fixtures.py`.

Qt test files (15): `tst_activity`, `tst_ai_usage`, `tst_ambient`,
`tst_command`, `tst_dashboard_store_safety`, `tst_dashboards`,
`tst_display_settings`, `tst_interaction`, `tst_monitor_settings`,
`tst_omarchy_health`, `tst_palette`, `tst_portal_layout`, `tst_store`,
`tst_theme`, `tst_theme_mapping`. They declare 136 `function test_*` methods
(counted from the source) and use `quickshell/tests/mocks/Quickshell/Io/` so no
daemon or process is started.

### 7.2 Status at `0f74318`, per repository records

From `TODO.md:709-762` (the "Nine-preset slide-out sidebar" section):

- PASS: 19 dashboard Qt checks plus three desktop-metric checks (focused run).
- PASS: the final isolated runner with `QT_QPA_PLATFORM=offscreen` — 28 Python
  contract/fixture tests and 163 Qt checks.
- `qmllint` completed **with existing unqualified-access warnings** in
  unchanged sections/components; the new sidebar and routing component have no
  warnings. (So `qmllint` is not warning-clean repository-wide.)
- PASS: Rust formatting, 165 workspace tests, Clippy with warnings denied,
  ShellCheck, and the isolated integration runner with 13 startup and 31
  installer/lifecycle scenarios including generated Lua syntax and lifecycle
  checks.
- Visual: a real Quickshell source tour rendered all nine pages at 1280x360
  logical / 2560x720 captured pixels, with screenshots visually inspected.
- Explicitly NOT physical validation: "Runtime/fixture interaction is separate
  from physical touchscreen validation."

Earlier sections of `TODO.md` record the physical EDGE gate as passed for the
panel that predates this commit (`:251-273`: exact EDID/model/serial/USB
identity verified, native 2560x720 at 2x scale enabled, touch captured, Ambient
woken, one `xeneon-edge-agent-portal` layer surface on `DP-2` only) while the
hotplug lifecycle **physical** gate remains open (`:195-198`).

Counts I could not reconcile exactly: `TODO.md` says "163 Qt checks" and "165
workspace tests" while the source declares 136 Qt test functions and 112
`#[test]` attributes under `crates/`. The Qt runner count includes data-driven
rows; the Rust gap is **UNKNOWN** (possibly doctests or macro-generated
tests). The 28 Python figure matches the source exactly (22 + 6).

I did not execute any of these commands for this document; the status above is
quoted from repository records, not observed.

---

## 8. Extraction

### 8.1 Pin

```bash
git -C /home/blr2/Work/Github/blr/omarchy/xeneon-edge-agents rev-parse HEAD
# 0f74318c38f37f7df2ad5001ec969ce32bf286f1  (branch local/omarchy)
```

### 8.2 Get the dashboard into a worktree

```bash
# Read-only inspection worktree at the pinned commit
git -C <repo> worktree add --detach /tmp/agent-dashboard-template 0f74318

# Or export only the dashboard surface
mkdir -p /tmp/agent-dashboard-template && git -C <repo> archive 0f74318 \
  quickshell schema docs config scripts README.md AGENTS.md \
  | tar -x -C /tmp/agent-dashboard-template

# Or a portable patch against a matching base
git -C <repo> format-patch -1 0f74318 -o /tmp/patches
git -C <repo> diff 8710778..0f74318 -- quickshell docs README.md > /tmp/dashboard.patch
```

### 8.3 Files that constitute the dashboard

Presentation (the reusable part):

```
quickshell/shell.qml
quickshell/PortalPanel.qml
quickshell/components/            (26 .qml + PortalPalette.js)
quickshell/state/                 (6 .qml + ThemePalette.js)
quickshell/fixtures/              (12 .ndjson)
quickshell/tests/                 (15 .qml + 2 .py + mocks/)
```

Backing contract and host integration (needed for a live portal, not for a
static template):

```
schema/portal-v1.schema.json
config/applications/xeneon-edge-agents.desktop.in
config/systemd/user/xeneon-edge-{agentd,portal,reconcile}.service.in
config/systemd/user/xeneon-edge-input.path.in
config/hypr/xeneon_edge_agents.lua.in
config/xeneon-edge-agents/config.toml.example
config/xeneon-edge-agents/commissioning.toml.example
config/bin/xeneon-edge-{launch,session,reconcile}
scripts/{install.sh,uninstall.sh,check.sh,detect-hardware.sh,lib.sh,preview}
crates/xeneon-agent-core, crates/xeneon-agentd, crates/xeneon-agentctl
tests/{run-qml-tests,run-integration-tests,install_integration.sh,
       startup_lifecycle_test.py,hypr_lifecycle_test.lua}
docs/{architecture.md,protocol.md,dashboards.md,concept-motion.md,
      commissioning.md,agent-workflow.md}
design-qa.md, justfile, mise.toml, .github/workflows/ci.yml
```

If the destination is a different product, `crates/`, `config/`, and `scripts/`
are the parts most likely to be replaced entirely; `quickshell/` plus
`docs/protocol.md` is the part that transfers most directly.

### 8.4 What must be re-decided in a new host

| Decision | Current value | Why it cannot be inherited |
|---|---|---|
| Transport binary | `xeneon-agentctl qml-bridge`, NDJSON over stdin/stdout | A new host defines its own bridge or drops the daemon entirely |
| Protocol schema | `schema_version: 1`, `snapshot`/`action_result`/`notice`/`command` | Versioning and field set are product-specific |
| Environment variable namespace | `XENEON_EDGE_*` (preview, fixture, serial/model/output, theme root, motion, ambient timeout, settings path) | Names are hardcoded in `shell.qml`, `OmarchyTheme.qml`, and `scripts/preview` |
| Settings file | `$XDG_RUNTIME_DIR/xeneon-edge-portal-settings.ini`, category `display` | A second product must not share this file |
| Layer-shell namespace / IPC target | `xeneon-edge-agent-portal`, `xeneonMonitor` | Identifies this surface to the compositor and to `quickshell ipc` |
| Screen identity inputs | `XENEON_EDGE_OUTPUT` / `_SERIAL` / `_MODEL`, plus connector/EDID/USB commissioning | Hardware-specific by definition |
| Theme root | `$XDG_STATE_HOME/omarchy/current` (Omarchy-specific `theme.name` + `theme/colors.toml` layout) | A non-Omarchy host needs its own palette reader |
| Design surface | 2560x720 design units, 1280x360 preview | New panel geometry means re-tuning every design-pixel constant |
| Preset set | nine labels, `agentControlsWidth` 704 | Product-specific routing |
| Agent manager concept | `herdr` / `t3code` allowlist in `CommandBuilder`, `PortalStore`, `PortalView` | A different product may have a different or no manager |
| Installation path | `scripts/install.sh`, XDG user units, Hyprland require insertion | Deployment policy is host-owned |
| Contract tests | `quickshell/tests/test_contract.py` asserts on literal QML source text | Every rename/reshape breaks them; they must be rewritten, not reused |

---

## 9. Known constraints and gaps

- **Touch-target density is an open finding, not a closed gate.**
  `TODO.md:778-780` lists material findings to resolve before deployment:
  reversible motion preference, Monitor keyboard/modal exit, compact agent
  identification, sidebar touch/text density, pending trading acknowledgement
  ordering, and lost desktop results. Some were addressed by `0f74318` (the
  sidebar ten-card readability fix, `TODO.md:751-757`), but the list is
  recorded as unresolved at `0f74318`.
- **`qmllint` is not clean.** Unqualified-access warnings persist in unchanged
  sections (`TODO.md:734-735`). A reuse that treats `qmllint` as a gate will
  have to fix or suppress them.
- **Stale installed artifact.** `DashboardSwitcher.qml` still exists in the
  installed user Quickshell config even though it was deleted from source
  (`TODO.md:772-773`). Source-tree templates do not inherit that fix; the
  installed config must be reconciled separately.
- **Preview and production differ.** Preview uses the primary display, a
  fixture, and blocks desktop/trading controls. A preview is explicitly not
  evidence of live execution (`docs/dashboards.md:262-266`). Installed QML is
  copied from the source tree, so source edits require reinstall/relaunch.
- **Broker trading capability is deliberately limited.** Close, Reverse, and
  Flatten stay disabled in the current gateway implementation until complete
  broker order/position enumeration is proven (`docs/dashboards.md:192-194`),
  and the legacy-route compatibility view is permanently read-only.
- **T3 Code mode has fewer actions.** No zoom, approve, or interrupt; card
  activation only focuses the exact `t3code` window; ordering is a daemon-owned
  preference (`docs/architecture.md:100-106`).
- **Monitor backlight stays disabled** on the tested EDGE unit because it
  exposes no independent DDC backlight control; the row remains visible and
  disabled. Software dimming is a veil, not a backlight.
- **Physical gates remain open** for hotplug lifecycle, DPMS, suspend/resume,
  focus/privacy, and coordinate validation (`TODO.md:195-198`,
  `AGENTS.md:57-58`).
- **One-command-in-flight** in the monitor overlay is a deliberate throughput
  limit; sliders cannot pipeline commands.
- **Ambient idle is 60 seconds** in production; the 2.25s concept transition is
  presentation timing only and must not become the inactivity policy
  (`docs/concept-motion.md:69-72`).
- **`PortalView.qml` (1335 lines) and `RiptideDashboard.qml` (1350 lines) are
  the two large files.** Neither is split by a module boundary; splitting them
  during reuse would break the source-text contract tests and most object-name
  anchors.
- **`design-qa.md` evidence is ephemeral by its own statement** — the captured
  frames live outside the repository and must be regenerated from an
  authorized source before a later release.
