# XENEON EDGE Agent Command Center Ledger

## Local Omarchy setup (2026-10-01)

- Editable clone: `local/omarchy`, based on `6c0bcc55fe74b476a0707932a94f2e50bc136ead`.
- Installed Herdr reports v0.9.3 / protocol 22; package metadata still reports
  v0.8.2. Verified official v0.9.3 source at `7b116c05`, live projected snapshot
  field types, and all 20 current event subscription acknowledgements.
- Added explicit protocol-22 status, focus, and zoom compatibility. Ordering
  and guarded actions stay unavailable; protocol 21 and unknown versions stay
  incompatible. Independent review approved the adapter and authority checks.
- Upstream Rust, QML, shell, and isolated installer checks passed. After the
  compatibility change, formatting, 110 Rust tests, Clippy, and the release
  build passed. Unchanged QML gates passed 28 Python contract/fixture tests,
  116 QML tests, and 30 isolated installer scenarios.
- Exact connected EDGE identity and touchscreen passed production staging.
  USB touchscreen `wch.cn-touchscreen-1` has stable uniq `9LQ0172005164`;
  commissioning uses this identity rather than its changing USB topology.
- Read/write/restore proof: exact EDGE DDC bus brightness 95 -> 94 -> 95.
  Production activation passed; the daemon observes three agents through
  Herdr protocol 22, and the portal surface exists only on the exact EDGE.
  Hyprland reload, config-error, Lua syntax, and installed identity checks pass.
  The hardware reconciler and input watcher are enabled; application services
  run only through the commissioned hardware lifecycle.
  Interactive touch coordinates, unplug/replug, suspend, and lock privacy
  remain physical acceptance checks; do not describe them as tested.

## Goal

Implement a simulator-first, touch-oriented XENEON EDGE portal for all running
local Herdr sessions, with host health, fail-closed output placement, and
guarded quick actions. Complete every software gate and commission the
connected physical display without weakening exact output or touch identity.

The current UX checkpoint corrects Herdr agent naming and brings the existing
Codex Micro state language to the portal: shared state colors, observable
Omarchy voice states, and a dynamic ambient perimeter treatment. This work is
isolated from the package-review checkout and must not weaken the production
output or action boundaries.

The current visual checkpoint uses `herdr-xeneon-edge-concept.mp4` as a motion
reference: an opaque dashboard crossfade, center-out radar reveal, quiet
constellation hold, and bounded state-colored orbital trails. The exact
storyboard and product boundaries are recorded in `docs/concept-motion.md`.

The active home-command checkpoint replaces the host-health footer with
agent-command information: adaptive Herdr cards, normalized AI provider
capacity, fixed native desktop launch/focus actions, and a read-only Codex
Micro projection. QML remains presentation-only; cache parsing, socket reads,
and desktop actions stay in `xeneon-agentd`.

The completed AI-detail follow-up expands that footer with both reported capacity
windows, reset timing, plan/freshness state, and bounded aggregate today/hour
token activity. Prompt text, per-model history, credentials, and raw provider
payloads remain outside the portal protocol.

The completed review checkpoint audited the complete tracked repository with Claude
Fable 5 over a persistent ACP session. Any verified findings are fixed only on
`claude-fable-review`, revalidated through the required software gates, and
returned to the same reviewer until no substantive findings remained.

The completed source theme-sync checkpoint makes portal chrome follow Omarchy's current
runtime palette without copying a named theme. The project-owned QML reader
watches Omarchy's stable theme-name beacon, reloads the atomically replaced
`colors.toml`, validates an allowlisted palette, and retains the fixed agent
state meanings while mapping their hues to the active theme's blue, yellow,
green, and red roles.
Installation and a physical theme switch remain a separate live gate.

The active hotplug checkpoint replaces connector-pinned autostart with an
event-driven lifecycle. The commissioned EDID, serial/model, and USB touch
identity remain authoritative while the current connector becomes runtime
state; the daemon and portal run only while that exact hardware is present.

The active agent-manager checkpoint adds T3 Code as a second agent manager with
the same card semantics as Herdr, switched from a new header Manager control.
The daemon owns the selection, persists it under the state directory, reads
only T3 Code's bounded read-only projections gated on its live server process,
maps threads onto the existing attention vocabulary, and lets T3 Code's own
settle acknowledge review badges. T3 Code has no public thread-focus API on
Linux, so a card tap only activates its exact desktop window; zoom, approve,
and interrupt stay unavailable in that mode.

## Done criteria

- [x] Rust daemon and QML bridge expose versioned normalized snapshots.
- [x] All running local Herdr sessions reconnect and reconcile safely.
- [x] Standalone Quickshell portal renders six attention-ordered cards and
      deterministic fixture states at 2560x720.
- [x] Direct actions are capability-gated inside Herdr; QML cannot send raw
      input.
- [x] Installer/check/uninstall flows are reversible and preserve Omarchy and
      user-owned configuration.
- [x] Automated checks and completed independent reviews pass.
- [x] Portal cards use the same public agent names as Herdr's Agents section.
- [x] Agent colors, voice states, and ambient perimeter behavior retain the
      reviewed Codex Micro meanings, use active Omarchy hue roles, and support
      reduced motion.
