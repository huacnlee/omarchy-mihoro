import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  required property var service
  required property color textColor
  required property color successColor
  required property string panelFontFamily
  property bool hasCursor: false

  signal backRequested()
  signal installRequested()

  spacing: Style.space(12)

  Item {
    width: parent.width
    implicitHeight: installHeader.implicitHeight

    Row {
      id: installHeader
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
        text: "MIHORO INSTALLATION"
        foreground: root.textColor
        fontFamily: root.panelFontFamily
      }
    }
  }

  Rectangle {
    width: parent.width
    implicitHeight: installStatus.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: root.service.probe.mihoroInstalled ? Qt.rgba(root.successColor.r, root.successColor.g, root.successColor.b, 0.10)
      : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.04)
    border.width: 1
    border.color: root.service.probe.mihoroInstalled ? Qt.rgba(root.successColor.r, root.successColor.g, root.successColor.b, 0.55)
      : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

    Column {
      id: installStatus
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(5)

      Row {
        spacing: Style.space(8)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(7)
          height: width
          radius: width / 2
          color: root.service.probe.mihoroInstalled ? root.successColor : Color.urgent
        }

        Text {
          text: root.service.probe.mihoroInstalled ? "Mihoro installed" : "Not installed"
          color: root.service.probe.mihoroInstalled ? root.successColor : root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      Text {
        visible: text !== ""
        text: root.service.probe.mihoroVersion
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.58)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Text {
    width: parent.width
    text: "The official installer opens in an Omarchy terminal so progress and errors remain visible."
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.58)
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Button {
    width: parent.width
    text: "Install Now"
    iconText: "+"
    foreground: root.textColor
    bordered: true
    enabled: !root.service.busy
    hasCursor: root.hasCursor
    fontSize: Style.font.bodySmall
    onClicked: root.installRequested()
  }
}
