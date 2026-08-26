import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Every Selector group the subscription defines (GLOBAL excepted — the mode
// chips own it), each with a searchable picker over its nodes. This is the
// panel form of `proxy-node`: pick a group, see each node's last measured
// delay, switch. Delays come from the core's probe history until the group's
// test button asks for fresh ones, and the list sorts fastest-first once it
// has them.
Column {
  id: root

  required property color textColor
  required property string panelFontFamily
  required property color fastColor
  required property color slowColor
  property color accentColor: Color.accent
  property var groups: []
  // The switch in flight, as `{group, name}`; null when nothing is.
  property var pendingNode: null
  property string testingGroup: ""
  // Not `enabled`: that is an Item property, and shadowing it would also stop
  // the section receiving input events rather than just greying out. False
  // when the API is not answering — a picker against a dead core would fire a
  // doomed PUT and the data on screen is stale anyway.
  property bool switchable: true
  property int cursorIndex: -1

  signal nodeRequested(string group, string name)
  signal testRequested(string group)
  signal dropdownHovered(int index, bool isHovered)

  // While any group's picker is open its search field owns the keys; the
  // panel reads this to suspend its own shortcuts, as it does for the URL
  // editor.
  readonly property bool searchOpen: {
    for (var i = 0; i < groupRepeater.count; i++) {
      var item = groupRepeater.itemAt(i)
      if (item && item.dropdownOpen) return true
    }
    return false
  }

  function openGroup(name) {
    for (var i = 0; i < groupRepeater.count; i++) {
      var item = groupRepeater.itemAt(i)
      if (item && item.groupName === String(name)) { item.openDropdown(); return }
    }
  }

  function delayFor(group, nodeName) {
    var nodes = group.nodes
    for (var i = 0; i < nodes.length; i++)
      if (nodes[i].name === nodeName) return nodes[i].delay
    return NaN
  }

  function delayColor(ms) {
    var state = Model.delayState(ms)
    if (state === "fast") return root.fastColor
    if (state === "slow") return root.slowColor
    return Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
  }

  spacing: Style.space(8)

  Item {
    width: parent.width
    implicitHeight: Math.max(nodesHeader.implicitHeight, testingLabel.implicitHeight)

    PanelSectionHeader {
      id: nodesHeader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "PROXY NODES"
      foreground: root.textColor
      fontFamily: root.panelFontFamily
    }

    Text {
      id: testingLabel
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.testingGroup !== ""
      text: "testing…"
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Repeater {
    id: groupRepeater
    model: root.groups

    delegate: Column {
      id: groupRow
      required property var modelData
      required property int index

      readonly property string groupName: String(modelData.name)
      readonly property string currentNode: root.pendingNode !== null && root.pendingNode.group === groupName
        ? String(root.pendingNode.name)
        : String(modelData.now)
      readonly property real currentDelay: root.delayFor(modelData, currentNode)
      readonly property alias dropdownOpen: dropdown.popupOpen

      function openDropdown() { dropdown.open() }

      width: parent.width
      spacing: Style.space(6)

      Item {
        width: parent.width
        implicitHeight: Math.max(groupLabel.implicitHeight, testButton.implicitHeight)

        Text {
          id: groupLabel
          anchors.left: parent.left
          anchors.right: testButton.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: groupRow.groupName
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        PanelActionButton {
          id: testButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          foreground: root.textColor
          hoverColor: root.textColor
          size: Style.space(26)
          enabled: root.switchable && root.testingGroup === ""
          opacity: enabled ? 1.0 : 0.45
          tooltipText: "Test delays"
          onClicked: root.testRequested(groupRow.groupName)

          ActionIcon {
            anchors.centerIn: parent
            name: "bolt"
            iconSize: Style.font.body
            color: testButton._hot ? testButton.hoverColor : testButton.foreground
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)
        visible: groupRow.currentNode !== ""

        Text {
          text: "now: " + groupRow.currentNode
          color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: Math.min(implicitWidth, parent.width - delayText.width - parent.spacing)
        }

        Text {
          id: delayText
          text: Model.formatDelay(groupRow.currentDelay)
          color: root.delayColor(groupRow.currentDelay)
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
        }
      }

      SearchableDropdown {
        id: dropdown
        width: parent.width
        showLabel: false
        enabled: root.switchable
        opacity: root.switchable ? 1.0 : 0.45
        value: groupRow.currentNode
        options: Model.sortNodesByDelay(groupRow.modelData.nodes).map(function(node) {
          return { value: node.name, label: node.name, description: Model.formatDelay(node.delay) }
        })
        placeholderText: "Choose a node…"
        emptyText: "No nodes available"
        foreground: root.textColor
        accent: root.accentColor
        fontFamily: root.panelFontFamily
        hasCursor: root.cursorIndex === groupRow.index
        onChanged: function(value) { root.nodeRequested(groupRow.groupName, value) }
        onHovered: function(isHovered) { root.dropdownHovered(groupRow.index, isHovered) }
      }
    }
  }
}