- [x] Ambient transition and orbital motion match the concept timing and
      hierarchy without changing portal action authority.
- [x] Revised live laptop preview is visually compared with rectified concept
      frames at the same 1280x360 viewport.
- [x] One native perimeter halo uses two opposing clockwise runners while an
      agent is working or blocked, and disappears for idle or empty rosters.
- [x] The perimeter runners render as a Gaussian-style GPU bloom with bounded
      particle motes instead of stacked moving bars.
- [x] Agent-card status accents use bounded Gaussian blooms with no visible
      hard core: a state-colored left aura on every card and a moving blue top
      glint only while the agent is working.
- [x] Shared persistent Motion and Screen controls remain available in both
      control-center and Ambient views; reduced motion uses an evenly spaced
      static constellation with no trails/runners, and Screen minimum remains
      visibly reversible above a near-black portal veil.
- [x] The control-center header uses the uppercase live hostname, removes the
      redundant connection pill, and replaces the AI Capacity label tile with
      authoritative Herdr agent/session/focus counts.
- [x] Control-center cards expose only authoritative Herdr lifecycle,
      repository/worktree, focus, and state-age metadata.
- [x] Each ordinary agent card is one full-surface Herdr focus target; the
      redundant Open and Zoom controls are removed while capability-gated hold
      actions remain isolated when present.
- [x] The footer shows normalized Claude, Codex, and OpenCode usage with
      freshness and quota/local-budget semantics.
- [x] The footer shows both reported windows, reset timing, plan/freshness
      state, and bounded today/hour token activity without exposing raw data.
- [x] ChatGPT and Claude buttons focus or launch only their fixed native
      desktop IDs through daemon-owned actions.
- [x] A right-side read-only Micro drawer shows fresh device status, projected
      agent slots, and the shared voice/aggregate state language.
- [x] Focused Rust/QML tests, live laptop interaction, visual QA, and an
      independent review pass complete for the home-command checkpoint.
- [ ] Physical EDGE display/touch/focus/privacy/power checks pass (display,
      exact touch mapping, Ambient wake, and card focus are now confirmed).
- [x] Exact XENEON hotplug starts and maps the stack on its current connector;
      unplug stops both application services without touching other displays.
- [x] The header Manager control switches the daemon between Herdr and T3 Code
      with typed, sequence-gated commands; switching clears the previous
      roster, targets, latches, focus history, and subscriptions, and the
      choice persists across daemon restarts.
- [x] T3 Code mode reads only bounded thread, session, turn, and project
      projections, fails closed on a missing server or schema drift, and never
      writes T3 Code state or reads messages.
- [ ] Physical EDGE touch validation of the Manager toggle and T3 Code card
      focus (software gates and a live laptop preview are complete).

## Streams

