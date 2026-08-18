const assert = require("assert")
const { load } = require("./load")

const themeColors = load("ThemeColors.js")

assert.strictEqual(themeColors.blue('blue = "#7aa2f7"\ncolor4 = "#0088ff"'), "#7aa2f7")
assert.strictEqual(themeColors.blue('color4 = "#89b4fa"'), "#89b4fa")
assert.strictEqual(themeColors.blue('accent = "#bb9af7"'), "")
console.log("theme color tests passed")
