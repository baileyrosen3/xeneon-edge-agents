# Home dashboard parity plan

Scope: every element the live Omarchy menu bar renders that the new home
dashboard does not ship yet. The home dashboard currently ships clock/date,
workspaces, DND / stay-awake / nightlight pills, app launcher cluster, MPRIS
now-playing, CPU/GPU/memory stats, volume, tray, network, and power.

The authoritative source for "how it works today" is the file listed in each
entry: those files are the current implementation, not a design sketch. Nothing
here may be reimplemented by inventing a new collector; the point is to reuse or
lift the exact source and command.

Active bar host for reference:

- `/usr/share/omarchy/shell/plugins/bar/Bar.qml`
- `/usr/share/omarchy/shell/Commons/Color.qml`, `/usr/share/omarchy/shell/Commons/Style.qml`
- `/usr/share/omarchy/shell/Ui/BarWidget.qml`, `Ui/WidgetButton.qml`, `Ui/Panel.qml`
- Layout: `~/.config/omarchy/shell.json`

## Action classification used below

| Class | Meaning |
|---|---|
| SAFE | In-process Quickshell API (`Quickshell.Services.*`, `Quickshell.Hyprland`) or a fixed, bounded typed command with a literal argv. No shell text, no interpolation of user input into a command string. |
| NEEDS-CAVEAT | Bounded, but must be added as a typed allowlisted dispatch entry (daemon or `CommandBuilder`) rather than a `bar.run("<string>")` call, or requires an explicit confirm / one-shot non-idempotent guard, or mutates persisted config (`shell.json` / plugin state). |
| NOT-PORTABLE | Requires a terminal, a floating terminal launcher, an interactive TUI, or the screen-share / screen-recording pipeline. Not a home-surface element. |

`bar.run("...")` in the current bar passes a whole shell string to
`omarchy-launch-floating-terminal-with-presentation` or a shell. **Any such
action that this plan keeps must be replaced by a typed request**, per the
repo's `AGENTS.md` rule that QML never sends arbitrary terminal text.

---

## Tier 1 — high value, straightforward, fits the strip

### Keyboard layout

1. **File:** `/usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayout.qml` (+ `KeyboardLayoutModel.js`)
2. **Data:** `hyprctl -j devices` → JSON `keyboards[]`, fields `name`, `active_keymap`, `layout`. Secondary: `xkbcli list --load-exotic` → layout description table; `Hyprland.rawEvent` names `activelayout` / `configreloaded`.
3. **Actions:** click → `hyprctl switchxkblayout <keyboardName> next`.
   - SAFE (read). The switch is a fixed argv where `<keyboardName>` comes from
     `hyprctl` output, not from QML input → **NEEDS-CAVEAT**: add
     `keyboard_cycle { device }` to the typed dispatch and validate the device
     name against the last device read. Never build the argv in QML.
4. **Design note:** the information is "which language am I typing in". On a
   wide short strip that is a single small language pill that only appears when
   more than one layout exists — the same conditional-visibility rule the
   current widget already applies. No popup; the tap itself cycles.

### System update available

1. **File:** `/usr/share/omarchy/shell/plugins/bar/widgets/SystemUpdate.qml`
2. **Data:** `omarchy-update-available` — exit code 0 means pending updates. Polled every 21600000 ms (6 h), `triggeredOnStart`.
3. **Actions:** click → `omarchy-launch-floating-terminal-with-presentation omarchy-update`. IPC target `omarchy.system-update` exposes `refresh()` and `clear()`.
   - IPC `refresh` / `clear`: **SAFE**.
   - The click: **NOT-PORTABLE** on the home surface — it is a floating
     terminal. The portable action is to surface the boolean state plus a typed
     "apply updates" request routed to the daemon, which owns the update run.
4. **Design note:** convey one bit ("system needs updating"). A small badge on
   the power pill's corner, or a single quiet pill that only exists when true.
   The home surface must not host the update UI itself.

### Disk storage

