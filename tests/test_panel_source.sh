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
# Both directions share one full-width chart, drawn from the very stream
# readings that set the numbers over it, so the two cannot disagree.
grep -Fq 'history: root.service.downHistory' components/ConnectionSection.qml
grep -Fq 'history: root.service.upHistory' components/ConnectionSection.qml
grep -Fq 'Model.pushHistory(root.upHistory' Service.qml
grep -Fq 'Model.pushHistory(root.downHistory' Service.qml
[[ "$(grep -c 'Sparkline {' components/ConnectionSection.qml)" -eq 2 ]]
grep -Fq 'width: parent.width' components/ConnectionSection.qml
# One scale for both, or the eye reads a trickle as tall as a torrent.
grep -Fq 'scalePeak: trafficPanel.seriesPeak' components/ConnectionSection.qml
grep -Fq 'Model.peakOf(root.service.downHistory)' components/ConnectionSection.qml
# The chart is background: both curves are declared before the readouts.
[[ "$(grep -n 'Sparkline {' components/ConnectionSection.qml | tail -1 | cut -d: -f1)" -lt \
   "$(grep -n 'id: trafficRow' components/ConnectionSection.qml | cut -d: -f1)" ]]
# The history outlives a closed panel, but the seconds nothing was sampled are
# charged to it, so reopening continues the curve without closing the gap.
grep -Fq 'Model.padHistory(root.upHistory' Service.qml
grep -Fq 'Model.padHistory(root.downHistory' Service.qml
grep -Fq 'root.trafficIdleSince = Date.now() / 1000' Service.qml
! grep -Fq 'root.upHistory = []' Service.qml
! grep -Fq 'root.downHistory = []' Service.qml
# Every point was measured, not interpolated: straight segments only.
! grep -Eq 'bezierCurveTo|quadraticCurveTo' components/Sparkline.qml
! grep -Eq '#[0-9a-fA-F]{6}' components/Sparkline.qml

grep -Fq 'label: "TUN"' components/ConnectionSection.qml
grep -Fq 'root.service.liveConfigs.tunEnabled' components/ConnectionSection.qml

# ---- subscriptions --------------------------------------------------------

# URL subscriptions only: one remote config URL, fetched by the CLI.
grep -Fq 'Model.updateConfigCommand()' Service.qml
grep -Fq 'remote_config_url' MihoroConfig.js
# Selecting one fetches it; a selection nothing has downloaded would describe a
# subscription the proxy is not using.
grep -Fq 'writeConfig({ remoteConfigUrl: url }' Service.qml
grep -Fq 'function applyActiveSubscription()' Service.qml
grep -Fq 'applyActiveSubscription()' Service.qml

# The list is the panel's, because mihoro has one subscription at a time and no
# CLI verb that names a second. Only the selected entry reaches mihoro.toml.
grep -Fq 'Subscriptions.activeUrl(subscriptions)' Service.qml
grep -Fq 'function selectSubscription(id)' Service.qml
grep -Fq 'function addSubscription(name, url)' Service.qml
grep -Fq 'function saveSubscription(id, name, url)' Service.qml
grep -Fq 'function removeSubscription(id)' Service.qml

# Two entries can hold one URL, and mihoro.toml stores a URL rather than an
# entry — so the second is refused where it is typed, and a selection whose URL
# already matches the file is never re-derived from it.
grep -Fq 'function duplicateError(url, exceptId)' Service.qml
grep -Fq 'Subscriptions.duplicateOf(subscriptions, url, exceptId)' Service.qml
grep -Fq 'if (selected && selected.url === text) return { store: store, changed: false }' Subscriptions.js

# A refused or failed subscription action has to say so on the page it happened
# on, or it reads as the panel ignoring the click.
grep -Fq 'visible: (root.panelPage === 1 || root.panelPage === 2) && text !== ""' Panel.qml

