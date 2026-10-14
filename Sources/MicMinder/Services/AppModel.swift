import Combine
import Foundation
import OSLog

final class AppModel: ObservableObject {
  @Published private(set) var snapshot = MicrophoneSnapshot.unknown
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

  @Published var fadeMusicEnabled: Bool {
    didSet {
      defaults.set(fadeMusicEnabled, forKey: "fadeMusicEnabled")
      if fadeMusicEnabled != oldValue { cancelFade() }
    }
  }

  @Published var autoControlEnabled: Bool {
    didSet {
      defaults.set(autoControlEnabled, forKey: Self.autoControlDefaultsKey)

      guard autoControlEnabled != oldValue else { return }
      cancelFade()
      // Disabling relinquishes ownership; enabling gives the active session a
      // fresh chance to pause on the next microphone snapshot.
      microphoneSession = snapshot.isActive ? MicrophoneSession() : nil
      setPausedByApp(false)
      if !autoControlEnabled { setLastAction(.key("action.auto_control_off")) }
      updatePlaybackTimer()
      if autoControlEnabled, snapshot.isActive { handle(snapshot, fromMonitor: false) }
    }
  }

  private static let autoControlDefaultsKey = "autoControlEnabled"

  private let microphoneMonitor: MicrophoneMonitoring
  private let playback: PlaybackAccess
  private let volumeFader: VolumeFadeController
  private let defaults: UserDefaults
  private let logger = Logger(subsystem: "dev.ginolino.MicMinder", category: "Playback")
  private var handlingSnapshot = false
  private var queuedSnapshot: MicrophoneSnapshot?
  private var microphoneSession: MicrophoneSession?
  private var playbackTimer: Timer?
  private var didFinishInitializing = false
  private var isSyncingLaunchAtLogin = false

  init(microphoneMonitor: MicrophoneMonitoring = MicrophoneMonitor(),
       playback: PlaybackAccess = .live(), defaults: UserDefaults = .standard) {
    self.microphoneMonitor = microphoneMonitor
    self.playback = playback
    volumeFader = VolumeFadeController(playback: playback)
    fadeMusicEnabled = defaults.object(forKey: "fadeMusicEnabled") as? Bool ?? true
    self.defaults = defaults
    autoControlEnabled = defaults.object(forKey: Self.autoControlDefaultsKey) as? Bool ?? true
    launchAtLoginEnabled = LaunchAtLoginService.isEnabled

    volumeFader.onStepFinished = { [weak self] in self?.drainQueuedSnapshot() }
    microphoneMonitor.onChange = { [weak self] snapshot in
      DispatchQueue.main.async {
        self?.handle(snapshot)
      }
    }
    microphoneMonitor.start()

    didFinishInitializing = true
  }

