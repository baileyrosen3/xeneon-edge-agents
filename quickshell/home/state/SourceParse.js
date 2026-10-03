.pragma library

// Parsing helpers shared by the home data sources. Every helper is pure and
// returns an explicit "no reading" marker rather than a zero, so an absent or
// unreadable input can never be presented as a real measurement.

var missing = null

function finiteNumber(value) {
    var number = Number(value)
    return Number.isFinite(number) ? number : null
}

function clampPercent(value) {
    var number = finiteNumber(value)
    if (number === null)
        return null
    return Math.max(0, Math.min(100, number))
}

// /proc/stat. Requires the previous sample to compute a delta, so a single
// read legitimately yields no percentage until the next poll.
function parseProcStat(raw, previous) {
    var lines = String(raw || "").split("\n")
    var snapshot = ({})
    for (var index = 0; index < lines.length; index += 1) {
        var fields = lines[index].trim().split(/\s+/)
        if (!/^cpu\d*$/.test(fields[0] || "") || fields.length < 5)
            continue

        var values = []
        for (var field = 1; field <= 8; field += 1)
            values.push(Number(fields[field]) || 0)
        var total = 0
        for (var value = 0; value < values.length; value += 1)
            total += values[value]
        snapshot[fields[0]] = { total: total, idle: values[3] + values[4] }
    }

    if (!snapshot.cpu)
        return { "snapshot": snapshot, "overall": null, "cores": [] }

    var overall = null
    var before = previous ? previous.cpu : null
    if (before) {
        var totalDelta = snapshot.cpu.total - before.total
        var idleDelta = snapshot.cpu.idle - before.idle
        if (totalDelta > 0 && idleDelta >= 0)
            overall = clampPercent((totalDelta - idleDelta) * 100 / totalDelta)
    }

    var labels = []
    for (var label in snapshot) {
        if (Object.prototype.hasOwnProperty.call(snapshot, label) && label !== "cpu")
            labels.push(label)
    }
    labels.sort(function(left, right) {
        return Number(left.slice(3)) - Number(right.slice(3))
    })

    var cores = []
    for (var core = 0; core < labels.length; core += 1) {
        var previousCore = previous ? previous[labels[core]] : null
        var percent = null
        if (previousCore) {
            var coreTotal = snapshot[labels[core]].total - previousCore.total
            var coreIdle = snapshot[labels[core]].idle - previousCore.idle
            if (coreTotal > 0 && coreIdle >= 0)
                percent = clampPercent((coreTotal - coreIdle) * 100 / coreTotal)
        }
        cores.push({ "name": labels[core], "percent": percent })
    }

    return { "snapshot": snapshot, "overall": overall, "cores": cores }
}

// /proc/meminfo, in bytes.
function parseMemInfo(raw) {
    var values = ({})
    var lines = String(raw || "").split("\n")
    for (var index = 0; index < lines.length; index += 1) {
        var match = lines[index].match(/^([A-Za-z_()]+):\s+(\d+)/)
        if (match !== null)
            values[match[1]] = Number(match[2]) * 1024
    }

    var total = values.MemTotal || 0
    if (total <= 0)
        return null

    var available = Number.isFinite(values.MemAvailable) ? values.MemAvailable : 0
    var used = Math.max(0, total - available)
    return {
        "totalBytes": total,
        "usedBytes": used,
        "percent": clampPercent(used * 100 / total),
        "swapTotalBytes": values.SwapTotal || 0,
        "swapUsedBytes": Math.max(0, (values.SwapTotal || 0) - (values.SwapFree || 0))
    }
}

