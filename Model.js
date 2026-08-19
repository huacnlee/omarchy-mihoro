.pragma library

// Everything the panel derives rather than displays raw: the CLI invocations it
// schedules, the one shell probe it runs per refresh, and the formatting and
// state rules the views read. Kept out of QML so it can be tested with plain
// node, without a compositor.

var MODES = [
  { value: "rule",   label: "Rule",   hint: "Match traffic against the subscription's rules" },
  { value: "global", label: "Global", hint: "Send everything through the selected proxy" },
  { value: "direct", label: "Direct", hint: "Bypass the proxy entirely" }
]

function modeLabel(value) {
  for (var i = 0; i < MODES.length; i++) if (MODES[i].value === value) return MODES[i].label
  return "Rule"
}

function modeIndex(value) {
  for (var i = 0; i < MODES.length; i++) if (MODES[i].value === value) return i
  return 0
}

function modeSelectionAction(next, current) {
  var wanted = String(next || "").toLowerCase()
  if (modeIndex(wanted) >= MODES.length || MODES[modeIndex(wanted)].value !== wanted) return "none"
  if (wanted === "global") return "choose_proxy"
  return wanted === String(current || "").toLowerCase() ? "none" : "switch"
}

// ------------------------------------------------------------------ the CLI
//
// mihoro owns the mihomo binary, the systemd unit, and the subscription
// download. The plugin opens the upstream installation guide and leaves
// installation entirely to the user.

var INSTALL_DOCS_URL = "https://github.com/spencerwooo/mihoro#installation"
var PROJECT_URL = "https://github.com/spencerwooo/mihoro"

function initCommand() { return ["mihoro", "init", "-y"] }
function updateConfigCommand() { return ["mihoro", "update", "--config"] }
function applyCommand() { return ["mihoro", "apply"] }
function startCommand() { return ["mihoro", "start"] }
function stopCommand() { return ["mihoro", "stop"] }
function restartCommand() { return ["mihoro", "restart"] }
function proxyExportCommand() { return ["mihoro", "proxy", "export"] }
function installationGuideCommand() {
  return ["omarchy", "launch", "browser", INSTALL_DOCS_URL]
}

// One probe per refresh instead of five processes. It answers: is the CLI on
// PATH, where is the mihomo binary, what does systemd think of mihomo.service,
// when did it last come up, and has the subscription ever been written to disk.
//
// mihomo is looked for where mihoro.toml says it is (`$2`, already
// home-expanded) before PATH is consulted: `mihoro init` installs it to
// `~/.local/bin`, which is not on every shell's PATH, and a user who moved it
// elsewhere recorded that move in `mihomo_binary_path`. PATH remains the
// fallback so a distro-packaged mihomo in `/usr/bin` is still found when the
// configured path is stale or absent.
//
// `date -d` converts systemd's human timestamp to an epoch here rather than in
// QML, because "Sun 2026-08-17 19:15:03 CST" is not something Date.parse can be
// trusted with.
var PROBE_SCRIPT = [
  "unit=mihomo.service",
  "mihoro_bin=$(command -v mihoro 2>/dev/null || true)",
  "printf 'mihoro_bin=%s\\n' \"$mihoro_bin\"",
  "if [ -n \"$mihoro_bin\" ]; then printf 'mihoro_version=%s\\n' \"$(\"$mihoro_bin\" --version 2>/dev/null | head -n 1 || true)\"; fi",
  "mihomo_bin=${2:-}",
  "[ -n \"$mihomo_bin\" ] && [ -x \"$mihomo_bin\" ] || mihomo_bin=$(command -v mihomo 2>/dev/null || true)",
  "printf 'mihomo_bin=%s\\n' \"$mihomo_bin\"",
  "systemctl --user show \"$unit\" -p LoadState -p ActiveState -p SubState -p UnitFileState -p MainPID -p ActiveEnterTimestamp 2>/dev/null || true",
  "started=$(systemctl --user show \"$unit\" -p ActiveEnterTimestamp --value 2>/dev/null || true)",
  "if [ -n \"$started\" ]; then printf 'active_enter_epoch=%s\\n' \"$(date -d \"$started\" +%s 2>/dev/null || echo 0)\"; fi",
  "if [ -f \"$1\" ]; then printf 'config_present=1\\nconfig_mtime=%s\\n' \"$(stat -c %Y -- \"$1\" 2>/dev/null || echo 0)\"; else printf 'config_present=0\\n'; fi",
  "printf 'now=%s\\n' \"$(date +%s)\""
].join("\n")

