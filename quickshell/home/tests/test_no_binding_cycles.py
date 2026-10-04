"""Structural guards against QML binding cycles and silent gates.

A binding cycle is evaluated once by QML and never recovers, so a property that
reads a value derived from itself settles permanently on its initial value. When
that property is an identity gate, the surface silently never appears — which is
indistinguishable, to a user and to a unit test, from a screen with nothing to
show.

These tests catch the whole class rather than one instance: any property that
reads its own derived value through a conditional on itself fails.
"""

import pathlib
import re
import unittest


HOME = pathlib.Path(__file__).resolve().parents[1]
SHELL = HOME / "shell.qml"

# `property <type> name: <expression>`, allowing multi-line expressions.
DECLARATION = re.compile(
    r"^\s*(?:readonly\s+)?property\s+[A-Za-z]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*:",
    re.M,
)
BODY = re.compile(
    r"^\s*(?:readonly\s+)?property\s+[A-Za-z]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*:",
    re.M,
)


def declarations(text: str):
    """Yields (name, expression) for every property binding in a QML file."""
    matches = list(DECLARATION.finditer(text))
    for index, match in enumerate(matches):
        start = match.end()
        # The expression runs to the start of the next declaration, or to the end
        # of the file. Line-based, which is enough for these bindings.
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        yield match.group(1), text[start:end]


def referenced(expression: str, name: str) -> bool:
    """Whether an expression reads `name` from the enclosing root object."""
    return bool(re.search(r"root\.%s\b" % re.escape(name), expression)) or bool(
        re.search(r"(?<![\w.])%s\b" % re.escape(name), expression)
    )


class NoBindingCycleTests(unittest.TestCase):
    def setUp(self):
        self.shell = SHELL.read_text(encoding="utf-8")
        self.decls = list(declarations(self.shell))

    def test_the_file_has_properties_to_check(self):
        self.assertGreater(len(self.decls), 10, "the guard is not seeing the file")

    def test_no_property_reads_itself(self):
        """The direct form: a property whose own expression names it."""
        offenders = [
            name for name, expression in self.decls if referenced(expression, name)
        ]
        self.assertEqual(
            offenders,
            [],
            "these properties read themselves and will settle on their initial "
            "value forever: %s" % offenders,
        )

    def test_no_property_is_derived_from_a_property_derived_from_it(self):
        """The indirect form that actually shipped: a gate that read the very
        property defined in terms of it.

        `serialGateOpen` read `targetScreens`, and `targetScreens` was defined as
        `serialGateOpen ? ... : []`. Neither mentions itself lexically, so the
        check above cannot see it. The guard walks the one-step derivation graph
        instead.
        """
        direct = {name: expression for name, expression in self.decls}
        offenders = []
        for name, expression in self.decls:
            for other, other_expression in self.decls:
                if other == name:
                    continue
                # Does this expression depend on `other`...
                if not referenced(expression, other):
                    continue
                # ...and is `other` itself derived from `name`?
                if referenced(other_expression, name):
                    offenders.append("%s -> %s" % (name, other))
        self.assertEqual(
            offenders,
            [],
            "mutually dependent properties, which QML evaluates once and never "
            "recovers: %s" % offenders,
        )

    def test_the_identity_gate_reads_screen_matches_not_target_screens(self):
        gate = dict(self.decls)["serialGateOpen"]
        self.assertIn("screenMatches", gate)
        self.assertNotIn(
            "targetScreens",
            gate,
            "serialGateOpen must not read the property defined from it",
        )

    def test_target_screens_is_the_gate_result(self):
        declared = dict(self.decls)["targetScreens"]
        self.assertIn("serialGateOpen", declared)
        self.assertIn("screenMatches", declared)


class GateRefusalIsObservableTests(unittest.TestCase):
    """A gate that fails closed silently is worse than no gate."""

    def setUp(self):
        self.shell = SHELL.read_text(encoding="utf-8")

    def test_a_refusal_reason_property_exists(self):
        self.assertIn("readonly property string refusalReason", self.shell)

    def test_every_failing_condition_names_itself(self):
        # Each condition must contribute a distinct, non-empty phrase.
        start = self.shell.index("function refusalReasonFor()")
        # The function body runs to the next top-level comment block.
        end = self.shell.index("// The gate itself lives in", start)
        body = self.shell[start:end]
        # Zero matches, several matches, unverifiable, contradicted, and an
        # unknown state must each be named.
        self.assertIn("no screen matches output", body)
        self.assertIn("screens match output", body)
        self.assertIn("unverifiable", body)
        self.assertIn("serial mismatch", body)
        # And the values that led to the refusal are included, not just the verdict.
        self.assertIn("root.targetSerial", body)
        self.assertIn("source.reportedSerial", body)

    def test_the_reason_is_logged(self):
        self.assertIn('logIdentity("no surface: " + reason)', self.shell)

    def test_logging_is_deduplicated_so_a_steady_refusal_is_not_spammed(self):
        self.assertIn("lastReportedRefusal", self.shell)
        self.assertIn("if (reason === root.lastReportedRefusal)", self.shell)

    def test_preview_mode_never_reports_an_identity_refusal(self):
        self.assertIn('if (root.previewMode)\n            return ""', self.shell)

    def test_binding_never_logs_a_refusal(self):
        # A successful bind is logged too, so silence is never ambiguous.
        self.assertIn("surface bound:", self.shell)


if __name__ == "__main__":
    unittest.main()