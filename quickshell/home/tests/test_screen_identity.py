"""The live screen-identity gate, executed.

This gate is the one rule that decides whether the dashboard is ever shown. It
cannot be verified by reading, because the bug it had rendered perfectly in
preview and could never bind on a real compositor. So it lives in a pure helper
and is executed here against realistic Hyprland screen objects.

The screen fixtures below are the exact property set Qt publishes for Hyprland's
`wl_output`: `name` and `model` populated, `serialNumber` an empty string for
*every* screen, and `manufacturer` / `description` / `logicalWidth` /
`logicalHeight` / `scale` / `virtual` undefined.
"""

import json
import pathlib
import re
import subprocess
import unittest


HOME = pathlib.Path(__file__).resolve().parents[1]
STATE = HOME / "state"


def node_available() -> bool:
    try:
        return subprocess.run(
            ["node", "--version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def run_js(script: str):
    prelude = (
        'const fs = require("fs");\n'
        'const src = fs.readFileSync(process.argv[1], "utf8")'
        '  .replace(/^\\.pragma library\\n/, "");\n'
        'const mod = {exports: {}};\n'
        'const names = "identityConfigured,screenMatches,matchingScreens,'
        'targetScreen,refusalReason";\n'
        'new Function("module", "exports", src + "\\nmodule.exports={" + names + "};")'
        '(mod, mod.exports);\n'
        'const S = mod.exports;\n'
    )
    result = subprocess.run(
        ["node", "-e", prelude + script, str(STATE / "ScreenIdentity.js")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr.strip())
    return json.loads(result.stdout.strip())


# The real Hyprland XENEON EDGE, as Qt publishes it.
EDGE = {
    "name": "DP-3",
    "model": "XENEON EDGE",
    "serialNumber": "",
    "manufacturer": None,
    "description": None,
    "logicalWidth": None,
    "logicalHeight": None,
    "scale": None,
    "virtual": None,
    "width": 960,
    "height": 270,
    "devicePixelRatio": 3,
}
LG = {
    "name": "DP-1",
    "model": "LG HDR 4K",
    "serialNumber": "",
    "width": 1920,
    "height": 1080,
}
HDMI = {
    "name": "HDMI-A-1",
    "model": "HDMI",
    "serialNumber": "",
    "width": 600,
    "height": 960,
}

IDENTITY = {"output": "DP-3", "model": "XENEON EDGE", "serial": "035926215698"}


@unittest.skipUnless(node_available(), "node is not available")
class ScreenIdentityTests(unittest.TestCase):
    def matches(self, screens, identity=IDENTITY):
        return run_js(
            "console.log(JSON.stringify(S.matchingScreens(%s, %s)));"
            % (json.dumps(screens), json.dumps(identity))
        )

    def test_real_hyprland_edge_matches_despite_an_empty_serial(self):
        """The live case. Hyprland publishes no serial, so requiring one made
        the gate unsatisfiable and the surface could never bind."""
        self.assertEqual(self.matches([EDGE]), [EDGE])

    def test_wrong_model_does_not_match(self):
        other = dict(EDGE, model="Some Other Panel")
        self.assertEqual(self.matches([other]), [])

    def test_wrong_output_name_does_not_match(self):
        other = dict(EDGE, name="DP-9")
        self.assertEqual(self.matches([other]), [])

    def test_a_name_match_alone_is_never_sufficient(self):
        # Same output name, wrong model: must still refuse.
        self.assertEqual(self.matches([dict(EDGE, model="Other")]), [])

    def test_non_empty_mismatched_serial_is_refused(self):
        # The case the previous code did get right, and must not regress.
        other = dict(EDGE, serialNumber="DEADBEEF")
        self.assertEqual(self.matches([other]), [])

    def test_non_empty_matching_serial_is_accepted(self):
        # A compositor that does expose a serial is still compared exactly.
        other = dict(EDGE, serialNumber="035926215698")
        self.assertEqual(self.matches([other]), [other])

    def test_two_identical_matches_are_ambiguous(self):
        found = run_js(
            "console.log(JSON.stringify(S.targetScreen(%s, %s)));"
            % (json.dumps([EDGE, dict(EDGE)]), json.dumps(IDENTITY))
        )
        self.assertIsNone(found)

    def test_zero_matches_produce_no_surface(self):
        found = run_js(
            "console.log(JSON.stringify(S.targetScreen(%s, %s)));"
            % (json.dumps([LG, HDMI]), json.dumps(IDENTITY))
        )
        self.assertIsNone(found)

    def test_one_match_produces_exactly_that_surface(self):
        found = run_js(
            "console.log(JSON.stringify(S.targetScreen(%s, %s)));"
            % (json.dumps([LG, EDGE, HDMI]), json.dumps(IDENTITY))
        )
        self.assertEqual(found, EDGE)

    def test_incomplete_identity_never_matches(self):
        # All three components are required; dropping any one is unsatisfiable.
        for broken in (
            {"output": "", "model": "XENEON EDGE", "serial": "035926215698"},
            {"output": "DP-3", "model": "", "serial": "035926215698"},
            {"output": "DP-3", "model": "XENEON EDGE", "serial": ""},
        ):
            self.assertEqual(self.matches([EDGE], broken), [])

    def test_a_screen_with_no_area_is_never_a_surface(self):
        self.assertEqual(self.matches([dict(EDGE, width=0)]), [])

    def test_refusal_reason_is_logged_for_every_failure(self):
        for screens, needle in (
            ([EDGE, dict(EDGE)], "screens match"),
            ([LG, HDMI], "no screen"),
        ):
            reason = run_js(
                "console.log(JSON.stringify(S.refusalReason(%s, %s)));"
                % (json.dumps(screens), json.dumps(IDENTITY))
            )
            self.assertIn(needle, reason)

    def test_no_primary_or_first_screen_fallback_exists(self):
        """A near-miss must not resolve to some other screen."""
        found = run_js(
            "console.log(JSON.stringify(S.targetScreen(%s, %s)));"
            % (json.dumps([LG, HDMI, dict(EDGE, model="Other")]), json.dumps(IDENTITY))
        )
        self.assertIsNone(found)


@unittest.skipUnless(node_available(), "node is not available")
class OldPredicateRegressionTests(unittest.TestCase):
    """Proves the fix was necessary: the previous predicate fails these."""

    def test_the_previous_predicate_would_refuse_the_real_edge(self):
        # The predicate as it was, verbatim.
        previous = (
            'function oldPredicate(screen, identity) {\n'
            '  if (screen === null || screen === undefined) return false;\n'
            '  var runtimeSerial = String(screen.serialNumber || "");\n'
            '  if (runtimeSerial === "" || runtimeSerial !== identity.serial)\n'
            '    return false;\n'
            '  return String(screen.name || "") === identity.output;\n'
            '}\n'
        )
        script = (
            previous
            + "console.log(JSON.stringify(oldPredicate(%s, %s)));"
            % (json.dumps(EDGE), json.dumps(IDENTITY))
        )
        self.assertFalse(run_js(script), "the old predicate unexpectedly passed")

    def test_the_previous_predicate_made_the_gate_unsatisfiable(self):
        previous = (
            'function oldPredicate(screen, identity) {\n'
            '  var runtimeSerial = String(screen.serialNumber || "");\n'
            '  if (runtimeSerial === "" || runtimeSerial !== identity.serial)\n'
            '    return false;\n'
            '  return true;\n'
            '}\n'
            "console.log(JSON.stringify(oldPredicate(%s, %s)));"
            % (json.dumps(EDGE), json.dumps(IDENTITY))
        )
        self.assertFalse(run_js(previous))


class ScreenIdentitySourceTests(unittest.TestCase):
    """Structural guarantees that do not need node."""

    def test_shell_uses_the_shared_predicate(self):
        shell = (HOME / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("ScreenIdentity.targetScreen", shell)
        self.assertIn("ScreenIdentity.matchingScreens", shell)
        # The unsatisfiable form must not survive anywhere.
        self.assertNotIn('runtimeSerial === "" ||', shell)

    def test_serial_variable_is_still_required(self):
        shell = (HOME / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("XENEON_HOME_SERIAL", shell)
        self.assertIn("XENEON_HOME_MODEL", shell)
        self.assertIn("XENEON_HOME_OUTPUT", shell)
        helper = (STATE / "ScreenIdentity.js").read_text(encoding="utf-8")
        self.assertIn('String(record.serial || "") !== ""', helper)

    def test_no_primary_or_first_screen_fallback_in_source(self):
        shell = (HOME / "shell.qml").read_text(encoding="utf-8")
        for forbidden in ("Quickshell.screens[0]", "primaryScreen", "defaultScreen"):
            self.assertNotIn(forbidden, shell)

    def test_only_properties_hyprland_publishes_are_read(self):
        """The gate may only read properties Qt actually supplies on
        Hyprland: name, model, serialNumber, width and height."""
        helper = (STATE / "ScreenIdentity.js").read_text(encoding="utf-8")
        read = set(re.findall(r"screen\.([A-Za-z_]+)", helper))
        self.assertEqual(
            read,
            {"name", "width", "height", "serialNumber", "model"},
            "the gate reads a screen property Hyprland does not publish",
        )

    def test_960x270_is_a_verified_size(self):
        shell = (HOME / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("XENEON_HOME_PREVIEW_SIZE", shell)
        docs = (HOME.parent.parent / "docs" / "home-dashboard.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("960x270", docs)


if __name__ == "__main__":
    unittest.main()
