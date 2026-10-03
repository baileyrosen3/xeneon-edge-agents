"""Behavioural tests for the home dashboard's safety boundary.

The contract suite proves that the *shape* of the code is right. These tests
instead execute the validators against hostile inputs and assert refusal, which
is what actually matters: a validator that is never called cannot be proven
correct by reading it.

The pure JavaScript modules are executed through node when it is available, and
skipped with a clear reason when it is not, so the suite stays deterministic
and free of any dependency on this host's live state.
"""

import json
import os
import pathlib
import re
import subprocess
import unittest


HOME = pathlib.Path(__file__).resolve().parents[1]
STATE = HOME / "state"


def node_available() -> bool:
    """Whether node can actually be executed.

    This is evaluated when the skip decorators are applied, at import time, so a
    missing binary has to return False rather than raise: an exception here
    escapes module import and the whole file errors instead of skipping.
    """
    try:
        return subprocess.run(
            ["node", "--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def run_js(script: str):
    """Runs a JavaScript snippet with the config's own modules in scope.

    The modules are loaded from the source tree by path and their export names
    are resolved from the module itself, so the harness cannot drift out of step
    with the code it is testing. Nothing is written into the source tree.
    """
    # The module body assigns to its own `module.exports`, so the container is
    # passed in as an argument rather than relying on Node's own module object.
    prelude = (
        'const fs = require("fs");\n'
        'function load(path, names) {\n'
        '  const src = fs.readFileSync(path, "utf8").replace(/^\\.pragma library\\n/, "");\n'
        '  const mod = {exports: {}};\n'
        '  const run = new Function("module", "exports", src + "\\nmodule.exports={" + names + "};");\n'
        '  run(mod, mod.exports);\n'
        '  return mod.exports;\n'
        '}\n'
        'const Actions = load(process.argv[1], process.argv[2]);\n'
        'const Parse = load(process.argv[3], "parsePciIds,parseDefaultRoute,parseMemInfo");\n'
    )
    result = subprocess.run(
        [
            "node",
            "-e",
            prelude + script,
            str(STATE / "HomeActions.js"),
            ", ".join(action_exports()),
            str(STATE / "SourceParse.js"),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr.strip())
    return json.loads(result.stdout.strip())


def action_exports():
    # The top-level function declarations of HomeActions.js.
    text = (STATE / "HomeActions.js").read_text(encoding="utf-8")
    return sorted(set(re.findall(r"^function ([A-Za-z0-9_]+)", text, re.M)))


@unittest.skipUnless(node_available(), "node is not available")
class ActionBoundaryBehaviourTests(unittest.TestCase):
    """Hostile inputs are refused. These execute the real validators."""

    @classmethod
    def setUpClass(cls):
        action_exports()
        cls.context = json.dumps(
            {
                # A window address that genuinely exists in the snapshot, and the
                # track length every seek is bounded against.
                "windows": ["0x5dea5c227e60"],
                "lengthSeconds": 180.0,
            }
        )

    def call(self, action, parameter=None, context=None):
        ctx = context if context is not None else self.context
        script = (
            'const out = Actions.plan(%s, %s, %s);\n'
            "console.log(JSON.stringify(out));\n" % (json.dumps(action), json.dumps(parameter), ctx)
        )
        return run_js(script)

    def test_launcher_id_carrying_a_shell_is_not_allowlisted(self):
        # A hostile "action id" must not reach argv, and must not fall through to
        # any default either.
        for hostile in (
            "launch.terminal; rm -rf /",
            "launch.terminal && id",
            "$(id)",
            "launch.terminal|nc",
        ):
            result = self.call(hostile)
            self.assertNotIn("argv", result, hostile)
            self.assertIn("error", result, hostile)

    def test_known_launcher_resolves_only_to_its_fixed_argv(self):
        result = self.call("launch.terminal")
        self.assertEqual(result.get("argv"), ["/usr/bin/foot"])

    def test_window_address_absent_from_the_snapshot_is_refused(self):
        # An address that the compositor never published must not be accepted,
        # even though it is well formed.
        result = self.call("window.focus", "0xdeadbeef")
        self.assertNotIn("argv", result)

    def test_window_address_from_the_snapshot_is_accepted(self):
        result = self.call("window.focus", "0x5dea5c227e60")
        self.assertEqual(result.get("argv", [])[-1], "address:0x5dea5c227e60")

    def test_window_address_with_injection_is_refused(self):
        for hostile in ("0x1;id", "0x1&id", "$(id)", "0x1`id`"):
            result = self.call("window.focus", hostile)
            self.assertNotIn("argv", result, hostile)

    def test_workspace_outside_the_bounded_range_is_refused(self):
        for hostile in (0, -1, 999, 2.5, "1;id"):
            result = self.call("workspace.focus", hostile)
            self.assertNotIn("argv", result, hostile)

    def test_media_seek_beyond_the_track_is_refused(self):
        result = self.call("media.seek", 9999.0)
        self.assertNotIn("method", result)

    def test_media_seek_within_the_track_is_accepted(self):
        result = self.call("media.seek", 12.5)
        self.assertEqual(result.get("method"), "seek")
        self.assertEqual(result.get("parameter"), 12.5)

    def test_media_method_is_never_caller_named(self):
        # Only the table decides which MPRIS method runs.
        result = self.call("media.toggle", "exec")
        self.assertNotIn("argv", result)

    def test_tray_item_not_in_the_snapshot_is_refused(self):
        result = run_js(
            'const out = Actions.planTray("tray.activate", "no-such-item", '
            '{"entries": [{"id": "other"}]});\nconsole.log(JSON.stringify(out));\n'
        )
        self.assertIn("error", result)

    def test_tray_method_is_constrained_to_the_allowlist(self):
        result = run_js(
            'const out = Actions.planTray("tray.activate", "ok", '
            '{"entries": [{"id": "ok"}]});\nconsole.log(JSON.stringify(out));\n'
        )
        self.assertEqual(result.get("method"), "activate")


@unittest.skipUnless(node_available(), "node is not available")
class ProbeArgvBehaviourTests(unittest.TestCase):
    """Every probe argv in every source must actually pass validation.

    This is the check that would have caught the `DEVICE,TYPE,STATE` rejection:
    a comma is an ordinary character, and a probe carrying one must still run.
    """

    def validator_body(self) -> str:
        text = (STATE / "SourceBase.qml").read_text(encoding="utf-8")
        start = text.index("function validArgv(argv)")
        end = text.index("function acceptProbes", start)
        return text[start:end]

    def test_every_declared_probe_argv_passes_validation(self):
        # Collect every argv literal declared by a source and run it through the
        # real validator.
        body = self.validator_body()
        script = (
            body.replace("validArg(value)", "validArg(value)")
            + "\nconst results = [];\n"
        )
        found = 0
        for path in sorted(STATE.glob("*Source.qml")):
            text = path.read_text(encoding="utf-8")
            for argv in re.findall(r'"argv": \[([^\]]*)\]', text):
                elements = re.findall(r'"([^"]*)"', argv)
                if not elements:
                    continue
                found += 1
                probe = json.dumps(elements)
                script += (
                    "results.push({file: %s, argv: %s, ok: validArgv(%s)});\n"
                    % (json.dumps(path.name), probe, probe)
                )
        self.assertGreater(found, 0, "no probe argv found to check")
        script += "console.log(JSON.stringify(results));\n"
        results = run_js(script)
        for entry in results:
            self.assertTrue(
                entry["ok"],
                "%s declares an argv the validator refuses: %s"
                % (entry["file"], entry["argv"]),
            )

    def test_validator_accepts_a_comma_bearing_field_specification(self):
        script = (
            self.validator_body()
            + "\nconsole.log(JSON.stringify(validArg('DEVICE,TYPE,STATE')));\n"
        )
        self.assertTrue(run_js(script))

    def test_validator_refuses_shell_constructs(self):
        body = self.validator_body()
        script = body + "\nconst out=[];\n"
        for hostile in (";rm -rf /", "a;b", "a|b", "$(id)", "`id`", "a>b", "a*b", "a\nb"):
            script += "out.push(validArg(%s));\n" % json.dumps(hostile)
        script += "console.log(JSON.stringify(out));\n"
        for accepted in run_js(script):
            self.assertFalse(accepted, "a shell construct was accepted")


class DispatcherStructureTests(unittest.TestCase):
    """Structural guarantees that a text-reading test can still establish."""

    def test_every_dispatcher_process_has_a_watchdog(self):
        # A Process with no watchdog can hold a single-flight lock forever.
        dispatcher = (STATE / "ActionDispatcher.qml").read_text(encoding="utf-8")
        self.assertIn("property Timer watchdog", dispatcher)
        self.assertIn("actionWatchdog.restart()", dispatcher)
        self.assertIn("actionWatchdog.stop()", dispatcher)
        self.assertIn("function releaseLock(reason)", dispatcher)

    def test_launchers_are_detached_and_never_take_the_lock(self):
        actions = (STATE / "HomeActions.js").read_text(encoding="utf-8")
        dispatcher = (STATE / "ActionDispatcher.qml").read_text(encoding="utf-8")
        launchers = re.findall(
            r'"(launch\.[a-z_]+)": \{\n        "kind": "launch",\n        "detached": true,',
            actions,
        )
        self.assertGreaterEqual(len(launchers), 4)
        self.assertIn("Quickshell.execDetached(argv)", dispatcher)

    def test_presence_probe_is_guarded_by_the_probed_map(self):
        # Checking `presence` instead of `probed` meant the probe never ran.
        dispatcher = (STATE / "ActionDispatcher.qml").read_text(encoding="utf-8")
        queue = re.search(
            r"function queueProbe\(actionId\) \{(.*?)\n    \}", dispatcher, re.S
        )
        self.assertIsNotNone(queue)
        self.assertIn("root.probed", queue.group(1))

    def test_source_probe_settles_through_one_guarded_exit(self):
        base = (STATE / "SourceBase.qml").read_text(encoding="utf-8")
        self.assertIn("function settleProbe(exitCode, timeoutReason)", base)
        self.assertIn("if (root.probeSettled)", base)

    def test_icon_listing_has_a_watchdog(self):
        resolver = (STATE / "IconResolver.qml").read_text(encoding="utf-8")
        self.assertIn("listingWatchdog", resolver)
        self.assertIn("function settle(found", resolver)

    def test_meter_reading_is_derived_from_the_measurement(self):
        meter = (HOME / "components" / "StatMeter.qml").read_text(encoding="utf-8")
        match = re.search(
            r"readonly property bool hasReading:(.*?):\s*root\.percent", meter, re.S
        )
        self.assertIsNotNone(match)
        # The deciding expression must be the measurement, never a display string.
        self.assertNotIn("capacityLabel", match.group(1))

    def test_artwork_is_restricted_to_local_sources(self):
        card = (HOME / "components" / "NowPlayingCard.qml").read_text(encoding="utf-8")
        self.assertIn("function localOnly(artUrl)", card)
        self.assertIn("source: root.localArtUrl", card)

    def test_tray_logs_only_on_change(self):
        tray = (STATE / "TraySource.qml").read_text(encoding="utf-8")
        self.assertIn("lastSignature", tray)

    def test_media_rebuild_is_gated_on_a_registered_player(self):
        media = (STATE / "MediaSource.qml").read_text(encoding="utf-8")
        rebuild = re.search(r"function rebuild\(\) \{(.*?)\n    \}", media, re.S)
        self.assertIsNotNone(rebuild)
        self.assertIn("root.players.length === 0", rebuild.group(1))

    def test_live_panel_never_resolves_to_the_primary_display(self):
        panel = (HOME / "components" / "HomePanel.qml").read_text(encoding="utf-8")
        # A null screen resolves to the primary display, so the window stays
        # hidden until a verified screen has been supplied.
        self.assertIn("visible: root.modelData !== null", panel)
        self.assertIn("screen: root.modelData === null ? undefined : root.modelData", panel)

    def test_reduced_motion_reaches_the_live_surface(self):
        shell = (HOME / "shell.qml").read_text(encoding="utf-8")
        panel = (HOME / "components" / "HomePanel.qml").read_text(encoding="utf-8")
        self.assertIn("livePanel.item.reducedMotion = root.reducedMotion", shell)
        self.assertIn("property bool reducedMotion", panel)


if __name__ == "__main__":
    unittest.main()
