import Combine
import Foundation
import OSLog

final class AppModel: ObservableObject {
  @Published private(set) var snapshot = MicrophoneSnapshot.unknown
  @Published private(set) var hasAccessibilityAccess: Bool
  @Published private(set) var lastAction = LocalizedMessage.key("action.listening")
  @Published private(set) var pausedByApp = false
  var onPermissionAuthorizationNeeded: (() -> Void)?

  @Published var launchAtLoginEnabled: Bool {
    didSet {
      guard didFinishInitializing, !isSyncingLaunchAtLogin, launchAtLoginEnabled != oldValue else {
        return
      }

      updateLaunchAtLogin(enabled: launchAtLoginEnabled, previousValue: oldValue)
    }
  }

  @Published var autoControlEnabled: Bool {
    didSet {
      defaults.set(autoControlEnabled, forKey: Self.autoControlDefaultsKey)

      guard autoControlEnabled != oldValue else { return }
      // Disabling relinquishes ownership; enabling gives the active session a
      // fresh chance to pause on the next microphone snapshot.
      microphoneSession = snapshot.isActive ? MicrophoneSession() : nil
      setPausedByApp(false)
      if !autoControlEnabled { setLastAction(.key("action.auto_control_off")) }
      updatePlaybackTimer()
      if autoControlEnabled, snapshot.isActive { handle(snapshot) }
    }
  }

  private static let autoControlDefaultsKey = "autoControlEnabled"

  private let microphoneMonitor: MicrophoneMonitoring
  private let playback: PlaybackAccess
  private let defaults: UserDefaults
  private let logger = Logger(subsystem: "dev.ginolino.MicMinder", category: "Playback")
  private var microphoneSession: MicrophoneSession?
  private var permissionTimer: Timer?
  private var playbackTimer: Timer?
  private var didFinishInitializing = false
  private var isSyncingLaunchAtLogin = false

  init(microphoneMonitor: MicrophoneMonitoring = MicrophoneMonitor(),
       playback: PlaybackAccess = .live(), defaults: UserDefaults = .standard) {
    self.microphoneMonitor = microphoneMonitor
    self.playback = playback
    self.defaults = defaults
    hasAccessibilityAccess = playback.isAccessibilityTrusted()
    autoControlEnabled = defaults.object(forKey: Self.autoControlDefaultsKey) as? Bool ?? true
    launchAtLoginEnabled = LaunchAtLoginService.isEnabled

    microphoneMonitor.onChange = { [weak self] snapshot in
      DispatchQueue.main.async {
        self?.handle(snapshot)
      }
    }
    microphoneMonitor.start()

    permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      self?.refreshAccessibilityStatus()
    }

