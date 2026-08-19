const assert = require("assert")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")
const { load } = require("./load")

const model = load("Model.js")

// ------------------------------------------------------------------ commands
//
// The plugin schedules the user's own CLI. It must never invoke anything that
// installs, upgrades, or removes it.

assert.deepStrictEqual(Array.from(model.initCommand()), ["mihoro", "init", "-y"])
assert.deepStrictEqual(Array.from(model.updateConfigCommand()), ["mihoro", "update", "--config"])
assert.deepStrictEqual(Array.from(model.applyCommand()), ["mihoro", "apply"])
assert.deepStrictEqual(Array.from(model.startCommand()), ["mihoro", "start"])
assert.deepStrictEqual(Array.from(model.stopCommand()), ["mihoro", "stop"])
assert.deepStrictEqual(Array.from(model.restartCommand()), ["mihoro", "restart"])
assert.deepStrictEqual(Array.from(model.proxyExportCommand()), ["mihoro", "proxy", "export"])
assert.deepStrictEqual(Array.from(model.installationGuideCommand()), [
  "omarchy", "launch", "browser", "https://github.com/spencerwooo/mihoro#installation"
])

for (const forbidden of ["uninstall", "upgrade", "install.sh", "curl -fsSL"])
  assert.ok(!JSON.stringify(model.PROBE_SCRIPT).includes(forbidden),
    "the probe never runs " + forbidden)

const probeCmd = model.probeCommand("/home/ada/.config/mihomo/config.yaml", "/opt/mihomo/bin/mihomo")
assert.strictEqual(probeCmd[0], "bash")
assert.strictEqual(probeCmd[1], "-c")
assert.strictEqual(probeCmd[3], "omahoro-probe")
assert.strictEqual(probeCmd[4], "/home/ada/.config/mihomo/config.yaml")
// The configured binary path is an argument, never spliced into the script:
// it comes out of a file the user edits by hand.
assert.strictEqual(probeCmd[5], "/opt/mihomo/bin/mihomo")
assert.ok(!probeCmd[2].includes("/opt/mihomo"))
assert.ok(probeCmd[2].includes("command -v mihomo"), "PATH stays the fallback")
assert.ok(probeCmd[2].includes("systemctl --user"), "the unit is a user service")
assert.ok(!probeCmd[2].includes("sudo"))

// A caller with no configured path still gets a well-formed argv.
assert.deepStrictEqual(Array.from(model.probeCommand("/tmp/config.yaml")).slice(4),
  ["/tmp/config.yaml", ""])

// ---------------------------------------------------------- probe parsing

const PROBE_OUTPUT = `mihoro_bin=/home/ada/.local/bin/mihoro
mihoro_version=mihoro 0.8.1
mihomo_bin=/home/ada/.local/bin/mihomo
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=4242
ActiveEnterTimestamp=Sun 2026-08-17 19:15:03 CST
active_enter_epoch=1755429303
config_present=1
config_mtime=1755420000
now=1755432903
`

const probe = model.parseProbe(PROBE_OUTPUT)
assert.strictEqual(probe.mihoroInstalled, true)
assert.strictEqual(probe.mihoroVersion, "mihoro 0.8.1")
assert.strictEqual(probe.mihomoInstalled, true)
assert.strictEqual(probe.mihomoPath, "/home/ada/.local/bin/mihomo")
assert.strictEqual(probe.unitLoaded, true)
assert.strictEqual(probe.activeState, "active")
assert.strictEqual(probe.subState, "running")
assert.strictEqual(probe.unitFileState, "enabled")
assert.strictEqual(probe.mainPid, 4242)
assert.strictEqual(probe.startedAt, 1755429303)
assert.strictEqual(probe.configPresent, true)
assert.strictEqual(probe.configMtime, 1755420000)
assert.strictEqual(probe.now, 1755432903)