# mihoro.toml wins over the stored selection: a URL set by `mihoro init` or a
# hand edit is adopted into the list rather than overwritten by it.
grep -Fq 'function reconcileSubscriptions()' Service.qml
grep -Fq 'Subscriptions.adopt(subscriptions, config.remoteConfigUrl)' Service.qml
grep -Fq 'root.reconcileSubscriptions()' Service.qml
# ...but not while a switch is in flight, when the file still holds the old URL.
grep -Fq 'if (configWriteProcess.running || _afterWrite !== "") return' Service.qml

# The refresh poll must not grey the list out every interval, so switching is
# gated on the writes it actually races.
grep -Fq 'readonly property bool applying: configWriteProcess.running || actionProcess.running' Service.qml
grep -Fq 'if (applying) return false' Service.qml

# The credential is absent from read-only mode; it only enters a control after
# the user explicitly chooses Edit/Add. Rows carry the name, never the URL.
! grep -Fq 'property bool revealed:' components/SubscriptionSection.qml
! grep -Fq 'Model.displayUrl(' components/SubscriptionSection.qml
! grep -Fq 'modelData.url' components/SubscriptionSection.qml
# The list is not in shell.json: that file is world-readable, people paste it
# when they ask for help with their bar, and its writer rebuilds plugin entries
# from the manifest schema.
! grep -Fq 'updateEntryInline' Service.qml Panel.qml
! grep -Fq '"key": "subscriptions"' manifest.json

# Both writes are atomic. mihoro.toml keeps its own permissions; the panel's own
# store is 0600 outright — it holds several bearer URLs.
grep -Fq 'mktemp' MihoroConfig.js
grep -Fq 'chmod --reference' MihoroConfig.js
grep -Fq 'mktemp' Subscriptions.js
grep -Fq 'chmod 600' Subscriptions.js
# The list lives in mihoro's own directory, hardcoded beside the config file
# mihoro itself hardcodes — the two have to agree on one place, and a path that
# can be configured is a path that can disagree.
grep -Fq '/.config/mihoro/subscriptions.json' Subscriptions.js
grep -Fq 'Subscriptions.storePath(home)' Service.qml
# The write makes the directory: nothing else creates ~/.config/mihoro/.
grep -Fq 'mkdir -p' Subscriptions.js

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
grep -Fq 'text: "Mihoro docs..."' components/PanelMenu.qml
! grep -Fq 'text: "Install Guides"' components/PanelMenu.qml
! grep -Fq 'text: "Open install guide"' components/PanelMenu.qml
grep -Fq 'Model.INSTALL_DOCS_URL' components/PanelMenu.qml
grep -Fq 'text: "Dashboard..."' components/PanelMenu.qml
grep -Fq 'text: "GitHub..."' components/PanelMenu.qml
grep -Fq 'text: "Mihoro..."; onActivated: root.openUrl(Model.PROJECT_URL)' components/PanelMenu.qml
grep -Fq 'text: "Mihoro docs..."' components/PanelMenu.qml
grep -Fq 'text: "Mihoro..."' components/PanelMenu.qml
! grep -Fq 'text: "mihoro"' components/PanelMenu.qml
! grep -Fq 'text: "Mihoro Docs"' components/PanelMenu.qml
! grep -Fq 'https://wiki.metacubex.one' components/PanelMenu.qml
grep -Fq 'text: "Subscriptions..."' components/PanelMenu.qml
[[ "$(grep -n 'text: "Install Mihoro..."' components/PanelMenu.qml | cut -d: -f1)" -lt \
   "$(grep -n 'text: "Subscriptions..."' components/PanelMenu.qml | cut -d: -f1)" ]]
grep -Fq 'onSubscriptionRequested: root.openSubscriptionPage()' Panel.qml
grep -Fq 'text: "Install Mihoro..."' components/PanelMenu.qml
grep -Fq 'onInstallRequested: root.openInstallPage()' Panel.qml
sed -n '/id: menuButton/,/onClicked:/p' components/PanelMenu.qml | grep -Fq 'bordered: false'
[[ "$(grep -c 'PanelSeparator {' components/PanelMenu.qml)" -eq 3 ]]
grep -Fq 'implicitWidth: Style.space(24)' components/PanelMenu.qml
grep -Fq 'implicitHeight: Style.space(24)' components/PanelMenu.qml
grep -Fq 'Model.proxyExportCommand()' Service.qml
grep -Fq 'clipboardProcess.write(root._pendingClipboard)' Service.qml