    didFinishInitializing = true
  }

  deinit {
    microphoneMonitor.stop()
    permissionTimer?.invalidate()
    playbackTimer?.invalidate()
  }

  func statusTitle(localizer: AppLocalizer) -> String {
    if let errorMessage = snapshot.errorMessage {
      return localizer.text("status.monitor_error %@", errorMessage.resolve(with: localizer))
    }

    return snapshot.isActive ? localizer.text("status.mic_active") : localizer.text("status.mic_idle")
  }

  var menuBarIcon: String {
    if snapshot.errorMessage != nil {
      return "exclamationmark.triangle"
    }

    if snapshot.isActive {
      return autoControlEnabled ? "mic.fill" : "mic.fill.slash"
    }

    return autoControlEnabled ? "mic" : "mic.slash"
  }

  func deviceTitle(localizer: AppLocalizer) -> String {
    snapshot.primaryDeviceName(localizer: localizer)
  }

  func permissionTitle(localizer: AppLocalizer) -> String {
    hasAccessibilityAccess ? localizer.text("status.accessibility_granted") : localizer.text("status.accessibility_needed")
  }

  func lastActionTitle(localizer: AppLocalizer) -> String {
    lastAction.resolve(with: localizer)
  }

  func requestAccessibility() {
    hasAccessibilityAccess = AccessibilityPermission.requestPrompt()
    setLastAction(hasAccessibilityAccess ? .key("action.accessibility_granted") : .key("action.accessibility_waiting"))
  }

  func openAccessibilitySettings() {
    AccessibilityPermission.openSettings()
  }

  func requestPermissionAuthorizationFlow() {
    requestPermissionAuthorization()
  }

  func refresh() {
    refreshAccessibilityStatus()
    syncLaunchAtLoginStatus()
    microphoneMonitor.refresh()
  }

  func testPlayPause() {
    refreshAccessibilityStatus()
    guard hasAccessibilityAccess else {
      setLastAction(.key("action.accessibility_missing"))
      requestPermissionAuthorization()
      return
    }

    microphoneSession?.resumeTarget = nil
    microphoneSession?.pendingPause = nil
    microphoneSession?.resumeIdentity = nil
    microphoneSession?.didAttemptPause = true
    microphoneSession?.reconsiderAfterAuthorization = nil
    setPausedByApp(false)
    setLastAction(playback.sendMediaKey() ? .key("action.media_key_sent") : .key("action.media_key_failed"))
  }

  private func handle(_ snapshot: MicrophoneSnapshot) {
    defer { updatePlaybackTimer() }
    if snapshot.isActive != self.snapshot.isActive || snapshot.errorMessage != self.snapshot.errorMessage {
      logger.notice("Microphone active=\(snapshot.isActive), error=\(snapshot.errorMessage != nil)")
    }
    if self.snapshot != snapshot { self.snapshot = snapshot }
    refreshAccessibilityStatus()

    guard snapshot.errorMessage == nil else {
      // An interrupted observation cannot establish continuous pause ownership.
      microphoneSession?.resumeTarget = nil
      microphoneSession?.pendingPause = nil
      microphoneSession?.resumeIdentity = nil
      microphoneSession?.didAttemptPause = true
      microphoneSession?.reconsiderAfterAuthorization = nil
      setPausedByApp(false)
      return
    }

    if snapshot.isActive {
      startMicrophoneSessionIfNeeded()
      return
    }

    if microphoneSession != nil {
      finishMicrophoneSession()
    }
  }

  private func startMicrophoneSessionIfNeeded() {
    if microphoneSession == nil {
      microphoneSession = MicrophoneSession()
      setPausedByApp(false)
    }

    if microphoneSession?.pendingPause != nil {
      confirmPendingPause()
      return
    }

    if let player = microphoneSession?.resumeTarget {
      // A user restart, player quit, or lost permission cancels our ownership.
      guard playback.isRunning(player), playback.hasAutomationPermission(player),
            playback.state(player) == .notPlaying,
            playback.identity(player) == microphoneSession?.resumeIdentity else {
        microphoneSession?.resumeTarget = nil
        logger.notice("Resume ownership canceled while microphone active")
        setPausedByApp(false)
        setLastAction(.key("action.playback_changed"))
        return
      }
      return
    }

    if let previous = microphoneSession?.reconsiderAfterAuthorization {
      let status = playback.currentStatus()
      let newlyAvailable = status.authorizedPlayers.subtracting(previous)
      guard !newlyAvailable.isEmpty else { return }
      microphoneSession?.reconsiderAfterAuthorization = status.authorizedPlayers
      // A newly available player must never cause us to repause an old
      // player the user has chosen to restart during this microphone session.
      guard status.state == .playing, let player = status.player,
            newlyAvailable.contains(player.bundleIdentifier) else { return }
      microphoneSession?.reconsiderAfterAuthorization = nil
      microphoneSession?.didAttemptPause = false
      pausePlaybackForMicrophone(status: status)
    } else if microphoneSession?.didAttemptPause == false {
      pausePlaybackForMicrophone()
    }
  }

  private func pausePlaybackForMicrophone(status suppliedStatus: MediaPlaybackStatus? = nil) {
    guard autoControlEnabled else {
      setLastAction(.key("action.auto_control_off"))
      return
    }

    let status = suppliedStatus ?? playback.currentStatus()
    guard let player = status.player else {
      setLastAction(.key("action.playback_unconfirmed"))
      return
    }
    guard playback.hasAutomationPermission(player) else {
      setLastAction(.key("action.automation_permission_missing"))
      return
    }

    switch status.state {
    case .some(.playing):
      guard let identity = playback.identity(player) else {
        setLastAction(.key("action.playback_unconfirmed"))
        return
      }
      microphoneSession?.didAttemptPause = true
      // An explicit pause is safe; a global toggle is not. Confirm it took
      // effect before claiming ownership of a later resume.
      let sent = playback.pause(player)
      let state = playback.state(player)
      let identityMatches = playback.identity(player) == identity
      logger.notice("Pause sent=\(sent), state=\(String(describing: state), privacy: .public), same item=\(identityMatches)")
      guard sent, identityMatches else {
        setLastAction(.key("action.pause_failed"))
        return
      }
      microphoneSession?.pendingPause = PendingPause(
        player: player, identity: identity, deadline: playback.now() + 3
      )
      confirmPendingPause()
    case .some(.notPlaying), .some(.stopped):
      microphoneSession?.didAttemptPause = true
      microphoneSession?.reconsiderAfterAuthorization = status.authorizedPlayers
      setLastAction(.key("action.music_already_paused"))
    case .none:
      // Permission may be granted while the microphone is still active.
      setLastAction(.key("action.playback_unconfirmed"))
    }
  }

  private func finishMicrophoneSession() {
    confirmPendingPause()
    // A short microphone session can end before the player's state catches
    // up. Keep checking the same pending command until it confirms or expires.
    guard microphoneSession?.pendingPause == nil else { return }
    let player = microphoneSession?.resumeTarget
    let identity = microphoneSession?.resumeIdentity
    logger.notice("Microphone idle: auto=\(self.autoControlEnabled), resume target=\(player != nil)")
    microphoneSession = nil
    setPausedByApp(false)

    guard autoControlEnabled, let player else {
      setLastAction(autoControlEnabled ? .key("action.mic_idle") : .key("action.auto_control_off"))
      return
    }
    guard playback.isRunning(player), playback.hasAutomationPermission(player),
          playback.state(player) == .notPlaying, let identity,
          playback.identity(player) == identity else {
      setLastAction(.key("action.playback_changed"))
      return
    }
    // Respect playback the user started in another supported player as well.
    guard playback.currentStatus().state != .playing else {
      setLastAction(.key("action.playback_changed"))
      return
    }
    setLastAction(playback.play(player) ? .key("action.resumed") : .key("action.resume_failed"))
    logger.notice("Resume command result=\(self.lastAction == .key("action.resumed"))")
  }

  private func confirmPendingPause() {
    guard let pending = microphoneSession?.pendingPause else { return }
    guard playback.now() <= pending.deadline,
          playback.isRunning(pending.player),
          playback.hasAutomationPermission(pending.player),
          playback.identity(pending.player) == pending.identity else {
      microphoneSession?.pendingPause = nil
      setLastAction(.key("action.pause_failed"))
      logger.notice("Pending pause expired or player/item changed")
      return
    }
    let state = playback.state(pending.player)
    logger.notice("Pending pause state=\(String(describing: state), privacy: .public)")
    if state == .notPlaying {
      microphoneSession?.pendingPause = nil
      microphoneSession?.resumeTarget = pending.player
      microphoneSession?.resumeIdentity = pending.identity
      setPausedByApp(true)
      setLastAction(.key("action.paused_player %@", [.raw(pending.player.displayName)]))
      logger.notice("Pause confirmed; resume ownership retained")
    } else if state == .stopped {
      microphoneSession?.pendingPause = nil
      setLastAction(.key("action.pause_failed"))
    }
  }

  private func refreshAccessibilityStatus() {
    let trusted = playback.isAccessibilityTrusted()
    if hasAccessibilityAccess != trusted { hasAccessibilityAccess = trusted }
  }

  private func setLastAction(_ value: LocalizedMessage) {
    if lastAction != value { lastAction = value }
  }

  private func setPausedByApp(_ value: Bool) {
    if pausedByApp != value { pausedByApp = value }
  }

  private func updatePlaybackTimer() {
    let needsChecks = autoControlEnabled && snapshot.errorMessage == nil
      && (snapshot.isActive || microphoneSession?.pendingPause != nil)
    guard needsChecks else {
      playbackTimer?.invalidate()
      playbackTimer = nil
      return
    }
    guard playbackTimer == nil else { return }
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.handle(self.snapshot)
    }
    playbackTimer?.tolerance = 0.05
  }

  private func requestPermissionAuthorization() {
    onPermissionAuthorizationNeeded?()
  }

  private func updateLaunchAtLogin(enabled: Bool, previousValue: Bool) {
    if let message = LaunchAtLoginService.setEnabled(enabled) {
      setLaunchAtLoginEnabledWithoutApplying(previousValue)
      setLastAction(.key("action.login_item_error %@", [message]))
    } else {
      setLastAction(enabled ? .key("action.login_item_enabled") : .key("action.login_item_disabled"))
    }
  }

  private func syncLaunchAtLoginStatus() {
    setLaunchAtLoginEnabledWithoutApplying(LaunchAtLoginService.isEnabled)
  }

  private func setLaunchAtLoginEnabledWithoutApplying(_ enabled: Bool) {
    isSyncingLaunchAtLogin = true
    launchAtLoginEnabled = enabled
    isSyncingLaunchAtLogin = false
  }

  private struct MicrophoneSession {
    var pendingPause: PendingPause?
    var resumeTarget: ScriptableMediaPlayer?
    var resumeIdentity: String?
    var didAttemptPause = false
    var reconsiderAfterAuthorization: Set<String>?
  }

  private struct PendingPause {
    var player: ScriptableMediaPlayer
    var identity: String
    var deadline: TimeInterval
  }
}
