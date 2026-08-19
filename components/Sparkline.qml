import QtQuick
import qs.Commons
import "../Model.js" as Model

// A history curve for a single series, meant to sit behind a readout rather
// than beside it: the number stays the thing you read, and the curve answers
// "and how has that been moving" without costing a row of its own.
//
// Drawn on a Canvas for the same reason the bar icon is — this is a few dozen
// pixels tall and the shape is a handful of line segments, so a path stroked
// at the exact pixel size beats scaling anything.
//
// Straight segments, not a spline: every point here was measured, and a
// smoothed curve would invent values between two samples that never were. The
// geometry itself lives in Model.js so it can be tested without a compositor.
Item {
  id: root

  property var history: []
  property int capacity: Model.HISTORY_LIMIT
  // Zero scales the curve to its own window. Set it to share one scale across
  // several curves drawn side by side, so their heights stay comparable.
  property real scalePeak: 0
  property color curveColor: Color.accent
  // Background, so it reads as texture behind text rather than as a chart
  // competing with it.
  property real curveAlpha: 0.45
  property real areaAlpha: 0.12

  onHistoryChanged: curve.requestPaint()
  onScalePeakChanged: curve.requestPaint()
  onCurveColorChanged: curve.requestPaint()
  onCapacityChanged: curve.requestPaint()
  onWidthChanged: curve.requestPaint()
  onHeightChanged: curve.requestPaint()

  Canvas {
    id: curve
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      if (w <= 0 || h <= 0) return

      var series = Model.sparkline(root.history, root.capacity, root.scalePeak)
      var points = series.points
      var lead = series.lead
      if (lead.length + points.length < 2) return

      // Capped: this is background texture, and a line that thickens with the
      // box would read as a chart competing with the number in front of it.
      var stroke = Math.max(1, Math.min(2, h * 0.08))
      var pad = stroke / 2
      var baseline = h - pad

      function px(u) { return u * w }
      function py(v) { return baseline - v * (h - pad * 2) }

      function trace(list, started) {
        for (var i = 0; i < list.length; i++) {
          if (started) ctx.lineTo(px(list[i].x), py(list[i].y))
          else ctx.moveTo(px(list[i].x), py(list[i].y))
          started = true
        }
        return started
      }

      // The area covers only what was measured, and is filled first so the
      // line is stroked on top of its own fill rather than under it.
      if (points.length >= 2) {
        ctx.beginPath()
        trace(points, false)
        ctx.lineTo(px(points[points.length - 1].x), baseline)
        ctx.lineTo(px(points[0].x), baseline)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(root.curveColor.r, root.curveColor.g,
                                root.curveColor.b, root.areaAlpha)
        ctx.fill()
      }

      // The line runs the full width, baseline included.
      ctx.beginPath()
      trace(points, trace(lead, false))
      ctx.strokeStyle = Qt.rgba(root.curveColor.r, root.curveColor.g,
                                root.curveColor.b, root.curveAlpha)
      ctx.lineWidth = stroke
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.stroke()
    }
  }
}