// hwmon temperatures in millidegrees Celsius. `wanted` is a list of chip names
// accepted in preference order, so a machine whose CPU package is published as
// k10temp, coretemp, or zenpower is read without guessing.
function parseHwmon(raw, wanted) {
    var chips = {}
    try {
        chips = JSON.parse(String(raw || ""))
    } catch (error) {
        return null
    }
    if (chips === null || typeof chips !== "object")
        return null

    // hwmon names a chip "<driver>-pci-<slot>" or just "<driver>", so an
    // accepted driver name matches as a prefix rather than exactly.
    for (var index = 0; index < wanted.length; index += 1) {
        var wantedName = wanted[index]
        var chipName = null
        for (var candidate in chips) {
            if (!Object.prototype.hasOwnProperty.call(chips, candidate))
                continue
            if (candidate === wantedName || candidate.indexOf(wantedName + "-") === 0) {
                chipName = candidate
                break
            }
        }
        if (chipName === null)
            continue
        var chip = chips[chipName]
        for (var label in chip) {
            if (!Object.prototype.hasOwnProperty.call(chip, label))
                continue
            if (label.indexOf("temp") !== 0 || label.indexOf("_input") === -1)
                continue
            var reading = finiteNumber(chip[label][label + "_input"])
            if (reading !== null)
                return { "chip": chipName, "sensor": label, "celsius": reading }
        }
    }

    var fallback = null
    for (var name in chips) {
        if (!Object.prototype.hasOwnProperty.call(chips, name))
            continue
        var group = chips[name]
        for (var key in group) {
            if (!Object.prototype.hasOwnProperty.call(group, key))
                continue
            if (key.indexOf("temp") !== 0 || key.indexOf("_input") === -1)
                continue
            var celsius = finiteNumber(group[key][key + "_input"])
            if (celsius !== null) {
                fallback = { "chip": name, "sensor": key, "celsius": celsius }
                break
            }
        }
        if (fallback !== null)
            break
    }
    return fallback
}

// The CPU marketing name, exactly as /proc/cpuinfo publishes it.
function parseCpuModel(raw) {
    var match = String(raw || "").match(/^model name\s*:\s*(.+)$/m)
    if (match === null)
        return ""
    return match[1].trim()
}

// The CPU chip names accepted for the package temperature, in the order the
// kernel publishes them across vendors.
var cpuChips = ["k10temp", "coretemp", "zenpower", "cpu_thermal", "soc_thermal"]

// The GPU chip names accepted from hwmon. amdgpu publishes "amdgpu", nouveau
// and i915 publish their driver name, and xe's package sensor is "xe".
var gpuChips = ["amdgpu", "xe", "i915", "nouveau"]

function parseGpuSysfs(device) {
    var result = {
        "busyPercent": null,
        "vramUsedBytes": null,
        "vramTotalBytes": null,
        "driver": "",
        "card": ""
    }
    if (device === null || device === undefined)
        return result

    var card = String(device.card || "")
    var busy = finiteNumber(device.busyPercent)
    if (busy !== null)
        result.busyPercent = clampPercent(busy)

    var used = finiteNumber(device.vramUsedBytes)
    var total = finiteNumber(device.vramTotalBytes)
    if (used !== null && total !== null && total > 0) {
        result.vramUsedBytes = used
        result.vramTotalBytes = total
    }
    result.driver = String(device.driver || "")
    result.card = card
    return result
}

// Ranks a GPU card the way the Omarchy system monitor does: a card publishing
// a utilisation counter beats a temperature-only card, then larger video
// memory wins, so a discrete adapter is preferred without hardcoding an ID.
function betterGpu(candidate, incumbent) {
    if (incumbent === null || incumbent === undefined)
        return true
    var candidateRank = candidate.busyPercent === null ? 1 : 2
    var incumbentRank = incumbent.busyPercent === null ? 1 : 2
    if (candidateRank !== incumbentRank)
        return candidateRank > incumbentRank
    var candidateMemory = candidate.vramTotalBytes === null ? 0 : candidate.vramTotalBytes
    var incumbentMemory = incumbent.vramTotalBytes === null ? 0 : incumbent.vramTotalBytes
    return candidateMemory > incumbentMemory
}