function probeCommand(mihomoConfigPath, mihomoBinaryPath) {
  return ["bash", "-c", PROBE_SCRIPT, "omahoro-probe",
    String(mihomoConfigPath || ""), String(mihomoBinaryPath || "")]
}

function emptyProbe() {
  return {
    mihoroInstalled: false,
    mihoroVersion: "",
    mihomoInstalled: false,
    mihomoPath: "",
    unitLoaded: false,
    activeState: "unknown",
    subState: "",
    unitFileState: "",
    mainPid: 0,
    startedAt: 0,
    configPresent: false,
    configMtime: 0,
    now: 0
  }
}

function parseProbe(text) {
  var probe = emptyProbe()
  var lines = String(text === undefined || text === null ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var eq = line.indexOf("=")
    if (eq < 0) continue
    var key = line.substring(0, eq).trim()
    var value = line.substring(eq + 1).trim()
    if (key === "mihoro_bin") probe.mihoroInstalled = value !== ""
    else if (key === "mihoro_version") probe.mihoroVersion = value
    else if (key === "mihomo_bin") { probe.mihomoPath = value; probe.mihomoInstalled = value !== "" }
    else if (key === "LoadState") probe.unitLoaded = value === "loaded"
    else if (key === "ActiveState") probe.activeState = value || "unknown"
    else if (key === "SubState") probe.subState = value
    else if (key === "UnitFileState") probe.unitFileState = value
    else if (key === "MainPID") probe.mainPid = Number(value) || 0
    else if (key === "active_enter_epoch") probe.startedAt = Number(value) || 0
    else if (key === "config_present") probe.configPresent = value === "1"
    else if (key === "config_mtime") probe.configMtime = Number(value) || 0
    else if (key === "now") probe.now = Number(value) || 0
  }
  return probe
}

// ------------------------------------------------------- mihoro CLI output
//
// `mihoro update` and `mihoro init` report in stages — a `●` line per stage
// while running, then a summary of `✓` / `↷` / `✗`. Following that gives the
// panel a live progress line and, on failure, the stage that actually broke
// instead of a generic "command failed".

// `colored` turns itself off when stdout is not a tty, so mihoro's output
// through a pipe is normally plain. It is stripped anyway: a user with
// CLICOLOR_FORCE set would otherwise see escape codes in the panel.
function stripAnsi(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/\x1b\[[0-9;]*[A-Za-z]/g, "")
}

function parseStageLine(line) {
  var text = stripAnsi(line).replace(/\s+$/, "")
  var trimmed = text.trim()
  if (trimmed === "") return null
  if (trimmed.indexOf("●") === 0)
    return { kind: "stage", name: trimmed.substring(1).trim(), detail: "" }
  if (trimmed.indexOf("⎿") === 0)
    return { kind: "detail", name: "", detail: trimmed.substring(1).trim() }
  if (trimmed.indexOf("✓") === 0)
    return { kind: "ok", name: trimmed.substring(1).trim(), detail: "" }
  if (trimmed.indexOf("↷") === 0)
    return { kind: "skip", name: trimmed.substring(1).trim(), detail: "" }
  if (trimmed.indexOf("✗") === 0) {
    var body = trimmed.substring(1).trim()
    var split = body.indexOf(":")
    return split < 0
      ? { kind: "fail", name: body, detail: "" }
      : { kind: "fail", name: body.substring(0, split).trim(), detail: body.substring(split + 1).trim() }
  }
  if (/^error:/i.test(trimmed))
    return { kind: "fail", name: "", detail: trimmed.replace(/^error:\s*/i, "") }
  return { kind: "other", name: "", detail: trimmed }
}

