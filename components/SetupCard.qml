import QtQuick
import qs.Commons
import qs.Ui

// Shown until the panel has something real to drive.
Rectangle {
  id: root

  required property color textColor
  required property string panelFontFamily
  property string stateKey: "cli_missing"
  property bool busy: false
  property bool hasCursor: false

  signal addUrlRequested()
  signal installRequested()

  readonly property bool missingCli: stateKey === "cli_missing"

  width: parent ? parent.width : 0
  implicitHeight: body.implicitHeight + Style.space(26)
  radius: Style.cornerRadius
  color: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.04)
  border.width: 1
  border.color: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(14)
    anchors.rightMargin: Style.space(14)
    spacing: Style.space(8)

    Text {
      width: parent.width
      text: root.missingCli ? "Install the mihoro CLI" : "Add a subscription URL"
      color: root.textColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      text: root.missingCli
        ? "Install the mihoro CLI to manage your Mihomo subscription and service from this panel."
        : "mihoro subscribes to one remote config URL. Add yours and mihoro will download it, install mihomo.service, and start the proxy."
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.58)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Button {
      visible: root.missingCli
      text: "Install Mihoro..."
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.bodySmall
      enabled: !root.busy
      hasCursor: root.hasCursor
      onClicked: root.installRequested()
    }

    Button {
      visible: !root.missingCli
      text: "Add subscription URL..."
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.bodySmall
      enabled: !root.busy
      hasCursor: root.hasCursor
      onClicked: root.addUrlRequested()
    }
  }
}