| Stream | Branch/worktree | Files to own | Status |
| --- | --- | --- | --- |
| Foundation and Rust adapter | `main` | Rust workspace, schemas, fixtures | Complete through `c32b5cd` |
| Herdr safe actions | `agent/xeneon-safe-actions` in the Herdr repository | Public Herdr API, PTY guard, tests, next docs | Installed from reviewed v0.8.0 head `fd53378d`; not pushed |
| Shared agent ordering | `xeneon-order-mode-sync` in `herdr-worktrees/xeneon-order-mode-sync` plus `header-launch-order-fix` here | Herdr `agent.order.get/set`, adapter snapshot/action, QML toggle, ordering and motion tests | Reviewed fork `51af53be` installed to `~/.local/bin/herdr` and activated through a 52-pane live handoff; portal ordering is available and grouped/priority round trips synchronize through Herdr's public API |
| Header launcher repair | `header-launch-order-fix` | move the fixed ChatGPT/Claude actions beside ordering, update the allowlisted ChatGPT desktop ID, verify both launch/focus paths, and reactivate authoritative ordering | Source-reviewed, installed, and live-verified: fixed ChatGPT/Claude actions sit after Order, direct sandbox-safe `uwsm app` launches both exact desktop classes, and existing windows focus without arbitrary input |
| Quickshell portal | `main` | `quickshell/`, QML tests | Complete through `34e6037` |
| Live naming, voice, and ambient ring UX | `agent/portal-voice-ring` in `portal-voice-ring` worktree | normalized public protocol fields, `quickshell/`, fixtures, UX docs/tests | Live on the physical EDGE; remaining power/privacy checks are open |
| Concept motion parity | `agent/portal-voice-ring` in `portal-voice-ring` worktree | ambient presentation, preview timing, visual QA | Live on the physical EDGE; remaining power/privacy checks are open |
| Agent-command home redesign | `agent/portal-voice-ring` in `portal-voice-ring` worktree | normalized safe metadata, usage/Micro collectors, fixed app actions, control-center QML | Software complete, live-previewed, and independently reviewed |
| AI usage detail expansion | `main` | bounded usage protocol, AI dock, tests/docs | Complete, installed, and physically verified |
| Full Claude Fable 5 review | `claude-fable-review` | complete tracked repository; preserve untracked `packaging/` artifacts | Complete: all 14 findings fixed and ACP re-review clean |
| Desktop launcher | `desktop-launcher` | managed XDG desktop entry, helper, icon, installer lifecycle, tests | Complete, installed, and launched through Omarchy |
| Omarchy runtime theme sync | `omarchy-theme-sync` | project-owned QML palette reader, semantic chrome and state tokens, theme reload/fallback tests | Theme sync and semantic state roles installed, reviewed, and physically verified |
| Herdr v0.8 compatibility | `herdr-v0.8-compat` in `herdr-v0.8-compat` worktree | Herdr protocol gate, adapter fixture, protocol docs | Installed from `6edfcd3`; live handoff, protocol 19 connection, services, and production checker passed |
| Hotplug lifecycle | `hotplug-lifecycle` in `hotplug-lifecycle` worktree | lifecycle reconciler, user units, Hyprland event hook, runtime connector override, installer/tests | Installed and independently reviewed; exact `DP-2` unplug stopped both services and replug restored the stack and touch mapping; burst and mid-settle races are covered by regression tests |
| T3 Code agent manager | `t3code-backend` | `t3code.rs` adapter, backend dispatch and persistence in `runtime.rs`, `backend` protocol field and `backend_*` commands, header Manager toggle, manager-aware copy, `t3code.ndjson` fixture, docs/config/schema | Software complete on 2026-09-11: Rust (107 tests, clippy, fmt), QML (116 Qt tests, 28 contract tests) green; live source preview switched to T3 Code and back over the daemon socket, showed 13 real threads, focused the `t3code` window on card open, applied daemon-owned ordering, and persisted `agent-backend.toml`; a refresh-dispatch deadlock found in that live run is fixed with a regression test; independent review complete (one confirmed race, a late Herdr refresh committing over a T3 Code roster, fixed with a regression test, plus two minor findings fixed; 108 Rust tests); installed on 2026-09-11 from local merge `t3code-install` (this branch plus `herdr-protocol-21`, gate green with 112 Rust tests) via `cargo install` and `scripts/install.sh --apply-production --activate`; the installed daemon reconnected to Herdr 0.8.2 (protocol 21, 28 agents), switched to T3 Code over its socket with a live roster and a 0600 persisted `agent-backend.toml`, and switched back; physical EDGE touch validation of the toggle is the remaining gate |
| Global display controls | `agent/portal-voice-ring` in `portal-voice-ring` worktree | persistent presentation settings, reduced-motion composition, dim veil | Live on the physical EDGE; default full-motion/normal-screen state restored |
| Omarchy integration | `agent/portal-voice-ring` in `portal-voice-ring` worktree | `config/`, `scripts/`, services, install tests | Production user integration installed and active on the physical EDGE |

Header/order review workers `header_order_review` (Claude, pane `wW:pP`) and
`header_launch_service_review` (Claude, pane `wW:pQ`, tab `wW:tG`) completed
read-only review/fix/re-review loops with no remaining P0-P2 findings. Both
loop-created resources were closed; the orchestrator owned all fixes,
verification, installation, and the live handoff.

## Allowed actions

- Create local branches/worktrees and commits.
- Build, test, lint, and run explicit development previews.
- Change files in this repository and the isolated Herdr worktree.
- Install reviewed user-owned files only after isolated installer tests pass.

## Forbidden actions

- Production deployment, release publication, secrets, billing, or customer
  data.
- Editing `/usr/share/omarchy`.
- Global touch mapping, primary-monitor fallback, arbitrary key forwarding, or
  automatic replay of input actions.
- Claiming physical success without the connected device.

## Gates and evidence

- [x] Hotplug lifecycle software gate: Rust config tests, shell/static checks,
      31 isolated installer/reconciler scenarios, generated Lua syntax, and
      independent review with no remaining substantive findings.
- [ ] Hotplug lifecycle physical gate: reviewed live install, actual
      `/dev/input` path activation, display/USB unplug-replug ordering, and real
      touch disable/re-enable mapping pass. DPMS, suspend/resume, focus/privacy,
      and coordinate validation on the XENEON remain open.

- [x] Foundation focused tests: 24 core plus 1 CLI test and strict clippy.
- [x] Herdr gates: 2,825 unit, 213 integration, 86 maintenance, 17
      integration-asset, and 12 marketplace tests; strict Linux all-target and
      Windows-bin clippy.
- [x] QML gate: `qmllint`, 21 Python contract/fixture tests, 37 Qt tests,
      exact 1280x360 mapped preview, and inspected 1280x360 offscreen render.
- [x] Installer gate: 25 temporary-XDG scenarios plus installed-unit
      `systemd-analyze verify`.
- [x] Independent Rust/API and PTY concurrency review.
- [x] Independent QML/UX review.
- [x] Independent packaging/safety review with no remaining high/medium
      findings.
- [x] Naming/voice/ring focused Rust and QML tests: 43 core plus 1 CLI, strict
      clippy/fmt, 22 Python contracts/fixtures, and 51 Qt tests.
- [x] Live laptop preview using real Herdr agents and observable voice-state
      transitions, without installing or activating production display config.
- [x] Independent review of the naming/privacy boundary, voice-state
      ownership, animation lifecycle, and reduced-motion behavior.
