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


def run_parse_js(script: str):
    """Runs a snippet with SourceParse.js loaded as `Parse`."""
    prelude = (
        'const fs = require("fs");\n'
        'const src = fs.readFileSync(process.argv[1], "utf8")'
        '  .replace(/^\\.pragma library\\n/, "");\n'
        'const mod = {exports: {}};\n'
        'new Function("module", "exports",'
        ' src + "\\nmodule.exports={parseMonitorSerial,serialVerdict};")(mod, mod.exports);\n'
        'const Parse = mod.exports;\n'
    )
    result = subprocess.run(
        ["node", "-e", prelude + script, str(STATE / "SourceParse.js")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr.strip())
    return json.loads(result.stdout.strip())


def run_js(script: str):
    prelude = (
        'const fs = require("fs");\n'
        'const src = fs.readFileSync(process.argv[1], "utf8")'
        '  .replace(/^\\.pragma library\\n/, "");\n'
        'const mod = {exports: {}};\n'
        'const names = "identityConfigured,screenMatches,matchingScreens,'
        'targetScreen,refusalReason,screenList";\n'
        'new Function("module", "exports", src + "\\nmodule.exports={" + names + "};")'
        '(mod, mod.exports);\n'
        'const S = mod.exports;\n'
    )
    result = subprocess.run(
        ["node", "-e", prelude + script, str(STATE / "ScreenIdentity.js"), str(STATE / "SourceParse.js"), str(STATE / "SourceParse.js")],
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


# The shape `Quickshell.screens` really has on this build: indexed and with a
# numeric `length`, but not a JavaScript Array.
FOREIGN_ARRAY_SETUP = """
function makeForeign(list) {
    const holder = {length: list.length};
    for (let i = 0; i < list.length; i++) holder[i] = list[i];
    return holder;
}
const FA = makeForeign(%s);
const IS_FOREIGN = Array.isArray(FA) === false && FA.constructor.name !== "Array";
"""


@unittest.skipUnless(node_available(), "node is not available")
class ForeignArrayTests(unittest.TestCase):
    """The list normaliser must not require a real JavaScript Array.

    A unit test built on a literal `[]` can never reproduce this defect, so
    every case here runs against an object shaped the way Qt exposes
    `Quickshell.screens`.
    """

    def run_with(self, prelude: str, script: str):
        return run_js(prelude + script)

    def test_the_fixture_really_is_not_a_javascript_array(self):
        # Guards the guard: if this ever stops being foreign, the tests below
        # would stop testing anything.
        out = run_js(
            FOREIGN_ARRAY_SETUP % json.dumps([EDGE])
            + "console.log(JSON.stringify([IS_FOREIGN, FA.length, FA[0].name]));"
        )
        self.assertEqual(out, [True, 1, "DP-3"])

    def test_foreign_screen_list_still_matches_the_edge(self):
        out = run_js(
            FOREIGN_ARRAY_SETUP % json.dumps([LG, EDGE, HDMI])
            + "console.log(JSON.stringify(S.targetScreen(FA, %s)));" % json.dumps(IDENTITY)
        )
        self.assertEqual(out, EDGE)

    def test_foreign_screen_list_refuses_on_ambiguity(self):
        out = run_js(
            FOREIGN_ARRAY_SETUP % json.dumps([EDGE, dict(EDGE)])
            + "console.log(JSON.stringify(S.targetScreen(FA, %s)));" % json.dumps(IDENTITY)
        )
        self.assertIsNone(out)

    def test_screen_list_normalises_all_four_shapes_identically(self):
        foreign, plain, nullish, missing = run_js(
            FOREIGN_ARRAY_SETUP % json.dumps([EDGE, LG])
            + "const PLAIN = %s;\n" % json.dumps([EDGE, LG])
            + "console.log(JSON.stringify(["
            "  S.screenList(FA),"
            "  S.screenList(PLAIN),"
            "  S.screenList(null),"
            "  S.screenList(undefined)"
            "]));"
        )
        self.assertEqual(foreign, plain)
        self.assertEqual(nullish, [])
        self.assertEqual(missing, [])
        self.assertEqual(foreign, [EDGE, LG])

    def test_screen_list_rejects_values_with_no_usable_length(self):
        script = (
            "console.log(JSON.stringify(["
            "S.screenList({}),"
            "S.screenList({length: -1}),"
            "S.screenList({length: 'nope'})"
            "]));"
        )
        self.assertEqual(run_js(script), [[], [], []])

    def test_the_previous_isarray_implementation_fails_on_a_foreign_list(self):
        # The old implementation, verbatim, run against the real shape.
        script = (
            FOREIGN_ARRAY_SETUP % json.dumps([EDGE])
            + "function oldMatching(screens, identity) {\n"
            "  if (!S.identityConfigured(identity)) return [];\n"
            "  var list = Array.isArray(screens) ? screens : [];\n"
            "  var matches = [];\n"
            "  for (var i = 0; i < list.length; i++)\n"
            "    if (S.screenMatches(list[i], identity)) matches.push(list[i]);\n"
            "  return matches;\n"
            "}\n"
            "console.log(JSON.stringify(oldMatching(FA, %s)));" % json.dumps(IDENTITY)
        )
        self.assertEqual(
            run_js(script),
            [],
            "the old implementation unexpectedly matched a foreign list",
        )


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

    def test_the_gate_never_gates_on_a_javascript_array_type(self):
        """`Quickshell.screens` is a foreign array. Any isArray/instanceof check
        on a Quickshell-exposed list silently collapses it to empty."""
        gate = (STATE / "ScreenIdentity.js").read_text(encoding="utf-8")
        body = gate[gate.index("function screenList"):]
        self.assertNotIn("Array.isArray", body)
        self.assertNotIn("instanceof Array", body)
        self.assertNotIn(".constructor", gate)

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
        # The live panel geometry is documented, in either notation.
        self.assertTrue(
            "960x270" in docs or "960×270" in docs,
            "the live 960x270 logical geometry must be documented",
        )


if __name__ == "__main__":
    unittest.main()
