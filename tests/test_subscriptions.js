const assert = require("assert")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")
const { load } = require("./load")

const subs = load("Subscriptions.js")

// The library runs in its own vm context, so its arrays and objects have
// prototypes from that realm and `deepStrictEqual` rejects them on identity.
// Structure is what these tests are about.
function same(actual, expected, message) {
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected), message)
}

const A = "https://example.com/sub?token=aaaa"
const B = "https://backup.example.net/sub?token=bbbb"

// ---------------------------------------------------------------- defaults

const empty = subs.defaults()
assert.strictEqual(empty.activeId, "")
same(empty.items, [])
assert.strictEqual(subs.activeUrl(empty), "")
assert.strictEqual(subs.count(empty), 0)
// mihoro's own directory, beside the config file it hardcodes. The name says
// what the file is because the directory says whose it is.
assert.strictEqual(subs.storePath("/home/user"),
  "/home/user/.config/mihoro/subscriptions.json")

// ------------------------------------------------------------------- adding

const first = subs.add(empty, "", A)
assert.strictEqual(subs.count(first.store), 1)
// An unnamed subscription is named after its host: it is the one part of the
// URL that identifies it without carrying the token.
assert.strictEqual(first.store.items[0].name, "example.com")
assert.strictEqual(first.store.items[0].url, A)
// The original is untouched — QML only re-evaluates bindings on assignment.
assert.strictEqual(subs.count(empty), 0)

const named = subs.add(first.store, "  Work  ", B)
assert.strictEqual(named.store.items[1].name, "Work")
assert.notStrictEqual(named.store.items[0].id, named.store.items[1].id)

// Two subscriptions from one provider arrive distinguishable.
const twice = subs.add(subs.add(empty, "", A).store, "", "https://example.com/other")
assert.strictEqual(twice.store.items[1].name, "example.com 2")

// Userinfo and port are not part of the name.
assert.strictEqual(
  subs.add(empty, "", "https://user:pass@example.com:8443/sub").store.items[0].name,
  "example.com")
// Something unparseable still gets a label rather than an empty row.
assert.strictEqual(subs.add(empty, "", "not-a-url").store.items[0].name, "Subscription")

// --------------------------------------------------------------- selecting

let store = subs.add(empty, "Home", A).store
const homeId = store.items[0].id
store = subs.add(store, "Work", B).store
const workId = store.items[1].id

assert.strictEqual(subs.activeUrl(store), "")
store = subs.select(store, workId).store
assert.strictEqual(store.activeId, workId)
assert.strictEqual(subs.activeUrl(store), B)
assert.strictEqual(subs.activeEntry(store).name, "Work")
// Selecting something that is not there leaves the selection alone.
assert.strictEqual(subs.select(store, "nope").store.activeId, workId)

assert.strictEqual(subs.find(store, homeId).name, "Home")
assert.strictEqual(subs.find(store, "nope"), null)
assert.strictEqual(subs.findByUrl(store, A).id, homeId)
assert.strictEqual(subs.findByUrl(store, ""), null)
assert.strictEqual(subs.indexOf(store, workId), 1)

// ----------------------------------------------------------------- editing

// A rename keeps the URL: the editor must not demand the credential back.
const renamed = subs.save(store, homeId, "House", "").store
assert.strictEqual(renamed.items[0].name, "House")
assert.strictEqual(renamed.items[0].url, A)

// Clearing the name falls back to the host, and its own old name does not
// force a "2" suffix.
const homeOnly = subs.add(empty, "Home", A).store
const unnamed = subs.save(homeOnly, homeOnly.items[0].id, "", "").store
assert.strictEqual(unnamed.items[0].name, "example.com")

const repointed = subs.save(store, homeId, "Home", B).store
assert.strictEqual(repointed.items[0].url, B)
// Editing something that is gone is a no-op, not a crash.
assert.strictEqual(subs.count(subs.save(store, "nope", "x", A).store), 2)

// ---------------------------------------------------------------- removing