- [x] Concept-motion QML gate: 22 Python contract/fixture tests and 65 Qt tests,
      with `qmllint`, reduced-motion, bounded trails, reverse-transition,
      accessibility-shield, and live-state coverage.
- [x] Visual QA against four perspective-rectified concept states at 1280x360;
      post-fix result is recorded as passed in `design-qa.md`.
- [x] Independent concept-motion re-review approved after phase-wrap and
      fade-shield lifecycle fixes; no actionable findings remain.
- [x] Independent reverse-transition re-review approved after forward-coast,
      full-duration staging, bounded trail-cost, and accessibility action
      shielding fixes; no P0, P1, or P2 findings remain.
- [x] Integrated local simulator smoke: one Herdr 0.7.5/protocol-17 session,
      two active Codex agents, versioned snapshot, and expected open/zoom-only
      actions from the unchanged stable Herdr.
- [x] Agent-command home gates: 52 core plus 1 CLI test, strict fmt/clippy,
      23 Python contracts/fixtures, 72 Qt tests with `qmllint`, schema parse,
      shell syntax, and the isolated installer suite.
- [x] Agent-command home live 1280x360 visual QA used real Herdr names, live
      provider capacity, verified Micro status, a real ChatGPT focus result,
      and a real Claude launch plus mapped-client focus result.
- [x] Perimeter halo live QA captured the two runners moving clockwise through
      rounded corners on command-center and ambient views; the native Shape
      implementation remained responsive after the Canvas prototype was
      rejected for excessive paint cost.
- [x] Perimeter bloom live QA captured two frames in both command-center and
      ambient views: the runners remained opposing and clockwise, the blur
      stayed soft at corners, particle trails remained bounded, and the mapped
      preview stayed responsive.
- [x] Independent QML re-review caught and verified the production hostname
      pass-through; the final focused review found no remaining P0/P1/P2
      issues.
- [x] Card-focus QA verified the full-size target contract, the fixed
      `agent.focus` action against the live preview daemon, and the resulting
      authoritative focused-agent update for `seform-codex`.
- [x] Physical EDGE display and touch QA verified the exact commissioned EDID,
      model, serial, USB identity, and touch device; enabled native 2560x720 at
      2x scale; captured a real touch sequence; woke Ambient; focused an agent;
      and observed Herdr report that exact agent focused. Host-specific hardware
      identifiers remain in the local commissioning file rather than this
      repository.
- [x] Production activation verified both user services active with zero
      restarts, a mode-`0600` daemon socket inside a mode-`0700`
      systemd-owned runtime directory, a connected Herdr protocol-17 snapshot
      with five real agents, live provider/Micro telemetry, and one
      `xeneon-edge-agent-portal` layer surface on `DP-2` only.
- [x] Physical card-accent QA replaced the rigid left and working-state top
      bars with two bounded `MultiEffect` blooms, captured the result at native
      2560x720, and verified zero service restarts or shader warnings.
- [x] Global display-control gate: 52 core plus 1 CLI test, strict fmt/clippy,
      25 Python contracts/fixtures, 80 Qt tests with `qmllint`, and 25 isolated
      installer scenarios.
- [x] Physical display-control QA used real DP-2 taps in both views: Motion
      persisted through a production service restart, suppressed perimeter
      runners and trails, and placed four agents without overlap on an evenly
      spaced static ellipse; Screen minimum dimmed and restored both
      control-center and Ambient views without waking Ambient.
- [x] Independent display-control review approved QML layering, restore
      reachability, reduced-motion coverage, Qt Settings persistence, and the
      narrowly writable systemd StateDirectory with no P0/P1/P2 findings.
- [x] Physical runtime fixes were independently reviewed before reactivation:
      the reconciler exclusively owns and preserves the systemd runtime
      directory needed for connector handoff, Quickshell receives narrowly
      writable shared runtime paths, Qt's unavailable Wayland EDID serial is
      tolerated only after the installer verifies the configured serial
      through Hyprland, and the unique connector/model match remains
      fail-closed.
- [x] Agent-command home independent Rust/QML review resolved launch
      coalescing, collector non-blocking behavior, verified Micro identity, and
      fail-closed usage; final re-review found no remaining P0/P1/P2 issues.
- [x] AI usage detail gate: 53 core plus 1 CLI test, strict fmt/clippy, 25
      Python contracts/fixtures, 85 Qt tests with `qmllint`, and 25 isolated
      installer scenarios.
- [x] AI usage detail physical QA captured the installed native 2560x720 DP-2
      surface with both available usage windows, reset timing, plan/freshness,
      explicit provider status, and bounded today/hour token activity; both
      services remained active with zero restarts.
- [x] Independent AI usage detail review approved the additive schema-v1
      fields, trust clearing, Rust/QML bounds, and 1280x360 composition with no
      substantive findings.
- [x] Claude-review remediation software gate: 56 Rust core plus 1 CLI test,
      strict fmt/clippy, ShellCheck 0.11.0, 26 Python QML contracts/fixtures,
      85 Qt tests with `qmllint`, and 25 isolated installer scenarios.
- [x] Claude Fable 5 full-repository ACP review has no remaining substantive
      findings after verified fixes and required local gates.
