.pragma library

function paletteColor(raw, name, fallbackName) {
  var lines = String(raw || "").split("\n")
  var fallback = ""
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (!match) continue
    if (match[1] === name) return match[2]
    if (match[1] === fallbackName) fallback = match[2]
  }
  return fallback
}

function blue(raw) { return paletteColor(raw, "blue", "color4") }
