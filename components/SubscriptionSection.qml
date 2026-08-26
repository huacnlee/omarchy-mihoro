import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Subscriptions.js" as Subscriptions

// The subscription list. mihoro holds one subscription at a time —
// `remote_config_url` in mihoro.toml, fetched by `mihoro update --config` — so
// the panel keeps the list and hands the selected entry down. Selecting one and
// fetching it are a single action here: a selection nothing had downloaded
// would show a subscription the proxy is not actually using.
//
// The URL is a bearer credential, so nothing outside the editor renders it —
// rows carry the name the user gave the subscription, which defaults to its
// host. It only enters a control after an explicit Add or Edit.
Column {
  id: root

  required property var service
  required property color textColor
  required property string panelFontFamily
  property bool editing: false
  // The entry being edited; empty while adding a new one.
  property string editingId: ""
  // The row whose removal is waiting to be confirmed. Removing the selected
  // subscription switches the proxy, so it does not happen on one stray click.
  property string confirmingId: ""
  property string cursorTarget: ""

  signal rowHovered(int index, bool isHovered)
  signal selectRequested(string id)
  signal commitRequested(string id, string name, string url)
  signal removeRequested(string id)
  signal updateRequested()
  signal backRequested()

  readonly property var entries: service.subscriptionList
  readonly property string activeId: service.activeSubscriptionId
  readonly property bool updating: service.actionKind === "update" || service.actionKind === "init"

  // Only complaints about what has been typed. An empty URL is the editor's
  // starting state, not a mistake to shout about.
  readonly property string editorError: {
    if (urlField.text.trim() !== "" && Model.subscriptionUrlError(urlField.text) !== "")
      return Model.subscriptionUrlError(urlField.text)
    return Subscriptions.nameError(nameField.text)
  }

  spacing: Style.space(8)

  function beginAdd() {
    root.confirmingId = ""
    root.editingId = ""
    nameField.text = ""
    urlField.text = ""
    root.editing = true
    Qt.callLater(function() { urlField.forceActiveFocus() })
  }

  function beginEdit(id) {
    var entry = Subscriptions.find(root.service.subscriptions, id)
    if (!entry) {
      root.beginAdd()
      return
    }
    root.confirmingId = ""
    root.editingId = entry.id
    nameField.text = entry.name
    urlField.text = entry.url
    root.editing = true
    Qt.callLater(function() { urlField.forceActiveFocus(); urlField.selectAll() })
  }

  function beginEditActive() {
    if (root.activeId === "") root.beginAdd()
    else root.beginEdit(root.activeId)
  }

  function cancelEdit() {
    root.editing = false
    root.editingId = ""
    root.confirmingId = ""
  }

  function commit() {
    if (Model.subscriptionUrlError(urlField.text) !== "") return
    if (Subscriptions.nameError(nameField.text) !== "") return
    var id = root.editingId
    root.editing = false
    root.editingId = ""
    root.commitRequested(id, nameField.text.trim(), urlField.text.trim())
  }

  Item {
    width: parent.width
    implicitHeight: sectionHeader.implicitHeight

    Row {
      id: sectionHeader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Button {
        text: "←"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.title
        onClicked: root.backRequested()
      }

      PanelSectionHeader {
        anchors.verticalCenter: parent.verticalCenter
        text: "SUBSCRIPTIONS"
        foreground: root.textColor
        fontFamily: root.panelFontFamily
      }
    }

  }

  // ---- the list
  Column {
    id: subscriptionList
    visible: !root.editing
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: root.entries

      delegate: CursorSurface {
        id: row
        required property var modelData
        required property int index

        readonly property bool isActive: String(row.modelData.id) === root.activeId
        readonly property bool confirming: String(row.modelData.id) === root.confirmingId

        width: subscriptionList.width
        implicitHeight: Style.space(40)
        foreground: root.textColor
        accent: Color.accent
        current: row.isActive
        hasCursor: root.cursorTarget === "sub:" + String(row.modelData.id)

        // The whole row is the switch; the buttons at its right edge are not
        // part of it, so they sit above this and take their own clicks.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: row.isActive ? Qt.ArrowCursor : Qt.PointingHandCursor
          enabled: !row.confirming
          onContainsMouseChanged: root.rowHovered(row.index, containsMouse)
          onClicked: if (!row.isActive) root.selectRequested(String(row.modelData.id))
        }

        Item {
          id: rowBody
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: rowActions.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          implicitHeight: rowText.implicitHeight
          visible: !row.confirming

          Rectangle {
            id: selectedDot
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6)
            height: width
            radius: width / 2
            color: row.isActive ? Color.accent : "transparent"
            border.width: row.isActive ? 0 : 1
            border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.35)
          }

          Column {
            id: rowText
            anchors.left: selectedDot.right
            anchors.leftMargin: Style.space(7)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              width: parent.width
              text: String(row.modelData.name)
              color: root.textColor
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: row.isActive
              text: root.service.probe.configPresent
                ? "Last updated " + Model.formatAgo(root.service.probe.configMtime, root.service.probe.now)
                : "Not fetched yet"
              color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Row {
          id: rowActions
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: !row.confirming
          spacing: Style.space(2)

          // Both actions are ActionIcon on its one grid at one size, so the
          // pair reads as a pair. See DESIGN.md.
          PanelActionButton {
            id: editAction
            anchors.verticalCenter: parent.verticalCenter
            tooltipText: "Edit subscription..."
            foreground: root.textColor
            hoverColor: root.textColor
            fontFamily: root.panelFontFamily
            onClicked: root.beginEdit(String(row.modelData.id))

            ActionIcon {
              anchors.centerIn: parent
              name: "edit"
              iconSize: Style.font.icon
              color: editAction._hot ? editAction.hoverColor : editAction.foreground
            }
          }

          PanelActionButton {
            id: removeAction
            anchors.verticalCenter: parent.verticalCenter
            tooltipText: "Remove subscription"
            foreground: root.textColor
            hoverColor: Color.urgent
            fontFamily: root.panelFontFamily
            enabled: !root.service.applying
            onClicked: root.confirmingId = String(row.modelData.id)

            ActionIcon {
              anchors.centerIn: parent
              name: "trash"
              iconSize: Style.font.icon
              color: !removeAction.enabled
                ? Qt.darker(removeAction.foreground, 2.0)
                : (removeAction._hot ? removeAction.hoverColor : removeAction.foreground)
            }
          }
        }

        // ---- inline removal confirmation
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: confirmActions.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: row.confirming
          text: row.isActive && root.entries.length === 1
            ? "Remove the only subscription?"
            : "Remove " + String(row.modelData.name) + "?"
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Row {
          id: confirmActions
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: row.confirming
          spacing: Style.spacing.controlGap

          Button {
            text: "Remove"
            foreground: Color.urgent
            bordered: true
            fontSize: Style.font.caption
            enabled: !root.service.applying
            onClicked: {
              root.confirmingId = ""
              root.removeRequested(String(row.modelData.id))
            }
          }

          Button {
            text: "Cancel"
            foreground: root.textColor
            bordered: false
            fontSize: Style.font.caption
            onClicked: root.confirmingId = ""
          }
        }
      }
    }

    Rectangle {
      id: emptyState
      visible: root.entries.length === 0
      width: parent.width
      implicitHeight: Style.space(40)
      radius: Style.cornerRadius
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.04)
      border.width: 1
      border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: "No subscriptions yet"
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Row {
    id: subscriptionActions
    visible: !root.editing
    width: parent.width
    spacing: Style.spacing.controlGap

    Button {
      width: (subscriptionActions.width - subscriptionActions.spacing) / 2
      text: root.updating ? "Updating…" : "Update"
      foreground: root.textColor
      bordered: true
      enabled: root.activeId !== "" && !root.service.busy
      hasCursor: root.cursorTarget === "update"
      fontSize: Style.font.bodySmall
      onClicked: root.updateRequested()
    }

    Button {
      width: (subscriptionActions.width - subscriptionActions.spacing) / 2
      text: "Add..."
      foreground: root.textColor
      bordered: true
      enabled: !root.service.applying
      hasCursor: root.cursorTarget === "add"
      fontSize: Style.font.bodySmall
      onClicked: root.beginAdd()
    }

  }

  // ---- editor
  Column {
    visible: root.editing
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: "NAME"
      foreground: root.textColor
      fontFamily: root.panelFontFamily
    }

    TextField {
      id: nameField
      width: parent.width
      foreground: root.textColor
      accent: Color.accent
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.body
      placeholderText: "Optional — defaults to the host"
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.cancelEdit()
          event.accepted = true
        }
      }
    }

    PanelSectionHeader {
      text: "SUBSCRIPTION URL"
      foreground: root.textColor
      fontFamily: root.panelFontFamily
    }

    QQC.TextArea {
      id: urlField
      width: parent.width
      implicitHeight: Math.max(Style.space(74), contentHeight + topPadding + bottomPadding)
      color: root.textColor
      selectionColor: Color.accent
      selectedTextColor: root.textColor
      placeholderTextColor: Qt.darker(root.textColor, 1.6)
      placeholderText: "https://example.com/subscription"
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.body
      wrapMode: TextEdit.WrapAnywhere
      selectByMouse: true
      leftPadding: Style.spacing.controlPaddingX
      rightPadding: Style.spacing.controlPaddingX
      topPadding: Style.spacing.inputPaddingY
      bottomPadding: Style.spacing.inputPaddingY
      background: Rectangle {
        radius: Style.cornerRadius
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b,
          urlField.activeFocus ? 0.09 : 0.04)
        border.width: urlField.activeFocus ? 2 : 1
        border.color: urlField.activeFocus
          ? Color.accent
          : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.24)
      }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.cancelEdit()
          event.accepted = true
        }
      }
    }

    Text {
      width: parent.width
      visible: root.editorError !== ""
      text: root.editorError
      color: Color.urgent
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Row {
      id: editorActions
      width: parent.width
      spacing: Style.spacing.controlGap

      Button {
        width: (editorActions.width - editorActions.spacing) / 2
        text: root.service.probe.configPresent ? "Save" : "Save and set up"
        foreground: root.textColor
        bordered: true
        enabled: Model.subscriptionUrlError(urlField.text) === ""
          && Subscriptions.nameError(nameField.text) === ""
          && !root.service.applying
        fontSize: Style.font.bodySmall
        onClicked: root.commit()
      }

      Button {
        width: (editorActions.width - editorActions.spacing) / 2
        text: "Cancel"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.bodySmall
        onClicked: root.cancelEdit()
      }
    }
  }
}
