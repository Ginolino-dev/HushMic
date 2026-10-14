import Foundation

// Isolate OS/media-app side effects from playback session decisions.
struct PlaybackAccess {
  var currentStatus: () -> MediaPlaybackStatus
  var state: (ScriptableMediaPlayer) -> ReliablePlaybackState?
  var pause: (ScriptableMediaPlayer) -> Bool
  var play: (ScriptableMediaPlayer) -> Bool
  var isRunning: (ScriptableMediaPlayer) -> Bool
  var hasAutomationPermission: (ScriptableMediaPlayer) -> Bool
  var identity: (ScriptableMediaPlayer) -> String? = { _ in nil }
  var volume: (ScriptableMediaPlayer) -> Int? = { _ in nil }
  var setVolume: (ScriptableMediaPlayer, Int) -> Bool = { _, _ in false }
  var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

  static func live() -> PlaybackAccess {
    let provider = MediaPlaybackStateProvider()
    return PlaybackAccess(
      currentStatus: { provider.currentStatus() },
      state: { $0.playbackState() },
      pause: { $0.pause() },
      play: { $0.play() },
      isRunning: { $0.isRunning },
      hasAutomationPermission: { PlayerControlSettings.shared.isEnabled($0.bundleIdentifier) && PermissionAuthorizationService.hasAutomationPermission(for: $0) },
      identity: { $0.playbackIdentity() },
      volume: { $0.volume() },
      setVolume: { $0.setVolume($1) }
    )
  }
}
