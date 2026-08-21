import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Rule / Global / Direct as one mutually-exclusive row. The switch talks to
// mihomo's running core, so it is only offered while something is running —
// with nothing to switch, a chip that lit up would be describing a mode that
// is not in effect anywhere.
Column {
  id: root

  required property color textColor
  required property string panelFontFamily
  property color accentColor: Color.accent
  property string mode: "rule"
  // Not `enabled`: that is an Item property, and shadowing it would also
  // stop the section receiving input events rather than just greying out.
  property bool switchable: true
  property bool pending: false
  property string hint: ""
  property int cursorIndex: -1
  property var proxyOptions: []
  property string currentProxy: ""
  property bool selectingGlobal: false

  signal modeRequested(string value)
  signal globalRequested()
  signal proxyRequested(string value)
  signal chipHovered(int index, bool isHovered)
  signal subscriptionRequested()

  readonly property var options: Model.MODES.map(function(entry) {
    return { value: entry.value, label: entry.label, tooltip: entry.hint }
  })

  spacing: Style.space(8)

  Item {
    width: parent.width
    implicitHeight: Math.max(sectionHeader.implicitHeight, pendingLabel.implicitHeight)

    PanelSectionHeader {
      id: sectionHeader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "PROXY MODE"
      foreground: root.textColor
      fontFamily: root.panelFontFamily
    }

    Text {
      id: pendingLabel
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.pending
      text: "switching…"
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    id: modeControlRow
    width: parent.width
    spacing: Style.space(6)

    Row {
      id: group
      anchors.verticalCenter: parent.verticalCenter
      width: modeControlRow.width - subscriptionButton.width - modeControlRow.spacing
      spacing: Style.space(6)
      opacity: root.switchable ? 1.0 : 0.45
      enabled: root.switchable

      Repeater {
        model: root.options

        delegate: Button {
          id: chip
          required property var modelData
          required property int index
          text: String(modelData.label)
          selected: String(modelData.value) === root.mode
          hasCursor: root.cursorIndex === index
          bordered: true
          foreground: root.textColor
          accent: root.accentColor
          fontFamily: root.panelFontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(14)
          verticalPadding: Style.space(9)
          onHovered: function(isHovered) { root.chipHovered(chip.index, isHovered) }
          onClicked: {
            var value = String(chip.modelData.value)
            if (value === "global") {
              root.selectingGlobal = true
              root.globalRequested()
            } else {
              root.selectingGlobal = false
              root.modeRequested(value)
            }
          }
        }
      }
    }

    PanelActionButton {
      id: subscriptionButton
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.textColor
      hoverColor: root.textColor
      size: Style.space(26)
      tooltipText: "Manage subscriptions..."
      onClicked: root.subscriptionRequested()

      ActionIcon {
        anchors.centerIn: parent
        name: "settings"
        iconSize: Style.font.body
        color: subscriptionButton._hot
          ? subscriptionButton.hoverColor
          : subscriptionButton.foreground
      }
    }
  }

  SearchableDropdown {
    width: parent.width
    visible: root.selectingGlobal || root.mode === "global"
    label: "GLOBAL CONNECTION"
    value: root.currentProxy
    options: root.proxyOptions
    placeholderText: root.proxyOptions.length > 0 ? "Choose a connection…" : "No connections available"
    emptyText: "No connections available"
    foreground: root.textColor
    accent: root.accentColor
    fontFamily: root.panelFontFamily
    onChanged: function(value) { root.proxyRequested(value) }
  }

  Text {
    width: parent.width
    visible: root.hint !== ""
    text: root.hint
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
