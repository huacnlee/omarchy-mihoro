import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

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

  // Every row here reads "DNS bypassed" while the TUN's DNS goes around it, so
  // the cause and its fix sit above them. The fix's progress and failure
  // report here too: this is the page it was pressed on.
  readonly property string dnsNotice: root.service.actionStatus !== "" && root.service.repairingDns
    ? root.service.actionStatus
    : (root.service.lastError !== "" ? root.service.lastError
      : (root.service.dnsBypassed ? Model.DNS_BYPASSED_NOTICE
        : (root.service.actionStatus === Model.DNS_ROUTED_STATUS ? root.service.actionStatus : "")))

  Text {
    visible: root.dnsNotice !== ""
    width: parent.width
    text: root.dnsNotice
    color: root.service.lastError !== "" || (root.service.dnsBypassed && !root.service.repairingDns)
      ? Color.urgent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.58)
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
    maximumLineCount: 3
    elide: Text.ElideRight
  }

  Button {
    visible: root.service.dnsBypassed && !root.service.repairingDns
    // `...` because it opens the system's password dialog.
    text: "Fix DNS..."
    foreground: root.textColor
    bordered: true
    fontSize: Style.font.bodySmall
    onClicked: root.service.repairTunDns()
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
            || modelData.result === "Not found" || modelData.result === "DNS bypassed" ? Color.urgent
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
        visible: index === 5
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
