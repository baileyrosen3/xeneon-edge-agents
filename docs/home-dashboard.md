# Home dashboard

A second, standalone Quickshell surface for the XENEON EDGE: a wide, short
strip that mirrors the desktop's own menu bar, restyled as system UI.

## What it is, and what it is not

This configuration is **completely independent** of the XENEON EDGE agent
command center in this repository. It is a separate Quickshell config with its
own state directory, its own theme mapping, and its own action boundary.

It is **not deployed**. There is no installer, no systemd unit, no Hyprland
rule, and no packaged file for it. Nothing in `scripts/install.sh`, the portal
service, or the Hyprland Lua module knows this surface exists. It is run
manually and nothing starts it automatically.

It is **not wired into the portal**. It does not read the portal store, the
agent protocol, the bridge, or anything under `crates/`. The two configs can run
at the same time without sharing state.

The only things shared with the agent dashboard are non-visual foundations, and
each is a deliberate copy so this config stays self-contained:

- the Omarchy theme palette parser (`colors.toml` reading and its derived
  semantic roles),
- the screen-identity fail-closed rule,
- the typed allowlisted action pattern.

## Visual separation from the agent portal

The two surfaces are meant to look like different products from different
design teams. The home surface deliberately does **not** share the portal's
visual vocabulary. Removed, compared against the portal:

- the grid of hairlines across the backdrop,
- the glowing horizon ellipse,
- the vertical and horizontal rule field,
- the animated scanline,
- the decorative particles and orbit trails,
- the neon bloom and the accent-heavy framing,
- the dense instrument-panel card silhouette.

What remains is a calm, materially Apple surface: one smooth palette-derived
field behind everything, layered translucent cards floating on it with a
hairline rim and a single soft wide shadow, generous negative space between the
zones, and a clear type hierarchy. The backdrop carries **no structural
pattern at all** — `ThemeBackdrop.qml` contains no `Repeater` and no drawn
border, and a contract test enforces both.

The active theme on the authoring host is `vantablack`, which is deliberately
monochrome. That palette is preserved exactly; hierarchy comes from
translucency, weight, scale, and spacing rather than from an invented saturated
accent.

## Running it

### Preview, offscreen, with a screenshot

```sh
XENEON_HOME_PREVIEW=1 \
XENEON_HOME_PREVIEW_SIZE=1280x360 \
XENEON_HOME_SHOT=/tmp/xeneon-home-dashboard/shots/home-1280x360.png \
XENEON_HOME_SETTINGS_PATH=/tmp/xeneon-home-settings.ini \
QT_QPA_PLATFORM=offscreen \
quickshell --no-duplicate --path "$(pwd)/quickshell/home"
```

Swap `XENEON_HOME_PREVIEW_SIZE` for `1024x288` to capture the shorter logical
surface. The process writes the PNG and exits with status 0.

### Preview, interactive

Same command without `XENEON_HOME_SHOT`; the window stays open until closed.

### Live, on the panel

Live mode binds a layer surface to exactly one screen, matched by explicit
identity. All three components are required:

```sh
XENEON_HOME_SERIAL=<serial> \
XENEON_HOME_MODEL=<model> \
XENEON_HOME_OUTPUT=<output-name> \
XENEON_HOME_SETTINGS_PATH="${XDG_RUNTIME_DIR}/xeneon-home-settings.ini" \
quickshell --no-duplicate --path "$(pwd)/quickshell/home"
```

**Fail-closed.** Incomplete identity, no matching screen, or more than one
matching screen all create *no surface at all* and log the reason. There is no
fallback to the primary display, and no code path can reach one.

### Environment

| Variable | Meaning |
| --- | --- |
| `XENEON_HOME_PREVIEW=1` | Preview mode: a `FloatingWindow`, no live surface. |
| `XENEON_HOME_PREVIEW_SIZE=<WxH>` | Preview size, validated and bounded to 640–3840 × 180–720. Default `1280x360`. |
| `XENEON_HOME_SHOT=<path>` | With preview, write a PNG and exit. |
| `XENEON_HOME_REDUCED_MOTION=1` | Disables every animation; honoured per-`Behavior`. |
| `XENEON_HOME_SETTINGS_PATH=<path>` | Preference file location. |
| `XENEON_HOME_SERIAL` / `_MODEL` / `_OUTPUT` | Live screen identity. All three required. |
| `XENEON_HOME_WALLPAPER=<path>` | Optional wallpaper backdrop. Unset by default; see below. |
| `XENEON_HOME_THEME_ROOT` | Falls back to `$XDG_STATE_HOME/omarchy/current`. |

## Layout

A single horizontal band, with nothing legible or interactive within the outer
8% on any edge — that band is an edge-gesture zone on this touchscreen. The
safe band is computed from the live surface height, so one layout serves both
the 1024×288 logical surface and the 1280×360 preview without a second code
path.

- **Top strip** — clock and date on the left, the workspace indicator centred,
  indicator and status pills on the right.
- **Left zone** — the app launcher cluster (`DockIcon`).
- **Centre zone** — the now-playing media card (`NowPlayingCard`).
- **Right zone** — the hardware stats stack (`StatsStack` / `StatMeter`).