1. **File:** `~/.config/omarchy/plugins/zakarch.storage/Service.qml`, `BarWidget.qml`, `Panel.qml`
2. **Data:** `df -P -x tmpfs -x devtmpfs -x efivarfs -x squashfs`; fields per row `device`, `total_kb`, `used_kb`, `avail_kb`, `pct`, `mount`. Home-directory ranking via `sh -c "du -kx -d 1 ~/ 2>/dev/null | sort -nr | head -n 6"`. Poll 30 000 ms. Severity: `ok` < 75 %, `warn` 75–89 %, `crit` ≥ 90 %.
3. **Actions:** click → toggle panel. IPC `zakarch.storage`: `status()`, `refresh()`, `analyze()`.
   - All three IPC methods: **SAFE** (bounded, read-only except forcing a re-read).
   - `analyze()` shells `du` — **NEEDS-CAVEAT**: keep it out of any automatic path; only allow it from an explicit user tap.
4. **Design note:** the information is "how full is my disk". A small
   capacity ring or a thin filled bar next to the storage tile, tinted with the
   severity ramp already defined (`ok` / `warn` / `crit`). Tapping opens a
   per-volume list. Do not carry the `du` folder ranking to the strip.

### Network / Wi-Fi detail

1. **File:** `/usr/share/omarchy/shell/plugins/panels/network/Panel.qml` (+ `Model.js`)
2. **Data:** `omarchy-network-status --verbose` — tab-separated `kind`, `label`, `signalStrength`, `frequency`. Also band status (`band`, `selected`, `available`) and ping samples (`router_ping_ms`, `internet_ping_ms`, `iface`, `rx_bytes`, `tx_bytes`). Wi-Fi rows come from the NetworkManager API with fields `name`, `connected`, `known`, `signalStrength`, `security`.
3. **Actions:** connect / disconnect / forget network; WPA2/PSK and WPA3/SAE; pin Wi-Fi band; enterprise EAP (`802-1x.*` via `nmcli connection edit`, password piped on stdin — argv is world-readable, so the password must never be an argument); copy throughput/latency.
   - Read paths: **SAFE**.
   - Forget a known, disconnected network: **NEEDS-CAVEAT** (destructive to saved credentials → confirm).
   - Enterprise connect: **NEEDS-CAVEAT** — needs a typed dispatch entry; the secret must arrive on stdin from the daemon boundary, never as a QML-built command line.
4. **Design note:** the strip carries the connection identity plus a signal
   glyph; everything else (band, ping, throughput sparkline, saved networks)
   lives in a Control Centre card. Apple-style: name + strength glyph on the
   strip, tap → card.

### App library / menu source

1. **File:** `/usr/share/omarchy/shell/plugins/menu/BarWidget.qml`, `Menu.qml`, `MenuModel.js`; library in `/usr/share/omarchy/shell/services/AppLibrary.qml` (+ `AppSearch.js`)
2. **Data:** `DesktopEntries.applications.values` (id, name, subtext, icon); hidden-entry filters from `~/.config/omarchy/extensions/omarchy-menu.jsonc` and `DesktopEntries`; icon resolution via `AppLibrary.iconIndex` then `Quickshell.iconPath(name, true)`, falling back to `application-x-executable`. Menu entries are declared in the same `omarchy-menu.jsonc`.
3. **Actions:** launch an application; run a configured menu entry; remove a pinned entry.
   - Launch by resolved desktop id: **SAFE** if dispatched as a typed
     `launch { app_id }` validated against the current `DesktopEntries` set.
   - "Run a configured menu entry" is an arbitrary argv from a config file →
     **NEEDS-CAVEAT**, and effectively **NOT-PORTABLE** on the home surface if
     the entry is a shell command; only entries that resolve to a desktop file
     should be reachable.
   - Entry removal: **NEEDS-CAVEAT** (writes user config).
4. **Design note:** the strip needs a single launcher affordance that reads as
   an app grid, not as a menu button. Icon cluster + blur backdrop, spotlight
   search on tap. The shell's own menu categories (system, power, log out) are
   *not* home-surface material — see Tier 3.

### System tray detail

