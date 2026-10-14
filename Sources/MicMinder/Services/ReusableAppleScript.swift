import Foundation

// Owns a stateless command, never its playback results or authorization.
final class ReusableAppleScript {
  private let source: String
  private var script: NSAppleScript?
  private var processIdentifier: Int32?
  private var executing = false
  init(source: String) { self.source = source }

  func execute(processIdentifier: Int32, authorized: () -> Bool) -> String? {
    precondition(Thread.isMainThread)
    // Apple events can reenter the run loop; never execute the same object twice.
    guard !executing else { return nil }
    executing = true
    defer { executing = false }
    guard authorized() else { return nil }
    if self.processIdentifier != processIdentifier {
      script = nil
      self.processIdentifier = processIdentifier
    }
    if script == nil { script = NSAppleScript(source: source) }
    var error: NSDictionary?
    guard let result = script?.executeAndReturnError(&error), error == nil else {
      script = nil
      return nil
    }
    return result.stringValue ?? ""
  }
}
