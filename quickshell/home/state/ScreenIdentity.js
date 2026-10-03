.pragma library

// The live screen-identity gate, as a pure function.
//
// This exists so the rule can be executed and tested rather than only read. A
// predicate that only ever runs inside a Quickshell process cannot be verified
// offline, which is exactly how an unsatisfiable gate survived: it rendered
// perfectly in preview and could never bind on a real compositor.
//
// Fail-closed means all of the following, always:
//
//   * the configured serial, model, and output must all be present;
//   * the output name must match exactly;
//   * the model must match exactly;
//   * the serial must match exactly WHEN the compositor publishes one;
//   * exactly one screen may match.
//
// There is no fallback to a primary, first, or default screen anywhere, and a
// name match alone is never sufficient.
//
// The serial rule is deliberately asymmetric, and the asymmetry is required
// rather than a weakening. Hyprland's `wl_output` does not expose an EDID
// serial to Qt at all: Qt reports `serialNumber == ""` for every screen on that
// compositor, so requiring a non-empty runtime serial makes the gate
// unsatisfiable there and the surface can never bind. Where a compositor *does*
// publish a serial, it is compared exactly, and a mismatch still refuses.

function identityConfigured(identity) {
    var record = identity === null || identity === undefined ? {} : identity
    return String(record.output || "") !== ""
        && String(record.model || "") !== ""
        && String(record.serial || "") !== ""
}

// Whether one screen satisfies the identity. `screen` is a plain object shaped
// like the properties Quickshell publishes on a screen.
function screenMatches(screen, identity) {
    if (screen === null || screen === undefined)
        return false
    var record = identity === null || identity === undefined ? {} : identity

    // A screen with no usable name or no area is not a surface.
    if (String(screen.name || "") === "")
        return false
    if (Number(screen.width) <= 0 || Number(screen.height) <= 0)
        return false

    // Output name and model must match exactly, and never by name alone.
    if (String(screen.name || "") !== String(record.output || ""))
        return false
    if (String(screen.model || "") !== String(record.model || ""))
        return false

    // The serial is compared only when the compositor publishes one. An empty
    // runtime serial means "this compositor does not expose serials", which is
    // not the same claim as "this is a different panel".
    var runtimeSerial = String(screen.serialNumber || "")
    if (runtimeSerial !== "" && runtimeSerial !== String(record.serial || ""))
        return false

    return true
}

// The screens that satisfy the identity.
function matchingScreens(screens, identity) {
    if (!identityConfigured(identity))
        return []
    var list = Array.isArray(screens) ? screens : []
    var matches = []
    for (var index = 0; index < list.length; index += 1) {
        if (screenMatches(list[index], identity))
            matches.push(list[index])
    }
    return matches
}

// The single surface a live window may be created on, or null. Zero matches and
// several matches both produce nothing.
function targetScreen(screens, identity) {
    var matches = matchingScreens(screens, identity)
    return matches.length === 1 ? matches[0] : null
}

// Why a live surface was or was not created, for the log.
function refusalReason(screens, identity) {
    if (!identityConfigured(identity))
        return "identity is incomplete; XENEON_HOME_SERIAL, XENEON_HOME_MODEL, and XENEON_HOME_OUTPUT are all required"
    var matches = matchingScreens(screens, identity)
    if (matches.length === 0)
        return "no screen matches output " + identity.output
            + " / model " + identity.model
            + " / serial " + identity.serial
    if (matches.length > 1)
        return matches.length + " screens match the configured identity"
    return ""
}
