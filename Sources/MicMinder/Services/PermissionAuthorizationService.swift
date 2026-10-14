import AppKit
import CoreServices
import Foundation

final class PermissionAuthorizationService {
  static let setupPlayers = ScriptableMediaPlayer.supportedPlayers

  static func connectionStatus(for player: ScriptableMediaPlayer) -> (authorized: Bool, denied: Bool) {
    let status = automationPermissionStatus(for: player, askUserIfNeeded: false)
    return (status == noErr, status == OSStatus(errAEEventNotPermitted))
  }

  static func hasAutomationPermission(for player: ScriptableMediaPlayer) -> Bool {
    automationPermissionStatus(for: player, askUserIfNeeded: false) == noErr
  }

  @discardableResult
  static func requestAutomationPermission(for player: ScriptableMediaPlayer) -> Bool {
    automationPermissionStatus(for: player, askUserIfNeeded: true) == noErr
  }

  static func openSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
      NSWorkspace.shared.open(url)
    }
  }

  private static func automationPermissionStatus(
    for player: ScriptableMediaPlayer, askUserIfNeeded: Bool
  ) -> OSStatus {
    guard player.isRunning else { return OSStatus(procNotFound) }
    let descriptor = NSAppleEventDescriptor(bundleIdentifier: player.bundleIdentifier)
    guard let target = descriptor.aeDesc else { return OSStatus(errAEEventNotPermitted) }
    return AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, askUserIfNeeded)
  }
}