// A machine with nothing installed still parses, and reads as "nothing here"
// rather than as an error.
const bare = model.parseProbe("mihoro_bin=\nmihomo_bin=\nLoadState=not-found\nActiveState=inactive\nconfig_present=0\n")
assert.strictEqual(bare.mihoroInstalled, false)
assert.strictEqual(bare.mihoroVersion, "")
assert.strictEqual(bare.mihomoInstalled, false)
assert.strictEqual(bare.mihomoPath, "")
assert.strictEqual(bare.unitLoaded, false)
assert.strictEqual(bare.activeState, "inactive")
assert.strictEqual(bare.configPresent, false)
assert.strictEqual(model.parseProbe("").activeState, "unknown")

// The systemd timestamp contains colons and spaces; splitting on the first `=`
// must keep the whole value intact for the lines that need it.
assert.strictEqual(model.parseProbe("ActiveEnterTimestamp=Sun 2026-08-17 19:15:03 CST\n").activeState, "unknown")

// ------------------------------------------- binary resolution, for real
//
// Which mihomo the panel reports is decided by shell, not by JS, so the rule is
// exercised by running the probe the way the panel runs it. The other lines of
// the script need systemd and GNU coreutils; only `mihomo_bin` is asserted.

// Spawned by absolute path: the cases below hand the probe a PATH with no
// mihomo on it, and that PATH is what would resolve `bash` itself.
const BASH = execFileSync("/bin/sh", ["-c", "command -v bash"], { encoding: "utf8" }).trim()

function probeBinary(configuredPath, pathDir) {
  const out = execFileSync(BASH, model.probeCommand("/nonexistent/config.yaml", configuredPath).slice(1), {
    encoding: "utf8",
    // The stripped PATH also hides `date` and `stat`; their complaints are not
    // what this is testing.
    stdio: ["ignore", "pipe", "ignore"],
    env: Object.assign({}, process.env, { PATH: pathDir === undefined ? "" : pathDir })
  })
  return model.parseProbe(out).mihomoPath
}

const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), "omahoro-probe-"))
const elsewhere = path.join(sandbox, "opt")
const onPath = path.join(sandbox, "bin")
fs.mkdirSync(elsewhere)
fs.mkdirSync(onPath)
for (const dir of [elsewhere, onPath]) {
  fs.writeFileSync(path.join(dir, "mihomo"), "#!/bin/sh\n", { mode: 0o755 })
}

// A mihomo installed outside PATH is found because mihoro.toml says where it is.
assert.strictEqual(probeBinary(path.join(elsewhere, "mihomo")), path.join(elsewhere, "mihomo"))
// Nothing configured, or configured to somewhere stale: PATH decides.
assert.strictEqual(probeBinary("", onPath), path.join(onPath, "mihomo"))
assert.strictEqual(probeBinary(path.join(sandbox, "gone", "mihomo"), onPath), path.join(onPath, "mihomo"))
// A path that exists but is not executable is not a usable binary.
const dud = path.join(sandbox, "dud")
fs.writeFileSync(dud, "", { mode: 0o644 })
assert.strictEqual(probeBinary(dud, onPath), path.join(onPath, "mihomo"))
// Nowhere at all reads as "not installed" rather than as an error.
assert.strictEqual(probeBinary(""), "")
fs.rmSync(sandbox, { recursive: true, force: true })

// ------------------------------------------------------- connection state

function probeWith(overrides) {
  const base = model.parseProbe(PROBE_OUTPUT)
  for (const key of Object.keys(overrides)) base[key] = overrides[key]
  return base
}

