import Foundation

// Isolate OS/media-app side effects from playback session decisions.
struct PlaybackAccess {
  var currentStatus: () -> MediaPlaybackStatus
  var state: (ScriptableMediaPlayer) -> ReliablePlaybackState?
  var pause: (ScriptableMediaPlayer) -> Bool
  var play: (ScriptableMediaPlayer) -> Bool
  var isRunning: (ScriptableMediaPlayer) -> Bool
  var hasAutomationPermission: (ScriptableMediaPlayer) -> Bool
  var isAccessibilityTrusted: () -> Bool
  var sendMediaKey: () -> Bool
  var identity: (ScriptableMediaPlayer) -> String? = { _ in nil }
  var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

  static func live() -> PlaybackAccess {
    let provider = MediaPlaybackStateProvider()
    let controller = MediaKeyPlaybackController()
    return PlaybackAccess(
      currentStatus: { provider.currentStatus() },
      state: { $0.playbackState() },
      pause: { $0.pause() },
      play: { $0.play() },
      isRunning: { $0.isRunning },
      hasAutomationPermission: { PermissionAuthorizationService.hasAutomationPermission(for: $0) },
      isAccessibilityTrusted: { AccessibilityPermission.isTrusted },
      sendMediaKey: { controller.sendPlayPause() },
      identity: { $0.playbackIdentity() }
    )
  }
}