// `hyprctl -j monitors`, reduced to the fields this surface renders.
function parseMonitors(raw) {
    var list = parseJsonArray(raw)
    if (list === null)
        return null

    var monitors = []
    for (var index = 0; index < list.length; index += 1) {
        var entry = list[index]
        if (entry === null || entry === undefined)
            continue
        monitors.push({
            "name": String(entry.name || ""),
            "model": String(entry.model || ""),
            "description": String(entry.description || ""),
            "width": Number(entry.width) || 0,
            "height": Number(entry.height) || 0,
            "scale": Number(entry.scale) || 1,
            "activeWorkspace": Number(entry.activeWorkspace) || 0,
            "focused": entry.focused === true
        })
    }
    return monitors
}

function parseWorkspaces(raw) {
    var list = parseJsonArray(raw)
    if (list === null)
        return null

    var workspaces = []
    for (var index = 0; index < list.length; index += 1) {
        var entry = list[index]
        if (entry === null || entry === undefined)
            continue
        var id = Number(entry.id)
        if (!Number.isInteger(id) || id <= 0)
            continue
        workspaces.push({
            "id": id,
            "name": String(entry.name === undefined ? String(id) : entry.name),
            "windows": Number(entry.windows) || 0,
            "active": entry.active === true,
            "hasfullscreen": entry.hasfullscreen === true
        })
    }
    workspaces.sort(function(left, right) {
        return left.id - right.id
    })
    return workspaces
}

function parseActiveWindow(raw) {
    var entry = parseJsonObject(raw)
    if (entry === null)
        return null
    return {
        "address": String(entry.address || ""),
        "class": String(entry.class || ""),
        "title": String(entry.title || "")
    }
}

// Every window address the compositor currently publishes, used to gate the
// focus-window action so no address can be minted by a caller.
function parseClientAddresses(raw) {
    var list = parseJsonArray(raw)
    if (list === null)
        return null

    var addresses = []
    for (var index = 0; index < list.length; index += 1) {
        var entry = list[index]
        if (entry === null || entry === undefined)
            continue
        var address = validAddress(String(entry.address || ""))
        if (address !== null && addresses.indexOf(address) === -1)
            addresses.push(address)
    }
    return addresses
}

var addressPattern = /^0x[0-9a-f]{1,16}$/

function validAddress(value) {
    return addressPattern.test(String(value || "")) ? String(value) : null
}

function parseJsonArray(raw) {
    var value = parseJson(raw)
    return Array.isArray(value) ? value : null
}

function parseJsonObject(raw) {
    var value = parseJson(raw)
    if (value === null || typeof value !== "object" || Array.isArray(value))
        return null
    return value
}

function parseJson(raw) {
    var text = String(raw === null || raw === undefined ? "" : raw).trim()
    if (text === "")
        return null
    try {
        return JSON.parse(text)
    } catch (error) {
        return null
    }
}

// pactl `get-sink-volume @DEFAULT_SINK@`.
function parseSinkVolume(raw) {
    var match = String(raw || "").match(/(\d{1,3})\s*%/)
    if (match === null)
        return null
    var percent = clampPercent(Number(match[1]))
    return percent === null ? null : { "percent": percent }
}

// pactl `get-sink-mute @DEFAULT_SINK@`.
function parseSinkMute(raw) {
    var match = String(raw || "").match(/Mute:\s*(yes|no)/i)
    if (match === null)
        return null
    return { "muted": match[1].toLowerCase() === "yes" }
}

// `bluetoothctl show`, reduced to controller power and adapter name.
function parseBluetoothController(raw) {
    var text = String(raw || "")
    if (text.indexOf("Controller ") === -1)
        return null

    var powered = text.match(/Powered:\s*(yes|no)/i)
    var name = text.match(/Name:\s*(.+)/)
    return {
        "powered": powered === null ? null : powered[1].toLowerCase() === "yes",
        "name": name === null ? "" : name[1].trim()
    }
}

