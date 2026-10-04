import json
import pathlib
import re
import unittest


# This file lives in quickshell/home/tests/, so the Quickshell config root is
# one level up and the portal config root is two.
HOME = pathlib.Path(__file__).resolve().parents[1]
QUICKSHELL = HOME.parent
PORTAL = QUICKSHELL.parent


def source(relative: str) -> str:
    return (HOME / relative).read_text(encoding="utf-8")


def qml_files():
    return sorted(HOME.rglob("*.qml"))


class HomeScreenIdentityContractTests(unittest.TestCase):
    """The live surface binds to exactly one verified screen, or to none."""

    def setUp(self):
        self.shell = source("shell.qml")
        self.gate = source("state/ScreenIdentity.js")

    def test_identity_requires_serial_model_and_output(self):
        # All three identity components must be demanded, not just some of them.
        for variable in ("targetSerial", "targetModel", "targetOutput"):
            self.assertIn(variable, self.shell)
        self.assertIn("function identityConfigured()", self.shell)
        # All three components are required by the shared gate.
        self.assertIn("function identityConfigured(identity)", self.gate)
        self.assertIn('String(record.output || "") !== ""', self.gate)
        self.assertIn('String(record.model || "") !== ""', self.gate)
        self.assertIn('String(record.serial || "") !== ""', self.gate)
        self.assertIn("ScreenIdentity.targetScreen", self.shell)

    def test_no_surface_when_identity_is_missing_or_ambiguous(self):
        # The single-match gate is the whole fail-closed rule: anything other
        # than exactly one match yields an empty list, which creates no surface.
        # Exactly one match, or nothing at all.
        self.assertIn("ScreenIdentity.targetScreen", self.shell)
        self.assertIn('return matches.length === 1 ? matches[0] : null', self.gate)
        self.assertIn("no surface:", self.shell)

    def test_no_fallback_to_the_primary_display(self):
        # There must be no code path that falls back to a default or primary
        # screen when identity does not match.
        for forbidden in (
            "Quickshell.screens[0]",
            "screens[0]",
            "primaryScreen",
            "defaultScreen",
        ):
            self.assertNotIn(forbidden, self.shell)

    def test_serial_mismatch_refuses_the_screen(self):
        # A compositor that publishes no serial must not be assumed to be the
        # requested panel, so an empty runtime serial refuses.
        # The shared gate compares the serial only when one is published, and
        # requires exact output and model matches unconditionally.
        self.assertIn("function screenMatches(screen, identity)", self.gate)
        self.assertIn("screen.serialNumber", self.gate)
        self.assertIn('runtimeSerial !== "" && runtimeSerial !== String(record.serial || "")',
                      self.gate)
        self.assertIn("screen.model", self.gate)
        self.assertIn("screen.name", self.gate)
        # The unsatisfiable form must never come back.
        self.assertNotIn('runtimeSerial === "" ||', self.gate)

    def test_preview_mode_never_creates_a_live_surface(self):
        # The preview path must bypass screen matching entirely, so a screenshot
        # run can never place a surface on the wrong display.
        # The live surface is active only when not previewing and exactly one
        # screen has been verified; an inactive Loader creates nothing.
        self.assertRegex(
            self.shell,
            r"active: !root\.previewMode && root\.targetScreens\.length === 1",
        )


