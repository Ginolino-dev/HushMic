import AppKit

final class PermissionAuthorizationWindowController: NSWindowController, NSWindowDelegate {
  private let appModel: AppModel
  private let localizer: AppLocalizer
  private let permissionStack = NSStackView()
  private var refreshTimer: Timer?
  private var welcome = false
  private var requesting: String?
  private var requestFailed = false

  init(appModel: AppModel, localizer: AppLocalizer) {
    self.appModel = appModel
    self.localizer = localizer
    super.init(window: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show(welcome: Bool = false) {
    if window?.isVisible == true { bringToFront(); return }
    self.welcome = welcome
    makeWindow()
    refreshPermissions()
    window?.center()
    bringToFront()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.refreshPermissions()
    }
  }

  private func bringToFront() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    window?.orderFrontRegardless()
  }

  func windowWillClose(_ notification: Notification) {
    refreshTimer?.invalidate()
    refreshTimer = nil
    if welcome { UserDefaults.standard.set(true, forKey: "welcomeCompleted") }
    appModel.refresh()
  }

  private func makeWindow() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = localizer.text(welcome ? "setup.welcome" : "permission.window.title")
    window.delegate = self
    window.isReleasedWhenClosed = false
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    let heading = label(localizer.text(welcome ? "setup.welcome" : "setup.players"), size: 20)
    heading.font = .boldSystemFont(ofSize: 20)
    stack.addArrangedSubview(heading)
    stack.addArrangedSubview(label(localizer.text("setup.message"), size: 13))
    permissionStack.arrangedSubviews.forEach { permissionStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    permissionStack.orientation = .vertical
    permissionStack.alignment = .leading
    permissionStack.spacing = 14
    stack.addArrangedSubview(permissionStack)
    stack.addArrangedSubview(label(localizer.text("setup.menu_hint"), size: 12))
    let buttons = NSStackView()
    buttons.orientation = .horizontal
    buttons.spacing = 10
    if welcome {
      buttons.addArrangedSubview(PermissionActionButton(title: localizer.text("setup.later")) { [weak self] in self?.close() })
    }
    buttons.addArrangedSubview(PermissionActionButton(title: localizer.text(welcome ? "setup.start" : "permission.window.confirm")) { [weak self] in self?.close() })
    stack.addArrangedSubview(buttons)
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20)
    ])
    self.window = window
  }

  private func label(_ text: String, size: CGFloat) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size)
    return field
  }

  private func refreshPermissions() {
    permissionStack.arrangedSubviews.forEach { permissionStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    for player in PermissionAuthorizationService.setupPlayers {
      let connected = PermissionAuthorizationService.hasAutomationPermission(for: player)
      let denied = PermissionAuthorizationService.isDenied(player)
      let busy = requesting == player.bundleIdentifier
      let title = player.bundleIdentifier == "com.apple.Music" ? "Apple Music" : player.displayName
      let status = busy ? "setup.connecting" : connected ? "setup.connected" : denied ? "setup.denied" : "setup.not_connected"
      let text = NSStackView()
      text.orientation = .vertical
      text.alignment = .leading
      text.addArrangedSubview(label(title, size: 14))
      text.addArrangedSubview(label(localizer.text(status), size: 12))
      let row = NSStackView()
      row.orientation = .horizontal
      row.spacing = 14
      row.addArrangedSubview(text)
      if !connected {
        let button = PermissionActionButton(title: localizer.text(denied ? "setup.settings" : "setup.enable")) { [weak self] in
          if denied { PermissionAuthorizationService.openSettings() }
          else { self?.connect(player) }
        }
        button.isEnabled = requesting == nil
        row.addArrangedSubview(button)
      }
      row.widthAnchor.constraint(equalToConstant: 472).isActive = true
      text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      permissionStack.addArrangedSubview(row)
    }
    if requestFailed { permissionStack.addArrangedSubview(label(localizer.text("setup.failed"), size: 12)) }
  }

  private func connect(_ player: ScriptableMediaPlayer) {
    requesting = player.bundleIdentifier
    requestFailed = false
    refreshPermissions()
    let authorize = { [weak self] in
      DispatchQueue.global(qos: .userInitiated).async {
        PermissionAuthorizationService.requestAutomationPermission(for: player)
        DispatchQueue.main.async {
          self?.requesting = nil
          self?.appModel.refresh()
          self?.refreshPermissions()
        }
      }
    }
    if player.isRunning { authorize(); return }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) else {
      requesting = nil; requestFailed = true; refreshPermissions(); return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
      DispatchQueue.main.async {
        if error != nil {
          self?.requesting = nil; self?.requestFailed = true; self?.refreshPermissions()
        } else { authorize() }
      }
    }
  }
}

private final class PermissionActionButton: NSButton {
  private let handler: () -> Void
  init(title: String, action: @escaping () -> Void) {
    handler = action
    super.init(frame: .zero)
    self.title = title
    bezelStyle = .rounded
    target = self
    self.action = #selector(invoke)
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func invoke() { handler() }
}