- [x] Claude-review live activation passed the exact DP-2/EDID/touch preflight,
      installed release binaries with source-matching hashes, retired the
      obsolete `HealthStrip.qml`, restarted both services with zero failures,
      reported one connected Herdr 0.7.5/protocol-17 session with four agents,
      and rendered one visually inspected portal layer on DP-2 only.
- [x] Desktop-launcher gate: strict ShellCheck, desktop-entry validation, 28
      isolated installer scenarios, and the full Rust/QML/software gates pass;
      independent re-review has no remaining P0/P1/P2 findings.
- [x] Desktop-launcher live QA found the custom entry and icon in Omarchy's
      Apps menu, launched it through that menu, rendered its success
      notification, kept already-running service PIDs stable, and separately
      restored a deliberately stopped portal through `gtk-launch` on DP-1.
- [x] Historical Herdr v0.8 compatibility gate: protocol-19 adapter fixture and
      full repository software checks passed against that earlier rebased API
      contract; the current protocol-20 checkpoint below supersedes it.
- [x] Omarchy theme-sync base source gate: strict palette parsing and fallback
      tests, repeated atomic theme-directory replacement in a source preview,
      full QML lint/tests, 31 installer scenarios, Rust and ShellCheck gates,
      plus independent review with no P0-P2 findings.
- [x] Install the reviewed theme-sync base and verify its active Omarchy
      palette renders on the physical EDGE.
- [x] Finish review, install the semantic state-role follow-up, and verify the
      theme-derived blue/yellow/green/red meanings on the physical EDGE.
- [ ] Add a top-right persisted Palette pane that shows the current Omarchy
      swatches and maps allowlisted roles onto Ready, Success, Working, Needs
      Help, Review Ready, Error, Unknown, Recording, and Processing. Done requires
      focused and full QML gates, hosted CI, independent review, a reviewed
      reinstall, and physical verification in command-center and Ambient
      views across at least two Omarchy themes.
- [x] Restore Claude, Codex, and OpenCode capacity after Omarchy replaced the
      legacy model-usage caches with schema-v1 agent records. Done requires
      legacy compatibility, fail-closed normalized parsing, a read-only local
      OpenCode fallback, Rust/full-repository gates, independent review, and
      live EDGE verification with all three cards populated.
- [ ] Physical hardware gate (hotplug, DPMS, suspend/resume, privacy,
      guarded-hold behavior, and DDC restore remain).
- [ ] Fit 14 agents per fixed 2560x720 command-center page, keep the full
      Claude/Codex quota-window labels visible, and show each card's Herdr
      space name for dense grouping. Show up to the same 14 agents on a
      bounded independent-lane ambient animation instead of the previous
      six-node cap; full-motion lanes may intentionally cross and overlap,
      while reduced motion stays static and evenly spaced.
      Done requires QML gates,
      independent review, a reviewed reinstall, a temporary 20-agent Herdr
      population proving 14+6 pagination, physical EDGE screenshots, and
      cleanup of only the disposable test tabs.
- [ ] Synchronize the EDGE grouped/priority control with Herdr's authoritative
      persisted ordering and restore the exact original independent ambient
      motion through six agents while extending the same independent-lane
      character through fourteen bounded nodes. Done requires Herdr and XENEON
      tests, independent reviews, a
      reviewed Herdr live handoff, physical toggle verification from both UIs,
      and physical ambient visual QA.
- [x] Header/order software and live API gate: the reviewed Herdr `51af53be`
      package replaced the stock server through a state-preserving 52-pane
      handoff; ordering round-tripped priority to grouped and back through the
      XENEON typed action plus Herdr public socket. The reviewed XENEON build
      was installed, and no-window launch plus existing-window focus passed for
      the exact ChatGPT and Claude desktop identities.

## Current local state

- Active goal (2026-08-13): the software and live-API portion of replacing the
  stock Omarchy Herdr protocol-20 server is complete. The reviewed fork is
  user-installed from package commit `51af53be`, the state-preserving handoff
  succeeded, guarded actions remain available, and grouped/priority ordering
  synchronizes through Herdr and XENEON. The reviewed XENEON release is also
  installed. Remaining goal gates are the physical EDGE touchscreen toggle,
  a matching Herdr-UI toggle, and final ambient visual QA. No PR is planned
  against Herdr upstream under its external-contributor policy.

- The 14-agent layout source and cleanup gates are complete: QML tests prove
  14+6 pagination, a temporary 20-agent Herdr population physically verified
  the first 14-card page plus the fourteen-node ambient view, and all 11
  disposable tabs were closed. A physical second-page screenshot remains open.
