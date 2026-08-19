.pragma library

// mihoro sets up mihomo's control API and prints its address at the end of
// `mihoro init`; this is the same API the metacubexd dashboard it installs
// talks to. Everything the panel needs to *read* live — the running mode, the
// version actually serving, traffic, open connections — comes from there, and
// so does the mode switch, because `PATCH /configs` changes the mode of the
// running core in place. The CLI is reserved for the things that have no API:
// service lifecycle and pulling the subscription.
//
// Requests go through curl rather than XMLHttpRequest because that is the
// shell's established way of reaching the network from a plugin, and it gives
// the panel an exit code and a stderr to classify failures with.
//
// `-w '\n%{http_code}'` appends the status to the body instead of using `-f`,
// so a 401 from a wrong `secret` stays distinguishable from a core that is not
// listening at all. Those two need different things said to the user.

var TIMEOUT_SECONDS = "4"
var MODES = ["rule", "global", "direct"]

function normalizeMode(value) {
  var mode = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return MODES.indexOf(mode) >= 0 ? mode : ""
}

function isWildcardHost(host) {
  var text = String(host || "").trim()
  return text === "" || text === "*" || text === "0.0.0.0" || text === "::" || text === "[::]"
}

// Mirrors mihoro's own `parse_controller_address`: strip any scheme, honour
// bracketed IPv6, and split the port off the right. A controller with no port
// is not addressable, and mihoro treats it the same way.
function parseController(controller) {
  var text = String(controller === undefined || controller === null ? "" : controller).trim()
  if (text === "") return null
  if (/^unix:/i.test(text)) return null
  text = text.replace(/^https?:\/\//i, "").replace(/\/+$/, "")

  if (text.charAt(0) === "[") {
    var close = text.indexOf("]")
    if (close < 0) return null
    var rest = text.substring(close + 1)
    if (rest.charAt(0) !== ":") return null
    var bracketPort = rest.substring(1).trim()
    if (bracketPort === "") return null
    return { host: text.substring(0, close + 1), port: bracketPort }
  }

  var split = text.lastIndexOf(":")
  if (split < 0) return null
  var host = text.substring(0, split).trim()
  var port = text.substring(split + 1).trim()
  if (port === "") return null
  return { host: host, port: port }
}

// A controller bound to every interface is still only reachable from here over
// loopback, so `0.0.0.0` and `[::]` become `127.0.0.1` — the same substitution
// mihoro makes when it prints the dashboard URL.
function baseUrl(controller) {
  var parsed = parseController(controller)
  if (!parsed) return ""
  var host = isWildcardHost(parsed.host) ? "127.0.0.1" : parsed.host
  if (host.indexOf(":") >= 0 && host.charAt(0) !== "[") host = "[" + host + "]"
  return "http://" + host + ":" + parsed.port
}

function authArgs(secret) {
  var token = String(secret === undefined || secret === null ? "" : secret)
  return token === "" ? [] : ["-H", "Authorization: Bearer " + token]
}

function getCommand(base, secret, path) {
  return ["curl", "-sS", "--max-time", TIMEOUT_SECONDS, "-w", "\\n%{http_code}"]
    .concat(authArgs(secret))
    .concat([String(base) + String(path)])
}

function versionCommand(base, secret) { return getCommand(base, secret, "/version") }
function configsCommand(base, secret) { return getCommand(base, secret, "/configs") }
function connectionsCommand(base, secret) { return getCommand(base, secret, "/connections") }
function proxiesCommand(base, secret) { return getCommand(base, secret, "/proxies") }

function setModeCommand(base, secret, mode) {
  return ["curl", "-sS", "--max-time", TIMEOUT_SECONDS, "-w", "\\n%{http_code}",
          "-X", "PATCH", "-H", "Content-Type: application/json",
          "-d", JSON.stringify({ mode: normalizeMode(mode) || "rule" })]
    .concat(authArgs(secret))
    .concat([String(base) + "/configs"])
}

function selectProxyCommand(base, secret, group, name) {
  return ["curl", "-sS", "--max-time", TIMEOUT_SECONDS, "-w", "\\n%{http_code}",
          "-X", "PUT", "-H", "Content-Type: application/json",
          "-d", JSON.stringify({ name: String(name || "") })]
    .concat(authArgs(secret))
    .concat([String(base) + "/proxies/" + encodeURIComponent(String(group || ""))])
}

// `/traffic` pushes one JSON object per second for as long as the socket is
// held open, so live speeds cost one long-lived curl while the panel is open
// instead of a poll loop. `--no-buffer` is what makes each line arrive as it
// is written rather than in 4KB chunks.
function trafficCommand(base, secret) {
  return ["curl", "-sS", "-N", "--no-buffer"]
    .concat(authArgs(secret))
    .concat([String(base) + "/traffic"])
}

function splitResponse(text) {
  var raw = String(text === undefined || text === null ? "" : text)
  var cut = raw.lastIndexOf("\n")
  if (cut < 0) return { status: parseInt(raw, 10) || 0, body: "" }
  return { status: parseInt(raw.substring(cut + 1), 10) || 0, body: raw.substring(0, cut) }
}

// One classifier for every call, so "unreachable", "wrong secret", and "the
// core answered with an error" are never collapsed into a single failure.
function classify(exitCode, stdout, stderr) {
  var response = splitResponse(stdout)
  if (Number(exitCode) !== 0 || response.status === 0) {
    return {
      ok: false,
      code: "unreachable",
      status: response.status,
      body: response.body,
      message: "mihomo's API is not answering."
    }
  }
  if (response.status === 401 || response.status === 403) {
    return {
      ok: false,
      code: "unauthorized",
      status: response.status,
      body: response.body,
      message: "mihomo rejected the API secret in mihoro.toml."
    }
  }
  if (response.status >= 400) {
    return {
      ok: false,
      code: "http_error",
      status: response.status,
      body: response.body,
      message: "mihomo's API returned HTTP " + response.status + "."
    }
  }
  return { ok: true, code: "ok", status: response.status, body: response.body, message: "" }
}

function parseJson(text) {
  try {
    var value = JSON.parse(String(text || ""))
    return (value && typeof value === "object") ? value : null
  } catch (error) {
    return null
  }
}

function parseVersion(body) {
  var payload = parseJson(body)
  if (!payload) return { version: "", meta: false }
  return { version: String(payload.version || ""), meta: payload.meta === true }
}

function parseConfigs(body) {
  var payload = parseJson(body)
  if (!payload) return null
  var tun = payload.tun
  var tunEnabled = tun && typeof tun === "object" && typeof tun.enable === "boolean"
    ? tun.enable
    : null
  return {
    mode: normalizeMode(payload.mode),
    port: Number(payload.port) || 0,
    socksPort: Number(payload["socks-port"]) || 0,
    mixedPort: Number(payload["mixed-port"]) || 0,
    allowLan: payload["allow-lan"] === true,
    tunEnabled: tunEnabled,
    logLevel: String(payload["log-level"] || "")
  }
}

// Only the totals and the count are kept. The connections array carries a
// metadata object per entry and can run to hundreds of them; holding that in
// the panel to render two numbers would be the most expensive thing it does.
function parseConnections(body) {
  var payload = parseJson(body)
  if (!payload) return null
  var list = payload.connections
  return {
    count: (list instanceof Array) ? list.length : 0,
    downloadTotal: Number(payload.downloadTotal) || 0,
    uploadTotal: Number(payload.uploadTotal) || 0,
    memory: Number(payload.memory) || 0
  }
}

function parseGlobalProxies(body) {
  var payload = parseJson(body)
  if (!payload) return null
  var proxies = payload.proxies
  var group = proxies && typeof proxies === "object" ? proxies.GLOBAL : null
  var all = group && group.all instanceof Array ? group.all : []
  var options = []
  for (var i = 0; i < all.length; i++) {
    var name = String(all[i] || "")
    if (name !== "") options.push({ value: name, label: name })
  }
  return { current: group ? String(group.now || "") : "", options: options }
}

// `Number(null)` is 0 and `Number("")` is 0, either of which would pass for a
// counter that is simply absent. A missing field has to stay missing.
function finiteNumber(value) {
  if (value === undefined || value === null || value === "") return NaN
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : NaN
}

// A `/traffic` message carries both a per-interval reading (`up`/`down`) and
// the core's cumulative counters (`upTotal`/`downTotal`). Both are kept: the
// totals are what the rate is actually derived from, and the per-interval
// numbers are the fallback for cores old enough not to send totals.
function parseTrafficLine(line) {
  var payload = parseJson(line)
  if (!payload) return null
  var up = Number(payload.up)
  var down = Number(payload.down)
  if (!isFinite(up) || !isFinite(down)) return null
  var upTotal = finiteNumber(payload.upTotal)
  var downTotal = finiteNumber(payload.downTotal)
  var hasTotals = isFinite(upTotal) && isFinite(downTotal)
  return {
    up: up,
    down: down,
    upTotal: hasTotals ? upTotal : 0,
    downTotal: hasTotals ? downTotal : 0,
    hasTotals: hasTotals
  }
}

// Below this there is not enough wall clock for the division to mean anything.
var MIN_RATE_INTERVAL_SECONDS = 0.2

// Why the rate is not simply `up`/`down`:
//
// mihomo fills `up`/`down` from a snapshot buffer that its own one-second
// ticker overwrites, but the stream is written by a *second* ticker started
// when the socket opened. The two run at the same rate out of phase, so the
// handler regularly emits one buffer twice and skips the next. Measured
// against the totals in the very same messages, 59 of 60 consecutive samples
// disagreed with the traffic that actually moved — the worst by 292x — even
// though the sum over the minute was correct to within 0.01%. Totals are
// exact and monotonic, so differencing them gives a reading that is right in
// the second you are looking at it, not merely right on average.
//
// `anchor` is the last reading a rate was published from, not the previous
// sample. When a sample arrives too soon after it to divide by, the anchor
// stays put: those bytes remain counted and land in the next reading instead
// of being divided by a near-zero interval into a spike.
function trafficRate(anchor, sample, atSeconds) {
  if (!sample) return null
  var now = Number(atSeconds)
  if (!isFinite(now) || now < 0) now = 0

  // Nothing to difference. The core's own reading is all there is.
  if (!sample.hasTotals)
    return { rate: { up: sample.up, down: sample.down }, anchor: null }

  var next = { up: sample.upTotal, down: sample.downTotal, at: now }

  // No anchor yet, or the counters went backwards because the core restarted
  // underneath the stream. Show what this message claims and start again here.
  if (!anchor || sample.upTotal < anchor.up || sample.downTotal < anchor.down)
    return { rate: { up: sample.up, down: sample.down }, anchor: next }

  var elapsed = now - anchor.at
  if (!(elapsed >= MIN_RATE_INTERVAL_SECONDS))
    return { rate: null, anchor: anchor }

  return {
    rate: {
      up: (sample.upTotal - anchor.up) / elapsed,
      down: (sample.downTotal - anchor.down) / elapsed
    },
    anchor: next
  }
}