// `bluetoothctl devices Connected`.
function parseBluetoothDevices(raw) {
    var lines = String(raw || "").split("\n")
    var devices = []
    for (var index = 0; index < lines.length; index += 1) {
        var match = lines[index].match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.*)$/)
        if (match !== null)
            devices.push({ "address": match[1], "name": match[2].trim() })
    }
    return devices
}

// `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device`, reduced to the interface
// carrying the default route.
function parseNetworkDevices(raw, primaryDevice) {
    var lines = String(raw || "").split("\n")
    var primary = String(primaryDevice || "")

    var connected = []
    var wirelessConnected = ""
    var wirelessTotal = 0
    for (var index = 0; index < lines.length; index += 1) {
        var line = lines[index]
        if (line === "")
            continue
        var fields = line.split(":")
        if (fields.length < 3)
            continue
        var name = fields[0]
        var type = fields[1]
        var state = fields[2]
        var connection = fields.length > 3 ? fields[3] : ""

        if (type === "wifi")
            wirelessTotal += 1
        if (state !== "connected")
            continue

        connected.push({ "device": name, "type": type, "connection": connection })
        if (type === "wifi" && wirelessConnected === "")
            wirelessConnected = connection
    }

    var primaryEntry = null
    for (var entry = 0; entry < connected.length; entry += 1) {
        if (connected[entry].device === primary)
            primaryEntry = connected[entry]
    }

    return {
        "primaryDevice": primaryEntry === null ? "" : primary.device,
        "primaryType": primaryEntry === null ? "" : primaryEntry.type,
        "primaryConnection": primaryEntry === null ? "" : primaryEntry.connection,
        "connectedCount": connected.length,
        "wirelessConnected": wirelessConnected,
        "wirelessTotal": wirelessTotal
    }
}

// `ip route show default`, reduced to the interface owning the default route.
function parseDefaultRoute(raw) {
    var match = String(raw || "").match(/\bdev\s+(\S+)/)
    return match === null ? "" : match[1]
}

var byteUnits = ["B", "KB", "MB", "GB", "TB"]

// A short, fixed-width byte label. Compactness on a 288px strip matters more
// than precision, so the value is rounded to one decimal above kilobytes.
function formatBytes(bytes) {
    var number = finiteNumber(bytes)
    if (number === null || number < 0)
        return "—"

    var unit = 0
    var value = number
    while (value >= 1024 && unit < byteUnits.length - 1) {
        value /= 1024
        unit += 1
    }
    if (unit === 0)
        return Math.round(value) + " " + byteUnits[unit]
    if (value >= 100)
        return Math.round(value) + " " + byteUnits[unit]
    return value.toFixed(1) + " " + byteUnits[unit]
}

function formatPercent(value) {
    var number = finiteNumber(value)
    if (number === null)
        return "—"
    return Math.round(number) + "%"
}

function formatCelsius(value) {
    var number = finiteNumber(value)
    if (number === null)
        return "—"
    return Math.round(number) + "°"
}

// Two-digit hours and minutes for the status strip.
function formatClock(date) {
    if (!(date instanceof Date) || Number.isNaN(date.getTime()))
        return "--:--"
    return pad(date.getHours()) + ":" + pad(date.getMinutes())
}

function formatClockWithSeconds(date) {
    if (!(date instanceof Date) || Number.isNaN(date.getTime()))
        return "--:--"
    return formatClock(date) + ":" + pad(date.getSeconds())
}

var weekdays = [
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
]
var months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

function formatDate(date) {
    if (!(date instanceof Date) || Number.isNaN(date.getTime()))
        return ""
    return weekdays[date.getDay()].slice(0, 3) + " " + date.getDate() + " " + months[date.getMonth()]
}

function pad(value) {
    return value < 10 ? "0" + value : String(value)
}

function formatDuration(seconds) {
    var number = finiteNumber(seconds)
    if (number === null || number < 0)
        return "—:—"
    var total = Math.round(number)
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var remainder = total % 60
    if (hours > 0)
        return hours + ":" + pad(minutes) + ":" + pad(remainder)
    return minutes + ":" + pad(remainder)
}