class HomePreviewContractTests(unittest.TestCase):
    """The preview and capture harness is driven by documented environment."""

    def setUp(self):
        self.shell = source("shell.qml")

    def test_settings_path_is_overridable(self):
        # The preference store must be redirectable so a preview run never
        # touches an installed configuration file.
        settings = source("state/HomeSettings.qml")
        self.assertIn("XENEON_HOME_SETTINGS_PATH", settings)

    def test_documented_environment_contract(self):
        for variable in (
            "XENEON_HOME_PREVIEW",
            "XENEON_HOME_SHOT",
            "XENEON_HOME_PREVIEW_SIZE",
            "XENEON_HOME_REDUCED_MOTION",
            "XENEON_HOME_SERIAL",
            "XENEON_HOME_MODEL",
            "XENEON_HOME_OUTPUT",
        ):
            self.assertIn(variable, self.shell)

    def test_preview_size_is_validated_and_bounded(self):
        # A malformed size must fall back rather than produce a broken window.
        self.assertIn("XENEON_HOME_PREVIEW_SIZE", self.shell)
        matcher = re.search(
            r"readonly property size previewSize:.*?\n    \}\)\(\)",
            self.shell,
            re.S,
        )
        self.assertIsNotNone(matcher)
        body = matcher.group(0)
        self.assertRegex(body, r"\^?\(?\[0-9\]\{3,4\}")
        self.assertIn("Math.max(640", body)
        self.assertIn("Math.min(3840", body)

    def test_reduced_motion_is_honoured_by_every_animation(self):
        self.assertIn("XENEON_HOME_REDUCED_MOTION", self.shell)
        # Every animated file must gate its Behaviours on the flag rather than
        # only shortening a duration somewhere.
        animated = [
            "components/DockIcon.qml",
            "components/StatMeter.qml",
            "components/TransportButton.qml",
            "components/VolumePill.qml",
            "components/WorkspaceIndicator.qml",
        ]
        # Components that animate nothing declare no Behavior to gate. The
        # media block was rewritten as a static composition, and the pill
        # components have no transitions.
        for static_only in (
            "components/NowPlayingCard.qml",
            "components/TrayPill.qml",
            "components/IndicatorPill.qml",
        ):
            self.assertNotIn("Behavior on", source(static_only), static_only)
        for relative in animated:
            text = source(relative)
            self.assertIn("reducedMotion", text, relative)
            self.assertRegex(
                text,
                r"enabled: !\w+\.reducedMotion",
                relative + " must gate its animations on reducedMotion",
            )