- The grouped/priority follow-up is live on the isolated Herdr branch
  `xeneon-order-mode-sync` at `51af53be` and current XENEON branch
  `header-launch-order-fix`. After the pane population fell to 52, the reviewed
  epoch-1 Herdr package was installed user-locally and a state-preserving live
  handoff replaced `/usr/bin/herdr` with `~/.local/bin/herdr` without closing
  this session. XENEON reports one connected protocol-20 session, 18 agents,
  and authoritative priority ordering; a typed priority-to-grouped-to-priority
  round trip matched `agent.order.get` after every step. The current XENEON
  gate passes 81 Rust core tests plus the CLI test, strict Clippy/rustfmt, 27
  Python and 113 Qt QML tests, all 31 installer scenarios, `qmllint`, and
  `git diff --check`. Independent Claude reviews are GO. The release daemon and
  Quickshell tree are installed; both services are active. Live typed actions
  launched exact ChatGPT and Claude desktop classes from no-window state and
  focused an existing Claude window. Physical touchscreen presses and a Herdr
  UI-side toggle remain human gates.

- `omarchy-theme-sync` is based on current `origin/main` and contains the
  pushed theme integration, semantic state-role follow-up, dense layout,
  protocol-20 adapter, and usage remediation in draft PR #7. A persisted
  allowlisted Palette pane and the hosted font-metric fix are now being added
  before merge; neither incremental change is installed or pushed yet.
  Independent read-only reviewer `xeneon_palette_review` (Claude) completed
  the review/fix/re-review loop with no remaining P0-P2 findings; its Herdr
  pane `wW:pN` was closed after graceful agent exit. PR #7 passed all hosted
  Rust, QML, and integration jobs and squash-merged into `main` at `ae54cee`;
  only physical pane/two-theme QA remains for this increment. Final local
  revalidation passes 78 Rust core tests, the CLI test, strict Clippy/rustfmt,
  ShellCheck, 27 Python and 112 Qt QML tests, all 31 installer scenarios, and
  `git diff --check`. The reviewed tree is installed after exact output/touch
  preflight; both services are active with zero restarts, installed Quickshell
  files match source, and Hyprland reports no config errors. A compositor-native
  2560x720 Tokyo Night capture confirms the new Palette button and 14-card
  command-center layout. The installed `cua-driver` 0.7.1 cannot capture this
  multi-monitor Wayland layer surface (`GetImage` Match failure), so opening
  the pane and two-theme physical QA remain human/live gates; no CUA action was
  attempted after capture failed.
- Production reinstall reverified the exact DP-2 EDID, XENEON serial/model,
  and USB touchscreen identity before activation, then correctly followed the
  same hardware after connector drift to live `DP-1`. The deployed Quickshell
  tree matches current source. Both services are active with zero restarts,
  the lifecycle reports `state=running`, and one inspected portal layer
  renders only on the XENEON using the active `rebel-rebel` palette.
- The source preview followed the real `rebel-rebel` palette and an isolated
  atomic purple-to-cyan theme replacement without restart. A final current
  fixture preview was visually inspected and closed cleanly.
- Theme validation passes 27 Python QML contracts, 93 Qt tests, all 31
      installer scenarios, 60 Rust core tests, the CLI fixture test, Clippy,
      rustfmt, ShellCheck, and `git diff --check`.
- The August 11 Omarchy usage migration regression is fixed in the installed
  daemon. Claude and Codex consume fresh fail-closed schema-v1 Omarchy records;
  OpenCode derives its documented local soft-budget signal from bounded scalar
  counters in the read-only message ledger. Two independent final reviews
  reported no P0-P2 findings. Full gates pass: 68 Rust core tests plus the CLI
  fixture, strict Clippy/rustfmt, 27 Python and 93 Qt QML tests, 30 installer
  scenarios, ShellCheck, and `git diff --check`. The live snapshot reports all
  three providers available and fresh, and the physical DP-1 EDGE screenshot
  shows populated Claude 9%/4%, Codex 58%, and OpenCode 1%/0% cards.
- PR #2 is squash-merged on `main` at `7eb773c`, including the reviewed
  physical commissioning, naming/voice/ring UX, card accents, and persistent
  display controls.
- The clean `agent/portal-voice-ring` worktree is retained as historical
  branch context; the merged implementation remains installed in user-owned
  XDG paths on this host.
- The final live preview showed the current Herdr public labels
  `seform-codex`, `wifi7`, `herdr-xeneon`, and `herdr-xeneon-design`; prior
  voice validation observed recording/idle ownership transitions,
  automatically cancelled a recording when its bridge client disconnected,
  and restored the prior ChatGPT window before laptop voice actions.
- `xeneon-agentd.service` and `xeneon-edge-portal.service` are enabled,
  active, and running without restarts after the reviewed AI usage detail
  activation.
- The managed `XENEON EDGE Command Center` desktop entry, icon, and bounded
  helper are installed in user-owned XDG paths. The default action starts the
  two fixed user units without disrupting active services; restart is an
  explicit secondary action.
- The installed physical footer now shows both reported provider windows,
  reset timing, plan/freshness and explicit status, plus bounded aggregate
  today/hour activity when available; no prompts, per-model history,
  credentials, or raw provider payloads cross the protocol.
- The uncommitted remediation isolates Herdr refreshes
  from the privacy-sensitive collector loop, fails closed on non-20 Herdr
  protocols and untrusted usage text, repairs QML recovery behavior, removes
  the retired HealthStrip, and adds ShellCheck plus an Arch/Quickshell CI gate.
- Portal preferences persist at
  `~/.local/state/xeneon-edge-agents/portal/preferences.ini` with mode `0600`;
  physical validation ended in the default full-motion, normal-screen state.