# Missing Mihoro is handled by opening its official installation guide; the
# plugin does not download or execute upstream installation code.
grep -Fq 'text: "Install Mihoro..."' components/SetupCard.qml
grep -Fq 'text: "Add subscription URL..."' components/SetupCard.qml
grep -Fq 'onInstallRequested: root.openInstallPage()' Panel.qml
grep -Fq 'function openInstallationGuide()' Service.qml
grep -Fq 'Model.installationGuideCommand()' Service.qml
! grep -Fq 'scripts/install-mihoro' Service.qml
[[ ! -e scripts/install-mihoro ]]
grep -Fq 'onClicked: mihoro.clearNotice()' Panel.qml
grep -Fq 'foreground: root.urgent' Panel.qml
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
grep -Fq 'text: "Open Installation Guide..."' components/InstallSection.qml
! grep -Fq 'text: "Install Mihoro..."' components/InstallSection.qml
grep -Fq 'onGuideRequested: mihoro.openInstallationGuide()' Panel.qml
grep -Fq 'onSubscriptionRequested: root.openSubscriptionPage()' Panel.qml
grep -Fq 'name: "settings"' components/ModeSection.qml
grep -Fq 'tooltipText: "Manage subscriptions..."' components/ModeSection.qml

# One icon set on one 16-unit grid at one stroke weight, which is the whole
# point of ActionIcon — a second drawn-icon component is a second grid, and two
# grids in one row is what this replaced. See DESIGN.md.
grep -Fq 'var s = width / 16' components/ActionIcon.qml
grep -Fq 'property real strokeScale: 1.4' components/ActionIcon.qml
grep -Fq 'ctx.lineWidth = Math.max(1, root.strokeScale * s)' components/ActionIcon.qml
grep -Fq 'for (var i = 0; i < 8; ++i)' components/ActionIcon.qml
! grep -Eq '#[0-9a-fA-F]{6}' components/ActionIcon.qml
[[ ! -e components/SettingsIcon.qml ]]
[[ ! -e components/TrashIcon.qml ]]
[[ ! -e components/PencilIcon.qml ]]
# MihoroIcon is the brand mark, not a member of the set: it has its own
# proportions and its own badge states.
[[ "$(ls components/*Icon.qml | wc -l)" -eq 2 ]]
grep -Fq 'PanelActionButton {' components/ModeSection.qml
grep -Fq 'id: modeControlRow' components/ModeSection.qml
grep -Fq 'width: modeControlRow.width - subscriptionButton.width - modeControlRow.spacing' components/ModeSection.qml
grep -Fq 'delegate: Button {' components/ModeSection.qml
grep -Fq 'selected: String(modelData.value) === root.mode' components/ModeSection.qml
grep -Fq 'bordered: true' components/ModeSection.qml
! grep -Fq 'text: "⚙"' components/ModeSection.qml
grep -Fq 'onBackRequested: root.leaveSubscriptionPage()' Panel.qml
grep -Fq 'if (root.panelPage === 2) root.leaveSubscriptionPage()' Panel.qml

