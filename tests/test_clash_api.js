const assert = require("assert")
const { load } = require("./load")

const api = load("ClashApi.js")

// ------------------------------------------------- controller normalisation
//
// These mirror mihoro's own `parse_controller_address` / `is_wildcard_host`,
// including the cases its tests cover, so the panel and the dashboard URL
// mihoro prints always point at the same place.

assert.strictEqual(api.baseUrl("0.0.0.0:9090"), "http://127.0.0.1:9090")
assert.strictEqual(api.baseUrl("127.0.0.1:9090"), "http://127.0.0.1:9090")
assert.strictEqual(api.baseUrl("[::]:19090"), "http://127.0.0.1:19090")
assert.strictEqual(api.baseUrl("[::1]:9090"), "http://[::1]:9090")
assert.strictEqual(api.baseUrl("10.108.25.191:19090"), "http://10.108.25.191:19090")
assert.strictEqual(api.baseUrl("  0.0.0.0:9090  "), "http://127.0.0.1:9090")
assert.strictEqual(api.baseUrl("http://127.0.0.1:9090/"), "http://127.0.0.1:9090")
assert.strictEqual(api.baseUrl("https://box.example:9090"), "http://box.example:9090")
assert.strictEqual(api.baseUrl(":9090"), "http://127.0.0.1:9090")

// No port means no address; a unix socket is not something curl reaches this
// way. Both must yield "" so the panel says the API is unconfigured rather
// than firing requests at a nonsense URL.
assert.strictEqual(api.baseUrl("127.0.0.1"), "")
assert.strictEqual(api.baseUrl(""), "")
assert.strictEqual(api.baseUrl(null), "")
assert.strictEqual(api.baseUrl(undefined), "")
assert.strictEqual(api.baseUrl("unix:///run/mihomo.sock"), "")
assert.strictEqual(api.baseUrl("[::1"), "")

// ---------------------------------------------------------------- commands

const version = api.versionCommand("http://127.0.0.1:9090", "")
assert.strictEqual(version[0], "curl")
assert.ok(version.includes("--max-time"))
assert.strictEqual(version[version.length - 1], "http://127.0.0.1:9090/version")
assert.ok(!version.some(arg => /Authorization/.test(arg)), "no auth header without a secret")

const authed = api.configsCommand("http://127.0.0.1:9090", "s3cret")
assert.ok(authed.includes("Authorization: Bearer s3cret"))
assert.strictEqual(authed[authed.length - 1], "http://127.0.0.1:9090/configs")

const connections = api.connectionsCommand("http://127.0.0.1:9090", "")
assert.strictEqual(connections[connections.length - 1], "http://127.0.0.1:9090/connections")

const proxies = api.proxiesCommand("http://127.0.0.1:9090", "s3cret")
assert.ok(proxies.includes("Authorization: Bearer s3cret"))
assert.strictEqual(proxies[proxies.length - 1], "http://127.0.0.1:9090/proxies")

const selectGlobal = api.selectProxyCommand("http://127.0.0.1:9090", "s3cret", "GLOBAL", "Tokyo JP")
assert.ok(selectGlobal.includes("PUT"))
assert.ok(selectGlobal.includes('{"name":"Tokyo JP"}'))
assert.strictEqual(selectGlobal[selectGlobal.length - 1], "http://127.0.0.1:9090/proxies/GLOBAL")

const setMode = api.setModeCommand("http://127.0.0.1:9090", "s3cret", "Global")
assert.ok(setMode.includes("PATCH"))
assert.ok(setMode.includes('{"mode":"global"}'), "mode is normalised before it is sent")
assert.ok(setMode.includes("Authorization: Bearer s3cret"))
assert.strictEqual(setMode[setMode.length - 1], "http://127.0.0.1:9090/configs")

// An unknown mode never reaches the core as-is.
assert.ok(api.setModeCommand("http://x:9090", "", "sideways").includes('{"mode":"rule"}'))

const traffic = api.trafficCommand("http://127.0.0.1:9090", "")
assert.ok(traffic.includes("-N"), "the traffic stream must not be buffered")
assert.ok(traffic.includes("--no-buffer"))
assert.ok(!traffic.includes("--max-time"), "a stream that is meant to stay open has no deadline")
assert.strictEqual(traffic[traffic.length - 1], "http://127.0.0.1:9090/traffic")

