import QtQuick
import qs.Commons

// The panel's icon set, drawn rather than rasterised from SVG assets or taken
// from a font: these render at 12–16px, where Qt's SVG renderer smears strokes
// and where a text glyph covers whatever fraction of its em box the family
// happens to choose — × is a multiplication sign and reads half the size of the
// number it was set at.
//
// One 16-unit grid and one stroke weight for every glyph, so a row of them
// reads as a set. Sibling glyphs are shared with omamail, whose ActionIcon this
// follows; the coordinates are the same ones its design sheet uses.
//
// The brand mark is not in here. MihoroIcon is a logo with its own proportions
// and its own badge states, and putting it on this grid would say it belongs to
// the same set as the row actions.
Canvas {
  id: root

  property string name: ""
  property color color: Color.foreground
  property real iconSize: Style.font.icon
  property real strokeScale: 1.4

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize
  antialiasing: true

  onNameChanged: requestPaint()
  onColorChanged: requestPaint()
  onIconSizeChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var s = width / 16
    if (s <= 0) return

    ctx.strokeStyle = root.color
    ctx.lineWidth = Math.max(1, root.strokeScale * s)
    ctx.lineCap = "round"
    ctx.lineJoin = "round"

    function move(x, y) { ctx.moveTo(x * s, y * s) }
    function line(x, y) { ctx.lineTo(x * s, y * s) }
    function arc(cx, cy, r, from, to) { ctx.arc(cx * s, cy * s, r * s, from, to) }

    ctx.beginPath()

    if (root.name === "trash") {
      move(2.5, 4); line(13.5, 4)
      move(6, 4); line(6, 2.5); line(10, 2.5); line(10, 4)
      move(4, 4); line(4.7, 13.5); line(11.3, 13.5); line(12, 4)
    } else if (root.name === "edit") {
      // A pencil pointing at the lower left, with the ferrule near the blunt
      // end. The barrel is narrow on purpose: widened, it stops reading as a
      // pencil and starts reading as a bar.
      move(2.5, 13.5); line(3.4, 10.4); line(11.2, 2.6); line(13.4, 4.8)
      line(5.6, 12.6); ctx.closePath()
      move(9.6, 4.2); line(11.8, 6.4)
    } else if (root.name === "settings") {
      // A gear, built from the grid rather than listed as points: eight teeth
      // are eight identical spokes, and writing them out would only invite one
      // of them to drift.
      var outer = 6.9
      var body = 5.0
      var hole = 1.9
      for (var i = 0; i < 8; ++i) {
        var angle = i * Math.PI / 4
        move(8 + Math.cos(angle) * body, 8 + Math.sin(angle) * body)
        line(8 + Math.cos(angle) * outer, 8 + Math.sin(angle) * outer)
      }
      ctx.stroke()
      ctx.beginPath()
      arc(8, 8, body, 0, Math.PI * 2)
      ctx.stroke()
      ctx.beginPath()
      arc(8, 8, hole, 0, Math.PI * 2)
    }

    ctx.stroke()
  }
}
