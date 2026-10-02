#!/usr/bin/env python3
"""Source-only session/lifecycle checks; all subprocesses use isolated stubs."""

import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class IsolatedCommands(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="xeneon-startup-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.log = self.root / "calls.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("XENEON_") and key not in (
                        "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DISPLAY")}
        self.env.update(XDG_RUNTIME_DIR=str(self.runtime),
                        WAYLAND_DISPLAY="wayland-test",
                        HYPRLAND_INSTANCE_SIGNATURE="fixture-session",
                        CALL_LOG=str(self.log),
                        XENEON_SYSTEMCTL=str(self.bin / "systemctl"),
                        XENEON_HYPRCTL=str(self.bin / "hyprctl"))
        self.stub("systemctl", r"""
import json, os, pathlib, sys, time
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps(['systemctl', *args]) + '\n')
if 'import-environment' in args:
    marker = pathlib.Path(os.environ['CALL_LOG'] + '.imported')
    marker.touch()
    if os.environ.get('IMPORT_DELAY'):
        time.sleep(float(os.environ['IMPORT_DELAY']))
    if os.environ.get('GATE_AFTER_IMPORT'):
        pathlib.Path(os.environ['XDG_RUNTIME_DIR'], 'xeneon-edge-agents-uninstalling').touch()
    if os.environ.get('FAIL_IMPORT'):
        sys.exit(1)
if 'start' in args and 'xeneon-edge-input.path' in args:
    if not pathlib.Path(os.environ['CALL_LOG'] + '.imported').exists():
        sys.exit(2)
    if os.environ.get('FAIL_WATCHER'):
        sys.exit(1)
if 'is-active' in args and os.environ.get('INACTIVE_WATCHER'):
    sys.exit(3)
""")
        self.stub("hyprctl", r"""
import json, os, sys
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps(['hyprctl', *sys.argv[1:]]) + '\n')
if os.environ.get('FAIL_HYPR'):
    sys.exit(1)
print('[]')
""")

    def stub(self, name, source):
        target = self.bin / name
        target.write_text("#!/usr/bin/python3\n" + source)
        target.chmod(0o755)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def run_helper(self, name="xeneon-edge-session", **changes):
        return subprocess.run([str(REPO / "config/bin" / name)],
                              env=self.env | changes, text=True,
                              capture_output=True, timeout=15)

    def wayland_socket(self):
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(self.runtime / "wayland-test"))
        self.addCleanup(sock.close)
        hypr = self.runtime / 'hypr/fixture-session'
        hypr.mkdir(parents=True)
        ipc = socket.socket(socket.AF_UNIX)
        ipc.bind(str(hypr / '.socket.sock'))
        self.addCleanup(ipc.close)