assert.strictEqual(model.connectionState(probeWith({ mihoroInstalled: false }), "ok").key, "cli_missing")
assert.strictEqual(model.connectionState(probeWith({ configPresent: false }), "ok").key, "not_initialized")
assert.strictEqual(model.connectionState(probeWith({ unitLoaded: false }), "ok").key, "unit_missing")
assert.strictEqual(model.connectionState(probeWith({ activeState: "failed" }), "ok").key, "failed")
assert.strictEqual(model.connectionState(probeWith({ activeState: "activating" }), "ok").key, "starting")
assert.strictEqual(model.connectionState(probeWith({ activeState: "deactivating" }), "ok").key, "stopping")
assert.strictEqual(model.connectionState(probeWith({ activeState: "inactive" }), "ok").key, "stopped")
assert.strictEqual(model.connectionState(probeWith({}), "unauthorized").key, "unauthorized")
assert.strictEqual(model.connectionState(probeWith({}), "unreachable").key, "running_no_api")
assert.strictEqual(model.connectionState(probeWith({}), "disabled").key, "running_no_api")
assert.strictEqual(model.connectionState(probeWith({}), "ok").key, "running")

// A running core is "active" even when its API is out of reach — the proxy is
// still carrying traffic, and the switch must not claim otherwise.
assert.strictEqual(model.connectionState(probeWith({}), "unreachable").active, true)
assert.strictEqual(model.connectionState(probeWith({ activeState: "inactive" }), "ok").active, false)
assert.strictEqual(model.connectionState(probeWith({ activeState: "failed" }), "ok").tone, "urgent")
assert.strictEqual(model.connectionState(probeWith({}), "ok").tone, "good")
assert.strictEqual(model.connectionState(null, "unknown").key, "cli_missing")

// Switching the mode means switching a running core. With nothing running the
// control goes quiet rather than writing a mode nothing is applying.
assert.strictEqual(model.canSwitchMode(probeWith({}), "ok"), true)
assert.strictEqual(model.canSwitchMode(probeWith({}), "unreachable"), true)
assert.strictEqual(model.canSwitchMode(probeWith({ activeState: "inactive" }), "ok"), false)
assert.strictEqual(model.canSwitchMode(probeWith({ mihoroInstalled: false }), "ok"), false)

assert.strictEqual(model.modeHint(probeWith({}), "ok"), "")
assert.ok(model.modeHint(probeWith({ activeState: "inactive" }), "ok").includes("Start mihomo"))
assert.ok(model.modeHint(probeWith({}), "unreachable").includes("restarts mihomo"))
assert.strictEqual(model.modeHint(probeWith({ mihoroInstalled: false }), "ok"), "")

// --------------------------------------------------------- mihoro CLI output

assert.strictEqual(model.parseStageLine("● config").kind, "stage")
assert.strictEqual(model.parseStageLine("● config").name, "config")
assert.strictEqual(model.parseStageLine(" ⎿  refreshing remote config").kind, "detail")
assert.strictEqual(model.parseStageLine(" ⎿  refreshing remote config").detail, "refreshing remote config")
assert.strictEqual(model.parseStageLine("  ✓ config").kind, "ok")
assert.strictEqual(model.parseStageLine("  ↷ core (already up to date)").kind, "skip")
assert.strictEqual(model.parseStageLine("  ✗ config: failed to download").kind, "fail")
assert.strictEqual(model.parseStageLine("  ✗ config: failed to download").name, "config")
assert.strictEqual(model.parseStageLine("  ✗ config: failed to download").detail, "failed to download")
assert.strictEqual(model.parseStageLine("error: `remote_config_url` undefined").kind, "fail")
assert.strictEqual(model.parseStageLine(""), null)
assert.strictEqual(model.parseStageLine("mihoro: update initiated").kind, "other")

// Colour escapes are stripped, and a bracket that is not an escape survives.
assert.strictEqual(model.stripAnsi("\x1b[32m✓\x1b[0m config"), "✓ config")
assert.strictEqual(model.stripAnsi("value [a] kept"), "value [a] kept")

// The failed stage beats the exit code and beats stderr.
const summary = `mihoro: update initiated
● config
 ⎿  refreshing remote config
mihoro: update summary
  ✗ config: error sending request for url
  ↷ service restart (skipped due to earlier failures)
`
assert.strictEqual(model.stageFailureMessage(summary, "fallback"),
  "config: error sending request for url")