# Page two owns the subscription list and its editor. Read-only mode never
# renders a URL; only the named Edit/Add action opens the field.
grep -Fq 'text: "SUBSCRIPTIONS"' components/SubscriptionSection.qml
grep -Fq 'text: "Add..."' components/SubscriptionSection.qml
grep -Fq 'tooltipText: "Edit subscription..."' components/SubscriptionSection.qml
grep -Fq 'text: root.updating ? "Updating…" : "Update"' components/SubscriptionSection.qml
grep -Fq 'text: root.service.probe.configPresent ? "Save" : "Save and set up"' components/SubscriptionSection.qml
grep -Fq 'QQC.TextArea {' components/SubscriptionSection.qml
grep -Fq 'wrapMode: TextEdit.WrapAnywhere' components/SubscriptionSection.qml
! grep -Fq 'QQC.TextField {' components/SubscriptionSection.qml
! grep -Fq 'text: "Show"' components/SubscriptionSection.qml
! grep -Fq 'text: "Hide"' components/SubscriptionSection.qml
grep -Fq '"Last updated " + Model.formatAgo' components/SubscriptionSection.qml
grep -Fq 'id: subscriptionList' components/SubscriptionSection.qml
grep -Fq 'id: subscriptionActions' components/SubscriptionSection.qml
grep -Fq 'width: (subscriptionActions.width - subscriptionActions.spacing) / 2' components/SubscriptionSection.qml
grep -Fq 'text: "SUBSCRIPTION URL"' components/SubscriptionSection.qml
grep -Fq 'id: editorActions' components/SubscriptionSection.qml
# The URL wraps, so it is a TextArea. The one single-line field is the name.
[[ "$(grep -c 'TextField {' components/SubscriptionSection.qml)" -eq 1 ]]
sed -n '/TextField {/,/^    }/p' components/SubscriptionSection.qml | grep -Fq 'id: nameField'
grep -Fq 'id: urlField' components/SubscriptionSection.qml

# The row is the switch and the selected one is marked; removing one is
# confirmed inline, because it switches whatever the proxy is using.
grep -Fq 'delegate: CursorSurface {' components/SubscriptionSection.qml
grep -Fq 'current: row.isActive' components/SubscriptionSection.qml
grep -Fq 'onClicked: if (!row.isActive) root.selectRequested(String(row.modelData.id))' components/SubscriptionSection.qml
grep -Fq 'property string confirmingId' components/SubscriptionSection.qml
grep -Fq 'text: "Remove"' components/SubscriptionSection.qml
grep -Fq 'text: "No subscriptions yet"' components/SubscriptionSection.qml

# Both row actions come from ActionIcon at one size, so the pair reads as a
# pair. No text glyph: × is a multiplication sign and covers about half the
# height it was set at, which is what made it look broken beside a drawn icon.
grep -Fq 'name: "edit"' components/SubscriptionSection.qml
grep -Fq 'name: "trash"' components/SubscriptionSection.qml
! grep -Fq 'iconText:' components/SubscriptionSection.qml
[[ "$(grep -c 'iconSize: Style.font.icon' components/SubscriptionSection.qml)" -eq 2 ]]
# Both keep PanelActionButton's own 22px footprint — the row actions are not
# where the eye should land.
! grep -Fq 'size: Style.space(2' components/SubscriptionSection.qml
grep -Fq 'onSelectRequested: function(id) { mihoro.selectSubscription(id) }' Panel.qml
grep -Fq 'onRemoveRequested: function(id) { mihoro.removeSubscription(id) }' Panel.qml
grep -Fq 'if (id === "") mihoro.addSubscription(name, url)' Panel.qml
grep -Fq 'subs.push("sub:" + items[i].id)' Panel.qml

# Keyboard: toggle, refresh, update, edit, add, subscriptions and modes by
# number.
grep -Fq 'key === "t"' Panel.qml
grep -Fq 'key === "r"' Panel.qml
grep -Fq 'key === "u"' Panel.qml
grep -Fq 'key === "e"' Panel.qml
grep -Fq 'key === "a"' Panel.qml
grep -Fq 'root.selectSubscriptionAt(Number(key) - 1)' Panel.qml
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
! grep -rEq 'console\.(log|warn|error).*(secret|remoteConfigUrl|remote_config_url|\.url)' \
  Panel.qml Service.qml components/*.qml Model.js ClashApi.js MihoroConfig.js Subscriptions.js
# Clipboard data is written over stdin, never embedded in a command argument.
! grep -rEq 'execDetached\(.*wl-copy|bash.*wl-copy' Panel.qml Service.qml components/*.qml

echo "panel source tests passed"
