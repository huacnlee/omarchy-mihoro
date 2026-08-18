.pragma library

// `~/.config/mihoro.toml` belongs to mihoro, not to this panel. The panel reads
// a handful of things out of it — the subscription URL, the proxy mode, where
// mihomo's binary and config tree live, and how to reach mihomo's own API — and
// writes exactly two back: `remote_config_url` and `mihomo_config.mode`.
//
// Writes are line-level replacements rather than a parse-and-reserialize round
// trip, because everything else in that file is the user's: key order, blank
// lines, comments, and the fields this panel has no opinion about. Re-emitting
// the file from a partial model would silently drop all of it.
//
// The scanner understands the TOML subset mihoro's serializer emits plus the
// hand-edits people actually make: bare keys, basic and literal strings,
// integers, booleans, comments, and `[table]` headers. Multi-line strings and
// inline tables are read as opaque text — no key this panel touches uses them.

var CONFIG_TABLE = "mihomo_config"
var MODES = ["rule", "global", "direct"]

function defaults() {
  return {
    remoteConfigUrl: "",
    mihomoConfigRoot: "~/.config/mihomo",
    mihomoBinaryPath: "~/.local/bin/mihomo",
    autoUpdateInterval: 0,
    mode: "rule",
    externalController: "",
    secret: "",
    port: 0,
    socksPort: 0,
    mixedPort: 0,
    allowLan: false,
    externalUi: ""
  }
}

function normalizeMode(value) {
  var mode = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return MODES.indexOf(mode) >= 0 ? mode : "rule"
}

function isMode(value) {
  return MODES.indexOf(String(value || "").trim().toLowerCase()) >= 0
}

// Splits a line into code and trailing comment. A `#` inside a string is part
// of the value — subscription URLs carry fragments — so quote state is tracked
// rather than searching for the first hash.
function splitComment(line) {
  var text = String(line === undefined || line === null ? "" : line)
  var inBasic = false
  var inLiteral = false
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    if (inBasic) {
      if (ch === "\\") { i++; continue }
      if (ch === "\"") inBasic = false
      continue
    }
    if (inLiteral) {
      if (ch === "'") inLiteral = false
      continue
    }
    if (ch === "\"") { inBasic = true; continue }
    if (ch === "'") { inLiteral = true; continue }
    if (ch === "#") return { code: text.substring(0, i), comment: text.substring(i) }
  }
  return { code: text, comment: "" }
}

function unquoteKey(key) {
  var text = String(key || "").trim()
  if (text.length >= 2) {
    var first = text.charAt(0)
    var last = text.charAt(text.length - 1)
    if ((first === "\"" && last === "\"") || (first === "'" && last === "'"))
      return text.substring(1, text.length - 1)
  }
  return text
}

function unescapeBasic(text) {
  var out = ""
  for (var i = 1; i < text.length; i++) {
    var ch = text.charAt(i)
    if (ch === "\"") break
    if (ch !== "\\") { out += ch; continue }
    i++
    var escape = text.charAt(i)
    if (escape === "n") out += "\n"
    else if (escape === "t") out += "\t"
    else if (escape === "r") out += "\r"
    else if (escape === "u") { out += String.fromCharCode(parseInt(text.substr(i + 1, 4), 16) || 0); i += 4 }
    else out += escape
  }
  return out
}

function unquoteLiteral(text) {
  var end = text.indexOf("'", 1)
  return end < 0 ? text.substring(1) : text.substring(1, end)
}

function parseValue(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "") return ""
  var first = text.charAt(0)
  if (first === "\"") return unescapeBasic(text)
  if (first === "'") return unquoteLiteral(text)
  if (text === "true") return true
  if (text === "false") return false
  if (/^[-+]?[0-9][0-9_]*$/.test(text)) return Number(text.replace(/_/g, ""))
  return text
}

function serializeString(value) {
  return "\"" + String(value === undefined || value === null ? "" : value)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, "\\\"") + "\""
}

// One pass over the file recording where every key lives, which table it
// belongs to, and where a new key would have to go. Both reading and writing
// are built on this, so the two can never disagree about the file's shape.
function scan(text) {
  var raw = (text === undefined || text === null) ? "" : String(text)
  var lines = raw.split("\n")
  var state = {
    lines: lines,
    entries: [],
    tableHeader: {},
    tableLastEntry: {},
    firstHeaderLine: -1
  }
  var table = ""
  for (var i = 0; i < lines.length; i++) {
    var parts = splitComment(lines[i])
    var trimmed = parts.code.trim()
    if (trimmed === "") continue
    if (trimmed.charAt(0) === "[") {
      table = trimmed.replace(/^\[+/, "").replace(/\]+$/, "").trim()
      if (state.tableHeader[table] === undefined) state.tableHeader[table] = i
      if (state.firstHeaderLine < 0) state.firstHeaderLine = i
      continue
    }
    var eq = trimmed.indexOf("=")
    if (eq < 0) continue
    var key = unquoteKey(trimmed.substring(0, eq))
    if (key === "") continue
    state.entries.push({
      table: table,
      key: key,
      line: i,
      indent: (parts.code.match(/^[ \t]*/) || [""])[0],
      comment: parts.comment,
      rawValue: trimmed.substring(eq + 1).trim()
    })
    state.tableLastEntry[table] = i
  }
  return state
}

function findEntry(state, table, key) {
  for (var i = 0; i < state.entries.length; i++)
    if (state.entries[i].table === table && state.entries[i].key === key) return state.entries[i]
  return null
}

