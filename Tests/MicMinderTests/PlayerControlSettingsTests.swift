import XCTest
@testable import MicMinder
final class PlayerControlSettingsTests: XCTestCase {
  func testExistingPlayersRemainEnabledUntilExplicitlyDisabled() {
    let name = "MicMinderTests.players." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = PlayerControlSettings(defaults: defaults)
    XCTAssertTrue(settings.isEnabled("com.spotify.client"))
    settings.setEnabled(false, for: "com.spotify.client")
    XCTAssertFalse(PlayerControlSettings(defaults: defaults).isEnabled("com.spotify.client"))
    XCTAssertTrue(settings.isEnabled("com.apple.Music"))
    settings.setEnabled(true, for: "com.spotify.client")
    XCTAssertTrue(settings.isEnabled("com.spotify.client"))
  }
}
