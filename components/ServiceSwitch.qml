import QtQuick
import qs.Commons

// The service switch uses semantic status colors rather than the shell's
// theme-selected fill. ToggleSwitch intentionally resolves its track through
// theme tokens, which can stay gray even when a caller supplies a green
// accent; this compact variant makes the running/stopped state unambiguous.
Item {
  id: root

  property bool checked: false
  property bool busy: false
  property color foreground: Color.foreground
  property color onColor: Color.accent
  property color knobOnColor: Color.foreground
  property color offColor: Qt.darker(foreground, 1.6)

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property int trackHeight: Style.space(24)
  readonly property int trackWidth: Math.round(trackHeight * 1.9)
  readonly property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  readonly property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))
  readonly property int cursorPad: Style.space(6)

  implicitWidth: trackWidth + cursorPad * 2
  implicitHeight: trackHeight

  Rectangle {
    id: track
    width: root.trackWidth
    height: root.trackHeight
    anchors.centerIn: parent
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: root.checked ? root.onColor : root.offColor
    border.width: 1
    border.color: Qt.darker(color, 1.2)

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: Style.cornerRadius > 0 ? height / 2 : 0
      anchors.verticalCenter: parent.verticalCenter
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      color: root.checked ? root.knobOnColor : Qt.lighter(root.offColor, 1.7)

      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: if (!root.busy) root.toggled()
  }
}