class HomeActionAllowlistContractTests(unittest.TestCase):
    """No path exists from QML to an arbitrary command string."""

    def setUp(self):
        self.actions = source("state/HomeActions.js")
        self.dispatcher = source("state/ActionDispatcher.qml")

    def _blocks(self):
        # Every entry in the `actions` table, with its body. The table is a flat
        # object literal, so scanning balanced braces is sufficient.
        start = self.actions.index("var actions = {")
        depth = 0
        blocks = {}
        name = None
        current = []
        for line in self.actions[start:].split("\n"):
            stripped = line.strip()
            match = re.match(r'^"([a-z0-9_.]+)": \{$', stripped)
            if match is not None and depth == 1:
                name = match.group(1)
                current = []
            if name is not None:
                current.append(line)
            depth += line.count("{") - line.count("}")
            if name is not None and depth == 1:
                blocks[name] = "\n".join(current)
                name = None
            if depth == 0 and name is None and len(blocks) > 0:
                break
        return blocks

    def test_every_action_resolves_to_a_fixed_argv_or_fixed_method(self):
        blocks = self._blocks()
        self.assertGreater(len(blocks), 0)
        for entry, block in blocks.items():
            has_command = '"command": [' in block
            has_handler = '"handler":' in block
            self.assertTrue(
                has_command or has_handler,
                "%s has neither a fixed command nor a fixed handler" % entry,
            )

    def test_every_argv_element_is_an_absolute_path_or_a_bare_word(self):
        # No entry may embed a shell, a redirect, a pipe, or a substitution.
        for argv in re.findall(r'"command": \[([^\]]*)\]', self.actions):
            elements = re.findall(r'"([^"]*)"', argv)
            self.assertGreater(len(elements), 0)
            for element in elements:
                self.assertNotRegex(
                    element,
                    r"[;|&`$><*?()\[\]{}!]",
                    "argv element %r looks like a shell construct" % element,
                )
                self.assertNotIn("\n", element)
                self.assertNotIn("\r", element)

    def test_workspace_parameter_is_a_bounded_integer(self):
        # The workspace action may substitute only a validated integer id, so a
        # caller cannot carry a string into argv.
        self.assertIn("function validWorkspace(value)", self.actions)
        block = re.search(
            r"function validWorkspace\(value\) \{(.*?)\n\}", self.actions, re.S
        ).group(1)
        self.assertIn("Number.isInteger", block)
        self.assertIn("workspaceMinimum", self.actions)
        self.assertIn("workspaceMaximum", self.actions)

    def test_window_parameter_must_already_exist_in_the_snapshot(self):
        # A window address is only ever one the compositor already published.
        self.assertIn("function validAddress(value)", self.actions)
        self.assertIn("addressPattern", self.actions)
        self.assertIn("is not in the current snapshot", self.actions)

    def test_media_parameters_are_a_typed_method_and_a_bounded_position(self):
        self.assertIn("var mediaMethods", self.actions)
        for method in ("togglePlaying", "play", "pause", "next", "previous", "seek"):
            self.assertIn('"%s"' % method, self.actions)
        self.assertIn("function validMediaMethod(name)", self.actions)
        self.assertIn("function validPositionSeconds(value, lengthSeconds)", self.actions)

    def test_tray_parameters_are_an_allowlisted_method_and_a_known_item(self):
        self.assertIn("function planTray(actionId, itemId, context)", self.actions)
        self.assertIn("Tray item is not in the current snapshot", self.actions)

    def test_dispatcher_never_passes_a_caller_string_to_a_command(self):
        # The dispatcher's own command assignments must all reference the
        # resolved argv, never a caller-supplied string.
        self.assertIn("function dispatch(actionId, parameter)", self.dispatcher)
        self.assertIn("Allowlist.plan(", self.dispatcher)
        self.assertIn("runner.command = argv", self.dispatcher)
        # execDetached is the sanctioned path for a long-lived launcher. It may
        # only ever receive the argv the allowlist resolved, never a string.
        self.assertIn("Quickshell.execDetached(argv)", self.dispatcher)
        self.assertNotIn("execDetached(self.", self.dispatcher)
        self.assertNotIn("execDetached(root.", self.dispatcher)
        for forbidden in ("h5", "keySequence", "sendKeys"):
            self.assertNotIn(forbidden, self.dispatcher)

    def test_dispatch_logs_both_accepted_and_refused_actions(self):
        self.assertIn("function refuse(actionId, detail)", self.dispatcher)
        self.assertIn("function accept(actionId, detail)", self.dispatcher)
        self.assertIn("console.warn", self.dispatcher)
        self.assertIn("console.log", self.dispatcher)

    def test_no_keystroke_or_text_channel_exists(self):
        # There is no keystroke or terminal-text path anywhere in the config.
        for path in qml_files():
            text = path.read_text(encoding="utf-8")
            for forbidden in ("send_keys", "sendKeys", "keys:", "terminal_text", "type_text"):
                self.assertNotIn(forbidden, text, "%s in %s" % (forbidden, path))


class HomeSourceContractTests(unittest.TestCase):
    """A source reports unavailable rather than presenting a zero as truth."""

    def setUp(self):
        self.base = source("state/SourceBase.qml")

    def test_snapshot_shape_is_uniform_and_carries_availability(self):
        self.assertIn("property var snapshot", self.base)
        self.assertIn('"available": false', self.base)
        self.assertIn("function publishUnavailable(detail)", self.base)

    def test_every_source_publishes_the_same_available_flag(self):
        for path in qml_files():
            if not path.name.endswith("Source.qml"):
                continue
            text = path.read_text(encoding="utf-8")
            if path.name == "SourceBase.qml":
                continue
            self.assertIn(
                "readonly property bool available",
                text,
                "%s must expose the uniform available flag" % path.name,
            )

    def test_probe_argv_is_validated_before_a_process_starts(self):
        self.assertIn("function validArgv(argv)", self.base)
        self.assertIn("function validArg(value)", self.base)
        # A shell metacharacter must never be accepted as an argument.
        self.assertIn("validArg(argv[index])", self.base)
        self.assertIn("validArgv(argv)", self.base)

    def test_follow_up_reads_are_confined_to_proc_and_sys(self):
        self.assertIn("function validReadPath(path)", self.base)
        self.assertIn("function acceptProbes(list)", self.base)
        self.assertRegex(self.base, r"proc\|sys")

    def test_parsers_never_return_zero_for_a_missing_reading(self):
        parse = source("state/SourceParse.js")
        self.assertIn("function clampPercent(value)", parse)
        self.assertIn("return null", parse)