assert.strictEqual(api.normalizeMode("RULE"), "rule")
assert.strictEqual(api.normalizeMode(" Direct "), "direct")
assert.strictEqual(api.normalizeMode("nope"), "")

// ---------------------------------------------------------------- responses

// Objects cross the vm boundary, so their prototypes differ from this realm's;
// fields are compared directly rather than with deepStrictEqual.
const split = api.splitResponse('{"mode":"rule"}\n200')
assert.strictEqual(split.status, 200)
assert.strictEqual(split.body, '{"mode":"rule"}')
assert.strictEqual(api.splitResponse("\n401").status, 401)
assert.strictEqual(api.splitResponse("\n401").body, "")
assert.strictEqual(api.splitResponse("").status, 0)
assert.strictEqual(api.splitResponse("").body, "")

// A body that itself contains newlines still gives up only its last line.
assert.strictEqual(api.splitResponse("{\n  \"a\": 1\n}\n200").body, "{\n  \"a\": 1\n}")

// classify keeps "not listening", "wrong secret", and "server said no" apart,
// because each one needs a different thing said to the user.
assert.strictEqual(api.classify(7, "", "connection refused").code, "unreachable")
assert.strictEqual(api.classify(0, "", "").code, "unreachable")
assert.strictEqual(api.classify(0, '{"message":"unauthorized"}\n401', "").code, "unauthorized")
assert.strictEqual(api.classify(0, "nope\n403", "").code, "unauthorized")
assert.strictEqual(api.classify(0, "boom\n500", "").code, "http_error")

const ok = api.classify(0, '{"mode":"global"}\n200', "")
assert.strictEqual(ok.ok, true)
assert.strictEqual(ok.body, '{"mode":"global"}')

// ------------------------------------------------------------------ parsers

const parsedVersion = api.parseVersion('{"version":"1.19.2","meta":true}')
assert.strictEqual(parsedVersion.version, "1.19.2")
assert.strictEqual(parsedVersion.meta, true)
assert.strictEqual(api.parseVersion("not json").version, "")
assert.strictEqual(api.parseVersion("not json").meta, false)

const configs = api.parseConfigs(JSON.stringify({
  port: 7891,
  "socks-port": 7892,
  "mixed-port": 7890,
  "allow-lan": true,
  tun: { enable: true },
  mode: "Global",
  "log-level": "info"
}))
assert.strictEqual(configs.mode, "global")
assert.strictEqual(configs.mixedPort, 7890)
assert.strictEqual(configs.port, 7891)
assert.strictEqual(configs.socksPort, 7892)
assert.strictEqual(configs.allowLan, true)
assert.strictEqual(configs.tunEnabled, true)
assert.strictEqual(api.parseConfigs('{"tun":{"enable":false}}').tunEnabled, false)
assert.strictEqual(api.parseConfigs('{"mode":"rule"}').tunEnabled, null)
assert.strictEqual(api.parseConfigs("["), null)

const conns = api.parseConnections(JSON.stringify({
  downloadTotal: 1024,
  uploadTotal: 512,
  connections: [{ id: "a" }, { id: "b" }, { id: "c" }],
  memory: 4096
}))
assert.strictEqual(conns.count, 3)
assert.strictEqual(conns.downloadTotal, 1024)
assert.strictEqual(conns.uploadTotal, 512)
assert.strictEqual(conns.memory, 4096)

// mihomo sends `connections: null` when there are none.
assert.strictEqual(api.parseConnections('{"downloadTotal":1,"uploadTotal":2,"connections":null}').count, 0)
assert.strictEqual(api.parseConnections("nope"), null)

const global = api.parseGlobalProxies(JSON.stringify({
  proxies: {
    GLOBAL: { type: "Selector", now: "Tokyo JP", all: ["DIRECT", "Tokyo JP", "Singapore"] },
    "Tokyo JP": { type: "Shadowsocks" }
  }
}))
assert.strictEqual(global.current, "Tokyo JP")
assert.strictEqual(global.options.length, 3)
assert.strictEqual(global.options[0].value, "DIRECT")
assert.strictEqual(global.options[2].label, "Singapore")
assert.strictEqual(api.parseGlobalProxies('{"proxies":{}}').options.length, 0)
assert.strictEqual(api.parseGlobalProxies("nope"), null)

