import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui

// Links out, plus the one maintenance action a status panel needs. No
// uninstall, no upgrade, nothing that changes what is on this machine beyond
// restarting the service the panel already starts and stops.
Item {
  id: root

  required property color textColor
  required property string panelFontFamily
  property string dashboardUrl: ""
  property bool canRestart: false
  property bool canCopyProxy: false

  signal restartRequested()
  signal copyProxyRequested()

  implicitWidth: Style.space(24)
  implicitHeight: Style.space(24)

  function openUrl(url) {
    Quickshell.execDetached(["xdg-open", url])
    menu.close()
  }

  Button {
    id: menuButton
    anchors.fill: parent
    text: "⋮"
    foreground: root.textColor
    bordered: true
    onClicked: menu.opened ? menu.close() : menu.open()
  }

  QQC.Popup {
    id: menu
    x: menuButton.width - width
    y: menuButton.height + Style.space(4)
    width: Style.space(190)
    implicitHeight: menuItems.implicitHeight + Style.space(8)
    padding: Style.space(4)
    modal: false
    focus: true
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside
    background: Rectangle {
      radius: Style.cornerRadius
      color: Color.background
      border.width: 1
      border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.16)
    }
    contentItem: Column {
      id: menuItems
      spacing: Style.space(2)

      MenuRow {
        text: "Dashboard"
        enabled: root.dashboardUrl !== ""
        onActivated: root.openUrl(root.dashboardUrl)
      }
      MenuRow {
        text: "GitHub"
        onActivated: root.openUrl("https://github.com/huacnlee/omarchy-mihoro")
      }
      MenuRow { text: "mihoro"; onActivated: root.openUrl("https://github.com/spencerwooo/mihoro") }
      MenuRow { text: "mihomo docs"; onActivated: root.openUrl("https://wiki.metacubex.one") }

      // Links above, the thing that changes this machine below.
      Item {
        width: menu.width - menu.leftPadding - menu.rightPadding
        implicitHeight: Style.space(7)
        PanelSeparator {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          foreground: root.textColor
        }
      }

      MenuRow {
        text: "Copy proxy export"
        enabled: root.canCopyProxy
        onActivated: {
          menu.close()
          root.copyProxyRequested()
        }
      }

      MenuRow {
        text: "Restart mihomo"
        enabled: root.canRestart
        onActivated: {
          menu.close()
          root.restartRequested()
        }
      }
    }
  }

  // `enabled` is Item's own, and it already stops the handlers below from
  // firing, so a disabled row only has to look disabled.
  component MenuRow: Rectangle {
    id: row
    required property string text
    signal activated()

    width: menu.width - menu.leftPadding - menu.rightPadding
    implicitHeight: Style.space(34)
    radius: Style.cornerRadius
    opacity: row.enabled ? 1.0 : 0.4
    color: hover.hovered
      ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.08)
      : "transparent"

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      text: row.text
      color: root.textColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
    }

    HoverHandler { id: hover }
    TapHandler { onTapped: row.activated() }
  }
}
