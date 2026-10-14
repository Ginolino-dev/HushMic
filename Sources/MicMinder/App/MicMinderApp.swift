import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let appModel = AppModel()
  private let localizer = AppLocalizer()
  private lazy var connections = PlayerConnectionModel(appModel: appModel)
  private var statusItem: NSStatusItem?
  private var panel: NSPanel?
  private var cancellables: Set<AnyCancellable> = []
  private var permissionWindowController: PermissionAuthorizationWindowController?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem
    statusItem.button?.image = MicMinderSymbol.image()
    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePanel)
    let host = NSHostingController(rootView: ControlPanelView(
      model: appModel, localizer: localizer, connections: connections,
      setup: { [weak self] in self?.panel?.close(); self?.showWelcome() },
      quit: { NSApp.terminate(nil) }))
    let panel = ControlPanelWindow(contentViewController: host)
    panel.title = "MicMinder"
    panel.styleMask = [.titled, .fullSizeContentView]
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.delegate = self
    panel.setContentSize(host.view.fittingSize)
    self.panel = panel
    appModel.onPermissionAuthorizationNeeded = { [weak self] in self?.showPanel() }
    appModel.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.updateStatus() }
    }.store(in: &cancellables)
    updateStatus()
    if CommandLine.arguments.contains("--show-panel") {
      DispatchQueue.main.async { [weak self] in self?.showPanel() }
    }
    if !UserDefaults.standard.bool(forKey: "welcomeCompleted") || CommandLine.arguments.contains("--show-setup") {
      DispatchQueue.main.async { [weak self] in self?.showWelcome() }
    }
  }
  private func updateStatus() {
    statusItem?.button?.toolTip = "MicMinder · " + appModel.statusTitle(localizer: localizer)
    statusItem?.button?.alphaValue = appModel.autoControlEnabled ? 1 : 0.45
  }
  @objc private func togglePanel() { if panel?.isVisible == true { panel?.close() } else { showPanel() } }
  private func showPanel() {
    guard let button = statusItem?.button, let panel else { return }
    if !panel.isVisible { connections.start() }
    connections.refresh()
    if let window = button.window, let screen = window.screen {
      let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
      let x = min(max(anchor.midX - panel.frame.width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - panel.frame.width - 8)
      panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - panel.frame.height - 8))
    }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }
  private func showWelcome() {
    if permissionWindowController == nil { permissionWindowController = PermissionAuthorizationWindowController(connections: connections) }
    permissionWindowController?.show()
  }
  func windowWillClose(_ notification: Notification) { connections.stop() }
  func windowDidResignKey(_ notification: Notification) {
    if !CommandLine.arguments.contains("--show-panel") { panel?.close() }
  }
  func applicationWillTerminate(_ notification: Notification) { appModel.prepareForTermination() }
}
private final class ControlPanelWindow: NSPanel {
  override func cancelOperation(_ sender: Any?) { close() }
}

@main
struct MicMinderApp {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
  }
}
