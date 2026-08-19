import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

Panel {
  id: root
  moduleName: "mihoro.omarchy"
  ipcTarget: "mihoro.omarchy"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent

  SystemTheme {
    id: systemTheme
  }
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool cursorActive: false
  property int cursorIndex: 0
  property int modeCursor: 0
  property int panelPage: 1

  // One flat list of what the keyboard can reach, rebuilt from the service
  // state. A panel this shallow does not need per-section cursors: the order
  // here is the order on screen.
  readonly property var targets: {
    if (root.panelPage === 2) return ["update", "edit"]
    if (root.panelPage === 3) return ["install"]
    if (!mihoro.probe.mihoroInstalled) return ["setup"]
    if (!mihoro.initialized) return ["setup"]
    var list = ["power"]
    if (mihoro.canSwitchMode) list.push("mode")
    list.push("subscription")
    return list
  }

  readonly property string cursorTarget: {
    if (!cursorActive) return ""
    if (cursorIndex < 0 || cursorIndex >= targets.length) return ""
    return targets[cursorIndex]
  }

  readonly property string dashboardUrl: mihoro.apiBase !== "" && mihoro.config.externalUi !== ""
    ? mihoro.apiBase + "/ui"
    : ""

  readonly property string barTooltip: mihoro.active
    ? "Mihoro · " + Model.modeLabel(mihoro.mode)
    : "Mihoro · " + mihoro.connection.label

  function clampCursor() {
    if (targets.length === 0) { cursorIndex = 0; return }
    if (cursorIndex < 0) cursorIndex = 0
    if (cursorIndex > targets.length - 1) cursorIndex = targets.length - 1
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    clampCursor()
    if (dx !== 0 && cursorTarget === "mode") {
      modeCursor = Math.max(0, Math.min(Model.MODES.length - 1, modeCursor + dx))
      return
    }
    if (dy !== 0) {
      cursorIndex = Math.max(0, Math.min(targets.length - 1, cursorIndex + dy))
      if (cursorTarget === "mode") modeCursor = Model.modeIndex(mihoro.mode)
    }
  }

  function activateCursor() {
    clampCursor()
    var target = cursorTarget
    if (target === "power") mihoro.toggleService()
    else if (target === "mode") root.requestMode(Model.MODES[modeCursor].value)
    else if (target === "subscription") root.openSubscriptionPage()
    else if (target === "edit") subscription.beginEdit()
    else if (target === "update") mihoro.updateSubscription()
    else if (target === "install") mihoro.openInstallationGuide()
    else if (target === "setup") {
      if (!mihoro.probe.mihoroInstalled) root.openInstallPage()
      else {
        root.openSubscriptionPage()
        subscription.beginEdit()
      }
    }
  }

  function requestMode(value) {
    var action = Model.modeSelectionAction(value, mihoro.mode)
    if (action === "choose_proxy") {
      modeSection.selectingGlobal = true
      mihoro.refreshProxies()
    } else {
      modeSection.selectingGlobal = false
      mihoro.cancelGlobalSelection()
      if (action === "switch") mihoro.setMode(value)
    }
  }

  function openSubscriptionPage() {
    panelPage = 2
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function leaveSubscriptionPage() {
    subscription.cancelEdit()
    panelPage = 1
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openInstallPage() {
    panelPage = 3
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function leaveInstallPage() {
    panelPage = 1
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function cycleMode(delta) {
    if (!mihoro.canSwitchMode) return
    var current = modeSection.selectingGlobal ? Model.modeIndex("global") : Model.modeIndex(mihoro.mode)
    var next = (current + delta + Model.MODES.length) % Model.MODES.length
    root.requestMode(Model.MODES[next].value)
  }

  Service {
    id: mihoro
    settings: root.settings
    panelOpen: root.opened
  }

  onOpenedChanged: if (opened) {
    subscription.cancelEdit()
    panelPage = 1
    cursorActive = false
    cursorIndex = 0
    modeCursor = Model.modeIndex(mihoro.mode)
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  onTargetsChanged: clampCursor()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { mihoro.refresh(); return "ok" }
    function start(): string { mihoro.startService(); return "ok" }
    function stop(): string { mihoro.stopService(); return "ok" }
    function restart(): string { mihoro.restartService(); return "ok" }
    function update(): string { mihoro.updateSubscription(); return "ok" }
    function mode(value: string): string {
      if (!Model.MODES.some(function(entry) { return entry.value === String(value).toLowerCase() }))
        return "expected one of rule, global, direct"
      mihoro.setMode(String(value).toLowerCase())
      return "ok"
    }
    function status(): string {
      return JSON.stringify({
        state: mihoro.connection.key,
        mode: mihoro.mode,
        service: mihoro.probe.activeState,
        api: mihoro.apiState,
        core: mihoro.mihomoVersion,
        connections: mihoro.connectionCount,
        subscription: mihoro.config.remoteConfigUrl !== "",
        updatedAt: mihoro.probe.configMtime
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.barTooltip

    // Read from inside `iconComponent`. Both BarIconButton and PanelHero name
    // their own root object `root`, so nothing inside a Component declared here
    // refers to `root` — it would be ambiguous about which one it meant.
    readonly property color glyphColor: mihoro.active
      ? root.barForeground
      : Qt.darker(root.barForeground, 1.55)

    iconComponent: Component {
      Item {
        MihoroIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: button.glyphColor
          badgeColor: Color.urgent
          crossed: !mihoro.active
          warning: mihoro.connection.tone === "urgent"
          ringed: mihoro.active && mihoro.mode === "global"
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) mihoro.toggleService()
      else if (buttonCode === Qt.MiddleButton) mihoro.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the URL editor is open every key belongs to it, including the
      // panel's single-letter shortcuts — a URL contains `r` and `u`.
      blocked: subscription.editing

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.panelPage === 2) root.leaveSubscriptionPage()
        else if (root.panelPage === 3) root.leaveInstallPage()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text || "").toLowerCase()
        if (root.panelPage === 2 && key === "u") mihoro.updateSubscription()
        else if (root.panelPage === 2 && key === "e") subscription.beginEdit()
        else if (root.panelPage === 1 && key === "t") mihoro.toggleService()
        else if (root.panelPage === 1 && key === "r") mihoro.refresh()
        else if (root.panelPage === 1 && key === "s") root.openSubscriptionPage()
        else if (root.panelPage === 1 && key === "i") root.openInstallPage()
        else if (root.panelPage === 1 && key === "m") root.cycleMode(1)
        else if (root.panelPage === 1 && key === "1") root.requestMode("rule")
        else if (root.panelPage === 1 && key === "2") root.requestMode("global")
        else if (root.panelPage === 1 && key === "3") root.requestMode("direct")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            visible: root.panelPage === 1
            width: parent.width
            implicitHeight: Math.max(hero.implicitHeight, headerControls.implicitHeight)

            PanelHero {
              id: hero
              anchors.left: parent.left
              anchors.right: headerControls.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              title: "Mihoro"
              meta: mihoro.connection.key === "running"
                ? Model.modeLabel(mihoro.mode) + " mode"
                : mihoro.connection.label
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: mihoro.active ? 1.0 : 0.5
              iconComponent: Component {
                MihoroIcon {
                  iconSize: Style.font.display
                  color: hero.foreground
                  badgeColor: Color.urgent
                  crossed: !mihoro.active
                  warning: mihoro.connection.tone === "urgent"
                  ringed: mihoro.active && mihoro.mode === "global"
                }
              }
            }

            Row {
              id: headerControls
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              ToggleSwitch {
                id: powerSwitch
                anchors.verticalCenter: parent.verticalCenter
                visible: mihoro.initialized
                checked: mihoro.active
                busy: mihoro.actionRunning
                cursorRing: false
                foreground: root.foreground
                onHovered: function(on) {
                  if (!on) return
                  root.cursorActive = true
                  root.cursorIndex = root.targets.indexOf("power")
                }
                onToggled: mihoro.toggleService()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: "Current status: " + mihoro.connection.label
                  fontFamily: root.fontFamily
                }
              }

              PanelMenu {
                anchors.verticalCenter: parent.verticalCenter
                textColor: root.foreground
                panelFontFamily: root.fontFamily
                dashboardUrl: root.dashboardUrl
                canOpenSubscription: mihoro.probe.mihoroInstalled
                canRestart: mihoro.initialized && mihoro.probe.unitLoaded
                canCopyProxy: mihoro.probe.mihoroInstalled && !mihoro.copyingProxyExport
                onRestartRequested: mihoro.restartService()
                onCopyProxyRequested: mihoro.copyProxyExport()
                onInstallRequested: root.openInstallPage()
                onSubscriptionRequested: root.openSubscriptionPage()
              }
            }
          }

          // One line for whatever the panel most needs to say: what it is
          // doing, what went wrong, or why the proxy is not connected.
          Item {
            visible: root.panelPage === 1 && text !== ""
            width: parent.width
            implicitHeight: Math.max(noticeText.implicitHeight, noticeClose.visible ? noticeClose.implicitHeight : 0)
            property alias text: noticeText.text

            Text {
              id: noticeText
              anchors.left: parent.left
              anchors.right: noticeClose.visible ? noticeClose.left : parent.right
              anchors.rightMargin: noticeClose.visible ? Style.space(6) : 0
              text: mihoro.actionStatus !== "" ? mihoro.actionStatus
                : (mihoro.lastError !== "" ? mihoro.lastError : mihoro.connection.detail)
              color: mihoro.lastError !== "" && mihoro.actionStatus === "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              id: noticeClose
              visible: mihoro.lastError !== "" && mihoro.actionStatus === ""
              anchors.right: parent.right
              anchors.top: parent.top
              text: "×"
              foreground: root.urgent
              bordered: false
              fontSize: Style.font.body
              onClicked: mihoro.clearNotice()
            }
          }

          SetupCard {
            visible: root.panelPage === 1 && (!mihoro.probe.mihoroInstalled || !mihoro.initialized)
            width: parent.width
            textColor: root.foreground
            panelFontFamily: root.fontFamily
            stateKey: mihoro.probe.mihoroInstalled ? "not_initialized" : "cli_missing"
            busy: mihoro.busy
            hasCursor: root.cursorTarget === "setup"
            onInstallRequested: root.openInstallPage()
            onAddUrlRequested: {
              root.openSubscriptionPage()
              subscription.beginEdit()
            }
          }

          PanelSeparator {
            visible: root.panelPage === 1 && mihoro.initialized
            foreground: root.foreground
          }

          ModeSection {
            id: modeSection
            visible: root.panelPage === 1 && mihoro.initialized
            width: parent.width
            textColor: root.foreground
            panelFontFamily: root.fontFamily
            mode: mihoro.mode
            switchable: mihoro.canSwitchMode
            pending: mihoro.pendingMode !== ""
            hint: mihoro.modeHint
            cursorIndex: root.cursorTarget === "mode" ? root.modeCursor : -1
            proxyOptions: mihoro.globalProxyOptions
            currentProxy: mihoro.pendingGlobalProxy !== "" ? mihoro.pendingGlobalProxy : mihoro.currentGlobalProxy
            onModeRequested: function(value) { root.requestMode(value) }
            onGlobalRequested: mihoro.refreshProxies()
            onProxyRequested: function(value) { mihoro.selectGlobalProxy(value) }
            onSubscriptionRequested: root.openSubscriptionPage()
            onChipHovered: function(index, isHovered) {
              if (!isHovered) {
                if (root.cursorTarget === "mode") root.cursorActive = false
                return
              }
              if (!mihoro.canSwitchMode) return
              root.cursorActive = true
              root.cursorIndex = root.targets.indexOf("mode")
              root.modeCursor = index
            }
          }

          PanelSeparator {
            visible: root.panelPage === 1 && mihoro.initialized
            foreground: root.foreground
          }

          ConnectionSection {
            visible: root.panelPage === 1 && mihoro.initialized
            width: parent.width
            service: mihoro
            textColor: root.foreground
            panelFontFamily: root.fontFamily
          }

          SubscriptionSection {
            id: subscription
            visible: root.panelPage === 2 && mihoro.probe.mihoroInstalled
            width: parent.width
            service: mihoro
            textColor: root.foreground
            panelFontFamily: root.fontFamily
            cursorTarget: root.cursorTarget
            onBackRequested: root.leaveSubscriptionPage()
            onUrlCommitted: function(url) { mihoro.setSubscriptionUrl(url) }
            onUpdateRequested: mihoro.updateSubscription()
            onEditingChanged: if (!editing) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }

          InstallSection {
            visible: root.panelPage === 3
            width: parent.width
            service: mihoro
            textColor: root.foreground
            successColor: systemTheme.green
            panelFontFamily: root.fontFamily
            hasCursor: root.cursorTarget === "install"
            onBackRequested: root.leaveInstallPage()
            onGuideRequested: mihoro.openInstallationGuide()
          }
        }
      }
    }
  }
}
