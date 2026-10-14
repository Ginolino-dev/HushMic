import XCTest
import Combine
@testable import MicMinder

@MainActor
final class PlaybackSessionTests: XCTestCase {
  func testEnablingIdleControlClearsDisabledStatus() async {
    let h = Harness()
    h.model.autoControlEnabled = false
    h.model.autoControlEnabled = true
    XCTAssertEqual(h.model.lastAction, .key("action.listening"))
  }

  func testDisablingPlayerDuringFadeRestoresVolumeAndCancelsPlayback() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    h.model.prepareToDisablePlayer(h.player)
    h.automationGranted = false
    await h.emit(active: false)
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.commands, [])
    h.automationGranted = true
    h.model.prepareForTermination()
  }

  func testSpotifyRoundedVolumeRepliesDoNotCancelFadeOrLeaveResumeMuted() async throws {
    let h = Harness()
    h.volume = 60
    h.onVolumeWrite = { [weak h] in
      guard let h, let volume = h.volume, volume > 0, volume < 100 else { return }
      h.volume = volume - 1
    }
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 850_000_000)
    XCTAssertEqual(h.volumeAtPause, 0)
    XCTAssertGreaterThanOrEqual(h.volume ?? 0, 59)
    await h.emit(active: false)
    try await Task.sleep(nanoseconds: 850_000_000)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
    XCTAssertGreaterThanOrEqual(h.volume ?? 0, 58)
    h.model.prepareForTermination()
  }

  func testFadeLowersVolumeBeforePauseAndRestoresVolumeWhilePaused() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    XCTAssertEqual(h.commands, [])
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertLessThan(h.volume!, 60)
    XCTAssertGreaterThan(h.volume!, 0)
    try await Task.sleep(nanoseconds: 450_000_000)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.volumeAtPause, 0)
  }

  func testFadeResumesAtNewUserVolumeAndFadesUp() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 750_000_000)
    h.volume = 35
    await h.emit(active: false)
    XCTAssertEqual(h.volumeAtPlay, 0)
    try await Task.sleep(nanoseconds: 750_000_000)
    XCTAssertEqual(h.volume, 35)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
  }

  func testShortMicrophoneSessionCancelsFadeWithoutPausing() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    await h.emit(active: false)
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.commands, [])
  }

  func testUserVolumeChangeDuringFadeIsNotOverwritten() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    h.volume = 80
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(h.volume, 80)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testDisablingControlDuringFadeRestoresVolumeWithoutPausing() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    h.model.autoControlEnabled = false
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.commands, [])
  }

  func testTerminationDuringFadeRestoresVolumeWithoutPausing() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    h.model.prepareForTermination()
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.commands, [])
  }

  func testChangedTrackDuringFadeRestoresVolumeButNeverPausesNewTrack() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    h.identity = "process-1:track-2"
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.commands, [])
  }

  func testDisabledFadePausesImmediatelyAtOriginalVolume() async {
    let h = Harness()
    h.volume = 60
    h.model.fadeMusicEnabled = false
    await h.emit(active: true)
    XCTAssertEqual(h.volumeAtPause, 60)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testDelayedPauseKeepsVolumeDownUntilPauseIsConfirmed() async throws {
    let h = Harness()
    h.volume = 60
    h.pauseChangesState = false
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 650_000_000)
    XCTAssertEqual(h.volume, 0)
    XCTAssertFalse(h.model.pausedByApp)
    h.state = .notPlaying
    await h.emit(active: true)
    XCTAssertEqual(h.volume, 60)
    XCTAssertTrue(h.model.pausedByApp)
  }

  func testPermissionReturningRestoresVolumeAndRetriesInterruptedFade() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 150_000_000)
    h.automationGranted = false
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertLessThan(h.volume!, 60)
    h.automationGranted = true
    await h.emit(active: true)
    XCTAssertEqual(h.volume, 60)
    try await Task.sleep(nanoseconds: 750_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testIdleFadeInRestoresVolumeWhenPermissionReturnsWithoutMicrophoneEvent() async throws {
    let h = Harness()
    defer { h.model.prepareForTermination() }
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 750_000_000)
    await h.emit(active: false)
    try await Task.sleep(nanoseconds: 150_000_000)
    h.automationGranted = false
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertLessThan(h.volume!, 60)
    h.automationGranted = true
    try await Task.sleep(nanoseconds: 1_200_000_000)
    XCTAssertEqual(h.volume, 60)
  }

  func testSlowPlayCommandDoesNotConsumeFadeInDuration() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 750_000_000)
    h.playDelay = 0.6
    await h.emit(active: false)
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertLessThan(h.volume!, 60)
    try await Task.sleep(nanoseconds: 650_000_000)
    XCTAssertEqual(h.volume, 60)
  }

  func testDelayedPlayingStateWaitsForPlaybackBeforeFadingIn() async throws {
    let h = Harness()
    h.volume = 60
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 750_000_000)
    h.playChangesState = false
    await h.emit(active: false)
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertEqual(h.volume, 0)
    h.state = .playing
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertLessThan(h.volume!, 60)
    try await Task.sleep(nanoseconds: 650_000_000)
    XCTAssertEqual(h.volume, 60)
  }

  func testMicrophoneEventDuringPlayIsNotLostToStaleTimerPoll() async {
    let h = Harness()
    await h.emit(active: true)
    h.onPlay = {
      h.monitor.onChange?(MicrophoneSnapshot(isActive: true, activeDeviceNames: [],
                                             inputDeviceNames: [], errorMessage: nil))
      RunLoop.main.run(until: Date().addingTimeInterval(0.35))
    }
    await h.emit(active: false)
    XCTAssertTrue(h.model.snapshot.isActive)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client", "pause:com.spotify.client"])
    h.onPlay = {}
    h.model.autoControlEnabled = false
  }

  func testCanceledFadeCannotBeRevivedByReentrantPlaybackConfirmation() async throws {
    let h = Harness()
    h.volume = 60
    let fader = VolumeFadeController(playback: h.playback)
    defer { fader.cancel() }
    let played = fader.fadeIn(h.player, identity: h.identity!, valid: { true }, ready: {
      fader.cancel()
      return true
    }, play: { true })
    XCTAssertTrue(played)
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.volumeWrites, [0, 60])
    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(h.volumeWrites, [0, 60])
  }

  func testMicrophoneEndingDuringVolumeWriteRestoresOriginalVolume() async throws {
    let h = Harness()
    h.volume = 60
    h.onVolumeWrite = {
      h.onVolumeWrite = {}
      h.monitor.onChange?(MicrophoneSnapshot(isActive: false, activeDeviceNames: [],
                                             inputDeviceNames: [], errorMessage: nil))
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    await h.emit(active: true)
    try await Task.sleep(nanoseconds: 750_000_000)
    XCTAssertEqual(h.volume, 60)
    XCTAssertEqual(h.commands, [])
  }

  func testDelayedPauseIsConfirmedWithoutRepeatedMicrophoneNotifications() async throws {
    let h = Harness()
    h.pauseChangesState = false
    await h.emit(active: true)
    h.state = .notPlaying
    try await Task.sleep(nanoseconds: 500_000_000)
    XCTAssertTrue(h.model.pausedByApp)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
  }

  func testUnchangedIdleSnapshotDoesNotPublishUIUpdates() async {
    let h = Harness()
    await h.emit(active: false)
    var updates = 0
    let subscription = h.model.objectWillChange.sink { updates += 1 }
    await h.emit(active: false)
    XCTAssertEqual(updates, 0)
    withExtendedLifetime(subscription) {}
  }

  func testUnchangedDisabledActiveSnapshotDoesNotPublishUIUpdates() async {
    let h = Harness()
    h.model.autoControlEnabled = false
    await h.emit(active: true)
    var updates = 0
    let subscription = h.model.objectWillChange.sink { updates += 1 }
    await h.emit(active: true)
    XCTAssertEqual(updates, 0)
    withExtendedLifetime(subscription) {}
  }


  func testResumesOnlyPlayerPausedByApp() async {
    let h = Harness()
    await h.emit(active: true)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
    XCTAssertTrue(h.model.pausedByApp)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
    XCTAssertFalse(h.model.pausedByApp)
  }

  func testAlreadyPausedPlaybackIsNeverStarted() async {
    let h = Harness(state: .notPlaying)
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, [])
  }

  func testDisablingControlCancelsPendingResume() async {
    let h = Harness()
    await h.emit(active: true)
    h.model.autoControlEnabled = false
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
    XCTAssertFalse(h.model.pausedByApp)
  }

  func testManualResumeDoesNotReceiveAnotherPlayCommandAtMicrophoneIdle() async {
    let h = Harness()
    await h.emit(active: true)
    h.state = .playing
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testUnknownRecipientNeverReceivesAutomaticMediaKeys() async {
    let h = Harness()
    h.useGlobalMediaKey = true
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, [])
  }

  func testScriptablePlayerUsesOnlyAutomation() async {
    let h = Harness()
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
  }

  func testMissingPermissionsDoNotOpenWindowsFromMonitoring() async {
    let h = Harness()
    h.automationGranted = false
    var windowsRequested = 0
    h.model.onPermissionAuthorizationNeeded = { windowsRequested += 1 }
    await h.emit(active: true)
    await h.emit(active: true)
    XCTAssertEqual(windowsRequested, 0)
    XCTAssertEqual(h.commands, [])
  }

  func testGrantingAutomationDuringActiveMicrophoneRetriesPause() async {
    let h = Harness()
    h.automationGranted = false
    await h.emit(active: true)
    h.automationGranted = true
    await h.emit(active: true)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testEnablingControlDuringActiveMicrophonePauses() async {
    let h = Harness()
    h.model.autoControlEnabled = false
    await h.emit(active: true)
    h.model.autoControlEnabled = true
    await h.emit(active: true)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testUserResumedPlaybackCancelsOwnership() async {
    let h = Harness()
    await h.emit(active: true)
    h.state = .playing
    await h.emit(active: true)
    h.state = .notPlaying
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testFailedPauseIsNotResumed() async {
    let h = Harness()
    h.pauseSucceeds = false
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertFalse(h.commands.contains("play:com.spotify.client"))
    XCTAssertFalse(h.model.pausedByApp)
  }

  func testChangedTrackIsNotResumed() async {
    let h = Harness()
    await h.emit(active: true)
    h.identity = "process-1:track-2"
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testRestartedPlayerIsNotResumed() async {
    let h = Harness()
    await h.emit(active: true)
    h.identity = "process-2:track-1"
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testUnconfirmedPauseDoesNotClaimResumeOwnership() async {
    let h = Harness()
    h.pauseChangesState = false
    await h.emit(active: true)
    XCTAssertFalse(h.model.pausedByApp)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testDelayedPauseConfirmationResumesWhenMicrophoneBecomesIdle() async {
    let h = Harness()
    h.pauseChangesState = false
    await h.emit(active: true)
    XCTAssertFalse(h.model.pausedByApp)
    h.state = .notPlaying
    await h.emit(active: true)
    XCTAssertTrue(h.model.pausedByApp)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
  }

  func testDelayedPauseCanBeConfirmedOnFirstIdleSnapshot() async {
    let h = Harness()
    h.pauseChangesState = false
    await h.emit(active: true)
    h.state = .notPlaying
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
  }

  func testPauseConfirmationContinuesAfterMicrophoneBecomesIdle() async {
    let h = Harness()
    h.pauseChangesState = false
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
    h.state = .notPlaying
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
  }

  func testExpiredPauseConfirmationNeverResumes() async {
    let h = Harness()
    h.pauseChangesState = false
    await h.emit(active: true)
    h.time = 4
    h.state = .notPlaying
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testChangedItemDuringPauseConfirmationNeverResumes() async {
    let h = Harness()
    h.pauseChangesState = false
    await h.emit(active: true)
    h.identity = "process-1:track-2"
    h.state = .notPlaying
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testUnknownItemIsNotAutomaticallyPaused() async {
    let h = Harness()
    h.identity = nil
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, [])
  }

  func testStoppedPlayerIsNotResumed() async {
    let h = Harness()
    await h.emit(active: true)
    h.state = .stopped
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }


  func testMonitoringErrorCancelsOutstandingResume() async {
    let h = Harness()
    await h.emit(active: true)
    await h.emit(active: false, error: .raw("Device disconnected"))
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testNewPlayerAuthorizationRetriesAfterAnotherPlayerWasAlreadyPaused() async {
    let h = Harness(state: .notPlaying)
    h.statusPlayer = ScriptableMediaPlayer(bundleIdentifier: "com.apple.Music", displayName: "Music")
    h.authorizedPlayers = ["com.apple.Music"]
    await h.emit(active: true)
    h.authorizedPlayers = ["com.apple.Music", "com.spotify.client"]
    h.statusPlayer = h.player
    h.state = .playing
    await h.emit(active: true)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client"])
  }

  func testNewStoppedPlayerDoesNotCauseRepausingManuallyResumedMusic() async {
    let h = Harness(state: .notPlaying)
    let music = ScriptableMediaPlayer(bundleIdentifier: "com.apple.Music", displayName: "Music")
    h.statusPlayer = music
    h.authorizedPlayers = ["com.apple.Music"]
    await h.emit(active: true)
    h.state = .playing
    h.authorizedPlayers = ["com.apple.Music", "com.spotify.client"]
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, [])
  }
}

@MainActor
private final class Harness {
  let monitor = TestMicrophoneMonitor()
  let player = ScriptableMediaPlayer(bundleIdentifier: "com.spotify.client", displayName: "Spotify")
  let defaults: UserDefaults
  let suiteName = "MicMinderTests." + UUID().uuidString
  var model: AppModel!
  var playback: PlaybackAccess!
  var onPlay: () -> Void = {}
  var onVolumeWrite: () -> Void = {}
  var volumeWrites: [Int] = []
  var state: ReliablePlaybackState
  var automationGranted = true
  var useGlobalMediaKey = false
  var pauseSucceeds = true
  var pauseChangesState = true
  var identity: String? = "process-1:track-1"
  var authorizedPlayers: Set<String> = ["com.spotify.client"]
  var statusPlayer: ScriptableMediaPlayer?
  var commands: [String] = []
  var playDelay: TimeInterval = 0
  var playChangesState = true
  var volume: Int?
  var volumeAtPause: Int?
  var volumeAtPlay: Int?
  var time: TimeInterval = 0

  init(state: ReliablePlaybackState = .playing) {
    self.state = state
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(true, forKey: "autoControlEnabled")
    let playback = PlaybackAccess(
      currentStatus: { [unowned self] in
        MediaPlaybackStatus(state: self.automationGranted ? self.state : nil,
                            player: self.useGlobalMediaKey ? nil : (self.statusPlayer ?? self.player),
                            authorizedPlayers: self.automationGranted ? self.authorizedPlayers : [])
      },
      state: { [unowned self] _ in self.state },
      pause: { [unowned self] player in
        self.volumeAtPause = self.volume
        self.commands.append("pause:" + player.bundleIdentifier)
        if self.pauseSucceeds && self.pauseChangesState { self.state = .notPlaying }
        return self.pauseSucceeds
      },
      play: { [unowned self] player in
        self.volumeAtPlay = self.volume
        self.commands.append("play:" + player.bundleIdentifier)
        if self.playDelay > 0 { Thread.sleep(forTimeInterval: self.playDelay) }
        if self.playChangesState { self.state = .playing }
        self.onPlay()
        return true
      },
      isRunning: { _ in true },
      hasAutomationPermission: { [unowned self] _ in self.automationGranted },
      identity: { [unowned self] _ in self.identity },
      volume: { [unowned self] _ in self.volume },
      setVolume: { [unowned self] _, value in self.volumeWrites.append(value); self.volume = value; self.onVolumeWrite(); return true },
      now: { [unowned self] in self.time }
    )
    self.playback = playback
    model = AppModel(microphoneMonitor: monitor, playback: playback, defaults: defaults)
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func emit(active: Bool, error: LocalizedMessage? = nil) async {
    monitor.onChange?(MicrophoneSnapshot(isActive: active, activeDeviceNames: [],
                                        inputDeviceNames: [], errorMessage: error))
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}

private final class TestMicrophoneMonitor: MicrophoneMonitoring {
  var onChange: ((MicrophoneSnapshot) -> Void)?
  func start() {}
  func stop() {}
  func refresh() {}
}
