import QtQuick
import Quickshell
import Quickshell.Io
import "MihoroConfig.js" as MihoroConfig
import "Subscriptions.js" as Subscriptions
import "Rules.js" as Rules
import "ClashApi.js" as ClashApi
import "Model.js" as Model

// Every process the panel runs lives here, so the views stay declarative and
// the ordering rules are in one file.
//
// The split of responsibilities follows mihoro's own: the CLI owns the things
// that touch the filesystem and systemd — setup, pulling the subscription,
// starting and stopping the service — and mihomo's control API, which mihoro
// configures and points its dashboard at, owns everything live: the running
// mode, the version actually serving, traffic, and open connections. Mode
// switching goes through the API because it takes effect on the running core
// without a restart; the same value is written back to `mihoro.toml` so the
// next `mihoro apply` or `mihoro update` does not quietly revert it.
Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  // ---- what the last refresh found
  property var probe: Model.emptyProbe()
  property var config: MihoroConfig.defaults()
  property string configRaw: ""
  property bool configLoaded: false

  // ---- the panel's own subscription list
  //
  // mihoro holds one subscription at a time, so the list is the panel's and
  // only the selected entry reaches mihoro.toml. See Subscriptions.js.
  property var subscriptions: Subscriptions.defaults()
  property bool subscriptionsLoaded: false
  property var ruleStore: Rules.defaults()
  property bool rulesLoaded: false

  // ---- what mihomo's API reports
  property string apiState: "unknown"       // ok | unauthorized | unreachable | disabled | unknown
  property string mihomoVersion: ""
  property var liveConfigs: null
  property int connectionCount: 0
  property real downloadTotal: 0
  property real uploadTotal: 0
  property real upSpeed: 0
  property real downSpeed: 0
  // The recent history of the two speeds above, appended from the same stream
  // readings that set them, and drawn behind them. It outlives the panel being
  // closed; the seconds the stream was down are filled in when it comes back,
  // so the curve continues rather than restarting. See `Model.padHistory`.
  property var upHistory: []
  property var downHistory: []
  property real trafficIdleSince: 0
  // The last `/traffic` reading a speed was published from. Not the previous
  // sample: see `ClashApi.trafficRate`.
  property var trafficAnchor: null
  property var globalProxyOptions: []
  property string currentGlobalProxy: ""
  property var ruleProxyOptions: []
  property string currentRuleProxy: ""
  property var routeOptions: [
    { value: "DIRECT", label: "DIRECT" },
    { value: "REJECT", label: "REJECT" }
  ]

  // ---- route test page
  property var routeTests: []
  property int routeTestIndex: -1
  readonly property bool routeTestRunning: routeTestIndex >= 0

  // ---- in-flight intent
  //
  // Both are optimistic overlays: the switch and the mode chips move the
  // instant they are clicked, and stop overriding once a refresh confirms the
  // real state. Waiting for systemd makes the panel feel broken.
  property int desiredActive: -1
  property string pendingMode: ""
  property string pendingGlobalProxy: ""
  property string pendingModeProxy: ""
  property string pendingProxyGroup: ""
  property bool globalSelectionRequested: false
  property string actionKind: ""
  property string actionStatus: ""
  property string lastError: ""

  // The one error worth handing to an agent is a staged mihoro command that
  // failed: its output runs to kilobytes and its cause is usually somewhere the
  // panel cannot look. A rejected URL is the user's to fix and a failed write is
  // a permissions problem, so neither sets this.
  //
  // The kind travels with the message, never outliving it — see reportError.
  property string lastErrorKind: ""
  property string lastFailureOutput: ""

  // Empty until the user picks one; Omarchy ships with no default agent, and
  // there is nothing to offer until there is something to open.
  property string defaultAgent: ""

  onLastErrorChanged: if (lastError === "") lastErrorKind = ""

  // Every error that is not a failed mihoro command reports through here, so it
  // takes the diagnosis offer down with it. Without this the button would
  // survive its own failure and point the agent at a log the user has already
  // moved past.
  function reportError(message) {
    lastErrorKind = ""
    lastError = message
  }

  readonly property int refreshIntervalSec: {
    var raw = settings ? settings.refreshIntervalSec : undefined
    var value = parseInt(String(raw === undefined || raw === null ? 30 : raw), 10)
    if (!isFinite(value)) value = 30
    return Math.max(5, Math.min(3600, value))
  }

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string mihoroConfigPath: MihoroConfig.configPath(home)
  readonly property string subscriptionsPath: Subscriptions.storePath(home)
  readonly property string rulesPath: Rules.storePath(home)
  readonly property string mihomoConfigPath: MihoroConfig.mihomoConfigPath(config.mihomoConfigRoot, home)
  readonly property string mihomoConfigRoot: MihoroConfig.expandHome(config.mihomoConfigRoot, home)
  readonly property string mihomoBinaryPath: MihoroConfig.mihomoBinaryPath(config.mihomoBinaryPath, home)
  readonly property string enhancerPath: localPath(Qt.resolvedUrl("scripts/config_enhancer.py"))
  readonly property string timerManagerPath: localPath(Qt.resolvedUrl("scripts/timer_manager.py"))
  readonly property string apiBase: ClashApi.baseUrl(config.externalController)

  // Not `state`: QQuickItem already owns that name for its own state machine.
  readonly property var connection: Model.connectionState(probe, apiState)
  readonly property bool serviceActive: probe.activeState === "active"
  readonly property bool active: desiredActive === -1 ? connection.active : (desiredActive === 1)
  readonly property bool initialized: probe.mihoroInstalled && probe.configPresent
  readonly property var subscriptionList: Subscriptions.list(subscriptions)
  readonly property string activeSubscriptionId: String(subscriptions.activeId || "")
  readonly property bool canSwitchMode: Model.canSwitchMode(probe, apiState)
  readonly property string modeHint: Model.modeHint(probe, apiState)

  // The API is the running truth; mihoro.toml is what survives a restart. They
  // agree except in the window between a switch and the next refresh.
  readonly property string mode: pendingMode !== "" ? pendingMode
    : (liveConfigs && liveConfigs.mode !== "" ? liveConfigs.mode : config.mode)
  readonly property string currentProxyGroup: mode === "rule" ? "PROXY"
    : (mode === "global" ? "GLOBAL" : "")
  readonly property var currentModeProxyOptions: mode === "rule" ? ruleProxyOptions
    : (mode === "global" ? globalProxyOptions : [])
  readonly property string currentModeProxy: mode === "direct" ? "DIRECT"
    : (pendingModeProxy !== "" && pendingProxyGroup === currentProxyGroup ? pendingModeProxy
      : (mode === "rule" ? currentRuleProxy : currentGlobalProxy))

  readonly property bool busy: probeProcess.running || configReadProcess.running
    || actionProcess.running || modeProcess.running || proxySelectProcess.running
    || configWriteProcess.running || guideProcess.running
    || subscriptionsReadProcess.running || subscriptionsWriteProcess.running
    || rulesReadProcess.running || rulesWriteProcess.running
    || configEnhancerProcess.running || timerManagerProcess.running
  readonly property bool actionRunning: actionProcess.running
  // Narrower than `busy`: only the writes and the CLI run that a subscription
  // change sets off. The refresh poll must not grey the list out every 30s.
  readonly property bool applying: configWriteProcess.running || actionProcess.running
    || subscriptionsWriteProcess.running
  readonly property bool copyingProxyExport: proxyExportProcess.running || clipboardProcess.running
  readonly property bool rulesApplying: configEnhancerProcess.running || rulesWriteProcess.running

  signal actionFinished(string kind, bool ok)
  signal proxySelectionFinished(bool ok)
  signal rulesApplyFinished(bool ok)

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  // ------------------------------------------------------------- refreshing

  function refresh() {
    if (configReadProcess.running) return
    configReadProcess.command = MihoroConfig.readCommand(mihoroConfigPath)
    configReadProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function refreshProbe() {
    if (probeProcess.running) return
    probeProcess.command = Model.probeCommand(mihomoConfigPath, mihomoBinaryPath)
    probeProcess.running = true
  }

  function refreshApi() {
    if (apiBase === "") {
      apiState = "disabled"
      liveConfigs = null
      mihomoVersion = ""
      return
    }
    if (!serviceActive) {
      apiState = "unreachable"
      return
    }
    if (!versionProcess.running) {
      versionProcess.command = ClashApi.versionCommand(apiBase, config.secret)
      versionProcess.running = true
    }
    if (!configsProcess.running) {
      configsProcess.command = ClashApi.configsCommand(apiBase, config.secret)
      configsProcess.running = true
    }
    refreshProxies()
  }

  function refreshProxies() {
    if (apiBase === "" || !serviceActive || proxiesProcess.running) return
    proxiesProcess.command = ClashApi.proxiesCommand(apiBase, config.secret)
    proxiesProcess.running = true
  }

  function refreshConnections() {
    if (!panelOpen || apiBase === "" || !serviceActive || connectionsProcess.running) return
    connectionsProcess.command = ClashApi.connectionsCommand(apiBase, config.secret)
    connectionsProcess.running = true
  }

  function routeTestEntries() {
    return Model.routeTestEntries()
  }

  function setRouteTestResult(index, result) {
    var next = routeTests.slice()
    next[index] = { label: next[index].label, host: next[index].host, result: result }
    routeTests = next
  }

  function testRoutes() {
    if (routeTestRunning) return
    routeTests = routeTestEntries()
    if (apiBase === "" || !serviceActive || apiState !== "ok") {
      for (var i = 0; i < routeTests.length; i++) setRouteTestResult(i, "Unavailable")
      return
    }
    routeTestIndex = 0
    startRouteTest()
  }

  function startRouteTest() {
    if (routeTestIndex < 0 || routeTestIndex >= routeTests.length) {
      routeTestIndex = -1
      return
    }
    setRouteTestResult(routeTestIndex, "Testing...")
    routeRequestProcess.command = ClashApi.routeTestCommand(routeTests[routeTestIndex].host)
    routeRequestProcess.running = true
    routeLookupDelay.restart()
  }

  function finishRouteTest(result) {
    if (!routeTestRunning) return
    setRouteTestResult(routeTestIndex, result)
    if (routeRequestProcess.running) routeRequestProcess.running = false
    routeTestIndex += 1
    if (routeTestIndex >= routeTests.length) routeTestIndex = -1
    else startRouteTest()
  }

  // ---------------------------------------------------------------- actions

  function setMode(next) {
    var wanted = ClashApi.normalizeMode(next)
    if (wanted === "" || !canSwitchMode || modeProcess.running) return
    if (wanted === mode) return

    pendingMode = wanted
    lastError = ""
    optimismTimer.restart()

    // Persisted first either way: if the PATCH lands, the file already agrees
    // with the core; if it does not, the file is what `mihoro apply` reads.
    // A write that could not start takes the optimistic chip back with it.
    if (!writeConfig({ mode: wanted }, apiBase === "" ? "apply" : "mode")) pendingMode = ""
  }

  function selectGlobalProxy(name) {
    var wanted = String(name || "")
    if (wanted === "" || !canSwitchMode || proxySelectProcess.running) return
    pendingGlobalProxy = wanted
    pendingProxyGroup = "GLOBAL"
    globalSelectionRequested = true
    lastError = ""
    proxySelectProcess.command = ClashApi.selectProxyCommand(apiBase, config.secret, "GLOBAL", wanted)
    proxySelectProcess.running = true
  }

  function selectModeProxy(name) {
    var wanted = String(name || "")
    if (wanted === "" || currentProxyGroup === "" || !canSwitchMode || proxySelectProcess.running) return false
    if (wanted === currentModeProxy) return false
    pendingModeProxy = wanted
    pendingProxyGroup = currentProxyGroup
    lastError = ""
    proxySelectProcess.command = ClashApi.selectProxyCommand(apiBase, config.secret, currentProxyGroup, wanted)
    proxySelectProcess.running = true
    return true
  }

  function cancelGlobalSelection() {
    globalSelectionRequested = false
    pendingGlobalProxy = ""
    if (pendingProxyGroup === "GLOBAL") pendingProxyGroup = ""
  }

  function toggleService() {
    if (!initialized) return
    if (active) stopService()
    else startService()
  }

  function startService() {
    desiredActive = 1
    optimismTimer.restart()
    runAction("start", Model.startCommand(), "Starting mihomo…")
  }

  function stopService() {
    desiredActive = 0
    optimismTimer.restart()
    runAction("stop", Model.stopCommand(), "Stopping mihomo…")
  }

  function restartService() {
    desiredActive = 1
    optimismTimer.restart()
    runAction("restart", Model.restartCommand(), "Restarting mihomo…")
  }

  function updateSubscription() {
    if (!initialized) return
    runConfigEnhancer("update", "Refreshing subscription…")
  }

  function copyProxyExport() {
    if (!probe.mihoroInstalled || copyingProxyExport) return
    _pendingClipboard = ""
    lastError = ""
    actionStatus = "Exporting proxy info…"
    proxyExportProcess.command = Model.proxyExportCommand()
    proxyExportProcess.running = true
  }

  function openInstallationGuide() {
    if (guideProcess.running) return
    lastError = ""
    actionStatus = "Opening Mihoro installation guide…"
    guideProcess.running = true
  }

  function clearNotice() {
    lastError = ""
  }

  // ---------------------------------------------------------- subscriptions
  //
  // The list is the panel's; mihoro.toml holds whichever entry is selected.
  // Every change here does both — the store keeps the entry, and the selected
  // URL goes on to mihoro.toml so `mihoro update --config` fetches it. A store
  // that named a subscription mihoro had never been told about would describe
  // one the proxy is not using.

  function loadSubscriptions() {
    if (subscriptionsReadProcess.running) return
    subscriptionsReadProcess.command = Subscriptions.readCommand(subscriptionsPath)
    subscriptionsReadProcess.running = true
  }

  function loadRules() {
    if (rulesReadProcess.running) return
    rulesReadProcess.command = Rules.readCommand(rulesPath)
    rulesReadProcess.running = true
  }

  function rulesFor(subscriptionId) { return Rules.list(ruleStore, subscriptionId) }

  function applyRules(subscriptionId, items) {
    if (rulesApplying || String(subscriptionId || "") === "") return false
    ruleStore = Rules.replace(ruleStore, subscriptionId, items).store
    _pendingRules = JSON.stringify(ruleStore, null, 2) + "\n"
    _afterRulesWrite = "apply"
    rulesWriteProcess.command = Rules.writeCommand(rulesPath)
    rulesWriteProcess.stdinEnabled = true
    rulesWriteProcess.running = true
    return true
  }

  // mihoro.toml wins: it is what the core is actually using. A URL that arrived
  // by `mihoro init` or a hand edit is taken into the list rather than being
  // overwritten by whatever the panel last had selected.
  function reconcileSubscriptions() {
    if (!subscriptionsLoaded || !configLoaded) return
    // Not while a switch is in flight: mihoro.toml still holds the old URL, and
    // adopting it would drag the selection back to where it just came from.
    if (configWriteProcess.running || _afterWrite !== "") return
    var result = Subscriptions.adopt(subscriptions, config.remoteConfigUrl)
    if (!result.changed) return
    subscriptions = result.store
    writeSubscriptions()
  }

  // Writes the selected subscription into mihoro.toml and pulls it. With
  // nothing selected the URL is cleared instead, so the panel reporting "not
  // set up" and an empty list say the same thing.
  function applyActiveSubscription() {
    var url = Subscriptions.activeUrl(subscriptions)
    if (url === "") {
      if (String(config.remoteConfigUrl || "") !== "") writeConfig({ remoteConfigUrl: "" }, "")
      return
    }
    writeConfig({ remoteConfigUrl: url }, probe.configPresent && probe.unitLoaded ? "update" : "init")
  }

  // Two entries holding the same URL are one subscription under two names, and
  // mihoro.toml — which stores a URL, not an entry — cannot tell them apart. The
  // second one is refused where it is typed rather than left to look like a
  // separate subscription that never becomes the selected one.
  function duplicateError(url, exceptId) {
    var clash = Subscriptions.duplicateOf(subscriptions, url, exceptId)
    return clash ? "That URL is already saved as \"" + clash.name + "\"." : ""
  }

  function selectSubscription(id) {
    if (applying) return false
    var entry = Subscriptions.find(subscriptions, id)
    if (!entry || entry.id === activeSubscriptionId) return false
    lastError = ""
    subscriptions = Subscriptions.select(subscriptions, entry.id).store
    writeSubscriptions()
    applyActiveSubscription()
    return true
  }

  // A new subscription is the one you meant to use, so it is selected and
  // fetched on the spot — the same single gesture the first URL always was.
  function addSubscription(name, url) {
    if (applying) return false
    var text = String(url || "").trim()
    var problem = Model.subscriptionUrlError(text)
    if (problem === "") problem = Subscriptions.nameError(name)
    if (problem === "") problem = duplicateError(text, "")
    if (problem !== "") {
      reportError(problem)
      return false
    }
    lastError = ""
    var result = Subscriptions.add(subscriptions, name, text)
    subscriptions = Subscriptions.select(result.store, result.id).store
    writeSubscriptions()
    applyActiveSubscription()
    return true
  }

  function saveSubscription(id, name, url) {
    if (applying) return false
    var entry = Subscriptions.find(subscriptions, id)
    if (!entry) return false
    var text = String(url || "").trim()
    var problem = Model.subscriptionUrlError(text)
    if (problem === "") problem = Subscriptions.nameError(name)
    if (problem === "") problem = duplicateError(text, entry.id)
    if (problem !== "") {
      reportError(problem)
      return false
    }
    lastError = ""
    var urlChanged = text !== entry.url
    subscriptions = Subscriptions.save(subscriptions, entry.id, name, text).store
    writeSubscriptions()
    // Renaming is not something mihoro has an opinion about; a new URL on the
    // selected entry is, and it has to be fetched before the panel claims it.
    if (urlChanged && entry.id === activeSubscriptionId) applyActiveSubscription()
    return true
  }

  function removeSubscription(id) {
    if (applying) return false
    var entry = Subscriptions.find(subscriptions, id)
    if (!entry) return false
    lastError = ""
    var wasActive = entry.id === activeSubscriptionId
    subscriptions = Subscriptions.remove(subscriptions, entry.id).store
    writeSubscriptions()
    // Removing the selected one falls through to whatever `remove` selected in
    // its place, and to clearing the URL when it was the last one — the list is
    // the set of subscriptions, so an empty list means none is configured.
    if (wasActive) applyActiveSubscription()
    return true
  }

  function writeSubscriptions() {
    if (subscriptionsWriteProcess.running) {
      // The store in hand is always the whole file, so a queued write does not
      // need to remember what it was for — it just re-serializes on the way out.
      _subscriptionsQueued = true
      return
    }
    _subscriptionsQueued = false
    _pendingSubscriptions = Subscriptions.serialize(subscriptions)
    subscriptionsWriteProcess.command = Subscriptions.writeCommand(subscriptionsPath)
    // Re-armed every write: `onStarted` closes stdin to give `cat` its EOF.
    subscriptionsWriteProcess.stdinEnabled = true
    subscriptionsWriteProcess.running = true
  }

  // Checked per open rather than once at startup, so choosing an agent takes
  // effect without restarting the shell. omarchy-crash-watch re-checks per crash
  // for the same reason.
  function refreshDefaultAgent() {
    if (defaultAgentProcess.running) return
    defaultAgentProcess.command = Model.defaultAgentCommand()
    defaultAgentProcess.running = true
  }

  // The output quotes back the URL it was given and whatever the server
  // answered with, so it goes to a 0600 file rather than into the prompt:
  // `--prompt` becomes argv, and the process list is world-readable.
  function diagnose() {
    if (!Model.canDiagnose(lastErrorKind, defaultAgent)) return
    if (failureLogWriteProcess.running || diagnoseProcess.running) return
    _pendingFailureLog = lastFailureOutput
    failureLogWriteProcess.command = Model.failureLogWriteCommand(Model.failureLogPath(home))
    failureLogWriteProcess.stdinEnabled = true
    failureLogWriteProcess.running = true
  }

  function runAction(kind, command, label) {
    if (actionProcess.running) return
    actionKind = kind
    actionStatus = label || ""
    lastError = ""
    _actionOutput = ""
    _actionError = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function enhancerCommand(kind) {
    return ["python3", enhancerPath, kind,
      "--config", mihomoConfigPath,
      "--rules", rulesPath,
      "--subscriptions", subscriptionsPath,
      "--mihoro-config", mihoroConfigPath,
      "--subscription-id", activeSubscriptionId,
      "--mihomo-bin", mihomoBinaryPath,
      "--config-dir", mihomoConfigRoot]
  }

  function runConfigEnhancer(kind, label) {
    if (configEnhancerProcess.running || activeSubscriptionId === "") return
    ruleActionKind = kind
    actionStatus = label
    lastError = ""
    configEnhancerProcess.command = enhancerCommand(kind)
    configEnhancerProcess.running = true
  }

  function installRuleTimer() {
    if (timerManagerProcess.running) return
    timerManagerProcess.command = ["python3", timerManagerPath, "install",
      "--mihoro-config", mihoroConfigPath,
      "--config-home", configHome,
      "--python", "python3",
      "--enhancer", enhancerPath,
      "--config", mihomoConfigPath,
      "--rules", rulesPath,
      "--subscriptions", subscriptionsPath,
      "--mihomo-bin", mihomoBinaryPath,
      "--config-dir", mihomoConfigRoot]
    timerManagerProcess.running = true
  }

  // ------------------------------------------------------ writing mihoro.toml

  property string _pendingText: ""
  property string _afterWrite: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _pendingClipboard: ""
  property string _pendingSubscriptions: ""
  property string _pendingRules: ""
  property string _afterRulesWrite: ""
  property string ruleActionKind: ""
  property string _pendingFailureLog: ""
  property bool _subscriptionsQueued: false

  function writeConfig(changes, thenAction) {
    if (configWriteProcess.running) return false
    _afterWrite = String(thenAction || "")
    var next = MihoroConfig.patch(configRaw, changes)
    _pendingText = next
    configWriteProcess.command = MihoroConfig.writeCommand(mihoroConfigPath)
    // Re-armed every time: closing stdin after the previous write replaced the
    // declared binding, so a second write would otherwise find it shut.
    configWriteProcess.stdinEnabled = true
    configWriteProcess.running = true
    // The panel shows the new value straight away; the write below is what
    // makes it true, and a failure rereads the file to undo this.
    configRaw = next
    config = MihoroConfig.parse(next)
    return true
  }

  function runAfterWrite() {
    var next = _afterWrite
    _afterWrite = ""
    if (next === "mode") {
      modeProcess.command = ClashApi.setModeCommand(apiBase, config.secret, pendingMode)
      modeProcess.running = true
    } else if (next === "apply") {
      runAction("apply", Model.applyCommand(), "Applying mode…")
    } else if (next === "update") {
      runConfigEnhancer("update", "Fetching subscription…")
    } else if (next === "init") {
      runAction("init", Model.initCommand(), "Setting up mihoro…")
    } else {
      // Nothing to run — the last subscription was removed and the URL cleared.
      // Re-probe anyway, or the panel goes on reporting the setup it just
      // deleted until the next poll comes round.
      settleTimer.restart()
    }
  }

  // --------------------------------------------------------- live traffic
  //
  // `/traffic` holds a socket open and pushes a sample a second, so speeds cost
  // one curl for as long as the panel is on screen rather than a poll loop. It
  // is torn down the moment the panel closes.

  function syncTraffic() {
    var wanted = panelOpen && apiBase !== "" && serviceActive && apiState === "ok"
    if (wanted === trafficProcess.running) return
    if (wanted) trafficProcess.running = true
    else {
      trafficProcess.running = false
      upSpeed = 0
      downSpeed = 0
      trafficAnchor = null
      trafficIdleSince = Date.now() / 1000
    }
  }

  onPanelOpenChanged: {
    if (panelOpen) {
      refresh()
      refreshConnections()
      refreshDefaultAgent()
    }
    syncTraffic()
  }
  onApiStateChanged: syncTraffic()
  onServiceActiveChanged: syncTraffic()
  onApiBaseChanged: {
    trafficProcess.running = false
    syncTraffic()
  }

  Component.onCompleted: {
    loadSubscriptions()
    loadRules()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: connectionsTimer
    interval: 5000
    repeat: true
    running: root.panelOpen
    onTriggered: root.refreshConnections()
  }

  // A refresh right after an action would race systemd, which reports the old
  // state for a moment after `start` returns.
  Timer {
    id: settleTimer
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: optimismTimer
    interval: 8000
    repeat: false
    onTriggered: {
      root.desiredActive = -1
      root.pendingMode = ""
    }
  }

  Timer {
    id: trafficRetry
    interval: 3000
    repeat: false
    onTriggered: root.syncTraffic()
  }

  Timer {
    id: routeLookupDelay
    interval: 350
    repeat: false
    onTriggered: {
      if (!root.routeTestRunning) return
      routeLookupProcess.command = ClashApi.connectionsCommand(root.apiBase, root.config.secret)
      routeLookupProcess.running = true
    }
  }

  // Every poll skips itself while its own process is still running, so one that
  // never exits would stop the panel refreshing for good. Reap anything still
  // alive well inside the shortest refresh interval.
  Timer {
    id: pollWatchdog
    interval: 12000
    repeat: false
    onTriggered: {
      if (probeProcess.running) probeProcess.running = false
      if (configReadProcess.running) configReadProcess.running = false
      if (versionProcess.running) versionProcess.running = false
      if (configsProcess.running) configsProcess.running = false
      if (connectionsProcess.running) connectionsProcess.running = false
      if (proxiesProcess.running) proxiesProcess.running = false
      if (subscriptionsReadProcess.running) subscriptionsReadProcess.running = false
    }
  }

  // ------------------------------------------------------------- processes

  Process {
    id: guideProcess
    running: false
    command: Model.installationGuideCommand()
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.actionStatus = "Mihoro installation guide opened."
        actionStatusTimer.restart()
      } else {
        root.actionStatus = ""
        root.reportError("Could not open the Mihoro installation guide.")
      }
      settleTimer.restart()
    }
  }

  Process {
    id: defaultAgentProcess
    running: false
    command: []
    stdout: StdioCollector { id: defaultAgentOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.defaultAgent = exitCode === 0 ? String(defaultAgentOut.text || "").trim() : ""
    }
  }

  Process {
    id: failureLogWriteProcess
    running: false
    command: []
    // Set per write, not bound: `onStarted` closes stdin, and a binding would
    // fight that.
    stdinEnabled: false
    onStarted: {
      failureLogWriteProcess.write(root._pendingFailureLog)
      root._pendingFailureLog = ""
      failureLogWriteProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.reportError("Could not save the failure log.")
        return
      }
      diagnoseProcess.command = Model.diagnoseCommand(
        Model.diagnosePrompt(root.lastErrorKind, Model.failureLogPath(root.home),
          root.mihoroConfigPath))
      diagnoseProcess.running = true
    }
  }

  Process {
    id: diagnoseProcess
    running: false
    command: []
    onExited: function(exitCode) {
      // omarchy-agent detaches the terminal, so a non-zero exit is the launch
      // itself failing rather than the agent finishing.
      if (exitCode !== 0) root.reportError("Could not open the diagnosis.")
    }
  }

  Process {
    id: configReadProcess
    running: false
    command: []
    stdout: StdioCollector { id: configOut; waitForEnd: true }
    onExited: {
      root.configRaw = String(configOut.text || "")
      root.config = MihoroConfig.parse(root.configRaw)
      root.configLoaded = true
      root.reconcileSubscriptions()
      root.refreshProbe()
    }
  }

  Process {
    id: probeProcess
    running: false
    command: []
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      var next = Model.parseProbe(probeOut.text)
      // The probe cannot see whether the subscription URL is set, only whether
      // mihomo's config.yaml exists; a mihoro.toml with an empty URL is still
      // "not set up", and that is the state the setup card keys off.
      next.configPresent = next.configPresent && String(root.config.remoteConfigUrl || "") !== ""
      root.probe = next
      if (root.desiredActive !== -1 && (next.activeState === "active") === (root.desiredActive === 1))
        root.desiredActive = -1
      root.refreshApi()
      if (root.panelOpen) root.refreshConnections()
    }
  }

  Process {
    id: versionProcess
    running: false
    command: []
    stdout: StdioCollector { id: versionOut; waitForEnd: true }
    stderr: StdioCollector { id: versionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = ClashApi.classify(exitCode, versionOut.text, versionErr.text)
      root.apiState = result.ok ? "ok" : result.code
      root.mihomoVersion = result.ok ? ClashApi.parseVersion(result.body).version : ""
      // Everything below is read from a core that just stopped answering.
      // Leaving the totals behind would keep them on screen as if they were
      // still being updated.
      if (!result.ok) {
        root.liveConfigs = null
        root.connectionCount = 0
        root.downloadTotal = 0
        root.uploadTotal = 0
      }
    }
  }

  Process {
    id: configsProcess
    running: false
    command: []
    stdout: StdioCollector { id: configsOut; waitForEnd: true }
    stderr: StdioCollector { id: configsErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = ClashApi.classify(exitCode, configsOut.text, configsErr.text)
      if (!result.ok) return
      var parsed = ClashApi.parseConfigs(result.body)
      if (!parsed) return
      root.liveConfigs = parsed
      // The core has spoken; stop overriding with the click.
      if (root.pendingMode !== "" && parsed.mode === root.pendingMode) root.pendingMode = ""
    }
  }

  Process {
    id: connectionsProcess
    running: false
    command: []
    stdout: StdioCollector { id: connectionsOut; waitForEnd: true }
    stderr: StdioCollector { id: connectionsErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = ClashApi.classify(exitCode, connectionsOut.text, connectionsErr.text)
      if (!result.ok) return
      var parsed = ClashApi.parseConnections(result.body)
      if (!parsed) return
      root.connectionCount = parsed.count
      root.downloadTotal = parsed.downloadTotal
      root.uploadTotal = parsed.uploadTotal
    }
  }

  Process {
    id: routeRequestProcess
    running: false
    command: []
    onExited: function(exitCode) {
      // A fast successful response can disappear before the API snapshot; a
      // failed request cannot have a route to report.
      if (root.routeTestRunning && exitCode !== 0 && !routeLookupProcess.running
          && !routeLookupDelay.running)
        root.finishRouteTest("Failed")
    }
  }

  Process {
    id: routeLookupProcess
    running: false
    command: []
    stdout: StdioCollector { id: routeLookupOut; waitForEnd: true }
    stderr: StdioCollector { id: routeLookupErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (!root.routeTestRunning) return
      var response = ClashApi.classify(exitCode, routeLookupOut.text, routeLookupErr.text)
      if (!response.ok) {
        root.finishRouteTest("Unavailable")
        return
      }
      var route = ClashApi.findRoute(response.body, root.routeTests[root.routeTestIndex].host)
      root.finishRouteTest(route === "" ? "Not found" : route)
    }
  }

  Process {
    id: proxiesProcess
    running: false
    command: []
    stdout: StdioCollector { id: proxiesOut; waitForEnd: true }
    stderr: StdioCollector { id: proxiesErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = ClashApi.classify(exitCode, proxiesOut.text, proxiesErr.text)
      if (!result.ok) return
      var globalGroup = ClashApi.parseProxyGroup(result.body, "GLOBAL")
      var ruleGroup = ClashApi.parseProxyGroup(result.body, "PROXY")
      if (!globalGroup || !ruleGroup) return
      root.globalProxyOptions = globalGroup.options
      root.currentGlobalProxy = globalGroup.current
      root.ruleProxyOptions = ruleGroup.options
      root.currentRuleProxy = ruleGroup.current
      root.routeOptions = ClashApi.parseRouteOptions(result.body)
    }
  }

  Process {
    id: proxySelectProcess
    running: false
    command: []
    stdout: StdioCollector { id: proxySelectOut; waitForEnd: true }
    stderr: StdioCollector { id: proxySelectErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = ClashApi.classify(exitCode, proxySelectOut.text, proxySelectErr.text)
      var modeSelection = root.pendingModeProxy !== ""
      if (!result.ok) {
        root.pendingModeProxy = ""
        root.pendingProxyGroup = ""
        root.cancelGlobalSelection()
        root.reportError(result.message)
        if (modeSelection) root.proxySelectionFinished(false)
        return
      }
      var selected = root.pendingGlobalProxy
      var selectedGroup = root.pendingProxyGroup
      var activateGlobal = root.globalSelectionRequested
      if (root.pendingModeProxy !== "") {
        if (selectedGroup === "PROXY") root.currentRuleProxy = root.pendingModeProxy
        else if (selectedGroup === "GLOBAL") root.currentGlobalProxy = root.pendingModeProxy
      }
      if (selected !== "") root.currentGlobalProxy = selected
      root.pendingGlobalProxy = ""
      root.pendingModeProxy = ""
      root.pendingProxyGroup = ""
      root.globalSelectionRequested = false
      if (modeSelection) root.proxySelectionFinished(true)
      if (activateGlobal && root.mode !== "global") root.setMode("global")
      else {
        if (activateGlobal) {
          root.actionStatus = "Global connection selected."
          actionStatusTimer.restart()
        }
      }
      root.refreshProxies()
    }
  }

  Process {
    id: trafficProcess
    running: false
    command: root.apiBase === "" ? [] : ClashApi.trafficCommand(root.apiBase, root.config.secret)
    stdout: SplitParser {
      onRead: function(line) {
        var sample = ClashApi.parseTrafficLine(line)
        if (!sample) return
        var now = Date.now() / 1000
        // First sample of a new stream: charge the time it was down to the
        // history before appending to it, so the gap occupies the width it
        // really lasted instead of vanishing between two adjacent points.
        if (root.trafficAnchor === null && root.trafficIdleSince > 0) {
          var gap = now - root.trafficIdleSince
          root.upHistory = Model.padHistory(root.upHistory, gap, Model.HISTORY_LIMIT)
          root.downHistory = Model.padHistory(root.downHistory, gap, Model.HISTORY_LIMIT)
          root.trafficIdleSince = 0
        }
        var reading = ClashApi.trafficRate(root.trafficAnchor, sample, now)
        if (!reading) return
        root.trafficAnchor = reading.anchor
        // A null rate means this sample came too soon after the anchor to
        // divide by. Its bytes are still counted; they arrive with the next
        // reading, and the displayed speed holds until then.
        if (reading.rate) {
          root.upSpeed = reading.rate.up
          root.downSpeed = reading.rate.down
          root.upHistory = Model.pushHistory(root.upHistory, reading.rate.up, Model.HISTORY_LIMIT)
          root.downHistory = Model.pushHistory(root.downHistory, reading.rate.down, Model.HISTORY_LIMIT)
        }
      }
    }
    onExited: {
      root.upSpeed = 0
      root.downSpeed = 0
      root.trafficAnchor = null
      // The history is kept; from here on it is a gap, and how long a gap is
      // only known once the stream comes back.
      root.trafficIdleSince = Date.now() / 1000
      // The stream ends whenever mihomo restarts or the network blips. Come
      // back on a delay rather than spinning on a core that is still booting.
      if (root.panelOpen) trafficRetry.restart()
    }
  }

  Process {
    id: proxyExportProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) { root._pendingClipboard += line + "\n" }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || root._pendingClipboard.trim() === "") {
        root._pendingClipboard = ""
        root.actionStatus = ""
        root.reportError("Could not export proxy info.")
        return
      }
      clipboardProcess.stdinEnabled = true
      clipboardProcess.running = true
    }
  }

  Process {
    id: clipboardProcess
    running: false
    command: ["wl-copy"]
    stdinEnabled: false
    onStarted: {
      clipboardProcess.write(root._pendingClipboard)
      root._pendingClipboard = ""
      clipboardProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      root.actionStatus = exitCode === 0 ? "Proxy export copied." : ""
      if (exitCode === 0) root.lastError = ""
      else root.reportError("Could not copy proxy info.")
      if (exitCode === 0) actionStatusTimer.restart()
    }
  }

  Process {
    id: configWriteProcess
    running: false
    command: []
    // Set by writeConfig, not bound here — `onStarted` closes it to give `cat`
    // its EOF, and a binding would fight that.
    stdinEnabled: false
    stderr: StdioCollector { id: writeErr; waitForEnd: true }
    // Anything written before the process is up is dropped, so the payload
    // waits here rather than being handed over at launch.
    onStarted: {
      configWriteProcess.write(root._pendingText)
      root._pendingText = ""
      configWriteProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._afterWrite = ""
        root.pendingMode = ""
        root.reportError(Model.noticeMessage(writeErr.text || "Could not write mihoro.toml."))
        // The file on disk is not what the panel just assumed it was.
        root.refresh()
        return
      }
      root.runAfterWrite()
    }
  }

  Process {
    id: subscriptionsReadProcess
    running: false
    command: []
    stdout: StdioCollector { id: subscriptionsOut; waitForEnd: true }
    onExited: {
      root.subscriptions = Subscriptions.parse(subscriptionsOut.text)
      root.subscriptionsLoaded = true
      // First run, or an upgrade from the single-URL panel: whatever
      // mihoro.toml already points at becomes the first entry in the list.
      root.reconcileSubscriptions()
    }
  }

  Process {
    id: subscriptionsWriteProcess
    running: false
    command: []
    // Set per write, not bound: `onStarted` closes stdin, and a binding would
    // fight that.
    stdinEnabled: false
    stderr: StdioCollector { id: subscriptionsWriteErr; waitForEnd: true }
    onStarted: {
      subscriptionsWriteProcess.write(root._pendingSubscriptions)
      root._pendingSubscriptions = ""
      subscriptionsWriteProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._subscriptionsQueued = false
        root.reportError(Model.noticeMessage(
          subscriptionsWriteErr.text || "Could not save the subscription list."))
        // What is on screen is not what is on disk; the file is the truth.
        root.loadSubscriptions()
        return
      }
      if (root._subscriptionsQueued) root.writeSubscriptions()
    }
  }

  Process {
    id: rulesReadProcess
    running: false
    command: []
    stdout: StdioCollector { id: rulesReadOut; waitForEnd: true }
    onExited: {
      root.ruleStore = Rules.parse(rulesReadOut.text)
      root.rulesLoaded = true
    }
  }

  Process {
    id: rulesWriteProcess
    running: false
    command: []
    stdinEnabled: false
    stderr: StdioCollector { id: rulesWriteErr; waitForEnd: true }
    onStarted: {
      rulesWriteProcess.write(root._pendingRules)
      root._pendingRules = ""
      rulesWriteProcess.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root._afterRulesWrite = ""
        root.reportError(Model.noticeMessage(rulesWriteErr.text || "Could not save local rules."))
        root.loadRules()
        root.rulesApplyFinished(false)
        return
      }
      var next = root._afterRulesWrite
      root._afterRulesWrite = ""
      if (next === "apply") root.runConfigEnhancer("apply", "Applying local rules…")
    }
  }

  Process {
    id: configEnhancerProcess
    running: false
    command: []
    stdout: StdioCollector { id: configEnhancerOut; waitForEnd: true }
    stderr: StdioCollector { id: configEnhancerErr; waitForEnd: true }
    onExited: function(exitCode) {
      var kind = root.ruleActionKind
      root.ruleActionKind = ""
      root.actionStatus = ""
      if (exitCode !== 0) {
        root.reportError(Model.noticeMessage(configEnhancerErr.text || "Could not apply local rules."))
        root.loadRules()
        if (kind === "apply") root.rulesApplyFinished(false)
        return
      }
      root.lastError = ""
      root.actionStatus = kind === "update" ? "Subscription and local rules updated." : "Local rules applied."
      actionStatusTimer.restart()
      root.loadRules()
      if (kind === "apply") root.rulesApplyFinished(true)
      root.installRuleTimer()
      settleTimer.restart()
    }
  }

  Process {
    id: timerManagerProcess
    running: false
    command: []
    stdout: StdioCollector { id: timerManagerOut; waitForEnd: true }
    stderr: StdioCollector { id: timerManagerErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.reportError(Model.noticeMessage(timerManagerErr.text || "Could not enable local-rule auto-update."))
    }
  }

  Process {
    id: modeProcess
    running: false
    command: []
    stdout: StdioCollector { id: modeOut; waitForEnd: true }
    stderr: StdioCollector { id: modeErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = ClashApi.classify(exitCode, modeOut.text, modeErr.text)
      if (result.ok) {
        root.actionStatus = "Switched to " + Model.modeLabel(root.pendingMode) + "."
        actionStatusTimer.restart()
        root.refreshApi()
        return
      }
      // The file already holds the new mode, so a restart is a real fallback
      // rather than a second guess at what the user asked for.
      root.runAction("apply", Model.applyCommand(), "Applying mode…")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        root._actionOutput += line + "\n"
        var stage = Model.parseStageLine(line)
        if (stage && stage.kind === "stage") root.actionStatus = stage.name
        else if (stage && stage.kind === "detail" && stage.detail !== "") root.actionStatus = stage.detail
      }
    }
    stderr: SplitParser { onRead: function(line) { root._actionError += line + "\n" } }
    onExited: function(exitCode) {
      var kind = root.actionKind
      var ok = exitCode === 0
      if (ok) {
        root.lastError = ""
        root.actionStatus = kind === "update" ? "Subscription updated."
          : kind === "init" ? "mihoro is set up."
          : kind === "apply" ? "Mode applied."
          : ""
        if (root.actionStatus !== "") actionStatusTimer.restart()
      } else {
        root.desiredActive = -1
        root.pendingMode = ""
        root.actionStatus = ""
        // The notice gets a message it can render; the log keeps the whole of
        // what was printed, for an agent that can read more than three lines.
        root.lastFailureOutput = root._actionOutput + "\n" + root._actionError
        root.lastError = Model.stageFailureMessage(root.lastFailureOutput,
          "mihoro " + kind + " failed.")
        root.lastErrorKind = kind
      }
      root.actionKind = ""
      root.actionFinished(kind, ok)
      settleTimer.restart()
    }
  }
}
