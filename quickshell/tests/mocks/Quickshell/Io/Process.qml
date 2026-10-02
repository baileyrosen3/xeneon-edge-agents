import QtQml

// Test-only transport double. It never launches a process or writes to stdin.
QtObject {
    property var command: []
    property bool running: false
    property bool stdinEnabled: false
    property QtObject stdout
    property QtObject stderr
    property var writes: []
    signal started()
    signal exited(int exitCode, int exitStatus)
    function write(data) { writes.push(data) }
}