class SessionStartupTests(IsolatedCommands):
    def test_import_precedes_watcher_and_nonblocking_reconcile(self):
        self.wayland_socket()
        result = self.run_helper(DISPLAY=":test")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(calls[0][:3], ['systemctl', '--user', 'import-environment'])
        self.assertIn('WAYLAND_DISPLAY', calls[0])
        self.assertIn('HYPRLAND_INSTANCE_SIGNATURE', calls[0])
        self.assertIn('DISPLAY', calls[0])
        self.assertNotIn('CALL_LOG', calls[0])
        self.assertEqual(calls[1:], [
            ['systemctl', '--user', 'start', 'xeneon-edge-input.path'],
            ['systemctl', '--user', 'is-active', '--quiet', 'xeneon-edge-input.path'],
            ['systemctl', '--user', '--no-block', 'start', 'xeneon-edge-reconcile.service']])
        self.assertEqual((self.runtime / 'xeneon-edge-agents').stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.runtime / 'xeneon-edge-agents/session-start.lock').stat().st_mode & 0o777, 0o600)

    def test_early_module_load_is_harmless_without_session_variables(self):
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE')
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_late_compositor_socket_is_waited_for_before_import(self):
        thread = threading.Thread(target=lambda: (time.sleep(0.35), self.wayland_socket()))
        thread.start()
        result = self.run_helper()
        thread.join()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0][:3], ['systemctl', '--user', 'import-environment'])

    def test_unready_initial_load_does_not_hide_ready_session_start(self):
        self.wayland_socket()
        process = subprocess.Popen([str(REPO / 'config/bin/xeneon-edge-session')],
                                   env=self.env | {'WAYLAND_DISPLAY': 'not-ready'},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not (self.runtime / 'xeneon-edge-agents').exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue((self.runtime / 'xeneon-edge-agents').exists())
            self.assertEqual(self.run_helper().returncode, 0)
            self.assertIn(['systemctl', '--user', '--no-block', 'start',
                           'xeneon-edge-reconcile.service'], self.calls())
        finally:
            process.terminate()
            process.communicate(timeout=3)

    def test_failed_readiness_is_bounded_and_never_imports_or_starts(self):
        self.wayland_socket()
        (self.runtime / 'hypr/fixture-session/.socket.sock').unlink()
        start = time.monotonic()
        result = self.run_helper()
        self.assertEqual(result.returncode, 1)
        self.assertLess(time.monotonic() - start, 10)
        self.assertIn('within 8 seconds', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_unresponsive_monitor_query_never_blocks_watcher_start(self):
        self.wayland_socket()
        result = self.run_helper(FAIL_HYPR='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(call[0] == 'systemctl' for call in self.calls()))
        self.assertIn(['systemctl', '--user', 'start', 'xeneon-edge-input.path'], self.calls())
        self.assertIn(['systemctl', '--user', '--no-block', 'start',
                       'xeneon-edge-reconcile.service'], self.calls())
        self.assertFalse(any('xeneon-agentd.service' in call or 'xeneon-edge-portal.service' in call
                             for call in self.calls()))

    def test_import_or_watcher_failure_never_requests_reconcile(self):
        self.wayland_socket()
        for failure in ('FAIL_IMPORT', 'FAIL_WATCHER', 'INACTIVE_WATCHER'):
            with self.subTest(failure=failure):
                self.log.unlink(missing_ok=True)
                self.assertNotEqual(self.run_helper(**{failure: '1'}).returncode, 0)
                self.assertFalse(any('xeneon-edge-reconcile.service' in call for call in self.calls()))

    def test_existing_or_mid_import_gate_is_preserved(self):
        self.wayland_socket()
        gate = self.runtime / 'xeneon-edge-agents-uninstalling'
        gate.write_text('owned by installer')
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertEqual(gate.read_text(), 'owned by installer')
        gate.unlink()
        self.assertEqual(self.run_helper(GATE_AFTER_IMPORT='1').returncode, 0)
        self.assertTrue(gate.exists())
        self.assertFalse(any('start' in call for call in self.calls()))

    def test_concurrent_boot_and_reload_are_coalesced_and_later_reload_recovers(self):
        self.wayland_socket()
        process = subprocess.Popen([str(REPO / 'config/bin/xeneon-edge-session')],
                                   env=self.env | {'IMPORT_DELAY': '0.5'},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        deadline = time.monotonic() + 3
        while not Path(str(self.log) + '.imported').exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(Path(str(self.log) + '.imported').exists())
        self.assertEqual(self.run_helper().returncode, 0)
        _, errors = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, errors)
        self.assertEqual(sum('import-environment' in call for call in self.calls()), 1)
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(sum('import-environment' in call for call in self.calls()), 2)


class DisplayTouchLifecycleTests(IsolatedCommands):
    def setUp(self):
        super().setUp()
        self.sys = self.root / 'sys'
        self.drm = self.sys / 'class/drm/card0-DP-2'
        self.drm.mkdir(parents=True)
        self.edid = b'unique EDGE fixture EDID'
        (self.drm / 'edid').write_bytes(self.edid)
        (self.drm / 'status').write_text('connected\n')
        (self.sys / 'class/input').mkdir(parents=True)
        config = self.root / 'config/xeneon-edge-agents'
        config.mkdir(parents=True)
        (config / 'commissioning.toml').write_text(f'''mode = "production"
[output]
edid_sha256 = "{hashlib.sha256(self.edid).hexdigest()}"
serial = "TEST-EDGE-SERIAL"
model = "XENEON EDGE"
[touch]
device = "fixture-edge-touch-1"
bustype = "0003"
vendor = "1111"
product = "2222"
uniq = "TEST-TOUCH-UNIQ"
phys = "fixture/input0"
''')
        self.monitors = self.root / 'monitors.json'
        self.devices = self.root / 'devices.json'
        self.monitor = dict(id=2, name='DP-2', model='XENEON EDGE', serial='TEST-EDGE-SERIAL',
                            width=2560, height=720, disabled=False)
        self.write_monitors([self.monitor])
        self.devices.write_text(json.dumps({'touch': [{'name': 'fixture-edge-touch-1'},
                                                     {'name': 'internal-touch'}],
                                            'mice': [{'name': 'ordinary-mouse'}]}))
        self.env.update(XDG_CONFIG_HOME=str(self.root / 'config'),
                        XENEON_SYS_ROOT=str(self.sys),
                        XENEON_RUNTIME_DIR=str(self.runtime / 'xeneon-edge-agents'),
                        XENEON_HYPR_MONITORS_JSON=str(self.monitors),
                        XENEON_HYPR_DEVICES_JSON=str(self.devices))

    def write_monitors(self, monitors):
        self.monitors.write_text(json.dumps(monitors))

    def kernel_touch(self, event='event1'):
        device = self.sys / 'class/input' / event / 'device'
        (device / 'id').mkdir(parents=True)
        for key, value in {'name': 'fixture edge touch', 'id/bustype': '0003',
                           'id/vendor': '1111', 'id/product': '2222',
                           'uniq': 'TEST-TOUCH-UNIQ', 'phys': 'fixture/input0',
                           'properties': 'ID_INPUT_TOUCHSCREEN=1'}.items():
            (device / key).write_text(value + '\n')

    def assert_touch_only_disabled(self):
        calls = [call for call in self.calls() if call[:2] == ['hyprctl', 'eval']]
        self.assertTrue(calls)
        self.assertTrue(all(call[2] == 'hl.device({ name = "fixture-edge-touch-1", enabled = false })'
                            for call in calls))
        self.assertFalse(any('ordinary-mouse' in str(call) or 'internal-touch' in str(call)
                             for call in self.calls()))

    def assert_degraded(self):
        result = self.run_helper('xeneon-edge-reconcile')
        self.assertEqual(result.returncode, 0, result.stderr)
        runtime = Path(self.env['XENEON_RUNTIME_DIR'])
        self.assertEqual((runtime / 'screen.env').read_text(), 'XENEON_EDGE_OUTPUT=DP-2\n')
        self.assertIn('state=degraded', (runtime / 'lifecycle.status').read_text())
        self.assertIn(['systemctl', '--user', 'start', 'xeneon-agentd.service',
                       'xeneon-edge-portal.service'], self.calls())
        self.assert_touch_only_disabled()

    def test_active_display_starts_degraded_when_usb_touch_is_absent_or_ambiguous(self):
        self.assert_degraded()
        self.kernel_touch()
        self.kernel_touch('event2')
        self.log.unlink()
        self.assert_degraded()

    def test_healthy_touch_then_usb_loss_keeps_portal_and_disables_exact_touch(self):
        self.kernel_touch()
        result = self.run_helper('xeneon-edge-reconcile')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('state=running', (Path(self.env['XENEON_RUNTIME_DIR']) / 'lifecycle.status').read_text())
        self.assertIn(['hyprctl', 'eval', 'hl.device({ name = "fixture-edge-touch-1", output = "DP-2", enabled = true })'], self.calls())
        (self.sys / 'class/input/event1/device/uniq').write_text('OTHER-TOUCH\n')
        self.log.unlink()
        self.assert_degraded()

    def test_missing_ambiguous_and_invalid_hypr_touch_inventory_remain_degraded(self):
        self.kernel_touch()
        for touch in ([], [{'name': 'fixture-edge-touch-1'}, {'name': 'fixture-edge-touch'}], 'invalid'):
            with self.subTest(touch=touch):
                self.devices.write_text(json.dumps({'touch': touch}))
                self.log.unlink(missing_ok=True)
                self.assert_degraded()

    def test_disabled_inactive_or_wrong_display_never_starts_daemon_or_portal(self):
        self.kernel_touch()
        cases = [[], [self.monitor | {'disabled': True}], [self.monitor | {'id': -1}],
                 [self.monitor | {'width': 0}], [self.monitor | {'serial': 'WRONG'}],
                 [self.monitor, self.monitor]]
        for monitors in cases:
            with self.subTest(monitors=monitors):
                self.write_monitors(monitors)
                self.log.unlink(missing_ok=True)
                result = self.run_helper('xeneon-edge-reconcile')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((Path(self.env['XENEON_RUNTIME_DIR']) / 'screen.env').exists())
                self.assertFalse(any('start' in call for call in self.calls()))
                self.assert_touch_only_disabled()


if __name__ == '__main__':
    unittest.main()