- `hyprland.lua` contains the installer-managed XENEON require, and the
  generated module maps only `wch.cn-touchscreen-1` to `DP-2`.
- The persisted home layout places the 1280x360 logical EDGE at `560,1350`,
  centered below the 2400x1350 logical external display, with the laptop
  immediately to its right at `1840,1350`. The external display is running at
  120 Hz instead of 240 Hz so the third display fits the available link
  bandwidth.
- Herdr was live-handed off twice without terminating its 48 pane processes:
  first from stable v0.7.5 to reviewed v0.8.0/protocol 19, then from the build
  artifact to the canonical `~/.local/bin/herdr`. The old server exited only
  after the replacement acknowledged PTY ownership. Installed Herdr and XENEON
  binary hashes match their reviewed release artifacts; both user services,
  `xeneon-agentctl doctor`, and `scripts/check.sh` pass. Backups are retained in
  the user-owned Herdr and XENEON state directories. Approval and Windows
  guarded actions remain unavailable.

## Open checkpoints

- Repair the installed Herdr focus handoff on branch
  `header-launch-order-fix`. Done requires an exact process/session-owned
  compositor selection regression, focused and broad Rust gates, independent
  review, a pushed PR, an exact reviewed local install, and a live typed open
  action that both focuses the Herdr agent and activates its hosting window.
  Do not weaken selection to a generic terminal class/title or focus an
  unrelated terminal when the session identity is absent or ambiguous.
  Independent Claude reviewer `xeneon_focus_review` ran in Herdr pane `wW:pR`,
  found and re-reviewed the CLI/session/environment/focus-history boundaries,
  and returned GO with no P0-P2 after 15 focused desktop tests and strict
  Clippy. The reviewer pane was then closed by this loop. Final source gates
  pass 87 Rust core tests plus the CLI test, strict workspace Clippy/rustfmt,
  27 Python and 113 Qt QML tests, all 31 installer scenarios, ShellCheck,
  `luac -p`, and `git diff --check`; publication, installation, and live
  typed-open verification remain.
- Complete the Claude Fable 5 ACP review/fix/re-review loop on
  `claude-fable-review`; do not include or modify the pre-existing untracked
  `packaging/` artifacts.
- Capture calibrated corner coordinates and guarded-hold cancellation.
- Verify hotplug, DPMS, suspend/resume, and privacy behavior.
- Probe DDC/CI read-only and expose brightness only after exact restoration
  succeeds.
- Before proposing the Herdr branch upstream, satisfy its contribution gate
  (accepted issue and maintainer approval when required); do not replace the
  stable Herdr install during physical commissioning without a separate
  reviewed upgrade.

## Two-dashboard runtime update — 2026-10-02

- Implemented the combined Omarchy/Agents dashboard and a full Riptide account,
  ticket, and activity dashboard with a fixed drag/tap switcher. Compact agent
  pagination retains all agent actions; an actual-click test reaches Agent 11
  in the 12-agent fixture and returns to page one.
- Final local gates pass: 142 core Rust tests plus one CLI test, rustfmt,
  strict workspace Clippy, 28 Python contracts, 137 Qt QML tests, qmllint,
  ShellCheck, all 31 isolated installer scenarios, generated installed Lua
  syntax, and staged systemd-unit verification.
- Independently reviewed and installed 51 runtime files on 2026-10-02 at
  01:45:21 -0400. Every installed hash matches the stage. Commissioning and
  the exact-output portal service remain byte-identical. Backups, reviewed
  manifest, and rollback script are in the task workspace at
  `work/runtime-update/`; the installed managed manifest is updated.
- Direct gateway observation is enabled with a private mode-0600 credentials
  file; trading execution remains disabled. An isolated temporary daemon
  verified three gateway accounts, three reported nonzero positions, zero
  orders, CPU/GPU health, audio controls, 22 themes, and two storage mounts.
  Legacy broker liveness is explicitly unverified. No orders were submitted.
- The exact DP-2 XENEON display and commissioned EDID remain connected. The
  commissioned USB touchscreen disconnected at 01:33:06 and is absent; the
  existing identity gate correctly leaves daemon/portal inactive. The input
  watcher is active and enabled and will reconcile on reconnect. Physical
  touch and actual production-layer visual QA await that reconnection.
- No LG preview, monitor changes, suspend/DPMS tests, or GitHub publication
  were performed during this update.

## Monitor hardware panel — 2026-10-02

- Added a global Monitor overlay on both dashboards, capability-driven raw
  hardware controls, integer touch keypad, exact device/display/touch
  diagnostics, and release-only writes. Commands require a successful result
  plus newer matching hardware readback; errors require explicit refresh and
  never resend a mutation. Production-only local IPC opens/closes this existing
  overlay without hardware actions or an additional window.
- Source checkpoints: `d04a4ad` UI, `c117d49` hardware backend, `f0b1f17` local
  menu IPC/Qt6 lint runner, `d586e22` bounded error presentation, and `beb972f`
  native mixed-get handling. The last fix accepts exit one only for a complete,
  uniquely validated read-only VCP batch with both values and unsupported ERR
  rows. Writes, fatal/malformed reads, timeouts, and signals remain strict.
