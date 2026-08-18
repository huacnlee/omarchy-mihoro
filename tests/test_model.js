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
assert.deepStrictEqual(Array.from(model.installCommand("/plugins/mihoro/scripts/install-mihoro")), [
  "omarchy", "launch", "terminal", "/plugins/mihoro/scripts/install-mihoro", "--from-ui"
])

const hangupNotice = model.installExitNotice(1, `warn: wayland.c:1854: compositor does not implement
the xdg-toplevel-icon protocol
warn: terminal.c:2034: slave exited with signal 1 (Hangup)`)
assert.strictEqual(hangupNotice.kind, "warning")
assert.ok(hangupNotice.message.includes("Hangup"))
assert.strictEqual(model.installExitNotice(1, "curl: could not resolve host").kind, "error")
assert.strictEqual(model.installExitNotice(1, "warn: wayland.c:1854\ncurl failed").kind, "error")
assert.strictEqual(model.installExitNotice(0, "").kind, "")

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

// ---------------------------------------------------------------- formatting

assert.strictEqual(model.formatBytes(0), "0 B")
assert.strictEqual(model.formatBytes(512), "512 B")
assert.strictEqual(model.formatBytes(1024), "1.0 KB")
assert.strictEqual(model.formatBytes(1536), "1.5 KB")
assert.strictEqual(model.formatBytes(1024 * 1024 * 3.5), "3.5 MB")
assert.strictEqual(model.formatBytes(1024 * 1024 * 20), "20 MB")
assert.strictEqual(model.formatBytes(-5), "0 B")
assert.strictEqual(model.formatSpeed(2048), "2.0 KB/s")

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