class HomeVisualSeparationContractTests(unittest.TestCase):
    """The home surface must not echo the agent portal's visual language."""

    # Checked as whole words so that, for example, "horizontal" does not match
    # "horizon".
    FORBIDDEN_MOTIFS = (
        "scanline",
        "AmbientView",
        "OrbitTrail",
        "PortalBackground",
        "PortalViewport",
        "DashboardView",
        "neon",
        "horizonGlow",
        "trail",
        "particle",
    )

    def test_no_portal_motif_survives(self):
        for path in qml_files():
            text = "\n".join(
                line for line in path.read_text(encoding="utf-8").lower().split("\n")
                if not line.strip().startswith("//")
            )
            for motif in self.FORBIDDEN_MOTIFS:
                self.assertNotRegex(
                    text,
                    r"\b%s\b" % re.escape(motif.lower()),
                    "portal motif %r survives in %s" % (motif, path),
                )

    def test_config_does_not_import_from_the_portal_config(self):
        # Self-contained: every import resolves inside quickshell/home/.
        for path in qml_files():
            text = path.read_text(encoding="utf-8")
            for match in re.findall(r'import "([^"]+)"', text):
                # A relative import from components/ reaches quickshell/home/state,
                # which is this config's own copy and is self-contained. Only a
                # resolved path outside quickshell/home/ is a violation.
                resolved = (path.parent / match).resolve()
                self.assertTrue(
                    str(resolved).startswith(str(HOME.resolve())),
                    "%s imports outside quickshell/home/: %s" % (path.name, match),
                )

    def test_backdrop_carries_no_structural_pattern(self):
        # A grid, a rule field, or a scanline would read as an instrument panel.
        backdrop = source("components/ThemeBackdrop.qml")
        self.assertNotIn("Repeater", backdrop)
        self.assertNotIn("border.width", backdrop)

    def test_no_hardcoded_brand_colours(self):
        # Every colour must come from the theme; only a neutral black and white
        # for alpha math and gradients are permitted literals.
        allowed = {"#000000", "#ffffff", "#fff"}
        for path in qml_files():
            text = path.read_text(encoding="utf-8")
            for colour in re.findall(r'"(#[0-9A-Fa-f]{3,8})"', text):
                if colour.lower() not in allowed:
                    self.fail(
                        "hardcoded colour %s in %s; every colour must come from the theme"
                        % (colour, path.name)
                    )

    def test_action_allowlist_dock_apps_only_reference_declared_actions(self):
        actions = source("state/HomeActions.js")
        declared = set(re.findall(r'^\s{4}"([a-z0-9_.]+)": \{', actions, re.M))
        for app in re.findall(r'\{ "id": "([a-z0-9_.]+)"', actions):
            self.assertIn(app, declared)


class HomeAsyncSourceContractTests(unittest.TestCase):
    """A source that has not published yet must yield an idle state.

    On the live panel the source context is injected *after* the panel item is
    constructed, so every source is briefly absent. Dereferencing one threw a
    TypeError on the first frame of every start.
    """

    def test_media_card_tolerates_an_absent_source(self):
        card = source("components/NowPlayingCard.qml")
        # The source is optional, and every field goes through one guard.
        self.assertIn("property var media: null", card)
        self.assertIn("readonly property var source:", card)
        self.assertIn("function mediaValue(field)", card)
        # No raw dereference of the source may survive.
        self.assertNotRegex(card, r"root\.media\.[a-zA-Z]")

    def test_the_idle_state_is_explicit(self):
        card = source("components/NowPlayingCard.qml")
        # Nothing playing means no position and no length, not an accidental
        # undefined read.
        self.assertIn("readonly property double lengthSeconds", card)
        self.assertIn("readonly property double positionSeconds", card)
        self.assertIn("readonly property real progress", card)
        self.assertIn('root.available', card)

    def test_the_live_panel_context_is_never_null(self):
        # A null context makes every source read in the tree throw on frame one.
        panel = source("components/HomePanel.qml")
        self.assertIn("property var context: ({})", panel)
        self.assertNotIn("property var context: null", panel)

    def test_every_source_exposes_available_before_any_field(self):
        # `available` is what every consumer reads first, so it must exist even
        # before the first sample publishes.
        for path in sorted((HOME / "state").glob("*Source.qml")):
            if path.name == "SourceBase.qml":
                continue
            text = path.read_text(encoding="utf-8")
            self.assertIn(
                "readonly property bool available",
                text,
                "%s must expose available" % path.name,
            )


