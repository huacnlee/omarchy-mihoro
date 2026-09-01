.pragma library

var TYPES = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "GEOSITE"]

function defaults() { return { version: 1, subscriptions: {} } }

function storePath(home) {
  return String(home || "") + "/.config/mihoro/subscription-rules.json"
}

function clone(value) { return JSON.parse(JSON.stringify(value)) }

function normalize(store) {
  var result = defaults()
  if (!store || typeof store !== "object") return result
  var source = store.subscriptions
  if (!source || typeof source !== "object" || source instanceof Array) return result
  var ids = Object.keys(source)
  for (var i = 0; i < ids.length; i++) {
    var entry = source[ids[i]]
    var items = entry instanceof Array ? entry : (entry && entry.rules instanceof Array ? entry.rules : [])
    var applied = entry && entry.applied instanceof Array ? entry.applied : []
    result.subscriptions[ids[i]] = { rules: sanitize(items), applied: sanitize(applied) }
  }
  return result
}

function sanitize(items) {
  var result = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i] || {}
    var type = String(item.type || "").toUpperCase()
    var match = String(item.match || "").trim()
    var route = String(item.route || "").trim()
    if (TYPES.indexOf(type) < 0 || match === "" || route === "") continue
    result.push({ id: String(item.id || makeId()), type: type, match: match, route: route })
  }
  return result
}

function parse(text) {
  try { return normalize(JSON.parse(String(text || ""))) }
  catch (error) { return defaults() }
}

function list(store, subscriptionId) {
  var clean = normalize(store)
  var entry = clean.subscriptions[String(subscriptionId || "")]
  return entry ? clone(entry.rules) : []
}

function makeId() {
  return Date.now().toString(36) + "-" + Math.random().toString(36).substring(2, 9)
}

function ensure(store, subscriptionId) {
  var clean = normalize(store)
  var id = String(subscriptionId || "")
  if (!clean.subscriptions[id]) clean.subscriptions[id] = { rules: [], applied: [] }
  return { store: clean, id: id, entry: clean.subscriptions[id] }
}

function ruleError(type, match, route) {
  var kind = String(type || "").toUpperCase()
  var value = String(match || "").trim()
  if (TYPES.indexOf(kind) < 0) return "Choose a rule type."
  if (value === "") return kind === "GEOSITE" ? "Choose a GeoSite." : "Enter a domain."
  if (kind !== "GEOSITE" && (/^[a-z][a-z0-9+.-]*:\/\//i.test(value) || value.indexOf("/") >= 0))
    return "Enter a domain without a scheme or path."
  if (String(route || "").trim() === "") return "Choose a route."
  return ""
}

function add(store, subscriptionId, type, match, route) {
  var state = ensure(store, subscriptionId)
  if (ruleError(type, match, route) !== "") return { store: state.store, changed: false }
  state.entry.rules.push({ id: makeId(), type: String(type).toUpperCase(),
    match: String(match).trim(), route: String(route).trim() })
  return { store: state.store, changed: true }
}

function save(store, subscriptionId, ruleId, type, match, route) {
  var state = ensure(store, subscriptionId)
  if (ruleError(type, match, route) !== "") return { store: state.store, changed: false }
  for (var i = 0; i < state.entry.rules.length; i++) {
    if (state.entry.rules[i].id !== String(ruleId || "")) continue
    state.entry.rules[i] = { id: state.entry.rules[i].id, type: String(type).toUpperCase(),
      match: String(match).trim(), route: String(route).trim() }
    return { store: state.store, changed: true }
  }
  return { store: state.store, changed: false }
}

function remove(store, subscriptionId, ruleId) {
  var state = ensure(store, subscriptionId)
  var before = state.entry.rules.length
  state.entry.rules = state.entry.rules.filter(function(rule) { return rule.id !== String(ruleId || "") })
  return { store: state.store, changed: state.entry.rules.length !== before }
}

function move(store, subscriptionId, ruleId, delta) {
  var state = ensure(store, subscriptionId)
  var from = -1
  for (var i = 0; i < state.entry.rules.length; i++) if (state.entry.rules[i].id === String(ruleId || "")) from = i
  if (from < 0) return { store: state.store, changed: false }
  var to = Math.max(0, Math.min(state.entry.rules.length - 1, from + Number(delta || 0)))
  if (to === from) return { store: state.store, changed: false }
  var item = state.entry.rules.splice(from, 1)[0]
  state.entry.rules.splice(to, 0, item)
  return { store: state.store, changed: true }
}

function replace(store, subscriptionId, items) {
  var state = ensure(store, subscriptionId)
  state.entry.rules = sanitize(items && typeof items.length === "number" ? items : [])
  return { store: state.store, changed: true }
}

function compile(rule) {
  return [String(rule.type || ""), String(rule.match || ""), String(rule.route || "")].join(",")
}

function writeCommand(path) {
  return ["bash", "-c", "set -e; d=$(dirname -- \"$1\"); mkdir -p -- \"$d\"; t=$(mktemp --tmpdir=\"$d\" .rules.XXXXXX); chmod 600 \"$t\"; cat >\"$t\"; mv -f -- \"$t\" \"$1\"", "omahoro-rules-write", String(path)]
}

function readCommand(path) {
  return ["bash", "-c", "cat -- \"$1\" 2>/dev/null || true", "omahoro-rules-read", String(path)]
}