1. **File:** `/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml` (+ `TrayModel.js`)
2. **Data:** `Quickshell.Services.SystemTray` — `StatusTrayItem` per item: `id`, `icon`, `title`, `tooltipTitle`, `menu`, `status` (`Status.Passive` items are hidden), `onlyMenu`. Pin/hide lists are inline in the `omarchy.tray` entry of `~/.config/omarchy/shell.json`.
3. **Actions:** `activate()` (left), `secondaryActivate()` (middle), right-click → the item's own `QsMenuEntry` tree rendered in-process, `scroll(angleDelta, false)` (wheel), pin / hide.
   - `activate`, `secondaryActivate`, `scroll`, and in-process menu rendering:
     **SAFE**.
   - Persisting the pin/hide list back into `shell.json`: **NEEDS-CAVEAT** —
     it is a config write, and the bar must own that write, not the dashboard.
4. **Design note:** on a strip this is "which background apps are talking to
   me". Render the pinned set inline, everything else in a small overflow
   chevron that opens the existing tray menu tree as a card. Hover-expand
   animation is not appropriate on touch; use tap.

### Clipboard

1. **File:** `/usr/share/omarchy/shell/plugins/clipboard/Clipboard.qml`
2. **Data:** `wl-paste --type text --watch …/shell/plugins/clipboard/capture.sh text` and `wl-paste --type image/png --watch … capture.sh image/png`, spawned via `setpriv --pdeathsig TERM`.
3. **Actions:** paste an entry; copy an entry back out; delete an entry.
   - **SAFE** — everything is an in-process model over the wl-paste feed plus a
     bounded `wl-copy` write.
4. **Design note:** one clipboard tile that shows the newest entry's type and a
   short preview; tap opens the chronological list. Clipboard content is user
   content, so it belongs on the surface the user is already touching — do not
   mirror it to any secondary display or OSD.

### Notifications and reminders

1. **Files:** `/usr/share/omarchy/shell/plugins/notifications/Service.qml`, `plugins/reminders/`, indicator `bar/indicators/Reminder.qml`
2. **Data:** notification service state directory `~/.local/state/omarchy/…` (created by the service via `mkdir -p`); reminder state from `omarchy reminder show --json`.
3. **Actions:** clear one; clear all; toggle DND (`setDoNotDisturb`); mark a reminder done.
   - **SAFE** — all in-process against the notification service.
4. **Design note:** a stack glyph with an unread count; tap opens the list as a
   card with per-item actions. The unread badge is the only thing the strip
   owes.

### Agent usage

1. **File:** `/usr/share/omarchy/shell/plugins/agents/Main.qml`
2. **Data:** `find $XDG_STATE_HOME/omarchy/agents/usage -maxdepth 1 -name '*.json' -printf '%f\n'`, then each per-agent JSON record written by `omarchy-agent-usage-update`.
3. **Actions:** none today — display only.
   - **SAFE**.
4. **Design note:** the information is "what are my agents doing right now".
   The home dashboard already has an agent surface; this should be read there
   rather than duplicated on the strip. If it appears on the strip it is one
   aggregate utilisation glyph, not per-agent rows.

---

## Tier 2 — needs deeper work or a popup surface

### Bluetooth audio

1. **File:** `~/.config/omarchy/plugins/ssupt.bluetooth-audio/Panel.qml` (+ `Service.qml`, `BluetoothAudioPolicyEngine.qml`, `AudioDropdown.qml`, `BluetoothDeviceDetails.qml`, `BluetoothDeviceRow.qml`), backend `bin/omarchy-bluetooth-service` (stdio)
2. **Data:** `Quickshell.Bluetooth` → `Bluetooth.devices.values`; paired/unpaired/trusted state, battery, profiles. Profile mutation goes through the helper with a bounded line protocol over stdio.
3. **Actions:** scan; pair; forget (with audio-data cleanup); connect/disconnect; switch profile; switch audio mode (A2DP / HFP) and persist that preference.
   - Read state and the in-process `Bluetooth` API: **SAFE**.
   - Profile/mode writes: **NEEDS-CAVEAT** — the helper is already a typed
     service boundary; the dashboard must call the service, not the helper, and
     must never hand it a constructed command string.
   - Forget + audio cleanup: **NEEDS-CAVEAT** (destructive; the current service
     already caps retries at `maximumAudioForgetAttempts` — preserve that).
