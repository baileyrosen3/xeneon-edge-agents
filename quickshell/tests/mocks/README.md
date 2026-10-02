The Qt test runner cannot load Quickshell's statically linked I/O plugin.
This module supplies an inert `Process`/`SplitParser` double so tests can
exercise the actual `PortalBridge.qml` preview guards without launching a
process or writing to a real daemon.

Import this directory only in `qmltestrunner` with
`-import quickshell/tests/mocks`. Production uses Quickshell's real I/O module;
the installer excludes the entire tests directory.
