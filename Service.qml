import QtQuick
import Quickshell
import Quickshell.Io
import "MihoroConfig.js" as MihoroConfig
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

  // ---- in-flight intent
  //
  // Both are optimistic overlays: the switch and the mode chips move the
  // instant they are clicked, and stop overriding once a refresh confirms the
  // real state. Waiting for systemd makes the panel feel broken.
  property int desiredActive: -1
  property string pendingMode: ""
  property string pendingGlobalProxy: ""
  property bool globalSelectionRequested: false
  property string actionKind: ""
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: {
    var raw = settings ? settings.refreshIntervalSec : undefined
    var value = parseInt(String(raw === undefined || raw === null ? 30 : raw), 10)
    if (!isFinite(value)) value = 30
    return Math.max(5, Math.min(3600, value))
  }

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string mihoroConfigPath: MihoroConfig.configPath(home)
  readonly property string mihomoConfigPath: MihoroConfig.mihomoConfigPath(config.mihomoConfigRoot, home)
  readonly property string mihomoBinaryPath: MihoroConfig.mihomoBinaryPath(config.mihomoBinaryPath, home)
  readonly property string apiBase: ClashApi.baseUrl(config.externalController)

  // Not `state`: QQuickItem already owns that name for its own state machine.
  readonly property var connection: Model.connectionState(probe, apiState)
  readonly property bool serviceActive: probe.activeState === "active"
  readonly property bool active: desiredActive === -1 ? connection.active : (desiredActive === 1)
  readonly property bool initialized: probe.mihoroInstalled && probe.configPresent
  readonly property bool canSwitchMode: Model.canSwitchMode(probe, apiState)
  readonly property string modeHint: Model.modeHint(probe, apiState)

  // The API is the running truth; mihoro.toml is what survives a restart. They
  // agree except in the window between a switch and the next refresh.
  readonly property string mode: pendingMode !== "" ? pendingMode
    : (liveConfigs && liveConfigs.mode !== "" ? liveConfigs.mode : config.mode)

  readonly property bool busy: probeProcess.running || configReadProcess.running
    || actionProcess.running || modeProcess.running || proxySelectProcess.running
    || configWriteProcess.running || guideProcess.running
  readonly property bool actionRunning: actionProcess.running
  readonly property bool copyingProxyExport: proxyExportProcess.running || clipboardProcess.running

  signal actionFinished(string kind, bool ok)

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
    globalSelectionRequested = true
    lastError = ""
    proxySelectProcess.command = ClashApi.selectProxyCommand(apiBase, config.secret, "GLOBAL", wanted)
    proxySelectProcess.running = true
  }

  function cancelGlobalSelection() {
    globalSelectionRequested = false
    pendingGlobalProxy = ""
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
    runAction("update", Model.updateConfigCommand(), "Refreshing subscription…")
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

  // Setting the URL and pulling it are one gesture: writing the file alone
  // would leave the panel showing a subscription that nothing has fetched.
  function setSubscriptionUrl(url) {
    var text = String(url || "").trim()
    if (Model.subscriptionUrlError(text) !== "") {
      lastError = Model.subscriptionUrlError(text)
      return false
    }
    lastError = ""
    writeConfig({ remoteConfigUrl: text }, probe.configPresent && probe.unitLoaded ? "update" : "init")
    return true
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

  // ------------------------------------------------------ writing mihoro.toml

  property string _pendingText: ""
  property string _afterWrite: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _pendingClipboard: ""

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
      runAction("update", Model.updateConfigCommand(), "Fetching subscription…")
    } else if (next === "init") {
      runAction("init", Model.initCommand(), "Setting up mihoro…")
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
    }
    syncTraffic()
  }
  onApiStateChanged: syncTraffic()
  onServiceActiveChanged: syncTraffic()
  onApiBaseChanged: {
    trafficProcess.running = false
    syncTraffic()
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
        root.lastError = "Could not open the Mihoro installation guide."
      }
      settleTimer.restart()
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
    id: proxiesProcess
    running: false
    command: []
    stdout: StdioCollector { id: proxiesOut; waitForEnd: true }
    stderr: StdioCollector { id: proxiesErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = ClashApi.classify(exitCode, proxiesOut.text, proxiesErr.text)
      if (!result.ok) return
      var parsed = ClashApi.parseGlobalProxies(result.body)
      if (!parsed) return
      root.globalProxyOptions = parsed.options
      root.currentGlobalProxy = parsed.current
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
      if (!result.ok) {
        root.cancelGlobalSelection()
        root.lastError = result.message
        return
      }
      var selected = root.pendingGlobalProxy
      var activateGlobal = root.globalSelectionRequested
      if (selected !== "") root.currentGlobalProxy = selected
      root.pendingGlobalProxy = ""
      root.globalSelectionRequested = false
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
        root.lastError = "Could not export proxy info."
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
      root.lastError = exitCode === 0 ? "" : "Could not copy proxy info."
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
        root.lastError = Model.elide(writeErr.text || "Could not write mihoro.toml.", 160)
        // The file on disk is not what the panel just assumed it was.
        root.refresh()
        return
      }
      root.runAfterWrite()
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
        root.lastError = Model.stageFailureMessage(
          root._actionOutput + "\n" + root._actionError,
          "mihoro " + kind + " failed.")
      }
      root.actionKind = ""
      root.actionFinished(kind, ok)
      settleTimer.restart()
    }
  }
}
