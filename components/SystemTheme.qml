import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../ThemeColors.js" as ThemeColors

QtObject {
  id: root

  property color green: Color.accent
  property color yellow: Color.accent

  function applyColors(raw) {
    var greenValue = ThemeColors.green(raw)
    var yellowValue = ThemeColors.yellow(raw)
    green = greenValue === "" ? Color.accent : greenValue
    yellow = yellowValue === "" ? Color.accent : yellowValue
  }

  property FileView colorsFile: FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyColors(text())
    onFileChanged: reload()
    onLoadFailed: {
      root.green = Color.accent
      root.yellow = Color.accent
    }
  }

  property Connections colorChanges: Connections {
    target: Color
    function onAccentChanged() { colorsFile.reload() }
  }
}
