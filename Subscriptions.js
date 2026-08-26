.pragma library

// The panel's own subscription list.
//
// mihoro keeps exactly one subscription — `remote_config_url` in mihoro.toml —
// and nothing in its CLI names a second, so holding several is the panel's job
// rather than something it can delegate. What it does delegate is applying one:
// switching writes the chosen URL into mihoro.toml and lets
// `mihoro update --config` fetch it, which is the same path a
// single-subscription setup already took.
//
// mihoro.toml stays the truth about which subscription is in effect. `adopt`
// reconciles the list against it every time the file is read, so a URL that
// arrived by `mihoro init` or a hand edit turns up here as an entry instead of
// being silently replaced by whatever the panel last had selected.
//
// The list is a file of the panel's own rather than fields on its shell.json
// entry: a subscription URL is a bearer credential, shell.json is the file
// people paste when they ask for help with their bar, and its writer rebuilds
// plugin entries from the keys the manifest schema declares — which has no
// shape for a list. This file is written 0600 and nothing else reads it.

var VERSION = 1

// Names are the only free text here, and they are labels in a narrow panel
// row. Long enough for "Provider — backup region", short enough to render.
var NAME_LIMIT = 60

// mihoro's own directory. mihoro hardcodes `~/.config/mihoro.toml` and does not
// consult XDG_CONFIG_HOME, so this is hardcoded beside it for the same reason
// `MihoroConfig.configPath` is: the two have to agree on one place, and a path
// that can be configured is a path that can disagree.
//
// The directory is what lets the file be called what it is. Loose in
// `~/.config` it would have had to carry a prefix — that directory is shared
// with every other application, and `subscriptions.json` there says nothing
// about whose it is.
function storePath(home) {
  return String(home || "") + "/.config/mihoro/subscriptions.json"
}

function defaults() {
  return { version: VERSION, activeId: "", nextId: 1, items: [] }
}

function trimmed(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

// Every mutator returns a fresh store: QML re-evaluates a `var` property's
// bindings when it is assigned, not when the object it holds is mutated.
function clone(store) {
  var source = store || defaults()
  var list = Array.isArray(source.items) ? source.items : []
  var items = []
  for (var i = 0; i < list.length; i++) {
    items.push({
      id: trimmed(list[i].id),
      name: trimmed(list[i].name),
      url: trimmed(list[i].url)
    })
  }
  var counter = Math.floor(Number(source.nextId))
  return {
    version: VERSION,
    activeId: trimmed(source.activeId),
    nextId: isFinite(counter) && counter > 1 ? counter : 1,
    items: items
  }
}

// Tolerant on purpose: this file is small enough to hand-edit, and a typo in it
// must not cost the user the subscriptions that parsed. Anything unusable is
// dropped, an entry with no id is given one, and a stored `activeId` that names
// no entry falls back to nothing selected rather than a dangling pointer.
function parse(raw) {
  var text = trimmed(raw)
  if (text === "") return defaults()
  var data = null
  try {
    data = JSON.parse(text)
  } catch (error) {
    return defaults()
  }
  if (!data || typeof data !== "object") return defaults()

  var store = defaults()
  var list = Array.isArray(data.items) ? data.items : []
  var pending = []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || typeof entry !== "object") continue
    // An entry with no URL is not a subscription anything could switch to.
    var url = trimmed(entry.url)
    if (url === "") continue
    pending.push({ id: trimmed(entry.id), name: trimmed(entry.name), url: url })
  }

  var used = {}
  var highest = 0
  var index
  for (index = 0; index < pending.length; index++) {
    var id = pending[index].id
    if (id === "" || used[id] === true) {
      pending[index].id = ""
      continue
    }
    used[id] = true
    var numeric = Number(id)
    if (isFinite(numeric) && numeric > highest) highest = Math.floor(numeric)
  }

  var counter = Math.floor(Number(data.nextId))
  var next = Math.max(highest + 1, isFinite(counter) && counter > 1 ? counter : 1)
  for (index = 0; index < pending.length; index++) {
    if (pending[index].id !== "") continue
    pending[index].id = String(next)
    used[pending[index].id] = true
    next++
  }

  store.items = pending
  store.nextId = next
  var active = trimmed(data.activeId)
  store.activeId = used[active] === true ? active : ""
  return store
}

function serialize(store) {
  return JSON.stringify(clone(store), null, 2) + "\n"
}

function list(store) {
  var source = store || defaults()
  return Array.isArray(source.items) ? source.items : []
}

function count(store) {
  return list(store).length
}

function indexOf(store, id) {
  var target = trimmed(id)
  if (target === "") return -1
  var items = list(store)
  for (var i = 0; i < items.length; i++) if (items[i].id === target) return i
  return -1
}

function find(store, id) {
  var at = indexOf(store, id)
  return at < 0 ? null : list(store)[at]
}

function findByUrl(store, url) {
  var target = trimmed(url)
  if (target === "") return null
  var items = list(store)
  for (var i = 0; i < items.length; i++) if (items[i].url === target) return items[i]
  return null
}

// The entry that already holds this URL, ignoring one id — the entry being
// edited is not a duplicate of itself. Two entries with the same URL are the
// same subscription under two names, and mihoro.toml cannot tell them apart.
function duplicateOf(store, url, exceptId) {
  var target = trimmed(url)
  if (target === "") return null
  var skip = trimmed(exceptId)
  var items = list(store)
  for (var i = 0; i < items.length; i++) {
    if (items[i].url !== target) continue
    if (skip !== "" && items[i].id === skip) continue
    return items[i]
  }
  return null
}

