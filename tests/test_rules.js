const assert = require("assert")
const { load } = require("./load")

const rules = load("Rules.js")

function same(actual, expected) {
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected))
}

const empty = rules.defaults()
assert.strictEqual(empty.version, 1)
same(rules.list(empty, "sub-a"), [])
assert.strictEqual(rules.storePath("/home/user"),
  "/home/user/.config/mihoro/subscription-rules.json")

let store = rules.add(empty, "sub-a", "GEOSITE", "CN", "DIRECT").store
let first = rules.list(store, "sub-a")[0]
assert.ok(first.id)
assert.strictEqual(first.type, "GEOSITE")
assert.strictEqual(first.match, "CN")
assert.strictEqual(first.route, "DIRECT")
assert.strictEqual(rules.list(store, "sub-b").length, 0)

store = rules.add(store, "sub-a", "DOMAIN-SUFFIX", "example.com", "PROXY").store
let list = rules.list(store, "sub-a")
assert.strictEqual(list.length, 2)
assert.strictEqual(rules.compile(list[0]), "GEOSITE,CN,DIRECT")
assert.strictEqual(rules.compile(list[1]), "DOMAIN-SUFFIX,example.com,PROXY")

store = rules.move(store, "sub-a", list[1].id, -1).store
assert.strictEqual(rules.list(store, "sub-a")[0].match, "example.com")
store = rules.move(store, "sub-a", rules.list(store, "sub-a")[0].id, -1).store
assert.strictEqual(rules.list(store, "sub-a")[0].match, "example.com")

const editedId = rules.list(store, "sub-a")[0].id
store = rules.save(store, "sub-a", editedId, "DOMAIN", "api.example.com", "DIRECT").store
assert.strictEqual(rules.list(store, "sub-a")[0].type, "DOMAIN")
assert.strictEqual(rules.list(store, "sub-a")[0].match, "api.example.com")

store = rules.remove(store, "sub-a", editedId).store
assert.strictEqual(rules.list(store, "sub-a").length, 1)

store = rules.replace(store, "sub-a", [
  { id: "kept", type: "GEOSITE", match: "private", route: "DIRECT" }
]).store
assert.strictEqual(rules.list(store, "sub-a")[0].id, "kept")
assert.strictEqual(rules.list(store, "sub-a")[0].match, "private")

assert.strictEqual(rules.ruleError("DOMAIN", "", "DIRECT"), "Enter a domain.")
assert.strictEqual(rules.ruleError("DOMAIN", "https://example.com", "DIRECT"),
  "Enter a domain without a scheme or path.")
assert.strictEqual(rules.ruleError("GEOSITE", "", "DIRECT"), "Choose a GeoSite.")
assert.strictEqual(rules.ruleError("NOPE", "x", "DIRECT"), "Choose a rule type.")
assert.strictEqual(rules.ruleError("DOMAIN", "example.com", ""), "Choose a route.")
assert.strictEqual(rules.ruleError("DOMAIN-KEYWORD", "google", "PROXY"), "")

const parsed = rules.parse(JSON.stringify(store))
assert.strictEqual(rules.list(parsed, "sub-a").length, 1)
assert.strictEqual(rules.parse("not json").version, 1)

console.log("rule store tests passed")
