#!/usr/bin/env bash
set -euo pipefail

# Quickshell's Process, Panel, and the qs.Ui kit only exist inside a running
# Omarchy shell, so the QML behaviour that matters is pinned here at the source
# level. Each check stands for a decision that is easy to undo by accident.

# ---- mode switching -------------------------------------------------------

# The API changes the running core in place; the file is what survives a
# restart. A switch must do both, in that order, or the two disagree.
grep -Fq 'writeConfig({ mode: wanted }' Service.qml
grep -Fq 'ClashApi.setModeCommand' Service.qml
grep -Fq 'Model.applyCommand()' Service.qml
# A rejected PATCH falls back to a restart rather than leaving the click on the
# floor.
grep -Fq 'root.runAction("apply"' Service.qml

# With nothing running there is nothing to switch. (`switchable`, not
# `enabled`: the latter is Item's own property.)
grep -Fq 'switchable: mihoro.canSwitchMode' Panel.qml
grep -Fq 'if (wanted === "" || !canSwitchMode || modeProcess.running) return' Service.qml

# All three modes, and no more.
grep -Fq '{ value: "rule"' Model.js
grep -Fq '{ value: "global"' Model.js
grep -Fq '{ value: "direct"' Model.js
[[ "$(grep -c 'value: "' Model.js)" -eq 3 ]]

# ---- connection status ----------------------------------------------------

# Live speeds come from the streaming endpoint, not a poll loop, and the stream
# is torn down with the panel.
grep -Fq 'ClashApi.trafficCommand' Service.qml
grep -Fq 'var wanted = panelOpen && apiBase !== "" && serviceActive && apiState === "ok"' Service.qml
grep -Fq 'SplitParser' Service.qml
# The connections poll is panel-scoped too — nothing polls a closed panel.
grep -Fq 'running: root.panelOpen' Service.qml

# One source of truth for what the panel is looking at. It is `connection`, not
# `state`: QQuickItem owns that name, so `mihoro.state` silently resolves to the
# item's own state string and every field off it reads as undefined.
grep -Fq 'Model.connectionState(probe, apiState)' Service.qml
grep -Fq 'mihoro.connection.label' Panel.qml
! grep -rFq 'mihoro.state' Panel.qml
! grep -rEq '\broot\.state\b' Service.qml

# Live traffic is presented as two centered, equally sized metrics with stable
# semantic colours: green for download and red for upload.
grep -Fq 'label: "DOWNLOAD"' components/ConnectionSection.qml
grep -Fq 'label: "UPLOAD"' components/ConnectionSection.qml
grep -Fq 'metricColor: Color.accent' components/ConnectionSection.qml
grep -Fq 'metricColor: Color.urgent' components/ConnectionSection.qml
grep -Fq 'horizontalAlignment: Text.AlignHCenter' components/ConnectionSection.qml
grep -Fq 'component Speed: Item {' components/ConnectionSection.qml
grep -Fq 'color: root.textColor' components/ConnectionSection.qml
! grep -Fq 'color: Qt.rgba(metricColor.r' components/ConnectionSection.qml
! grep -Eq '#[0-9a-fA-F]{6}' components/ConnectionSection.qml
grep -Fq 'label: "TUN"' components/ConnectionSection.qml
grep -Fq 'root.service.liveConfigs.tunEnabled' components/ConnectionSection.qml

# ---- subscriptions --------------------------------------------------------

# URL subscriptions only: one remote config URL, fetched by the CLI.
grep -Fq 'Model.updateConfigCommand()' Service.qml
grep -Fq 'remote_config_url' MihoroConfig.js
# Saving a URL fetches it; a saved-but-unfetched URL would describe a
# subscription the proxy is not using.
grep -Fq 'writeConfig({ remoteConfigUrl: text }' Service.qml

# The credential is absent from read-only mode; it only enters a control after
# the user explicitly chooses Edit/Add.
! grep -Fq 'property bool revealed:' components/SubscriptionSection.qml
! grep -Fq 'Model.displayUrl(' components/SubscriptionSection.qml

# The write is atomic and keeps the file's permissions — it holds a credential.
grep -Fq 'mktemp' MihoroConfig.js
grep -Fq 'chmod --reference' MihoroConfig.js

# stdin is opened per write and closed in onStarted to give `cat` its EOF. A
# declarative `stdinEnabled: true` would be replaced by that close, and the
# second write of the session would find stdin shut.
grep -Fq 'configWriteProcess.stdinEnabled = true' Service.qml
grep -Fq 'stdinEnabled: false' Service.qml

# ---- panel wiring ---------------------------------------------------------

grep -Fq 'ModeSection {' Panel.qml
grep -Fq 'ConnectionSection {' Panel.qml
grep -Fq 'SubscriptionSection {' Panel.qml
grep -Fq 'SetupCard {' Panel.qml
grep -Fq 'blocked: subscription.editing' Panel.qml
grep -Fq 'iconSize: Style.space(12)' Panel.qml
grep -Fq 'onCopyProxyRequested: mihoro.copyProxyExport()' Panel.qml
grep -Fq 'text: "Copy proxy export"' components/PanelMenu.qml
grep -Fq 'https://github.com/huacnlee/omarchy-mihoro' components/PanelMenu.qml
grep -Fq 'text: "Mihoro docs"' components/PanelMenu.qml
! grep -Fq 'text: "Install Guides"' components/PanelMenu.qml
! grep -Fq 'text: "Open install guide"' components/PanelMenu.qml
grep -Fq 'Model.INSTALL_DOCS_URL' components/PanelMenu.qml
grep -Fq 'text: "Mihoro"' components/PanelMenu.qml
! grep -Fq 'text: "mihoro"' components/PanelMenu.qml
! grep -Fq 'text: "Mihoro Docs"' components/PanelMenu.qml
! grep -Fq 'https://wiki.metacubex.one' components/PanelMenu.qml
grep -Fq 'text: "Subscription..."' components/PanelMenu.qml
[[ "$(grep -n 'text: "Install Mihoro..."' components/PanelMenu.qml | cut -d: -f1)" -lt \
   "$(grep -n 'text: "Subscription..."' components/PanelMenu.qml | cut -d: -f1)" ]]
grep -Fq 'onSubscriptionRequested: root.openSubscriptionPage()' Panel.qml
grep -Fq 'text: "Install Mihoro..."' components/PanelMenu.qml
grep -Fq 'onInstallRequested: root.openInstallPage()' Panel.qml
sed -n '/id: menuButton/,/onClicked:/p' components/PanelMenu.qml | grep -Fq 'bordered: false'
[[ "$(grep -c 'PanelSeparator {' components/PanelMenu.qml)" -eq 3 ]]
grep -Fq 'implicitWidth: Style.space(24)' components/PanelMenu.qml
grep -Fq 'implicitHeight: Style.space(24)' components/PanelMenu.qml
grep -Fq 'Model.proxyExportCommand()' Service.qml
grep -Fq 'clipboardProcess.write(root._pendingClipboard)' Service.qml

# Missing Mihoro is installed through an Omarchy-launched terminal, rather
# than silently executing the network installer inside the shell process.
grep -Fq 'text: "Install Mihoro..."' components/SetupCard.qml
grep -Fq 'text: "Add subscription URL..."' components/SetupCard.qml
grep -Fq 'onInstallRequested: root.openInstallPage()' Panel.qml
grep -Fq 'Model.installCommand(installScriptPath)' Service.qml
grep -Fq 'scripts/install-mihoro' Service.qml
grep -Fq -- '--from-ui' scripts/install-mihoro
grep -Fq 'property string lastWarning' Service.qml
grep -Fq 'Model.installExitNotice' Service.qml
grep -Fq 'onClicked: mihoro.clearNotice()' Panel.qml
grep -Fq 'systemTheme.yellow' Panel.qml
grep -Fq 'command: ["wl-copy"]' Service.qml

# The popup is two internal pages, and every fresh open returns to the main
# controls. Subscription navigation is explicit rather than a collapsible
# section or an accidental click on the credential display.
grep -Fq 'property int panelPage: 1' Panel.qml
grep -Fq 'panelPage = 1' Panel.qml
grep -Fq 'subscription.cancelEdit()' Panel.qml
grep -Fq 'visible: root.panelPage === 1' Panel.qml
grep -Fq 'visible: root.panelPage === 2' Panel.qml
grep -Fq 'visible: root.panelPage === 3' Panel.qml
grep -Fq 'text: "MIHORO INSTALLATION"' components/InstallSection.qml
grep -Fq 'text: root.service.probe.mihoroInstalled ? "Mihoro installed" : "Not installed"' components/InstallSection.qml
grep -Fq 'successColor: systemTheme.green' Panel.qml
grep -Fq 'root.service.probe.mihoroInstalled ? root.successColor' components/InstallSection.qml
grep -Fq 'root.service.probe.mihoroInstalled ? Qt.rgba(root.successColor.r' components/InstallSection.qml
grep -Fq 'text: root.service.probe.mihoroVersion' components/InstallSection.qml
grep -Fq 'text: "Install Now"' components/InstallSection.qml
grep -Fq 'iconText: "+"' components/InstallSection.qml
! grep -Fq 'text: "Install Mihoro..."' components/InstallSection.qml
grep -Fq 'onInstallRequested: mihoro.installMihoro()' Panel.qml
grep -Fq 'onSubscriptionRequested: root.openSubscriptionPage()' Panel.qml
grep -Fq 'SettingsIcon {' components/ModeSection.qml
grep -Fq 'tooltipText: "Manage subscription..."' components/ModeSection.qml
grep -Fq 'id: gear' components/SettingsIcon.qml
grep -Fq 'for (var i = 0; i < 8; ++i)' components/SettingsIcon.qml
! grep -Fq 'id: sliders' components/SettingsIcon.qml
! grep -Fq 'id: subscriptionGlyph' components/SettingsIcon.qml
! grep -Fq 'id: wrenchGlyph' components/SettingsIcon.qml
grep -Fq 'PanelActionButton {' components/ModeSection.qml
grep -Fq 'id: modeControlRow' components/ModeSection.qml
grep -Fq 'width: modeControlRow.width - subscriptionButton.width - modeControlRow.spacing' components/ModeSection.qml
grep -Fq 'delegate: Button {' components/ModeSection.qml
grep -Fq 'selected: String(modelData.value) === root.mode' components/ModeSection.qml
grep -Fq 'bordered: true' components/ModeSection.qml
! grep -Fq 'text: "⚙"' components/ModeSection.qml
grep -Fq 'onBackRequested: root.leaveSubscriptionPage()' Panel.qml
grep -Fq 'if (root.panelPage === 2) root.leaveSubscriptionPage()' Panel.qml

# Page two owns subscription editing. Read-only mode never renders the URL;
# only the named Edit/Add action opens the field.
grep -Fq 'text: "SUBSCRIPTION"' components/SubscriptionSection.qml
grep -Fq 'text: root.url === "" ? "Add..." : "Edit..."' components/SubscriptionSection.qml
grep -Fq 'text: root.updating ? "Updating…" : "Update"' components/SubscriptionSection.qml
grep -Fq 'text: root.service.probe.configPresent ? "Update" : "Save and set up"' components/SubscriptionSection.qml
grep -Fq 'QQC.TextArea {' components/SubscriptionSection.qml
grep -Fq 'wrapMode: TextEdit.WrapAnywhere' components/SubscriptionSection.qml
! grep -Fq 'QQC.TextField {' components/SubscriptionSection.qml
! grep -Fq 'text: "Show"' components/SubscriptionSection.qml
! grep -Fq 'text: "Hide"' components/SubscriptionSection.qml
grep -Fq 'text: "Last updated " + Model.formatAgo' components/SubscriptionSection.qml
grep -Fq 'visible: !root.editing && root.service.probe.configPresent' components/SubscriptionSection.qml
grep -Fq 'id: subscriptionStatus' components/SubscriptionSection.qml
grep -Fq 'id: subscriptionActions' components/SubscriptionSection.qml
grep -Fq 'width: (subscriptionActions.width - subscriptionActions.spacing) / 2' components/SubscriptionSection.qml
grep -Fq 'text: "SUBSCRIPTION URL"' components/SubscriptionSection.qml
grep -Fq 'id: editorActions' components/SubscriptionSection.qml
! sed -n '/\/\/ ---- editor/,$p' components/SubscriptionSection.qml | grep -Fq 'TextField {'

# Keyboard: toggle, refresh, update, edit, and the three modes by number.
grep -Fq 'key === "t"' Panel.qml
grep -Fq 'key === "r"' Panel.qml
grep -Fq 'key === "u"' Panel.qml
grep -Fq 'key === "e"' Panel.qml
grep -Fq 'root.requestMode("global")' Panel.qml
grep -Fq 'ToggleSwitch {' Panel.qml
grep -Fq 'cursorRing: false' Panel.qml
! grep -Fq 'hasCursor: root.cursorTarget === "power"' Panel.qml
grep -Fq 'text: "Current status: " + mihoro.connection.label' Panel.qml
! grep -Fq 'text: mihoro.active ? "Stop mihomo" : "Start mihomo"' Panel.qml
! grep -Fq 'onColor: systemTheme.blue' Panel.qml
! grep -Fq 'knobOnColor:' Panel.qml
[[ ! -e components/ServiceSwitch.qml ]]

# IPC is how the rest of Omarchy drives the panel.
grep -Fq 'function mode(value: string): string' Panel.qml
grep -Fq 'function status(): string' Panel.qml

# ---- QML scoping ----------------------------------------------------------
#
# Both BarIconButton and PanelHero name their own root object `root`, so a
# `root.` inside a Component declared in Panel.qml is ambiguous about which one
# it means. Everything inside a Component reaches panel state through an id
# that exists only here.
python3 - <<'PY'
import re
import sys

source = open("Panel.qml").read()
problems = []
for match in re.finditer(r"Component\s*\{", source):
    start = match.end() - 1
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                body = source[start:index + 1]
                if re.search(r"\broot\.", body):
                    problems.append(body.strip()[:80])
                break

if problems:
    print("Component blocks reference an ambiguous `root.`:", file=sys.stderr)
    for problem in problems:
        print("  " + problem, file=sys.stderr)
    sys.exit(1)
print("component scoping ok")
PY

# ---- privacy --------------------------------------------------------------

# The subscription URL and the API secret are credentials. Neither is written
# anywhere but back into mihoro.toml.
! grep -rEq 'console\.(log|warn|error).*(secret|remoteConfigUrl|remote_config_url)' \
  Panel.qml Service.qml components/*.qml Model.js ClashApi.js MihoroConfig.js
# Clipboard data is written over stdin, never embedded in a command argument.
! grep -rEq 'execDetached\(.*wl-copy|bash.*wl-copy' Panel.qml Service.qml components/*.qml

echo "panel source tests passed"