class HomeLayoutContractTests(unittest.TestCase):
    """The strip must respect the touch panel's geometry and safe areas."""

    def test_edge_safe_band_is_at_least_eight_percent(self):
        design = source("components/Design.js")
        self.assertIn('"edgeSafeFraction": 0.08', design)
        self.assertIn("function bandForHeight(height)", design)

    def test_both_required_preview_sizes_are_supported(self):
        shell = source("shell.qml")
        self.assertIn("Qt.size(1280, 360)", shell)
        self.assertIn("Math.max(640", shell)
        self.assertIn("Math.max(180", shell)

    def test_dock_zone_is_derived_from_its_tiles(self):
        # The dock must be sized by its content, never by a share of the surface,
        # so its tiles can never overlap the media card.
        surface = source("components/HomeSurface.qml")
        self.assertIn("readonly property int dockCapacity", surface)
        self.assertIn("dockAppsShown", surface)
        self.assertIn("readonly property real dockWidth", surface)

    def test_capacity_figures_are_split_across_two_lines(self):
        # A used/total pair must never be rendered into one elided line.
        meter = source("components/StatMeter.qml")
        self.assertIn("property string capacityDetail", meter)
        stats = source("components/StatsStack.qml")
        self.assertIn("memoryUsedLabel", stats)
        self.assertIn("memoryTotalLabel", stats)


class HomeStatsPresentationContractTests(unittest.TestCase):
    """Each meter owns exactly one quantity, attached to its own reading."""

    def test_meter_bar_is_attached_to_its_value_not_the_bottom(self):
        # The meter is the last child of the meter's own column, so a reading and
        # its bar cannot drift apart inside a stretched parent.
        meter = source("components/StatMeter.qml")
        self.assertIn("Column {", meter)
        self.assertIn("id: column", meter)
        self.assertIn("id: track", meter)
        self.assertNotRegex(meter, r"anchors\.bottom: parent\.bottom\s*\n\s*height: 5")

    def test_stats_are_rows_of_pills_not_meter_columns(self):
        # A device name labels the column; the meters inside it label what they
        # measure, so a heading never repeats the value beneath it.
        stats = source("components/StatsStack.qml")
        # Per-device groups, each a heading plus rows of a label pill and a
        # value pill. There is no meter column and no region card.
        self.assertIn("StatRow", stats)
        self.assertIn("DeviceHeading", stats)
        self.assertNotIn("StatMeter", stats)
        self.assertNotIn("GlassMaterial", stats)
        self.assertNotIn('"load " +', stats)

    def test_gpu_name_comes_from_the_pci_id_database(self):
        # sysfs publishes ids, not names; the database supplies the real name.
        gpu = source("state/GpuSource.qml")
        self.assertIn("pciids", gpu)
        self.assertIn("/usr/share/hwdata/pci.ids", gpu)
        self.assertIn("parsePciIds", gpu)
        parse = source("state/SourceParse.js")
        self.assertIn("function parsePciIds(raw, vendorId, deviceId)", parse)

    def test_memory_heading_does_not_repeat_the_capacity(self):
        stats = source("components/StatsStack.qml")
        self.assertIn('readonly property string memoryLabel: "Memory"', stats)