assert.strictEqual(model.stageFailureMessage("", "fallback"), "fallback")
assert.strictEqual(model.stageFailureMessage("something went sideways\n", "fallback"),
  "something went sideways")

// ------------------------------------------------------------ subscriptions

assert.strictEqual(model.subscriptionUrlError("https://example.com/sub"), "")
assert.strictEqual(model.subscriptionUrlError("http://example.com/sub"), "")
assert.ok(model.subscriptionUrlError("").includes("Enter"))
assert.ok(model.subscriptionUrlError("example.com/sub").includes("http://"))
assert.ok(model.subscriptionUrlError("ftp://example.com/sub").includes("http://"))
assert.strictEqual(model.isValidSubscriptionUrl("https://example.com/sub"), true)
assert.strictEqual(model.isValidSubscriptionUrl("nope"), false)

// The token is the credential, so it is hidden whole rather than partially —
// half a token is still half a token to anyone reading over a shoulder.
const masked = model.maskUrl("https://sub.example.com/link/AbCdEf123456789?clash=1&token=supersecretvalue")
assert.strictEqual(masked, "https://sub.example.com/*******")
assert.ok(!masked.includes("AbCdEf123456789"))
assert.ok(!masked.includes("supersecretvalue"))
assert.strictEqual(
  model.maskUrl("https://panel.example.com/users/api/s/abcdefghijklmnop?token=supersecretvalue"),
  "https://panel.example.com/*******")

// Even short paths can identify an account or endpoint, so the entire tail is
// hidden. Only the origin remains useful for recognizing the provider.
assert.strictEqual(model.maskUrl("https://example.com/sub"), "https://example.com/*******")
assert.strictEqual(model.maskUrl(""), "")

assert.strictEqual(model.displayUrl("", false), "No subscription URL yet")
assert.strictEqual(model.displayUrl("https://example.com/aVeryLongTokenHere", true),
  "https://example.com/aVeryLongTokenHere")
assert.ok(!model.displayUrl("https://example.com/aVeryLongTokenHere", false)
  .includes("aVeryLongTokenHere"))

// ------------------------------------------------------------------ history

// A `var` property's bindings only re-run on assignment, so the array the
// panel already holds must not be the one that grew.
const seed = [1, 2, 3]
const grown = model.pushHistory(seed, 4, 60)
assert.strictEqual(seed.length, 3, "the caller's array must not be mutated")
assert.strictEqual(grown.length, 4)
assert.strictEqual(grown[3], 4)

// The window slides once it is full; the oldest sample falls off the front.
let window = []
for (let i = 1; i <= 8; i++) window = model.pushHistory(window, i, 5)
assert.strictEqual(window.length, 5)
assert.strictEqual(window[0], 4)
assert.strictEqual(window[4], 8)

assert.deepStrictEqual(Array.from(model.pushHistory(null, 7, 3)), [7])
assert.deepStrictEqual(Array.from(model.pushHistory([], "nope", 3)), [0])
assert.deepStrictEqual(Array.from(model.pushHistory([], -5, 3)), [0])
assert.strictEqual(model.pushHistory([1, 2, 3], 4, 0).length, 1, "a zero cap still keeps the newest")

// ---- gaps
//
// The history outlives a closed panel, so the seconds nothing was sampled have
// to occupy the width they really lasted. Otherwise a sample from ten minutes
// ago ends up drawn next to one from now.
let before = null
for (const n of [10, 20, 30]) before = model.pushHistory(before, n, 60)
const afterGap = model.padHistory(before, 4, 60)
assert.strictEqual(afterGap.length, 7)
assert.deepStrictEqual(Array.from(afterGap).slice(3), [0, 0, 0, 0])
assert.deepStrictEqual(Array.from(afterGap).slice(0, 3), [10, 20, 30],
  "the samples either side of a gap must survive it")

