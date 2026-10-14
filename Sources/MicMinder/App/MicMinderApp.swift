import AppKit
import Combine
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let appModel = AppModel()
  private let localizer = AppLocalizer()
  private lazy var connections = PlayerConnectionModel(appModel: appModel)
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
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
      setup: { [weak self] in
        self?.popover.performClose(nil)
        DispatchQueue.main.async { self?.showWelcome() }
      },
      close: { [weak self] in self?.popover.performClose(nil) },
      quit: { NSApp.terminate(nil) }))
    popover.behavior = .transient
    popover.delegate = self
    popover.contentViewController = host
    popover.contentSize = host.view.fittingSize
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
  @objc private func togglePanel() { if popover.isShown { popover.performClose(nil) } else { showPanel() } }
  private func showPanel() {
    guard let button = statusItem?.button, !popover.isShown else { return }
    let started = ProcessInfo.processInfo.systemUptime
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    Logger(subsystem: "dev.ginolino.MicMinder", category: "Interface").notice("Native popover presented in \(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)) ms")
  }
  private func showWelcome() {
    if permissionWindowController == nil { permissionWindowController = PermissionAuthorizationWindowController(connections: connections) }
    permissionWindowController?.show()
  }
  func popoverDidShow(_ notification: Notification) { connections.start() }
  func popoverDidClose(_ notification: Notification) { connections.stop() }
  func applicationWillTerminate(_ notification: Notification) { appModel.prepareForTermination() }
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