- Final source gates pass 158 core Rust tests plus one CLI test, workspace
  Clippy/rustfmt, 28 Python contracts, 150 Qt QML tests, qmllint, ShellCheck,
  Lua syntax, 31 isolated installer scenarios, and seven independent host-update
  recovery fixtures. Backend, QML, IPC, and concrete stages received independent
  review. Source edits still require rebuilding/reinstalling the copied runtime.
- Reviewed reversible installations are retained under `work/monitor-update/`
  and `work/monitor-read-update/`. The latter guards all 54 runtime targets and
  replaces only two binaries, the diagnostic QML, and the managed manifest.
  Personal configuration, private mode-0600 credentials, the daemon profile,
  exact output/touch commissioning, and unrelated ownership remain preserved.
  Monitor observation and writes are explicitly enabled; trading remains
  read-only. Lifecycle gates prevent hotplug from starting a partial update;
  rollback restores the watcher before fresh exact-identity reconciliation.
- Native installed-daemon reads verify exact DP-2, serial 035926215698, the
  commissioned EDID, and bus 12. Seven writable controls expose brightness
  95/100, contrast 50/100, RGB 151/127/139 out of 255, sharpness 2/4, and
  preset 11 (User 1). Seven advertised preset choices are 1, 2, 4, 5, 6, 8, 11.
  Independent DDC backlight is unsupported. Display status is 2560×720 at
  60.266 Hz, scale 2.5, transform 0; the commissioned touchscreen is connected.
- One typed native brightness write changed 95 to 94 and confirmed readback;
  one typed write restored 94 to 95 and confirmed readback. Three/five snapshots
  streamed during those pending commands. No retries, other hardware changes,
  or trading mutations were sent. Independent direct post-restoration DDC reads
  confirm every baseline value, exact EDID/bus, all 54 installed files/modes, and
  all 103 implementation source hashes. Both services and the input watcher are
  active, reconciliation succeeded, and Hyprland reports no configuration errors.
- Actual production menu visual evidence is saved outside the clone at
  `outputs/monitor-settings-live.png`. The EDGE has exactly one portal layer,
  other outputs have none, and no LG preview was created. Physical finger-touch,
  hotplug, DPMS, and suspend acceptance remain separate tests.

## Responsive monitor adjustments — source stage

- Sliders dispatch during drag with immediate SET feedback and a separate
  confirmed READ value. One command is in flight; one latest target per
  continuous control is served through a unique FIFO, at least 100 ms between
  sends. Released targets survive closing the menu, and matching in-flight or
  confirmed targets are not sent twice. Presets and refresh wait for idle.
- Errors, rejected sends, timeouts, disconnects, and changed capabilities drop
  all unissued targets and require explicit refresh. No previous mutation is
  replayed. Backend review approves the QML scheduler and target/read display.
- Source checks pass 157 Qt tests, 28 Python contracts, changed QML lint, and
  diff checks. An independent focused monitor run passes all 19 cases.
- Native latency optimization, reviewed release installation, and acceptance
  are pending. The user's latest hardware brightness is 100, not the former
  95 acceptance baseline; any native test must capture and preserve current
  user values. No hardware writes were made by the UI implementation agent.

### Responsive monitor backend · 2026-10-02

- Native read-only benchmark on the exact commissioned EDGE showed single
  reads falling from about 866 ms to 40–42 ms with proven initialization reuse
  and fixed read multiplier 0.25. Process startup alone was about 5 ms. These
  are read timings, not a claim of physical write or full ACK latency.
- `monitor.read_sleep_multiplier` is explicit opt-in (default omitted), bounded
  to 0.25–1.0. A 60-second monotonic, full-Target proof requires a normal complete
  VCP probe and freshly acquired native MCCS 2.2 capabilities with the CLI
  capabilities cache disabled. Fast queries never renew that proof. Expiry,
  target/preset changes, failed or incomplete probes invalidate it.
- Known-target reads skip repeated compliance initialization. Every change
  still freshly identifies EDID/serial/bus and reads bounds, RGB preset when
  relevant, and independent post-write confirmation. Sets retain multiplier
  1, normal verification, and one write-only attempt; no mutation retry.
- Accepted user writes cancel only periodic read probes and their read-only
  finish/metadata work. RAII releases the pending counter on every exit. A real
  blocked subprocess/flock fixture proves native cancellation and lock release.
- Dedicated monitor publications own the dashboard field, independent of equal
  or backward wall clocks. Publications fetch the controller cache only after
  acquiring the state lock, so a queued old sample cannot revert a new readback
  or failure. Deterministic regressions cover both publication races.
- Focused 17 monitor and two runtime cases passed. Independent native review
  reproduced all 19; ordinary reviewer sandbox had one deferred child-PID
  disappearance assertion, while lock release and native child validation
  passed. Full workspace passed 164 core plus one CLI test; Clippy and formatting
  passed. Independent UI review passed all 19 focused Qt cases.
- Release installation and fresh-baseline write latency acceptance remain next.
  User brightness changed to 100 during read-only measurements; never restore
  the earlier 95 baseline over intervening user changes.
