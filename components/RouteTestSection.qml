import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  required property var service
  required property color textColor
  required property string panelFontFamily
  property bool hasCursor: false

  signal backRequested()
  signal testRequested()

  spacing: Style.space(8)

  Item {
    width: parent.width
    implicitHeight: routeHeader.implicitHeight

    Row {
      id: routeHeader
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
        text: "ROUTE TEST"
        foreground: root.textColor
        fontFamily: root.panelFontFamily
      }
    }
  }

  Text {
    width: parent.width
    text: "Actual outbound used for each test request."
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.58)
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.service.routeTests

    delegate: Column {
      required property int index
      required property var modelData
      width: root.width
      spacing: Style.space(8)

      Item {
        width: parent.width
        implicitHeight: Math.max(routeName.implicitHeight, routeResult.implicitHeight)

        Text {
          id: routeName
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(92)
          text: modelData.label
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: routeResult
          anchors.left: routeName.right
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.result
          color: modelData.result === "Failed" || modelData.result === "Unavailable"
            || modelData.result === "Not found" ? Color.urgent
            : (modelData.result === "Testing..." || modelData.result === "Waiting..."
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.58)
              : root.textColor)
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignRight
        }
      }

      PanelSeparator {
        visible: index === 2
        width: parent.width
        foreground: root.textColor
      }
    }
  }

  Button {
    width: parent.width
    text: root.service.routeTestRunning ? "Testing..." : "Test again"
    foreground: root.textColor
    bordered: true
    enabled: !root.service.routeTestRunning
    hasCursor: root.hasCursor
    fontSize: Style.font.bodySmall
    onClicked: root.testRequested()
  }
}