// Removing the selected entry hands the selection to its neighbour, so the
// list and mihoro.toml can still be made to agree.
const dropped = subs.remove(store, workId).store
assert.strictEqual(subs.count(dropped), 1)
assert.strictEqual(dropped.activeId, homeId)

// Removing one that is not selected leaves the selection where it was.
const droppedOther = subs.remove(store, homeId).store
assert.strictEqual(droppedOther.activeId, workId)

// Removing the last one leaves nothing selected — an empty list means no
// subscription is configured.
const emptied = subs.remove(subs.remove(store, homeId).store, workId).store
assert.strictEqual(subs.count(emptied), 0)
assert.strictEqual(emptied.activeId, "")
assert.strictEqual(subs.activeUrl(emptied), "")

// A middle entry hands over to the one that slid into its place.
let three = subs.add(subs.add(subs.add(empty, "One", A).store, "Two", B).store, "Three", "https://c.example.com/s").store
three = subs.select(three, three.items[1].id).store
const afterMiddle = subs.remove(three, three.items[1].id).store
assert.strictEqual(subs.activeEntry(afterMiddle).name, "Three")

// -------------------------------------------------------------- adopting
//
// mihoro.toml is the truth about what the proxy is using. The list follows it.

// First run: whatever mihoro.toml already points at becomes the first entry.
const adopted = subs.adopt(empty, A)
assert.strictEqual(adopted.changed, true)
assert.strictEqual(subs.count(adopted.store), 1)
assert.strictEqual(subs.activeUrl(adopted.store), A)
assert.strictEqual(adopted.store.items[0].name, "example.com")

// A URL already in the list selects it rather than adding a second copy.
const rejoined = subs.adopt(store, A)
assert.strictEqual(rejoined.changed, true)
assert.strictEqual(subs.count(rejoined.store), 2)
assert.strictEqual(rejoined.store.activeId, homeId)

// The common case — they already agree — must not rewrite the file.
assert.strictEqual(subs.adopt(rejoined.store, A).changed, false)

// Two entries can hold the same URL, and mihoro.toml — which stores a URL, not
// an entry — cannot tell them apart. A selection whose URL already matches the
// file is left exactly where it is, or the selection would snap back to
// whichever duplicate came first on every refresh.
let twins = subs.add(subs.add(empty, "First", A).store, "Second", A).store
twins = subs.select(twins, twins.items[1].id).store
assert.strictEqual(subs.adopt(twins, A).changed, false)
assert.strictEqual(subs.adopt(twins, A).store.activeId, twins.items[1].id)
// A URL the selection does not hold still re-points it — here to a third entry,
// because the file names a subscription the list had never heard of.
const moved = subs.adopt(twins, B)
assert.strictEqual(moved.changed, true)
assert.strictEqual(subs.count(moved.store), 3)
assert.strictEqual(subs.activeUrl(moved.store), B)

// Duplicates are what `duplicateOf` is for — an entry is never its own.
assert.strictEqual(subs.duplicateOf(twins, A, "").name, "First")
assert.strictEqual(subs.duplicateOf(twins, A, twins.items[0].id).name, "Second")
assert.strictEqual(subs.duplicateOf(store, B, workId), null)
assert.strictEqual(subs.duplicateOf(store, "https://unused.example.com/s", ""), null)
assert.strictEqual(subs.duplicateOf(store, "", ""), null)

// An empty URL means nothing is configured, whatever the list remembers.
const cleared = subs.adopt(store, "")
assert.strictEqual(cleared.changed, true)
assert.strictEqual(cleared.store.activeId, "")
assert.strictEqual(subs.count(cleared.store), 2)
assert.strictEqual(subs.adopt(cleared.store, "").changed, false)

// --------------------------------------------------------------- round trip

const text = subs.serialize(store)
const reread = subs.parse(text)
assert.strictEqual(subs.count(reread), 2)
assert.strictEqual(reread.activeId, workId)
assert.strictEqual(subs.activeUrl(reread), B)
same(reread.items, store.items)
// Newline-terminated, like every other file the panel writes.
assert.ok(text.endsWith("\n"))

