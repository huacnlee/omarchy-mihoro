const assert = require("assert")
const { load } = require("./load")

const themeColors = load("ThemeColors.js")

assert.strictEqual(themeColors.green('green = "#9ece6a"\ncolor2 = "#00aa00"'), "#9ece6a")
assert.strictEqual(themeColors.green('color2 = "#a6e3a1"'), "#a6e3a1")
assert.strictEqual(themeColors.green('accent = "#89b4fa"'), "")
assert.strictEqual(themeColors.yellow('yellow = "#e0af68"\ncolor3 = "#ffaa00"'), "#e0af68")
assert.strictEqual(themeColors.yellow('color3 = "#f9e2af"'), "#f9e2af")
assert.strictEqual(themeColors.yellow('urgent = "#f38ba8"'), "")
console.log("theme color tests passed")