Column widths are derived from content, never from a fixed share of the
surface. The dock's width is computed from the tiles it must hold, and fewer
tiles are shown rather than letting any of them be clipped or occluded. The
media card absorbs whatever width is left.

## File map

```
quickshell/home/
  shell.qml                      ShellRoot: preview, capture, and live modes
  components/
    Design.js                    The only spacing, radius, type, and motion
                                  values; also the superellipse path generator
    Squircle.qml                 Continuous-curvature shape
    GlassMaterial.qml            The one translucent material every card uses
    ThemeBackdrop.qml            The calm plane behind everything
    HomeSurface.qml              The composed layout and the safe-band maths
    HomePanel.qml                The live layer-shell overlay
    StatusBarStrip.qml           Clock, date, workspaces, pill group
    WorkspaceIndicator.qml       Workspace pills
    StatusPill.qml               Read-only status chip
    IndicatorPill.qml            Toggleable indicator pill
    VolumePill.qml               Volume level and mute
    TrayPill.qml                 Status-notifier tray wells
    DockIcon.qml                 One launcher tile
    NowPlayingCard.qml           Artwork, metadata, scrubber, transport
    TransportButton.qml          One transport control
    StatMeter.qml                One measured quantity
    StatsStack.qml               CPU / GPU / memory columns
    IconResolver.qml             Real application icon resolution
  state/
    OmarchyTheme.qml             Verbatim copy of the palette parser
    ThemePalette.js              Verbatim copy of the palette parser
    MappedTheme.qml              Verbatim copy of the palette parser
    HomeActions.js               The single action allowlist
    ActionDispatcher.qml         The only action boundary
    SourceBase.qml               Uniform source contract
    SourceParse.js               Pure parsers
    HomeSettings.qml             Persisted preferences
    IconResolver.qml             Icon resolution (shared by components)
    <Source>.qml                 One independent, replaceable data source
  tests/
    test_home_contract.py        Contract tests for this config
```

## Data sources

Every source is independent and replaceable, publishes one uniform snapshot
(`{ available, detail, updatedMs, ...fields }`), and polls on its own timer
without blocking the UI. A source whose tool is absent reports `available:
false` with a reason. **No source ever reports a zero it did not measure.**

Availability below is measured on the authoring host.

| Source | Reads | Status on the authoring host |
| --- | --- | --- |
| `ClockSource` | the system clock | working |
| `HyprlandSource` | `hyprctl -j monitors/workspaces/activewindow/clients` | working |
| `CpuSource` | `/proc/stat`, `/proc/cpuinfo`, hwmon | working |
| `MemorySource` | `/proc/meminfo` | working |
| `GpuSource` | `/sys/class/drm/card*/device`, hwmon | working |
| `MediaSource` | Quickshell MPRIS service | **unavailable — no MPRIS player registered** |
| `AudioSource` | `pactl` | working |
| `NetworkSource` | `/proc/net/route`, `nmcli` | working |
| `BluetoothSource` | `bluetoothctl` | working |
| `PowerSource` | Quickshell UPower service | working |
| `TraySource` | Quickshell SystemTray service | working |
| `IndicatorSource` | `omarchy toggle … --status`, notifications state file | working |

Notes on two deliberate absences:

- **Media** uses the MPRIS service, not `playerctl`. `playerctl` is not
  installed on this host, and MPRIS is the protocol every desktop music player
  actually implements. With no player running, the card shows its honest
  unavailable state.
- **GPU** reads sysfs only. NVIDIA's proprietary driver publishes nothing
  readable there and would require NVML, i.e. a helper process per sample. A
  host with no readable GPU path reports unavailable rather than inventing a
  number.

### About the wallpaper

Omarchy themes do publish a wallpaper at `<themeRoot>/background`. This theme's
is a regular dot field, and rendered as anything sharper than a faint smudge it
reads as a repeating rule pattern — exactly the structural noise the backdrop
must not carry. It is therefore **not used**; the field is a pure palette
gradient. `XENEON_HOME_WALLPAPER` exists for a host whose wallpaper is a real
image, and is still subject to heavy de-emphasis and a vignette.

## The action allowlist

Presentation code never supplies a command, a command string, an argument
string, or a keystroke. It supplies a typed identifier plus at most one typed
parameter. `ActionDispatcher` resolves that identifier through
`HomeActions.js` to either a **fixed argv** or a **fixed MPRIS method**, and
logs every dispatch — accepted or refused.

Four action kinds:

| Kind | Parameter rule |
| --- | --- |
| `launch` | none; a fixed executable |
| `workspace` | a bounded integer id, or a window address that already appears in the compositor's current snapshot |
| `media` | a fixed MPRIS method name, optionally a seek bounded by the track length |
| `audio` / `desktop` | none; a fixed executable, presence-probed once |

An executable's presence is probed once per process with `/usr/bin/test -x`,
using only a path from the table. A tile whose target is missing is drawn struck
through rather than pretending to launch.

Screenshots in this repository are regenerated locally and are not committed.