4. **Design note:** a Bluetooth glyph on the strip with a paired-device count;
   tap opens a Control Centre card listing devices with their codecs. Device
   rows need enough height to be a real target.

### Tailscale

1. **File:** `/usr/share/omarchy/shell/plugins/panels/tailscale/Panel.qml` (+ `Service.qml`, `Model.js`, `TailscaleIcon.qml`)
2. **Data:** `which tailscale`; `tailscale status --json` (peers with `HostName`, `DNSName`, `TailscaleIPs`, `OS`, `Online`); `tailscale exit-node list`; `tailscale switch --list --json` (accounts); service polls every `refreshIntervalSec` (default 30, clamped 5–3600).
4. **Actions:** login (`tailscale up`, auth URL opened); switch account (`tailscale switch <id>`); set exit node (`tailscale set --exit-node=<target>`); become operator (`pkexec tailscale set --operator=<user>`); Taildrop a file (`omarchy-tailscale-send <target>`); copy peer IP / name / DNS name.
5. **Design note:** the strip carries connection state (on / off / needs login)
   and the active exit-node name. Peer list, accounts, and operator elevation
   belong in a card. The peer rows should read as a device list, not a log.

### Mail (omamail)

1. **File:** `~/.config/omarchy/plugins/omamail/ui/BarWidget.qml` (+ `Service.qml`, `App.qml`)
2. **Data:** the plugin's own backend process (`ui/backend/Backend.qml`, spawned with `serve`); unread total arrives over the bridge state (`bridgeState.unreadTotal`, `barMessages`, `barEvents`). Calendar reminders use `scripts/notify-mail.py`; credentials live in the OS keyring via `scripts/keyring-store.sh` / `scripts/config-store.sh`.
3. **Actions:** open the mail window; compose; calendar read/write (`scripts/calendar-write.sh`, `calendar-delete.sh`); attach a file (`scripts/attachment.sh pick`).
   - Reading the unread count: **SAFE**.
   - Composing / calendar mutation / attachment picking: **NEEDS-CAVEAT** —
     all of these need a separate input surface (compose sheet), not a strip
     tap. Calendar delete is non-idempotent → confirm.
4. **Design note:** an envelope glyph with an unread badge; tap opens mail. The
   compose flow belongs in its own sheet, not in the dashboard.

### Weather

1. **File:** `/usr/share/omarchy/shell/plugins/panels/weather/BarWidget.qml` (+ `Panel.qml`, `Model.js`)
2. **Data:** `curl -fsS --max-time 10 https://wttr.in/<locationQuery>?format=j1` for conditions; `curl -fsS --max-time 4 "https://wttr.in/?format=%l"` for the resolved location name.
3. **Actions:** open the forecast card; change location (`omarchy-weather-location --set <name>` / `--clear`).
   - Read: **SAFE** (bounded curl to a fixed host, bounded timeout).
   - Location write: **NEEDS-CAVEAT** (persisted user setting).
4. **Design note:** temperature glyph + condition word on the strip; the
   forecast card carries the rest. Weather is a glanceable fact — do not give
   it more than a fraction of the strip.

### Weather radar

1. **File:** `~/.config/omarchy/plugins/eduardodallecort.weather-radar/BarWidget.qml` (+ `Panel.qml`, `Service.qml`, `lib/RadarModel.js`)
2. **Data:** `https://api.open-meteo.com/v1/forecast`, `https://api.rainviewer.com/public/weather-maps.json` (radar tiles; coastlines are cached), `https://geocoding-api.open-meteo.com/v1/search`. Location is read from the same file `omarchy-weather-location` writes, so the two widgets stay consistent. Bar summary + `outlookLevel` severity.
3. **Actions:** set / clear location (`omarchy-weather-location --set <name> <lat>,<lon>` / `--clear`); issue alerts (`omarchy-notification-send`).
4. **Design note:** this is an animated map — it has no honest representation
   as a strip glyph beyond an alert-level indicator. Keep a single severity
   pip that only appears when the outlook warrants attention, and put the map in
   its own full-width surface.

