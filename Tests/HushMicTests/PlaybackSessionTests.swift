import XCTest
import Combine
@testable import HushMic

@MainActor
final class PlaybackSessionTests: XCTestCase {
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

  func testPermissionChangesStillPublishWithUnchangedMicrophoneState() async {
    let h = Harness()
    h.accessibilityGranted = false
    await h.emit(active: false)
    var updates = 0
    let subscription = h.model.objectWillChange.sink { updates += 1 }
    h.accessibilityGranted = true
    await h.emit(active: false)
    XCTAssertEqual(updates, 1)
    XCTAssertTrue(h.model.hasAccessibilityAccess)
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

  func testScriptablePlayerDoesNotNeedAccessibility() async {
    let h = Harness()
    h.accessibilityGranted = false
    await h.emit(active: true)
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "play:com.spotify.client"])
  }

  func testMissingPermissionsDoNotOpenWindowsFromMonitoring() async {
    let h = Harness()
    h.automationGranted = false
    h.accessibilityGranted = false
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

  func testManualMediaKeyRelinquishesAutomaticResume() async {
    let h = Harness()
    await h.emit(active: true)
    h.model.testPlayPause()
    await h.emit(active: false)
    XCTAssertEqual(h.commands, ["pause:com.spotify.client", "media-key"])
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
  let suiteName = "HushMicTests." + UUID().uuidString
  var model: AppModel!
  var state: ReliablePlaybackState
  var accessibilityGranted = true
  var automationGranted = true
  var useGlobalMediaKey = false
  var pauseSucceeds = true
  var pauseChangesState = true
  var identity: String? = "process-1:track-1"
  var authorizedPlayers: Set<String> = ["com.spotify.client"]
  var statusPlayer: ScriptableMediaPlayer?
  var commands: [String] = []
  var time: TimeInterval = 0

  init(state: ReliablePlaybackState = .playing) {
    self.state = state
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(true, forKey: "autoControlEnabled")
    let playback = PlaybackAccess(
      currentStatus: { [unowned self] in
        MediaPlaybackStatus(state: self.automationGranted ? self.state : nil,
                            player: self.useGlobalMediaKey ? nil : (self.statusPlayer ?? self.player),
                            authorizedPlayers: self.authorizedPlayers)
      },
      state: { [unowned self] _ in self.state },
      pause: { [unowned self] player in
        self.commands.append("pause:" + player.bundleIdentifier)
        if self.pauseSucceeds && self.pauseChangesState { self.state = .notPlaying }
        return self.pauseSucceeds
      },
      play: { [unowned self] player in
        self.commands.append("play:" + player.bundleIdentifier)
        self.state = .playing
        return true
      },
      isRunning: { _ in true },
      hasAutomationPermission: { [unowned self] _ in self.automationGranted },
      isAccessibilityTrusted: { [unowned self] in self.accessibilityGranted },
      sendMediaKey: { [unowned self] in
        self.commands.append("media-key")
        return true
      },
      identity: { [unowned self] _ in self.identity },
      now: { [unowned self] in self.time }
    )
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