// The message to show when a staged command exits non-zero. A failed stage is
// far more useful than the exit code, so it wins over stderr.
function stageFailureMessage(output, fallback) {
  var lines = String(output === undefined || output === null ? "" : output).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parsed = parseStageLine(lines[i])
    if (parsed && parsed.kind === "fail") {
      if (parsed.name !== "" && parsed.detail !== "") return parsed.name + ": " + parsed.detail
      return parsed.detail !== "" ? parsed.detail : parsed.name
    }
  }
  var trimmed = stripAnsi(output).trim()
  if (trimmed !== "") {
    var last = trimmed.split("\n")
    return elide(last[last.length - 1].trim(), 160)
  }
  return String(fallback || "mihoro reported a failure.")
}

function elide(text, max) {
  var value = String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim()
  var limit = Number(max) || 80
  return value.length > limit ? value.substring(0, limit - 1) + "…" : value
}

// ---------------------------------------------------------- connection state
//
// One place decides what the panel is looking at, so the hero, the bar icon,
// and the enabled state of every control cannot disagree.

function connectionState(probe, api) {
  var state = probe || emptyProbe()
  var apiState = String(api || "unknown")

  if (!state.mihoroInstalled)
    return { key: "cli_missing", label: "mihoro not installed", detail: "Install the mihoro CLI to use this panel.", active: false, tone: "idle" }
  if (!state.configPresent)
    return { key: "not_initialized", label: "Not set up", detail: "Add a subscription URL to get started.", active: false, tone: "idle" }
  if (!state.unitLoaded)
    return { key: "unit_missing", label: "Service not installed", detail: "Run setup to install mihomo.service.", active: false, tone: "idle" }
  if (state.activeState === "failed")
    return { key: "failed", label: "Failed", detail: "mihomo.service failed to start.", active: false, tone: "urgent" }
  if (state.activeState === "activating")
    return { key: "starting", label: "Starting…", detail: "mihomo.service is coming up.", active: true, tone: "idle" }
  if (state.activeState === "deactivating")
    return { key: "stopping", label: "Stopping…", detail: "mihomo.service is shutting down.", active: false, tone: "idle" }
  if (state.activeState !== "active")
    return { key: "stopped", label: "Stopped", detail: "mihomo.service is not running.", active: false, tone: "idle" }
  if (apiState === "unauthorized")
    return { key: "unauthorized", label: "Running", detail: "Running, but the API secret is rejected.", active: true, tone: "urgent" }
  if (apiState !== "ok")
    return { key: "running_no_api", label: "Running", detail: "Running; mihomo's API is not reachable.", active: true, tone: "idle" }
  return { key: "running", label: "Connected", detail: "", active: true, tone: "good" }
}

// The mode switch talks to the running core. With nothing running there is
// nothing to switch, and writing the file alone would show a mode that is not
// in effect — so the control goes quiet instead of lying.
function canSwitchMode(probe, api) {
  var state = connectionState(probe, api)
  return state.key === "running" || state.key === "running_no_api"
}

function modeHint(probe, api) {
  var state = connectionState(probe, api)
  if (state.key === "running") return ""
  if (state.key === "running_no_api") return "Switching restarts mihomo — its API is unreachable."
  if (state.key === "cli_missing" || state.key === "not_initialized" || state.key === "unit_missing") return ""
  return "Start mihomo to switch modes."
}

// ------------------------------------------------------------- subscriptions

function isValidSubscriptionUrl(url) {
  var text = String(url === undefined || url === null ? "" : url).trim()
  return /^https?:\/\/[^\s\/]+\.?[^\s]*$/i.test(text)
}

