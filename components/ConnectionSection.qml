import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The full picture of what the proxy is doing right now: live throughput from
// mihomo's `/traffic` stream, then the facts that only change on an event —
// what systemd thinks, which core is serving, where its API is, which ports
// are open.
//
// Live speeds sit on top as the two large numbers because they are the one
// thing worth glancing at; everything below is reference.
Column {
  id: root

  required property var service
  required property color textColor
  required property string panelFontFamily

  readonly property bool live: service.apiState === "ok" && service.serviceActive
  property bool editingProxy: false
  property string draftProxy: ""
  property bool applyingProxy: false

  function beginProxyEdit() {
    draftProxy = service.currentModeProxy
    editingProxy = true
  }

  function cancelProxyEdit() {
    editingProxy = false
    applyingProxy = false
    draftProxy = ""
  }

  Connections {
    target: root.service
    function onProxySelectionFinished(ok) {
      root.applyingProxy = false
      if (ok) root.cancelProxyEdit()
    }
  }

  spacing: Style.space(10)

  PanelSectionHeader {
    text: "CONNECTION"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
  }

  // Both directions in one chart across the full width, with the two readouts
  // laid over it. Two half-width charts split the same minute of history into
  // two narrow windows and made the section read as two unrelated widgets;
  // sharing one box puts the curves on a common time axis, where the shape of
  // a transfer — upload spike, download answering it — is actually visible.
  Item {
    id: trafficPanel
    width: parent.width
    implicitHeight: trafficRow.implicitHeight + Style.space(12)
    height: implicitHeight
    opacity: root.live ? 1.0 : 0.45

    // One scale for both curves. Overlaid in one box they are compared by
    // height whether or not that was intended, so scaling each to its own
    // window would draw a 200 B/s trickle as tall as a 5 MiB/s download.
    // Upload therefore reads as a low line most of the time, which is the
    // truth about most sessions.
    readonly property real seriesPeak: Math.max(Model.peakOf(root.service.downHistory),
                                                Model.peakOf(root.service.upHistory))

    // Download first, upload over it: upload is the smaller series almost
    // always, and the one that would otherwise be buried under the other's
    // fill.
    Sparkline {
      anchors.fill: parent
      history: root.service.downHistory
      scalePeak: trafficPanel.seriesPeak
      curveColor: Color.accent
    }

    Sparkline {
      anchors.fill: parent
      history: root.service.upHistory
      scalePeak: trafficPanel.seriesPeak
      curveColor: Color.urgent
    }

    Row {
      id: trafficRow
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      Speed {
        width: (trafficRow.width - trafficRow.spacing) / 2
        glyph: "↓"
        label: "DOWNLOAD"
        metricColor: Color.accent
        value: Model.formatSpeed(root.service.downSpeed)
      }

      Speed {
        width: (trafficRow.width - trafficRow.spacing) / 2
        glyph: "↑"
        label: "UPLOAD"
        metricColor: Color.urgent
        value: Model.formatSpeed(root.service.upSpeed)
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(6)

    Item {
      width: parent.width
      visible: !root.editingProxy
      implicitHeight: Math.max(proxyLabel.implicitHeight, proxyValue.implicitHeight, editProxy.implicitHeight)

      Text {
        id: proxyLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "Proxy"
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        id: editProxy
        anchors.left: proxyLabel.right
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        visible: root.live && root.service.currentProxyGroup !== ""
        size: Style.space(20)
        tooltipText: "Change proxy..."
        foreground: root.textColor
        hoverColor: root.textColor
        fontFamily: root.panelFontFamily
        onClicked: root.beginProxyEdit()

        ActionIcon {
          anchors.centerIn: parent
          name: "edit"
          iconSize: Style.font.caption
          color: editProxy._hot ? editProxy.hoverColor : editProxy.foreground
        }
      }

      Text {
        id: proxyValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.72)
        horizontalAlignment: Text.AlignRight
        text: root.service.currentModeProxy !== "" ? root.service.currentModeProxy : "—"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Column {
      width: parent.width
      visible: root.editingProxy
      spacing: Style.space(6)

      SearchableDropdown {
        id: proxyPicker
        width: parent.width
        label: "Proxy"
        value: root.draftProxy
        options: root.service.currentModeProxyOptions
        placeholderText: "Choose a node…"
        emptyText: "No nodes available"
        foreground: root.textColor
        accent: Color.accent
        fontFamily: root.panelFontFamily
        enabled: !root.applyingProxy
        onChanged: function(value) {
          root.draftProxy = value
          // The control writes its own `value` when a row is picked, which
          // destroys this binding: without putting it back, Cancel would clear
          // the draft while the picked node stayed in the trigger, and the next
          // edit would open on it rather than on the current proxy.
          proxyPicker.value = Qt.binding(function() { return root.draftProxy })
        }
      }

      Row {
        id: proxyActions
        width: parent.width
        spacing: Style.spacing.controlGap

        Button {
          width: (proxyActions.width - proxyActions.spacing) / 2
          text: "Apply"
          foreground: root.textColor
          bordered: true
          fontSize: Style.font.bodySmall
          enabled: !root.applyingProxy && root.draftProxy !== ""
            && root.draftProxy !== root.service.currentModeProxy
          onClicked: {
            if (root.service.selectModeProxy(root.draftProxy)) root.applyingProxy = true
          }
        }

        Button {
          width: (proxyActions.width - proxyActions.spacing) / 2
          text: "Cancel"
          foreground: root.textColor
          bordered: true
          fontSize: Style.font.bodySmall
          enabled: !root.applyingProxy
          onClicked: root.cancelProxyEdit()
        }
      }
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "Connections"
      value: root.live ? String(root.service.connectionCount) : "—"
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "Transferred"
      value: root.live
        ? "↓ " + Model.formatBytes(root.service.downloadTotal) + "   ↑ " + Model.formatBytes(root.service.uploadTotal)
        : "—"
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "Service"
      value: {
        var probe = root.service.probe
        if (!probe.unitLoaded) return "not installed"
        var autostart = probe.unitFileState === "enabled" ? "enabled" : "not enabled"
        return probe.activeState + " · " + autostart
      }
      valueColor: root.service.probe.activeState === "failed" ? Color.urgent : root.textColor
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "Uptime"
      value: root.service.serviceActive && root.service.probe.startedAt > 0
        ? Model.formatDuration(root.service.probe.now - root.service.probe.startedAt)
        : "—"
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "Core"
      value: root.service.mihomoVersion !== ""
        ? "mihomo " + root.service.mihomoVersion
        : (root.service.probe.mihomoInstalled ? "installed" : "not installed")
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "API"
      value: {
        if (root.service.apiBase === "") return "external-controller unset"
        if (root.service.apiState === "ok") return root.service.apiBase.replace(/^https?:\/\//, "")
        if (root.service.apiState === "unauthorized") return "secret rejected"
        if (!root.service.serviceActive) return "—"
        return "unreachable"
      }
      valueColor: root.service.apiState === "unauthorized" ? Color.urgent : root.textColor
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "Ports"
      value: Model.formatPorts(root.service.config, root.service.liveConfigs)
    }

    // TUN is a stat here and an action in the panel menu. A switch on this
    // row put a state change one stray click away inside a block that is
    // otherwise read-only, and the change is not even persistent: the PATCH
    // reaches the running core, mihoro.toml has no tun key, and a restart
    // restores whatever config.yaml says.
    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "TUN"
      value: root.service.tunState === null ? "—"
        : (root.service.pendingTun !== -1
          ? (root.service.tunState ? "Enabling…" : "Disabling…")
          : (root.service.tunState ? "On" : "Off"))
    }

    StatRow {
      width: parent.width
      textColor: root.textColor
      panelFontFamily: root.panelFontFamily
      label: "LAN access"
      value: {
        var liveConfig = root.service.liveConfigs
        var allowed = liveConfig ? liveConfig.allowLan : root.service.config.allowLan
        return allowed ? "allowed" : "local only"
      }
    }
  }

  component Speed: Item {
    id: speed
    required property string glyph
    required property string label
    required property string value
    required property color metricColor

    implicitHeight: metricContent.implicitHeight + Style.space(20)

    Column {
      id: metricContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: speed.glyph + "  " + speed.label
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        width: parent.width
        text: speed.value
        color: speed.metricColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
