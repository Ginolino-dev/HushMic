import XCTest
@testable import MicMinder

@MainActor
final class ReusableAppleScriptTests: XCTestCase {
  // A script-local counter distinguishes recompilation from execution of the
  // same compiled object without involving a media app or Automation prompts.
  private let counter = """
    property runs : 0
    set runs to runs + 1
    return runs as string
    """

  func testRepeatedExecutionReusesCompiledScriptButReturnsFreshResult() {
    let command = ReusableAppleScript(source: counter)
    XCTAssertEqual(command.execute(processIdentifier: 1, authorized: { true }), "1")
    XCTAssertEqual(command.execute(processIdentifier: 1, authorized: { true }), "2")
  }

  func testRestartedPlayerGetsFreshScript() {
    let command = ReusableAppleScript(source: counter)
    XCTAssertEqual(command.execute(processIdentifier: 1, authorized: { true }), "1")
    XCTAssertEqual(command.execute(processIdentifier: 2, authorized: { true }), "1")
  }

  func testCachedScriptStillRequiresFreshAuthorization() {
    let command = ReusableAppleScript(source: counter)
    XCTAssertEqual(command.execute(processIdentifier: 1, authorized: { true }), "1")
    XCTAssertNil(command.execute(processIdentifier: 1, authorized: { false }))
    XCTAssertEqual(command.execute(processIdentifier: 1, authorized: { true }), "2")
  }

  func testExecutionErrorDiscardsCachedScript() {
    let command = ReusableAppleScript(source: """
      property runs : 0
      set runs to runs + 1
      if runs is 2 then error "test failure"
      return runs as string
      """)
    XCTAssertEqual(command.execute(processIdentifier: 1, authorized: { true }), "1")
    XCTAssertNil(command.execute(processIdentifier: 1, authorized: { true }))
    XCTAssertEqual(command.execute(processIdentifier: 1, authorized: { true }), "1")
  }
}