const sample = api.parseTrafficLine('{"up":120,"down":4096}')
assert.strictEqual(sample.up, 120)
assert.strictEqual(sample.down, 4096)
assert.strictEqual(sample.hasTotals, false, "a core that sends no totals must say so")
assert.strictEqual(api.parseTrafficLine(""), null)
assert.strictEqual(api.parseTrafficLine("{}"), null)

const withTotals = api.parseTrafficLine('{"up":1,"down":2,"upTotal":300,"downTotal":400}')
assert.strictEqual(withTotals.hasTotals, true)
assert.strictEqual(withTotals.upTotal, 300)
assert.strictEqual(withTotals.downTotal, 400)

// `Number(null)` is 0, which would pass for a counter reading zero.
assert.strictEqual(api.parseTrafficLine('{"up":1,"down":2,"upTotal":null,"downTotal":null}').hasTotals, false)
assert.strictEqual(api.parseTrafficLine('{"up":1,"down":2,"upTotal":5}').hasTotals, false)

// ------------------------------------------------------------- traffic rate
//
// mihomo's `up`/`down` are a buffer its own one-second ticker overwrites,
// emitted by a second ticker running out of phase with it, so consecutive
// samples double-count and skip. The totals in the same message are exact, so
// the rate comes from differencing them over the wall clock that really passed.

const first = api.parseTrafficLine('{"up":9,"down":9,"upTotal":1000,"downTotal":5000}')
const opening = api.trafficRate(null, first, 100)
// Objects come out of the vm realm the loader uses, so their prototype is not
// this realm's; fields are compared rather than whole objects.
assert.strictEqual(opening.rate.up, 9, "with nothing to difference yet, the core's own reading is all there is")
assert.strictEqual(opening.rate.down, 9)
assert.strictEqual(opening.anchor.up, 1000)
assert.strictEqual(opening.anchor.down, 5000)
assert.strictEqual(opening.anchor.at, 100)

// One second later: 500 up and 20000 down really moved, whatever `up`/`down` say.
const second = api.parseTrafficLine('{"up":999999,"down":1,"upTotal":1500,"downTotal":25000}')
const rated = api.trafficRate(opening.anchor, second, 101)
assert.strictEqual(rated.rate.up, 500)
assert.strictEqual(rated.rate.down, 20000)
assert.strictEqual(rated.anchor.up, 1500)
assert.strictEqual(rated.anchor.down, 25000)
assert.strictEqual(rated.anchor.at, 101)

// Half a second is still divisible, and the rate is per second, not per sample.
const half = api.parseTrafficLine('{"up":0,"down":0,"upTotal":1750,"downTotal":25000}')
assert.strictEqual(api.trafficRate(rated.anchor, half, 101.5).rate.up, 500)

// Two lines delivered back to back must not divide a whole interval by ~0. The
// anchor stays put so those bytes land in the next reading instead of spiking.
const burst = api.parseTrafficLine('{"up":0,"down":0,"upTotal":9000,"downTotal":30000}')
const held = api.trafficRate(rated.anchor, burst, 101.01)
assert.strictEqual(held.rate, null, "too soon to divide by")
assert.strictEqual(held.anchor, rated.anchor, "the anchor must not move")
// ...and the bytes are still there one second on: 9000-1500 over 1.01s.
const flushed = api.trafficRate(held.anchor, burst, 102.01)
assert.ok(Math.abs(flushed.rate.up - 7500 / 1.01) < 1e-9)

// A core that restarted underneath the stream resets its counters; a negative
// delta must not be shown as a negative speed.
const restarted = api.parseTrafficLine('{"up":7,"down":7,"upTotal":10,"downTotal":10}')
const recovered = api.trafficRate(rated.anchor, restarted, 105)
assert.strictEqual(recovered.rate.up, 7)
assert.strictEqual(recovered.rate.down, 7)
assert.strictEqual(recovered.anchor.up, 10)
assert.strictEqual(recovered.anchor.down, 10)
assert.strictEqual(recovered.anchor.at, 105)

// Cores too old to send totals keep the old behaviour and never grow an anchor.
const legacy = api.trafficRate(null, api.parseTrafficLine('{"up":8,"down":9}'), 200)
assert.strictEqual(legacy.rate.up, 8)
assert.strictEqual(legacy.rate.down, 9)
assert.strictEqual(legacy.anchor, null)

assert.strictEqual(api.trafficRate(null, null, 1), null)

console.log("clash API tests passed")