function subscriptionUrlError(url) {
  var text = String(url === undefined || url === null ? "" : url).trim()
  if (text === "") return "Enter a subscription URL."
  if (!/^https?:\/\//i.test(text)) return "The URL must start with http:// or https://."
  if (!isValidSubscriptionUrl(text)) return "That does not look like a valid URL."
  return ""
}

var MASK = "*******"

// A subscription URL is a bearer credential: the token is the whole of the
// authentication. Keep only the origin recognizable; paths, query names,
// values, and fragments can all identify an account or expose credentials.
function maskUrl(url) {
  var text = String(url === undefined || url === null ? "" : url).trim()
  if (text === "") return ""
  var parts = text.match(/^([a-z][a-z0-9+.\-]*:\/\/)([^\/?#]+)/i)
  if (!parts) return MASK
  return String(parts[1]) + String(parts[2]) + "/" + MASK
}

function displayUrl(url, revealed) {
  var text = String(url === undefined || url === null ? "" : url).trim()
  if (text === "") return "No subscription URL yet"
  return revealed === true ? text : maskUrl(text)
}

// ------------------------------------------------------------------ history
//
// Throughput is sampled from the `/traffic` stream that already feeds the two
// speed readouts, so the curve behind each one is drawn from the very numbers
// printed on top of it and cannot drift from them.
//
// The series survives the panel closing, so reopening continues the curve
// instead of starting from nothing. What it must not do is close the gap: the
// curve spaces its samples evenly, so butting the last sample from ten minutes
// ago against the first from now would draw them as neighbours and misstate
// when the traffic happened. The seconds the stream was not running are filled
// in as baseline slots instead — the same flat line the chart shows before it
// has any data, which is exactly what those seconds are.

// One minute at the stream's one-second cadence. The window is sized to how
// long the panel is realistically open, not to how much history would be nice:
// the curve grows in from the right, so a window that never fills would only
// ever draw a stub against empty space.
var HISTORY_LIMIT = 60

// QML re-evaluates a `var` property's bindings when it is assigned, not when
// the array it holds is mutated, so a new array is returned rather than the
// sample being pushed into the old one.
// `Array.isArray` rather than `instanceof Array` throughout: the check has to
// hold for an array that was not built in this realm, which is what the tests
// hand it when they load this file into a vm context.
function pushHistory(history, sample, limit) {
  var cap = Math.max(1, Math.floor(Number(limit) || 0) || 1)
  var list = Array.isArray(history) ? history : []
  var next = list.slice(Math.max(0, list.length - cap + 1))
  var reading = Number(sample)
  next.push(isFinite(reading) && reading > 0 ? reading : 0)
  return next
}

// Records `slots` seconds during which nothing was sampled. Capped at the
// window: a gap longer than the history leaves nothing of the old series to
// keep, and the chart correctly comes back as a flat line.
function padHistory(history, slots, limit) {
  var list = Array.isArray(history) ? history : []
  var count = Math.floor(Number(slots))
  if (!isFinite(count) || count <= 0) return list
  var cap = Math.max(1, Math.floor(Number(limit) || 0) || 1)
  var next = list
  var fill = Math.min(count, cap)
  for (var i = 0; i < fill; i++) next = pushHistory(next, 0, cap)
  return next
}

// Sparkline geometry in a 0..1 box: x runs left to right, y is 0 at the
// baseline and 1 at the peak, leaving the QML nothing to do but scale.
//
// The newest sample is pinned to the right edge and the series grows leftward,
// so a history that has only just started reads as a short line at "now"
// instead of a full-width line that is mostly invention.
//
// The scale runs from zero to the peak, not from the window's minimum: twice
// the throughput should draw twice as tall. Normalising to min..max instead
// would blow an idle line's own jitter up to full height and make a quiet
// minute look identical to a busy one.
function peakOf(history) {
  var list = Array.isArray(history) ? history : []
  var peak = 0
  for (var i = 0; i < list.length; i++) {
    var seen = Number(list[i])
    if (isFinite(seen) && seen > peak) peak = seen
  }
  return peak
}

function sparkline(history, capacity, scalePeak) {
  var list = Array.isArray(history) ? history : []
  var span = Math.max(2, Math.floor(Number(capacity) || 0) || 2) - 1
  // A caller that draws several series side by side passes one peak for all of
  // them, so equal heights mean equal throughput across the set. Left at zero,
  // each series scales to its own window.
  var forced = Number(scalePeak)
  var peak = (isFinite(forced) && forced > 0) ? forced : peakOf(list)
  var points = []
  var i
  var newest = list.length - 1
  for (i = 0; i < list.length; i++) {
    var reading = Number(list[i])
    if (!isFinite(reading) || reading < 0) reading = 0
    points.push({
      x: Math.max(0, 1 - (newest - i) / span),
      // Clamped: a shared peak can lag a series that just spiked past it.
      y: peak > 0 ? Math.min(1, reading / peak) : 0
    })
  }
  // Slots the panel was not open for. They are drawn as a flat line along the
  // baseline so the box reads as a chart from the first second rather than as
  // a stub floating at the right edge — but they are returned separately from
  // the measured points, so the filled area can still mark exactly what was
  // sampled and the empty stretch stays a bare line.
  //
  // With nothing sampled at all, `firstX` is the right edge and the lead spans
  // the whole width: an empty chart is a flat baseline, not a blank box.
  var lead = []
  var firstX = points.length > 0 ? points[0].x : 1
  if (firstX > 0) {
    lead.push({ x: 0, y: 0 })
    lead.push({ x: firstX, y: 0 })
  }

  return { points: points, lead: lead, peak: peak }
}

// ---------------------------------------------------------------- formatting

// Binary units, named as binary units. The arithmetic below divides by 1024,
// which is what mihomo's own dashboard does, so the numbers stay comparable
// with metacubexd — but calling 854,590,870 bytes "815 MB" understated it by
// 4.6% against the decimal megabyte every other tool and every ISP quotes.
var UNITS = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]

function formatBytes(bytes) {
  var value = Number(bytes)
  if (!isFinite(value) || value <= 0) return "0 B"
  var unit = 0
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024
    unit++
  }
  var digits = unit === 0 ? 0 : (value < 10 ? 1 : 0)
  return value.toFixed(digits) + " " + UNITS[unit]
}

function formatSpeed(bytesPerSecond) {
  return formatBytes(bytesPerSecond) + "/s"
}

function formatDuration(seconds) {
  var total = Math.floor(Number(seconds))
  if (!isFinite(total) || total < 0) return "—"
  if (total < 60) return total + "s"
  var minutes = Math.floor(total / 60)
  if (minutes < 60) return minutes + "m " + (total % 60) + "s"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h " + (minutes % 60) + "m"
  return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
}

function formatAgo(epochSeconds, nowSeconds) {
  var then = Number(epochSeconds)
  var now = Number(nowSeconds)
  if (!isFinite(then) || then <= 0 || !isFinite(now) || now <= 0) return "—"
  var delta = now - then
  if (delta < 0) return "just now"
  if (delta < 60) return "just now"
  return formatDuration(delta).split(" ")[0] + " ago"
}

function formatPorts(config, live) {
  var mixed = (live && live.mixedPort) || (config && config.mixedPort) || 0
  var http = (live && live.port) || (config && config.port) || 0
  var socks = (live && live.socksPort) || (config && config.socksPort) || 0
  var parts = []
  if (mixed > 0) parts.push("mixed " + mixed)
  if (http > 0) parts.push("http " + http)
  if (socks > 0) parts.push("socks " + socks)
  return parts.length > 0 ? parts.join(" · ") : "—"
}