function activeEntry(store) {
  var source = store || defaults()
  return find(source, source.activeId)
}

function activeUrl(store) {
  var entry = activeEntry(store)
  return entry ? entry.url : ""
}

// The host, which is the part of the URL `Model.maskUrl` already considers safe
// to show. Credentials in the userinfo and the port are not it.
function hostOf(url) {
  var match = trimmed(url).match(/^[a-z][a-z0-9+.\-]*:\/\/([^\/?#]+)/i)
  if (!match) return ""
  return String(match[1]).replace(/^[^@]*@/, "").replace(/:\d+$/, "")
}

// Two subscriptions from one provider are the common case, so an unnamed
// second one has to arrive distinguishable from the first.
function defaultName(url, store) {
  var base = hostOf(url)
  if (base === "") base = "Subscription"
  var taken = {}
  var items = list(store)
  for (var i = 0; i < items.length; i++) taken[items[i].name.toLowerCase()] = true
  if (taken[base.toLowerCase()] !== true) return base
  for (var suffix = 2; suffix < 1000; suffix++) {
    var candidate = base + " " + suffix
    if (taken[candidate.toLowerCase()] !== true) return candidate
  }
  return base
}

function nameError(name) {
  return trimmed(name).length > NAME_LIMIT
    ? "Keep the name under " + NAME_LIMIT + " characters."
    : ""
}

function withoutItem(store, id) {
  var next = clone(store)
  var at = indexOf(next, id)
  if (at >= 0) next.items.splice(at, 1)
  return next
}

// Ids are a counter rather than a slug of the name, so renaming a subscription
// cannot orphan the selection, and two subscriptions may share a name.
function add(store, name, url) {
  var next = clone(store)
  var text = trimmed(url)
  var id = String(next.nextId)
  next.nextId = next.nextId + 1
  var label = trimmed(name)
  next.items.push({
    id: id,
    name: label !== "" ? label : defaultName(text, next),
    url: text
  })
  return { store: next, id: id }
}

// An empty URL leaves the stored one alone: the editor is also how a
// subscription gets renamed, and a rename must not require re-typing the
// credential.
function save(store, id, name, url) {
  var next = clone(store)
  var at = indexOf(next, id)
  if (at < 0) return { store: next }
  var text = trimmed(url)
  if (text !== "") next.items[at].url = text
  var label = trimmed(name)
  next.items[at].name = label !== ""
    ? label
    : defaultName(next.items[at].url, withoutItem(next, next.items[at].id))
  return { store: next }
}

function remove(store, id) {
  var next = clone(store)
  var at = indexOf(next, id)
  if (at < 0) return { store: next }
  var wasActive = next.activeId === next.items[at].id
  next.items.splice(at, 1)
  if (wasActive) {
    // The entry that slid into its place, or the last one when it was the tail.
    // Selecting something is what keeps mihoro.toml and this list saying the
    // same thing; with the list empty there is nothing left to say.
    var fallback = next.items[Math.min(at, next.items.length - 1)]
    next.activeId = fallback ? fallback.id : ""
  }
  return { store: next }
}

function select(store, id) {
  var next = clone(store)
  if (indexOf(next, id) >= 0) next.activeId = trimmed(id)
  return { store: next }
}

// Reconciles the list against the URL mihoro.toml actually holds. The file
// wins: it is what the proxy is using, and the panel must not present a
// selection the core has never seen. `changed` is false when the two already
// agree, so the common refresh does not rewrite the store.
function adopt(store, url) {
  var text = trimmed(url)
  var current = clone(store)

  if (text === "") {
    if (current.activeId === "") return { store: store, changed: false }
    current.activeId = ""
    return { store: current, changed: true }
  }

  // The selection already points at this URL, so the two agree and there is
  // nothing to reconcile. Checked before the search because a URL can appear on
  // more than one entry — the file names a URL, not an entry, and re-deriving
  // the selection from it would drag it to whichever entry came first.
  var selected = activeEntry(current)
  if (selected && selected.url === text) return { store: store, changed: false }

  var match = findByUrl(current, text)
  if (match) {
    if (current.activeId === match.id) return { store: store, changed: false }
    current.activeId = match.id
    return { store: current, changed: true }
  }

  var added = add(current, "", text)
  added.store.activeId = added.id
  return { store: added.store, changed: true }
}

function readCommand(path) {
  return ["bash", "-c", "cat -- \"$1\" 2>/dev/null || true", "omahoro-subs-read", String(path)]
}

// Same shape as the mihoro.toml write: a temporary file in the same directory,
// renamed into place, so an interrupted write cannot leave a half-file the next
// read would parse as an empty list. 0600 outright rather than following the
// file being replaced — this file is the panel's own, it holds bearer URLs, and
// there is no earlier version whose permissions are worth inheriting.
var WRITE_SCRIPT = [
  "set -eu",
  "target=$1",
  "dir=$(dirname -- \"$target\")",
  "mkdir -p -- \"$dir\"",
  "tmp=$(mktemp -- \"$dir/.mihoro-subscriptions.XXXXXX\")",
  "trap 'rm -f -- \"$tmp\"' EXIT",
  "cat > \"$tmp\"",
  "chmod 600 -- \"$tmp\"",
  "mv -f -- \"$tmp\" \"$target\"",
  "trap - EXIT"
].join("\n")

function writeCommand(path) {
  return ["bash", "-c", WRITE_SCRIPT, "omahoro-subs-write", String(path)]
}
