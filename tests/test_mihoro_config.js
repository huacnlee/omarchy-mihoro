const assert = require("assert")
const { load } = require("./load")

const config = load("MihoroConfig.js")

// ---------------------------------------------------------------- parsing

const SAMPLE = `remote_config_url = "https://example.com/sub?token=abcdefghijkl"
mihomo_channel = "stable"
mihomo_binary_path = "~/.local/bin/mihomo"
mihomo_config_root = "~/.config/mihomo"
user_systemd_root = "~/.config/systemd/user"
mihoro_user_agent = "mihoro"
auto_update_interval = 12

[mihomo_config]
port = 7891
socks_port = 7892
mixed_port = 7890
allow_lan = false
bind_address = "*"
mode = "rule"
log_level = "info"
ipv6 = true
external_controller = "0.0.0.0:9090"
external_ui = "ui"
`

const parsed = config.parse(SAMPLE)
assert.strictEqual(parsed.remoteConfigUrl, "https://example.com/sub?token=abcdefghijkl")
assert.strictEqual(parsed.mihomoConfigRoot, "~/.config/mihomo")
assert.strictEqual(parsed.mihomoBinaryPath, "~/.local/bin/mihomo")
assert.strictEqual(parsed.mode, "rule")
assert.strictEqual(parsed.externalController, "0.0.0.0:9090")
assert.strictEqual(parsed.externalUi, "ui")
assert.strictEqual(parsed.mixedPort, 7890)
assert.strictEqual(parsed.port, 7891)
assert.strictEqual(parsed.socksPort, 7892)
assert.strictEqual(parsed.allowLan, false)
assert.strictEqual(parsed.secret, "")
assert.strictEqual(parsed.autoUpdateInterval, 12)

// An empty or missing file parses to defaults instead of throwing — the panel
// reads it before it knows whether mihoro has ever run.
assert.strictEqual(config.parse("").remoteConfigUrl, "")
assert.strictEqual(config.parse("").mode, "rule")
assert.strictEqual(config.parse(null).mihomoConfigRoot, "~/.config/mihomo")

// A `#` inside a value is part of the URL, not a comment.
const withFragment = config.parse('remote_config_url = "https://example.com/s#frag"\n')
assert.strictEqual(withFragment.remoteConfigUrl, "https://example.com/s#frag")

// An unknown mode falls back rather than propagating a value mihomo would reject.
assert.strictEqual(config.parse('[mihomo_config]\nmode = "tunnel"\n').mode, "rule")
assert.strictEqual(config.parse("[mihomo_config]\nallow_lan = true\n").allowLan, true)
assert.strictEqual(config.parse("[mihomo_config]\nsecret = 'literal-secret'\n").secret, "literal-secret")

// ---------------------------------------------------------------- patching

// Replacing in place leaves every other line — and their order — untouched.
const swapped = config.patch(SAMPLE, { mode: "global" })
assert.ok(swapped.includes('mode = "global"'))
assert.ok(!swapped.includes('mode = "rule"'))
assert.ok(swapped.includes('log_level = "info"'))
assert.strictEqual(swapped.split("\n").length, SAMPLE.split("\n").length)
assert.strictEqual(config.parse(swapped).mode, "global")

const reUrl = config.patch(SAMPLE, { remoteConfigUrl: "https://new.example.com/x" })
assert.strictEqual(config.parse(reUrl).remoteConfigUrl, "https://new.example.com/x")
assert.strictEqual(config.parse(reUrl).mode, "rule")

// Both at once.
const both = config.patch(SAMPLE, { remoteConfigUrl: "https://b.example/y", mode: "direct" })
assert.strictEqual(config.parse(both).remoteConfigUrl, "https://b.example/y")
assert.strictEqual(config.parse(both).mode, "direct")

// A trailing comment on the line being rewritten survives.
const commented = config.patch('mode = "rule"\n[mihomo_config]\nmode = "rule"  # keep me\n', { mode: "global" })
assert.ok(commented.includes('mode = "global"  # keep me'))

