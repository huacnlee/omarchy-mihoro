import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// URL subscriptions, which is the only kind mihoro has: `remote_config_url` in
// mihoro.toml, fetched by `mihoro update --config`. Setting a URL and fetching
// it are one action here — a saved URL that nothing has downloaded would show a
// subscription the proxy is not actually using.
//
// The URL is a bearer credential, so read-only mode never renders it. It only
// enters a control after the user explicitly chooses Edit/Add.
Column {
  id: root

  required property var service
  required property color textColor
  required property string panelFontFamily
  property bool editing: false
  property string cursorTarget: ""

  signal urlCommitted(string url)
  signal updateRequested()
  signal backRequested()

  readonly property string url: service.config.remoteConfigUrl
  readonly property bool updating: service.actionKind === "update" || service.actionKind === "init"

  spacing: Style.space(8)

  function beginEdit() {
    field.text = root.url
    root.editing = true
    Qt.callLater(function() { field.forceActiveFocus(); field.selectAll() })
  }

  function cancelEdit() {
    root.editing = false
  }

  function commit() {
    if (Model.subscriptionUrlError(field.text) !== "") return
    root.editing = false
    root.urlCommitted(field.text.trim())
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
        text: "SUBSCRIPTION"
        foreground: root.textColor
        fontFamily: root.panelFontFamily
      }
    }

  }

  Rectangle {
    id: subscriptionStatus
    visible: !root.editing && root.service.probe.configPresent
    width: parent.width
    implicitHeight: Style.space(38)
    radius: Style.cornerRadius
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.04)
    border.width: 1
    border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(7)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(6)
        height: width
        radius: width / 2
        color: Color.accent
      }

      Text {
        text: "Configured"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: "Last updated " + Model.formatAgo(root.service.probe.configMtime, root.service.probe.now)
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
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
      enabled: root.url !== "" && !root.service.busy
      hasCursor: root.cursorTarget === "update"
      fontSize: Style.font.bodySmall
      onClicked: root.updateRequested()
    }

    Button {
      width: (subscriptionActions.width - subscriptionActions.spacing) / 2
      text: root.url === "" ? "Add..." : "Edit..."
      foreground: root.textColor
      bordered: true
      enabled: !root.service.busy
      hasCursor: root.cursorTarget === "edit"
      fontSize: Style.font.bodySmall
      onClicked: root.beginEdit()
    }

  }

  // ---- editor
  Column {
    visible: root.editing
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: "SUBSCRIPTION URL"
      foreground: root.textColor
      fontFamily: root.panelFontFamily
    }

    QQC.TextArea {
      id: field
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
          field.activeFocus ? 0.09 : 0.04)
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus
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
      visible: field.text.trim() !== "" && Model.subscriptionUrlError(field.text) !== ""
      text: Model.subscriptionUrlError(field.text)
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
        text: root.service.probe.configPresent ? "Update" : "Save and set up"
        foreground: root.textColor
        bordered: true
        enabled: Model.subscriptionUrlError(field.text) === "" && !root.service.busy
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
