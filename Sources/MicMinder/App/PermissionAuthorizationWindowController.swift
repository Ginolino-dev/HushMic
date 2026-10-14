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
  func show() {
    if let window, window.isVisible { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
    let view = WelcomeView(connections: connections) { [weak self] in self?.close() }
    let host = GlassContentController(rootView: view)
    let window = NSWindow(contentViewController: host)
    window.title = "Welcome to MicMinder"
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = .clear
    window.isOpaque = false
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.setContentSize(host.preferredContentSize)
    self.window = window
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    connections.start()
  }
  func windowWillClose(_ notification: Notification) { connections.stop(); UserDefaults.standard.set(true, forKey: "welcomeCompleted") }
}
