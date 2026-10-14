import AppKit
import SwiftUI

final class PermissionAuthorizationWindowController: NSWindowController, NSWindowDelegate {
  private let connections: PlayerConnectionModel
  init(connections: PlayerConnectionModel) {
    self.connections = connections
    super.init(window: nil)
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func show(welcome: Bool = true) {
    if let window, window.isVisible { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
    let view = WelcomeView(connections: connections) { [weak self] in self?.close() }
    let host = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: host)
    window.title = "Welcome to MicMinder"
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.setContentSize(host.view.fittingSize)
    self.window = window
    connections.start()
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
  func windowWillClose(_ notification: Notification) { connections.stop(); UserDefaults.standard.set(true, forKey: "welcomeCompleted") }
}
