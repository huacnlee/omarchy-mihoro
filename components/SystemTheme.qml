import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../ThemeColors.js" as ThemeColors

QtObject {
  id: root

  property color blue: Color.accent

  function applyColors(raw) {
    var blueValue = ThemeColors.blue(raw)
    blue = blueValue === "" ? Color.accent : blueValue
  }

  property FileView colorsFile: FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyColors(text())
    onFileChanged: reload()
    onLoadFailed: {
      root.blue = Color.accent
    }
  }

  property Connections colorChanges: Connections {
    target: Color
    function onAccentChanged() { colorsFile.reload() }
  }
}