### Monitor / display

1. **File:** `/usr/share/omarchy/shell/plugins/panels/monitor/Panel.qml` (+ `Model.js`)
2. **Data:** `omarchy-monitor-state` → display list with `enabled` per display. Brightness is written with `omarchy-brightness-display --no-osd --monitor <connector> <percent>%` and read with `omarchy-brightness-display --monitor <connector>`. `Model.clampBrightness`, `Model.normalizeScale`, `Model.cleanScale`, `Model.availableScales`, `Model.brightnessName` ("Sun blast" … "Night owl") shape the values.
3. **Actions:** set brightness; set scale; identify a display.
4. **Design note:** the home surface should own a single brightness stepper as
   a hardware slider with the confirmed value shown separately from the target
   — the existing `MonitorSettings` overlay already implements exactly this and
   it should be reused rather than rebuilt. The strip itself carries a
   brightness glyph only.

### Mouse settings (davedes) and MX control

1. **Files:** `~/.config/omarchy/plugins/davedes.mouse-keybind-settings/Panel.qml`; `~/.config/omarchy/plugins/blr.mx-control/runtime/6f515fad79aa90d89d85/plugin/{BarWidget.qml,Panel.qml,Service.qml}` with `backend/mx4ctl.py serve` and `backend/mx4-hardware listen --control gesture --control haptic`.
2. **Data:** davedes reads/writes `~/.local/state/omarchy/settings/davedes.mouse-keybind-settings.json` and shells `python3 <script> status`, `toggle-accel`, `toggle-natural-scroll`. MX Control reads its own service projection: `state.device.battery`, `verified`, `reconnecting`.
3. **Actions:** toggle acceleration; toggle natural scroll; bind/unbind a mouse button; refresh MX hardware.
4. **Design note:** pointer behaviour is a Settings-level fact, not a status
   fact. The home surface should show nothing about it, or at most a pointer
   glyph when a non-default binding set is active. Full editing belongs in
   Settings.

### Theme and wallpaper

1. **File:** `/usr/share/omarchy/shell/plugins/background/Background.qml`; theme state in `/usr/share/omarchy/shell/Commons/Color.qml`
2. **Data:** active theme name at `~/.local/state/omarchy/current/theme.name`; palette at `~/.local/state/omarchy/current/theme/colors.toml` and `shell.toml`; wallpaper symlink `~/.local/state/omarchy/current/background`, resolved with `readlink -f`. Switching shells out to `omarchy-theme-bg-switcher` / `omarchy-theme-switcher`; the CLI is `omarchy theme list` / `omarchy theme set <slug>`.
3. **Actions:** set theme; cycle background.
4. **Design note:** the home dashboard already reads the palette directly
   (`quickshell/state/OmarchyTheme.qml`). It must never hardcode colours — read
   the theme. Theme *selection* is a Settings action, not a strip action.

### AI provider usage chip

1. **File:** `~/.config/omarchy/plugins/akitaonrails.ai-usagebar/omarchy/BarWidget.qml` (+ `Panel.qml`, `SettingsView.qml`, `Model.js`)
2. **Data:** `/usr/bin/env ai-usagebar usage --json`; settings via `ai-usagebar settings show` / `apply`. Bar entry settings currently: `barWindow: "auto"`, `lastSelectedEntryId: "openai"`, `showAll: false`, `showProvider: false`, `showValue: true`.
3. **Actions:** cycle the selected provider entry; open the TUI (`omarchy-launch-floating-terminal-with-presentation ai-usagebar-tui`); authenticate (`ai-usagebar auth nous login`, `gh auth login --web`).
4. **Design note:** the information is "how much of each provider's quota is
   left". On the strip that is one compact meter with a provider initial.
   Cycles on tap; the card lists every provider. The TUI launch is
   **NOT-PORTABLE** — leave it out of the home surface entirely.

### Omaq (calls / chat)