// Ids keep counting up across a save/load, so a new entry cannot reuse the id
// of one that was removed.
const grown = subs.add(reread, "Third", "https://third.example.com/s")
assert.strictEqual(
  grown.store.items.filter(function (entry) { return entry.id === grown.id }).length, 1)
assert.ok(Number(grown.id) > Number(workId))

// ----------------------------------------------------------------- parsing
//
// The file is small enough to hand-edit, so a mistake in it must not cost the
// subscriptions that did parse.

same(subs.parse(""), subs.defaults())
same(subs.parse(null), subs.defaults())
same(subs.parse("{not json"), subs.defaults())
same(subs.parse("[1,2,3]").items, [])

const messy = subs.parse(JSON.stringify({
  version: 1,
  activeId: "7",
  nextId: 2,
  items: [
    { id: "1", name: "Keep", url: A },
    { id: "2", name: "No URL", url: "" },     // nothing to switch to
    { id: "1", name: "Duplicate id", url: B },
    { name: "No id", url: "https://c.example.com/s" },
    null,
    "garbage"
  ]
}))
assert.strictEqual(subs.count(messy), 3)
assert.strictEqual(messy.items[0].name, "Keep")
// The duplicate and the id-less entry are given fresh ids rather than dropped.
assert.strictEqual(messy.items[1].name, "Duplicate id")
assert.strictEqual(messy.items[2].name, "No id")
const ids = messy.items.map(function (entry) { return entry.id })
assert.strictEqual(new Set(ids).size, 3)
// A selection naming no entry is not a dangling pointer.
assert.strictEqual(messy.activeId, "")
// The counter clears every id in the file, including the ones just assigned.
assert.ok(messy.nextId > Math.max.apply(null, ids.map(Number)))

// ------------------------------------------------------------------- names

assert.strictEqual(subs.nameError(""), "")
assert.strictEqual(subs.nameError("Work"), "")
assert.notStrictEqual(subs.nameError("x".repeat(61)), "")

// ---------------------------------------------------------------- commands

const STORE = "/home/user/.config/mihoro/subscriptions.json"

const write = subs.writeCommand(STORE)
assert.strictEqual(write[0], "bash")
// The store holds several bearer URLs and is the panel's own file: 0600, and
// renamed into place so a torn write cannot read back as an empty list. It also
// makes its own directory — nothing else creates `~/.config/mihoro/`.
assert.ok(write[2].includes("mktemp"))
assert.ok(write[2].includes("chmod 600"))
assert.ok(write[2].includes("mv -f"))
assert.ok(write[2].includes("mkdir -p"))
assert.strictEqual(write[write.length - 1], STORE)
// The payload arrives on stdin, never as an argument — arguments are visible
// in the process list.
assert.ok(!write.some(function (part) { return String(part).includes("token=") }))

const read = subs.readCommand(STORE)
assert.strictEqual(read[0], "bash")
assert.ok(read[2].includes("cat"))
assert.strictEqual(read[read.length - 1], STORE)

// The scripts are the part that touches the user's disk, so they are run rather
// than read. `Model.js`'s tests do the same with the probe.
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omahoro-subs-"))
const target = path.join(dir, ".config", "mihoro", "subscriptions.json")

// Nothing there yet reads as nothing, without an error and without a directory.
assert.strictEqual(
  execFileSync("bash", subs.readCommand(target).slice(1), { encoding: "utf8" }), "")

// The first write makes the directory and lands 0600.
execFileSync("bash", subs.writeCommand(target).slice(1),
  { input: subs.serialize(store), encoding: "utf8" })
assert.strictEqual(fs.readFileSync(target, "utf8"), subs.serialize(store))
assert.strictEqual(fs.statSync(target).mode & 0o777, 0o600)
assert.strictEqual(
  execFileSync("bash", subs.readCommand(target).slice(1), { encoding: "utf8" }),
  subs.serialize(store))

console.log("subscription store tests passed")
