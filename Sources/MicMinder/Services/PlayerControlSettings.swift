import Foundation
final class PlayerControlSettings {
  static let shared = PlayerControlSettings()
  private let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  func isEnabled(_ identifier: String) -> Bool { defaults.object(forKey: "playerEnabled." + identifier) as? Bool ?? true }
  func setEnabled(_ enabled: Bool, for identifier: String) { defaults.set(enabled, forKey: "playerEnabled." + identifier) }
}