1. **File:** `~/.config/omarchy/plugins/hancore.omaq/Panel.qml` (+ `Service.qml`, `ChatSurface.qml`, `PlacementController.qml`, `SurfaceCoordinator.qml`), helper `helper/omaq`, `scripts/float-omaq.sh`, `scripts/paste-image.sh`
2. **Data:** the plugin's own helper process and service; the surface floats over other windows via `Quickshell.Wayland`, and reads `Hyprland` for placement. It also carries a full settings UI (theme, sound picker, font size).
3. **Actions:** place/call, chat, paste image, change its own theme.
4. **Design note:** a floating call surface competing for the same overlay
   layer is a conflict, not a feature. If it is ported at all it should be a
   status glyph with a call action; its settings and theme editor do not belong
   on the home dashboard.

### Config sync

1. **File:** `~/.config/omarchy/plugins/gladimdim.config-sync/Panel.qml` (+ `Model.js`)
2. **Data:** `scripts/config_sync.py status` → `configured`, `sync_state` (`in-sync`, `not-configured`, `ready`, `empty`, `remote-ahead`, `local-ahead`, `conflicts`, `diverged`, `invalid`), `conflicts[]`, and per-file statuses `repo`, `added-repo`, `local`, `added-local`, `both`, `differs`.
3. **Actions:** review and push incoming changes; review and accept outgoing changes.
4. **Design note:** this is a real "you have unsynced dotfiles" warning. It
   earns one glyph on the strip when `alarming` (`conflicts` / `diverged` /
   `invalid`), and the review list belongs in a card. Pushing is
   **NEEDS-CAVEAT** — it is a consequential write, confirm before dispatch.

### hyprmoncfg

1. **File:** `~/.config/omarchy/plugins/crmne.hyprmoncfg/Panel.qml` (+ `MonitorInfo.qml`, `DisplayCanvas.qml`, `BrightnessControl.qml`, `ProfileActionsMenu.qml`, `PreviewGuard.qml`)
2. **Data:** live monitor inventory and applied profile state; brightness via `omarchy-brightness-display --monitor <connector>`; text size via `omarchy-display-text-size <px>`.
3. **Actions:** apply a saved profile; preview before applying; set per-monitor brightness; set display text size.
4. **Design note:** monitor layout is a spatial problem. It does not belong on
   a short horizontal strip — it needs a canvas. Treat as a Settings surface
   that the home dashboard may deep-link into, not render.

---

## Tier 3 — not appropriate for the home surface

### h4x0r (tmux multiplexer)

1. **File:** `~/.config/omarchy/plugins/io.github.johnsideserf.h4x0r/Panel.qml`
2. **Data:** `~/.local/bin/h4x0r` polled every `pollSeconds` (default 6); session rows, cursor index, status line. Palettes: `theme`, `phosphor`, `amber`, `ice`, `crimson`, `synthwave`, `mono`.
3. **Actions:** `Quickshell.execDetached([bin, "--mux", target])`, `[bin, "--mux", target, "--close"]`, `[bin, "--rebuild"]`.
4. **Why NOT-PORTABLE:** it is a terminal multiplexer whose only useful verbs
   open or tear down terminal sessions. There is no information a home strip
   can carry that a single status glyph would not trivially provide, and the
   only meaningful actions are terminal lifecycle operations. If it is surfaced
   at all, surface it as a link into the existing panel, not as a home tile.

### Omaplug (plugin marketplace)

1. **File:** `~/.config/omarchy/plugins/omaplug/BarWidget.qml` (+ `Panel.qml`, `plugin-state.sh`, `update-helper.sh`, `auto-check-coordinator.sh`, `nested-widget-toggle.sh`)
2. **Data:** `python3 <runtimeStatePath> read update.status` / `read install.status` / `reopen-read`; `omarchy-shell shell listShellConfig`.
3. **Actions:** install / update / remove an Omarchy plugin; restart the shell after a change (clear `~/.cache/quickshell/qmlcache`, then `omarchy-restart-shell`).
4. **Why NOT-PORTABLE:** installing a plugin means running third-party code
   inside the shell process — the panel's own copy says so ("Plugins run as
   arbitrary, unsandboxed code inside your omarchy-shell process"). This is a
   package manager, not status. **NEEDS-CAVEAT** at minimum even if it were
   hosted, because the action is high-consequence and not idempotent.