// A fractional gap counts whole slots only, and a gap of none changes nothing.
assert.strictEqual(model.padHistory(before, 2.9, 60).length, 5)
assert.strictEqual(model.padHistory(before, 0, 60), before)
assert.strictEqual(model.padHistory(before, -3, 60), before)
assert.strictEqual(model.padHistory(before, NaN, 60), before)

// A gap longer than the window leaves nothing of the old series: the chart
// comes back flat rather than showing a minute of stale traffic.
const stale = model.padHistory(before, 5000, 60)
assert.strictEqual(stale.length, 60)
assert.ok(Array.from(stale).every(function (n) { return n === 0 }))

// ---- sparkline geometry
//
// Newest on the right edge, growing leftward, so a series that has just
// started does not claim the full width.
const young = model.sparkline([10, 20], 11)
assert.strictEqual(young.points.length, 2)
assert.strictEqual(young.points[1].x, 1, "the newest sample is pinned to the right edge")
assert.strictEqual(young.points[0].x, 0.9, "one sample back is one slot in from it")

const full = model.sparkline([1, 2, 3], 3)
assert.strictEqual(full.points[0].x, 0, "a full window starts at the left edge")
assert.strictEqual(full.points[2].x, 1)

// Zero-based scale: twice the throughput draws twice as tall. A min..max scale
// would put the quiet second on the floor and the next one at the ceiling.
const jitter = model.sparkline([70, 71], 60)
assert.strictEqual(jitter.peak, 71)
assert.ok(jitter.points[0].y > 0.98, "an idle line's own jitter must not fill the box")
const doubled = model.sparkline([25, 50], 60)
assert.strictEqual(doubled.points[0].y, 0.5)
assert.strictEqual(doubled.points[1].y, 1)

// ---- shared scale
//
// Two curves side by side in the same units have to be comparable by height,
// so the caller passes one peak for both.
assert.strictEqual(model.peakOf([3, 91, 12]), 91)
assert.strictEqual(model.peakOf(null), 0)
assert.strictEqual(model.peakOf([]), 0)
assert.strictEqual(model.peakOf(["nope", 4]), 4)

const download = model.sparkline([500000, 1000000], 60, 1000000)
const upload = model.sparkline([1000, 2000], 60, 1000000)
assert.strictEqual(download.points[1].y, 1)
assert.ok(upload.points[1].y < 0.01, "a trickle beside a torrent must draw as a low line")
// Left to itself the same trickle would fill the box — that is the bug the
// shared peak exists to prevent.
assert.strictEqual(model.sparkline([1000, 2000], 60).points[1].y, 1)

// A shared peak can lag a series that just spiked past it; the curve clamps
// rather than drawing outside its own box.
const spike = model.sparkline([100, 5000], 60, 1000)
assert.strictEqual(spike.points[1].y, 1)
// A non-positive or unusable override falls back to the window's own peak.
assert.strictEqual(model.sparkline([25, 50], 60, 0).points[0].y, 0.5)
assert.strictEqual(model.sparkline([25, 50], 60, "nope").points[0].y, 0.5)

// An all-zero window has no peak to divide by and must stay flat, not NaN.
const idle = model.sparkline([0, 0, 0], 60)
assert.strictEqual(idle.peak, 0)
assert.ok(idle.points.every(function (point) { return point.y === 0 }))

// ---- the baseline lead
//
// The un-sampled part of the window is returned separately so the chart can
// draw a flat line across it — an empty chart is a baseline, not a blank box —
// while the filled area still marks only what was measured.
const empty = model.sparkline([], 60)
assert.strictEqual(empty.points.length, 0)
assert.strictEqual(empty.lead.length, 2, "an empty chart still draws a line")
assert.strictEqual(empty.lead[0].x, 0)
assert.strictEqual(empty.lead[1].x, 1, "the baseline spans the full width")
assert.ok(empty.lead.every(function (point) { return point.y === 0 }))