function parse(text) {
  var config = defaults()
  var state = scan(text)
  for (var i = 0; i < state.entries.length; i++) {
    var entry = state.entries[i]
    var value = parseValue(entry.rawValue)
    if (entry.table === "") {
      if (entry.key === "remote_config_url") config.remoteConfigUrl = String(value)
      else if (entry.key === "mihomo_config_root" && String(value) !== "") config.mihomoConfigRoot = String(value)
      else if (entry.key === "mihomo_binary_path" && String(value) !== "") config.mihomoBinaryPath = String(value)
      else if (entry.key === "auto_update_interval") config.autoUpdateInterval = Number(value) || 0
    } else if (entry.table === CONFIG_TABLE) {
      if (entry.key === "mode") config.mode = normalizeMode(value)
      else if (entry.key === "external_controller") config.externalController = String(value)
      else if (entry.key === "secret") config.secret = String(value)
      else if (entry.key === "port") config.port = Number(value) || 0
      else if (entry.key === "socks_port") config.socksPort = Number(value) || 0
      else if (entry.key === "mixed_port") config.mixedPort = Number(value) || 0
      else if (entry.key === "allow_lan") config.allowLan = value === true
      else if (entry.key === "external_ui") config.externalUi = String(value)
    }
  }
  return config
}

// Replaces a key in place, keeping its indentation and trailing comment. A key
// that is not there yet is appended to its own table rather than to the end of
// the file, because a bare `mode = ...` after `[mihomo_config]` would otherwise
// land in whichever table happened to come last.
function setValue(text, table, key, value) {
  var state = scan(text)
  var lines = state.lines.slice()
  var rendered = key + " = " + serializeString(value)
  var entry = findEntry(state, table, key)

  if (entry) {
    lines[entry.line] = entry.indent + rendered
      + (entry.comment !== "" ? "  " + entry.comment.trim() : "")
    return lines.join("\n")
  }

  if (table === "") {
    // Anything after the first `[table]` header belongs to that table, so a new
    // root key has to go above it.
    var rootAt = state.tableLastEntry[""] !== undefined
      ? state.tableLastEntry[""] + 1
      : (state.firstHeaderLine >= 0 ? state.firstHeaderLine : lines.length)
    lines.splice(rootAt, 0, rendered)
    return lines.join("\n")
  }

  if (state.tableHeader[table] !== undefined) {
    var tableAt = state.tableLastEntry[table] !== undefined
      ? state.tableLastEntry[table] + 1
      : state.tableHeader[table] + 1
    lines.splice(tableAt, 0, rendered)
    return lines.join("\n")
  }

  var block = []
  if (lines.length > 0 && String(lines[lines.length - 1]).trim() !== "") block.push("")
  block.push("[" + table + "]")
  block.push(rendered)
  return lines.concat(block).join("\n")
}

// `changes` carries only what the user actually changed: { remoteConfigUrl,
// mode }. Both are optional; an absent field is left exactly as it is on disk.
function patch(text, changes) {
  var next = (text === undefined || text === null) ? "" : String(text)
  var edits = changes || {}
  if (edits.remoteConfigUrl !== undefined)
    next = setValue(next, "", "remote_config_url", String(edits.remoteConfigUrl))
  if (edits.mode !== undefined)
    next = setValue(next, CONFIG_TABLE, "mode", normalizeMode(edits.mode))
  if (next !== "" && !/\n$/.test(next)) next += "\n"
  return next
}

// A file that has never been through `mihoro init` still has to be writable, so
// a first subscription URL lands in a minimal document rather than failing.
function seed(url) {
  return patch("", { remoteConfigUrl: String(url || "") })
}

function configPath(home) {
  // mihoro hardcodes `~/.config/mihoro.toml` and does not consult
  // XDG_CONFIG_HOME, so neither does the panel — they must agree on one file.
  return String(home || "") + "/.config/mihoro.toml"
}

// mihoro writes `~`-prefixed paths and people hand-edit them the same way, but
// nothing the panel hands to a process expands `~` for it.
function expandHome(path, home) {
  var text = String(path === undefined || path === null ? "" : path).trim()
  if (text.charAt(0) !== "~") return text
  if (text.length === 1 || text.charAt(1) === "/") return String(home || "") + text.substring(1)
  return text
}

function mihomoConfigPath(configRoot, home) {
  return expandHome(configRoot || "~/.config/mihomo", home) + "/config.yaml"
}

// Where the user says mihomo is. Empty means "no opinion" — the probe then
// falls back to whatever is on PATH.
function mihomoBinaryPath(binaryPath, home) {
  return expandHome(binaryPath, home)
}

function readCommand(path) {
  return ["bash", "-c", "cat -- \"$1\" 2>/dev/null || true", "omahoro-read", String(path)]
}

// Written through a temporary file in the same directory and renamed into
// place, so an interrupted write cannot leave mihoro with a half-file it then
// refuses to parse. Permissions follow the file being replaced — a
// subscription URL is a credential.
var WRITE_SCRIPT = [
  "set -eu",
  "target=$1",
  "dir=$(dirname -- \"$target\")",
  "mkdir -p -- \"$dir\"",
  "tmp=$(mktemp -- \"$dir/.mihoro.toml.XXXXXX\")",
  "trap 'rm -f -- \"$tmp\"' EXIT",
  "cat > \"$tmp\"",
  "if [ -f \"$target\" ]; then chmod --reference=\"$target\" -- \"$tmp\" 2>/dev/null || chmod 600 -- \"$tmp\"; else chmod 600 -- \"$tmp\"; fi",
  "mv -f -- \"$tmp\" \"$target\"",
  "trap - EXIT"
].join("\n")

function writeCommand(path) {
  return ["bash", "-c", WRITE_SCRIPT, "omahoro-write", String(path)]
}
