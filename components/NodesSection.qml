import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Every Selector group the mode row does not already own, each with a
// searchable picker over its nodes. This is the panel form of `proxy-node`:
// pick a group, see each node's last measured delay, switch. Delays come from
// the core's probe history until the group's test button asks for fresh ones,
// and the list sorts fastest-first once it has them.
//
// Folded away by default. A subscription with a handful of groups is three
// lines each, which would push CONNECTION off the bottom of the panel for
// everyone, including the majority who never change a node. The disclosure is
// the icon on the mode row, so nothing of this section is on screen — not even
// a header — until it is asked for.
//
// A pick is a draft until Apply, as it is for the mode row's proxy — switching
// on selection would fire a PUT at whatever the search filter happened to land
// on while typing.
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
  // Owned by the panel, which needs it to build the cursor target list before
  // this section exists, and which puts the disclosure on the mode row.
  property bool expanded: false

  signal nodeRequested(string group, string name)
  signal testRequested(string group)
  signal dropdownHovered(int index, bool isHovered)

  // While any group's picker is open its search field owns the keys; the
  // panel reads this to suspend its own shortcuts, as it does for the URL
  // editor.
  readonly property bool searchOpen: {
    if (!expanded) return false
    for (var i = 0; i < groupRepeater.count; i++) {
      var item = groupRepeater.itemAt(i)
      if (item && item.dropdownOpen) return true
    }
    return false
  }

  // The Repeater is keyed on group names rather than the group objects: a
  // delegate model over a JS array is rebuilt whenever the array's contents
  // change, and the groups carry the delays, so every refresh that measured
  // something new — a delay test above all — would destroy the open picker and
  // any unapplied draft with it. The names change only when the subscription
  // does, and each delegate reads its own group through `groupFor`, whose
  // bindings update in place.
  readonly property var groupNames: {
    var out = []
    for (var i = 0; i < groups.length; i++) out.push(String(groups[i].name))
    return out
  }

  function groupFor(name) {
    var wanted = String(name)
    for (var i = 0; i < groups.length; i++)
      if (String(groups[i].name) === wanted) return groups[i]
    return { name: wanted, now: "", nodes: [] }
  }

  function itemFor(name) {
    for (var i = 0; i < groupRepeater.count; i++) {
      var item = groupRepeater.itemAt(i)
      if (item && item.groupName === String(name)) return item
    }
    return null
  }

  function openGroup(name) {
    var item = itemFor(name)
    if (item) item.openDropdown()
  }

  // Enter on a group row: confirm the drafted pick if there is one, otherwise
  // open the picker. One key walks the whole switch.
  function activateGroup(name) {
    var item = itemFor(name)
    if (item) item.activate()
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

  Column {
    id: groupList
    width: parent.width
    spacing: Style.space(8)
    visible: root.expanded

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
      // Empty while the section is shut, so nothing is built for rows nobody
      // can reach: a shut section takes its open pickers and unapplied drafts
      // with it, rather than hiding a switch that is still waiting to fire.
      model: root.expanded ? root.groupNames : []

      delegate: Column {
        id: groupRow
        required property var modelData
        required property int index

        readonly property string groupName: String(modelData)
        readonly property var group: root.groupFor(groupRow.groupName)
        readonly property string currentNode: root.pendingNode !== null && root.pendingNode.group === groupName
          ? String(root.pendingNode.name)
          : String(group.now)
        readonly property real currentDelay: root.delayFor(groupRow.group, currentNode)
        readonly property alias dropdownOpen: dropdown.popupOpen
        // The pick waiting for Apply. Empty means the row shows the core's
        // own answer; the optimistic overlay makes an applied pick current, so
        // clearing it here is what takes the buttons away again.
        property string draftNode: ""
        readonly property bool hasDraft: draftNode !== "" && draftNode !== currentNode
        // What the picker should be showing: the draft while there is one, the
        // core's own answer otherwise.
        readonly property string pickerValue: draftNode !== "" ? draftNode : currentNode

        function openDropdown() { dropdown.open() }
        function closeDropdown() { dropdown.close() }
        function cancel() { draftNode = "" }

        function apply() {
          if (!root.switchable || !hasDraft) return
          root.nodeRequested(groupName, draftNode)
          draftNode = ""
        }

        function activate() {
          if (hasDraft) apply()
          else if (root.switchable) dropdown.open()
        }

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
          value: groupRow.pickerValue
          options: Model.sortNodesByDelay(groupRow.group.nodes).map(function(node) {
            return { value: node.name, label: node.name, description: Model.formatDelay(node.delay) }
          })
          placeholderText: "Choose a node…"
          emptyText: "No nodes available"
          foreground: root.textColor
          accent: root.accentColor
          fontFamily: root.panelFontFamily
          hasCursor: root.cursorIndex === groupRow.index
          onChanged: function(value) {
            groupRow.draftNode = String(value)
            // SearchableDropdown assigns its own `value` when a row is picked,
            // and that assignment destroys the binding installed above: after
            // one pick the trigger stopped following anything, so Cancel
            // cleared the draft while the picked node stayed on screen. Put the
            // binding back each time the control breaks it.
            dropdown.value = Qt.binding(function() { return groupRow.pickerValue })
          }
          onHovered: function(isHovered) { root.dropdownHovered(groupRow.index, isHovered) }
        }

        Row {
          id: groupActions
          width: parent.width
          spacing: Style.spacing.controlGap
          visible: groupRow.hasDraft

          Button {
            width: (groupActions.width - groupActions.spacing) / 2
            text: "Apply"
            foreground: root.textColor
            bordered: true
            fontSize: Style.font.bodySmall
            enabled: root.switchable
            onClicked: groupRow.apply()
          }

          Button {
            width: (groupActions.width - groupActions.spacing) / 2
            text: "Cancel"
            foreground: root.textColor
            bordered: true
            fontSize: Style.font.bodySmall
            onClicked: groupRow.cancel()
          }
        }
      }
    }
  }
}