// Partly filled: the lead runs from the left edge to where the samples start.
const partial = model.sparkline([5, 9], 11)
assert.strictEqual(partial.lead.length, 2)
assert.strictEqual(partial.lead[0].x, 0)
assert.strictEqual(partial.lead[1].x, partial.points[0].x)

// Full window: nothing left to lead in with.
assert.strictEqual(model.sparkline([1, 2, 3], 3).lead.length, 0)

assert.strictEqual(model.sparkline(null, 60).points.length, 0)
assert.strictEqual(model.sparkline([], 60).points.length, 0)
// A capacity too small to space samples in must not divide by zero.
assert.ok(model.sparkline([1, 2], 1).points.every(function (point) {
  return isFinite(point.x) && point.x >= 0 && point.x <= 1
}))

// ---------------------------------------------------------------- formatting

assert.strictEqual(model.formatBytes(0), "0 B")
assert.strictEqual(model.formatBytes(512), "512 B")
assert.strictEqual(model.formatBytes(1024), "1.0 KiB")
assert.strictEqual(model.formatBytes(1536), "1.5 KiB")
assert.strictEqual(model.formatBytes(1024 * 1024 * 3.5), "3.5 MiB")
assert.strictEqual(model.formatBytes(1024 * 1024 * 20), "20 MiB")
assert.strictEqual(model.formatBytes(-5), "0 B")
assert.strictEqual(model.formatSpeed(2048), "2.0 KiB/s")

// The divisor is 1024, so the unit has to say so: "815 MB" for 854,590,870
// bytes reads 4.6% low against the megabyte every other tool means.
assert.strictEqual(model.formatBytes(854590870), "815 MiB")
assert.ok(model.UNITS.every(function (unit) { return !/^[KMGTP]B$/.test(unit) }),
  "1024-based units must not be labelled with decimal names")

assert.strictEqual(model.formatDuration(0), "0s")
assert.strictEqual(model.formatDuration(45), "45s")
assert.strictEqual(model.formatDuration(90), "1m 30s")
assert.strictEqual(model.formatDuration(3600), "1h 0m")
assert.strictEqual(model.formatDuration(3600 * 26), "1d 2h")
assert.strictEqual(model.formatDuration(-1), "—")

assert.strictEqual(model.formatAgo(0, 100), "—")
assert.strictEqual(model.formatAgo(100, 0), "—")
assert.strictEqual(model.formatAgo(100, 130), "just now")
assert.strictEqual(model.formatAgo(0 + 1000, 1000 + 600), "10m ago")
assert.strictEqual(model.formatAgo(1000, 1000 + 7200), "2h ago")

// Live values beat the file's, since the file only says what the next restart
// will use.
assert.strictEqual(
  model.formatPorts({ mixedPort: 7890, port: 7891, socksPort: 7892 }, null),
  "mixed 7890 · http 7891 · socks 7892")
assert.strictEqual(
  model.formatPorts({ mixedPort: 7890, port: 0, socksPort: 0 }, { mixedPort: 1080, port: 0, socksPort: 0 }),
  "mixed 1080")
assert.strictEqual(model.formatPorts({ mixedPort: 0, port: 0, socksPort: 0 }, null), "—")

assert.strictEqual(model.modeLabel("global"), "Global")
assert.strictEqual(model.modeLabel("nope"), "Rule")
assert.strictEqual(model.modeIndex("direct"), 2)
assert.strictEqual(model.modeIndex("nope"), 0)
assert.strictEqual(model.MODES.length, 3)

// Global needs a concrete outbound before it can be enabled; the other modes
// are complete choices by themselves.
assert.strictEqual(model.modeSelectionAction("global", "rule"), "choose_proxy")
assert.strictEqual(model.modeSelectionAction("global", "global"), "choose_proxy")
assert.strictEqual(model.modeSelectionAction("direct", "rule"), "switch")
assert.strictEqual(model.modeSelectionAction("rule", "rule"), "none")
assert.strictEqual(model.modeSelectionAction("sideways", "rule"), "none")

console.log("model tests passed")