### Screen recording and screen share

1. **File:** `/usr/share/omarchy/shell/plugins/bar/indicators/ScreenRecording.qml`; commands from `crates/xeneon-agent-core/src/omarchy.rs` → `omarchy capture screenrecording --fullscreen` / `--stop-recording`
2. **Data:** recording state is `pgrep --quiet -f ^gpu-screen-recorder` (exit 0 = recording). Capture is gpu-screen-recorder.
3. **Actions:** start / stop fullscreen recording; screen-share.
4. **Why NOT-PORTABLE:** this drives a realtime capture pipeline with an
   external encoder. Starting and stopping it is non-idempotent and
   time-dependent — a dashboard tap that starts a recording is not a status
   affordance, and the recording indicator must keep its high-salience
   treatment rather than being folded into a settings row. Keep the indicator
   as an alert, not a control.

### The shell's own panel categories

1. **Files:** `/usr/share/omarchy/shell/plugins/menu/Menu.qml` providers, `plugins/polkit/PolkitAgent.qml`, `plugins/lock/`, `plugins/osd/`
2. **Data:** `omarchy-shell osd close`; polkit agent via the desktop portal; lock via `omarchy-hyprland-session-locked`, `omarchy-system-wake`, `omarchy-brightness-keyboard off`.
3. **Actions:** system power actions (reboot / shutdown / log out); polkit authentication; lock.
4. **Why NOT-PORTABLE:** polkit authentication requires `Password` /
   `config:` IpcHandler semantics and PAM conversations — a separate secure
   surface by construction. Reboot / shutdown are non-idempotent, session-
   ending, and belong in the system menu with a confirmation, never as a
   dashboard tap target.

### Notification-count-only widgets that duplicate existing home state

`gladimdim.config-sync` conflicts, `omarchy.agents` detail, and the `omamessage`
unread badge are each already implied by richer home surfaces. Porting them as
*additional* strip glyphs produces duplicate status language. Pick one owner per
fact.

---

## Cross-cutting rules for this surface

These are invariants every ported widget must obey. They come from
`AGENTS.md`, `docs/dashboards.md`, and the way the current bar already behaves;
breaking any of them is a defect, not a shortcut.

1. **No arbitrary shell from QML.** Every action is a typed dispatch entry with
   a fixed argv or an in-process API. No `bar.run("<shell string>")`, no string
   concatenation into a command, no free text or keys of any kind. Where the
   existing bar still uses a shell string, the port replaces it with a typed
   request.
2. **Allowlist and validate at the boundary.** Unknown operations and extra
   fields are rejected before dispatch. Dynamic identifiers (device names,
   connector names, output ids, theme slugs, power profiles, player names) are
   constrained against a fresh read at the daemon boundary, never accepted from
   QML.
3. **Never retry a non-idempotent action.** Screenshot, start/stop recording,
   lock, network forget, calendar delete, theme set, and plugin install each get
   at most one dispatch, and an unanswered request produces an explicit
   "outcome unknown" state requiring user review — never a resend.
4. **Honest unavailable states.** A reading that cannot be taken reports itself
   unavailable. No fabricated values, no carry-forward of stale numbers as if
   they were fresh, no placeholder that reads as real.
5. **No primary-display fallback.** If the XENEON identity is absent or
   ambiguous, this surface creates nothing. It is not a global layer surface.
6. **Theme-only colours.** Every colour comes from the theme through
   `OmarchyTheme` / `ThemePalette` / `MappedTheme` and the `Color.*` /
   `Style.*` roles. No hardcoded palette literals, no invented accent.
7. **Bounded work.** No unbounded scanning on a visual path. Sensor discovery,
   `du`, filesystem enumeration, and network probes run off the render path,
   poll at an explicit interval, and expose a bounded row count.
8. **Never expose private content on the surface.** No terminal text, no prompt
   contents, no worker logs, no T3 Code messages, activities, checkpoints,
   secrets, or provider payloads — and no tokens in any snapshot.
9. **Touch-sized targets on the strip.** The strip is short; anything that needs
   real space belongs in a card, not in a truncated row.