// A new key lands inside its own table, not after whatever table came last.
const noMode = `remote_config_url = "https://a.example/s"

[mihomo_config]
port = 7891
`
const added = config.patch(noMode, { mode: "direct" })
assert.strictEqual(config.parse(added).mode, "direct")
assert.ok(added.indexOf("[mihomo_config]") < added.indexOf('mode = "direct"'))

// A root key must go above the first table header, or it would be read as
// belonging to that table.
const noUrl = `[mihomo_config]
mode = "rule"
`
const seededUrl = config.patch(noUrl, { remoteConfigUrl: "https://c.example/s" })
assert.strictEqual(config.parse(seededUrl).remoteConfigUrl, "https://c.example/s")
assert.ok(seededUrl.indexOf("remote_config_url") < seededUrl.indexOf("[mihomo_config]"))

// A file with no `[mihomo_config]` at all gets one appended.
const flat = 'remote_config_url = "https://d.example/s"\n'
const withTable = config.patch(flat, { mode: "global" })
assert.ok(withTable.includes("[mihomo_config]"))
assert.strictEqual(config.parse(withTable).mode, "global")
assert.strictEqual(config.parse(withTable).remoteConfigUrl, "https://d.example/s")

// Every write ends with a newline, so mihoro's own parser and `cat` agree.
assert.ok(/\n$/.test(withTable))
assert.ok(/\n$/.test(swapped))

// Quotes and backslashes in a URL are escaped rather than breaking the file.
const nasty = config.patch("", { remoteConfigUrl: 'https://e.example/"x\\y' })
assert.strictEqual(config.parse(nasty).remoteConfigUrl, 'https://e.example/"x\\y')

// Seeding a file that has never existed.
const seeded = config.seed("https://f.example/s")
assert.strictEqual(config.parse(seeded).remoteConfigUrl, "https://f.example/s")

// Patching with nothing changes nothing but the trailing newline guarantee.
assert.strictEqual(config.patch(SAMPLE, {}), SAMPLE)

// ------------------------------------------------------------------- paths

assert.strictEqual(config.configPath("/home/ada"), "/home/ada/.config/mihoro.toml")
assert.strictEqual(
  config.mihomoConfigPath("~/.config/mihomo", "/home/ada"),
  "/home/ada/.config/mihomo/config.yaml")
assert.strictEqual(
  config.mihomoConfigPath("/opt/mihomo", "/home/ada"),
  "/opt/mihomo/config.yaml")

// Nothing downstream of here expands `~` — the probe gets a path it can stat.
assert.strictEqual(config.mihomoBinaryPath("~/.local/bin/mihomo", "/home/ada"),
  "/home/ada/.local/bin/mihomo")
assert.strictEqual(config.mihomoBinaryPath("/opt/mihomo/bin/mihomo", "/home/ada"),
  "/opt/mihomo/bin/mihomo")
assert.strictEqual(config.mihomoBinaryPath("  ~/bin/mihomo  ", "/home/ada"), "/home/ada/bin/mihomo")
assert.strictEqual(config.mihomoBinaryPath("~", "/home/ada"), "/home/ada")
// `~someone/bin` is another user's home, which is not this panel's to guess at.
assert.strictEqual(config.mihomoBinaryPath("~ada/bin/mihomo", "/home/ada"), "~ada/bin/mihomo")
// An unset path means "look on PATH", and must not become the bare home dir.
assert.strictEqual(config.mihomoBinaryPath("", "/home/ada"), "")
assert.strictEqual(config.mihomoBinaryPath(undefined, "/home/ada"), "")

// ---------------------------------------------------------------- commands

const read = config.readCommand("/home/ada/.config/mihoro.toml")
assert.strictEqual(read[0], "bash")
assert.strictEqual(read[1], "-c")
assert.strictEqual(read[read.length - 1], "/home/ada/.config/mihoro.toml")

const write = config.writeCommand("/home/ada/.config/mihoro.toml")
assert.strictEqual(write[0], "bash")
assert.ok(write[2].includes("mktemp"), "writes go through a temporary file")
assert.ok(write[2].includes("mv -f"), "and are renamed into place")
assert.strictEqual(write[write.length - 1], "/home/ada/.config/mihoro.toml")

console.log("mihoro.toml tests passed")