  deinit {
    volumeFader.cancel()
    microphoneMonitor.stop()
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

  func lastActionTitle(localizer: AppLocalizer) -> String {
    lastAction.resolve(with: localizer)
  }

  func requestPermissionAuthorizationFlow() {
    requestPermissionAuthorization()
  }

  func refresh() {
    volumeFader.retryRestoration()
    syncLaunchAtLoginStatus()
    microphoneMonitor.refresh()
  }

  private func handle(_ snapshot: MicrophoneSnapshot, fromMonitor: Bool = true) {
    // AppleScript replies can reenter the main run loop. Coalesce microphone
    // updates while a playback decision is in progress instead of running it twice.
    guard !handlingSnapshot && !volumeFader.isBusy else {
      if fromMonitor { queuedSnapshot = snapshot }
      return
    }
    handlingSnapshot = true
    defer {
      handlingSnapshot = false
      updatePlaybackTimer()
      drainQueuedSnapshot()
    }
    volumeFader.retryRestoration()
    if snapshot.isActive != self.snapshot.isActive || snapshot.errorMessage != self.snapshot.errorMessage {
      logger.notice("Microphone active=\(snapshot.isActive), error=\(snapshot.errorMessage != nil)")
    }
    if snapshot.isActive && !self.snapshot.isActive { cancelFade() }
    if self.snapshot != snapshot { self.snapshot = snapshot }

    if !snapshot.isActive && microphoneSession?.fading == true { cancelFade() }
    guard snapshot.errorMessage == nil else {
      cancelFade()
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

  private func drainQueuedSnapshot() {
    guard !handlingSnapshot && !volumeFader.isBusy else { return }
    let queued = queuedSnapshot
    queuedSnapshot = nil
    if let queued, queued != snapshot { handle(queued) }
  }

  private func startMicrophoneSessionIfNeeded() {
    if microphoneSession == nil {
      microphoneSession = MicrophoneSession()
      setPausedByApp(false)
    }

    if microphoneSession?.fading == true { return }
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
      if fadeMusicEnabled {
        let sessionID = microphoneSession?.id
        microphoneSession?.fading = true
        volumeFader.fadeOut(player, identity: identity, valid: { [weak self] in
          guard let self else { return false }
          return self.snapshot.isActive && self.autoControlEnabled
            && self.microphoneSession?.id == sessionID
            && self.playback.identity(player) == identity
            && self.playback.hasAutomationPermission(player)
            && self.playback.state(player) == .playing
        }, cancelled: { [weak self] in
          guard let self, self.microphoneSession?.id == sessionID else { return }
          self.microphoneSession?.fading = false
          self.microphoneSession?.reconsiderAfterAuthorization = self.playback.currentStatus().authorizedPlayers
          self.setLastAction(.key("action.playback_changed"))
        }, pause: { [weak self] in
          guard let self, self.microphoneSession?.id == sessionID else { return }
          self.microphoneSession?.fading = false
          self.sendPause(player, identity: identity)
        })
      } else {
        sendPause(player, identity: identity)
      }
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
    let played: Bool
    if fadeMusicEnabled {
      played = volumeFader.fadeIn(player, identity: identity, valid: { [weak self] in
        guard let self else { return false }
        return !self.snapshot.isActive && self.autoControlEnabled
          && self.playback.identity(player) == identity
          && self.playback.hasAutomationPermission(player)
      }, ready: { [playback] in playback.state(player) == .playing }, play: { playback.play(player) })
    } else { played = playback.play(player) }
    setLastAction(played ? .key("action.resumed") : .key("action.resume_failed"))
    logger.notice("Resume command result=\(played)")
  }

  private func cancelFade() {
    volumeFader.cancel()
    if microphoneSession?.fading == true {
      microphoneSession?.fading = false
      microphoneSession?.didAttemptPause = false
    }
  }

  func prepareForTermination() {
    cancelFade()
    playbackTimer?.invalidate()
    playbackTimer = nil
    microphoneMonitor.stop()
  }

  private func sendPause(_ player: ScriptableMediaPlayer, identity: String) {
    let sent = playback.pause(player)
    guard sent, playback.identity(player) == identity else {
      volumeFader.cancel()
      setLastAction(.key("action.pause_failed"))
      return
    }
    microphoneSession?.pendingPause = PendingPause(
      player: player, identity: identity, deadline: playback.now() + 3
    )
    confirmPendingPause()
    updatePlaybackTimer()
  }

  private func confirmPendingPause() {
    guard let pending = microphoneSession?.pendingPause else { return }
    guard playback.now() <= pending.deadline,
          playback.isRunning(pending.player),
          playback.hasAutomationPermission(pending.player),
          playback.identity(pending.player) == pending.identity else {
      volumeFader.cancel()
      microphoneSession?.pendingPause = nil
      setLastAction(.key("action.pause_failed"))
      logger.notice("Pending pause expired or player/item changed")
      return
    }
    let state = playback.state(pending.player)
    logger.notice("Pending pause state=\(String(describing: state), privacy: .public)")
    if state == .notPlaying {
      volumeFader.cancel()
      microphoneSession?.pendingPause = nil
      microphoneSession?.resumeTarget = pending.player
      microphoneSession?.resumeIdentity = pending.identity
      setPausedByApp(true)
      setLastAction(.key("action.paused_player %@", [.raw(pending.player.displayName)]))
      logger.notice("Pause confirmed; resume ownership retained")
    } else if state == .stopped {
      volumeFader.cancel()
      microphoneSession?.pendingPause = nil
      setLastAction(.key("action.pause_failed"))
    }
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
      self.handle(self.snapshot, fromMonitor: false)
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
    let id = UUID()
    var fading = false
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