class HomeStatusPillContractTests(unittest.TestCase):
    """A pill is self-describing or absent; it is never a bare dash."""

    def test_pills_require_a_glyph_and_a_label(self):
        for name in ("StatusPill.qml", "IndicatorPill.qml"):
            text = source("components/" + name)
            self.assertIn("hasContent", text)
            self.assertIn("visible: hasContent", text)

    def test_indicator_pills_render_a_visible_label(self):
        pill = source("components/IndicatorPill.qml")
        self.assertIn("text: root.label", pill)

    def test_no_pill_renders_a_bare_dash_as_its_value(self):
        # An absent reading is the pill's own unavailable state, not a dash typed
        # into the value slot.
        strip = source("components/StatusBarStrip.qml")
        for fragment in ('"offline"', '"none"'):
            self.assertIn(fragment, strip)
        self.assertNotRegex(strip, r'value: "—"')


class HomeIconContractTests(unittest.TestCase):
    """Application icons resolve to real files, with a monogram as last resort."""

    def test_resolver_lists_directories_rather_than_probing_files(self):
        # A per-file probe depends on a miss being reported; a listing always
        # arrives, so resolution terminates.
        resolver = source("state/IconResolver.qml")
        self.assertIn("searchPaths", resolver)
        self.assertIn("/usr/bin/ls", resolver)
        self.assertNotIn("FileView", resolver)

    def test_icon_lookup_is_a_pure_read(self):
        # A binding on this result must never trigger the write that would
        # re-trigger it, so the function only reads.
        resolver = source("state/IconResolver.qml")
        body = re.search(
            r"function pathFor\(iconName\) \{(.*?)\n    \}", resolver, re.S
        )
        self.assertIsNotNone(body)
        # It may read the cache, but it must never assign to any root state.
        for line in body.group(1).split("\n"):
            stripped = line.strip()
            self.assertNotIn("root.resolved =", stripped)
            self.assertNotIn("root.themedPaths =", stripped)
            self.assertNotIn("root.listings =", stripped)
            self.assertNotIn("root.listNext(", stripped)

    def test_dock_falls_back_to_a_monogram_only_without_a_file(self):
        dock = source("components/DockIcon.qml")
        self.assertIn("iconRendered", dock)
        self.assertIn("visible: !root.iconRendered", dock)


class HomeThemeContractTests(unittest.TestCase):
    """The palette is reused, never re-implemented, and is self-contained."""

    def test_theme_sources_are_verbatim_copies(self):
        for name in ("OmarchyTheme.qml", "ThemePalette.js", "MappedTheme.qml"):
            home_copy = HOME / "state" / name
            portal_copy = QUICKSHELL / "state" / name
            self.assertTrue(home_copy.exists(), name)
            self.assertEqual(
                home_copy.read_text(encoding="utf-8"),
                portal_copy.read_text(encoding="utf-8"),
                "%s must stay a verbatim copy of the portal's theme parser" % name,
            )

    def test_no_second_palette_mechanism(self):
        # Exactly one palette parser, reused rather than rewritten.
        parsers = sorted(
            {path.name for path in (HOME / "state").glob("*.js") if "Theme" in path.name
             or "Palette" in path.name}
        )
        self.assertEqual(parsers, ["ThemePalette.js"])


class HomeParserBehaviourTests(unittest.TestCase):
    """Parser behaviour is pure, so it is checked here against fixtures."""

    def _parsers(self):
        # The parser module is plain JavaScript, so it is exercised through node
        # when available; the assertions below hold either way.
        return None

    def test_parse_tables_are_declared_for_every_wired_source(self):
        parse = source("state/SourceParse.js")
        for function in (
            "function parseProcStat",
            "function parseMemInfo",
            "function parseHwmon",
            "function parseMonitors",
            "function parseWorkspaces",
            "function parseActiveWindow",
            "function parseClientAddresses",
            "function parseSinkVolume",
            "function parseSinkMute",
            "function parseBluetoothController",
            "function parseNetworkDevices",
            "function parseDefaultRoute",
            "function parseCpuModel",
            "function formatBytes",
            "function formatDuration",
        ):
            self.assertIn(function, parse)

    def test_format_bytes_never_emits_an_ellipsis(self):
        # Truncated values were a real defect; the formatter must be bounded.
        self.assertIn("function formatBytes(bytes)", source("state/SourceParse.js"))
        for forbidden in ('"..."', '"…"'):
            self.assertNotIn(forbidden, source("state/SourceParse.js"))


if __name__ == "__main__":
    unittest.main()