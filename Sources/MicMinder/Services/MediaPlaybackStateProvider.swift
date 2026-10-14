import AppKit
import Foundation

enum ReliablePlaybackState {
  case playing
  case notPlaying
  case stopped
}

struct MediaPlaybackStatus {
  var state: ReliablePlaybackState?
  var player: ScriptableMediaPlayer?
  var authorizedPlayers: Set<String> = []
}

final class MediaPlaybackStateProvider {
  func currentStatus() -> MediaPlaybackStatus {
    var pausedPlayer: ScriptableMediaPlayer?
    let authorizedPlayers = ScriptableMediaPlayer.supportedPlayers.filter {
      $0.isRunning && PermissionAuthorizationService.hasAutomationPermission(for: $0)
    }
    let authorizedIdentifiers = Set(authorizedPlayers.map(\.bundleIdentifier))

    // Background checks never request Automation consent. Only query players
    // the user has already authorized through the permissions window.
    for player in authorizedPlayers {
      guard let state = player.playbackState() else { continue }
      if state == .playing {
        return MediaPlaybackStatus(state: .playing, player: player,
                                   authorizedPlayers: authorizedIdentifiers)
      }
      pausedPlayer = pausedPlayer ?? player
    }

    if let pausedPlayer {
      return MediaPlaybackStatus(state: .notPlaying, player: pausedPlayer,
                                 authorizedPlayers: authorizedIdentifiers)
    }
    return MediaPlaybackStatus(state: nil, player: nil, authorizedPlayers: authorizedIdentifiers)
  }
}

struct ScriptableMediaPlayer: Equatable {
  static let supportedPlayers = [
    ScriptableMediaPlayer(bundleIdentifier: "com.apple.Music", displayName: "Music"),
    ScriptableMediaPlayer(bundleIdentifier: "com.spotify.client", displayName: "Spotify"),
    ScriptableMediaPlayer(bundleIdentifier: "com.apple.iTunes", displayName: "iTunes")
  ]

  var bundleIdentifier: String
  var displayName: String

  var isRunning: Bool {
    NSWorkspace.shared.runningApplications.contains { application in
      application.bundleIdentifier == bundleIdentifier
    }
  }

  func playbackState() -> ReliablePlaybackState? {
    guard let value = runAppleScript("tell application id \"\(bundleIdentifier)\" to return player state as string") else {
      return nil
    }

    switch value.lowercased() {
    case "playing":
      return .playing
    case "paused":
      return .notPlaying
    case "stopped":
      return .stopped
    default:
      return nil
    }
  }

  func pause() -> Bool {
    runAppleScript("tell application id \"\(bundleIdentifier)\" to pause") != nil
  }

  func playbackIdentity() -> String? {
    guard let application = NSWorkspace.shared.runningApplications.first(where: {
      $0.bundleIdentifier == bundleIdentifier
    }) else { return nil }
    let property = bundleIdentifier == "com.spotify.client" ? "id" : "persistent ID"
    guard let track = runAppleScript(
      "tell application id \"\(bundleIdentifier)\" to return \(property) of current track as string"
    ), !track.isEmpty else { return nil }
    return "\(application.processIdentifier):\(track)"
  }

  func play() -> Bool {
    runAppleScript("tell application id \"\(bundleIdentifier)\" to play") != nil
  }

  func volume() -> Int? {
    guard let value = runAppleScript("tell application id \"\(bundleIdentifier)\" to return sound volume"),
          let volume = Int(value), (0...100).contains(volume) else { return nil }
    return volume
  }

  func setVolume(_ volume: Int) -> Bool {
    guard (0...100).contains(volume) else { return false }
    return runAppleScript("tell application id \"\(bundleIdentifier)\" to set sound volume to \(volume)") != nil
  }

  private func runAppleScript(_ source: String) -> String? {
    guard isRunning, PermissionAuthorizationService.hasAutomationPermission(for: self) else {
      return nil
    }
    var error: NSDictionary?
    guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
      return nil
    }

    return descriptor.stringValue ?? ""
  }
}
