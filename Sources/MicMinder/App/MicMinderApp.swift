import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appModel = AppModel()
  private let localizer = AppLocalizer()
  private var statusItem: NSStatusItem?
  private var displayedStatusIcon: String?
  private var cancellables: Set<AnyCancellable> = []
  private var permissionWindowController: PermissionAuthorizationWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    appModel.onPermissionAuthorizationNeeded = { [weak self] in
      self?.presentPermissionConfirmationIfNeeded()
    }

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem
    statusItem.menu = makeMenu()
    updateStatusIcon()
    if !UserDefaults.standard.bool(forKey: "welcomeCompleted") {
      DispatchQueue.main.async { [weak self] in self?.showPermissionWindow(welcome: true) }
    }

    appModel.objectWillChange
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.updateStatusIcon()
        }
      }
      .store(in: &cancellables)

  }

  private func updateStatusIcon() {
    guard let button = statusItem?.button else {
      return
    }

    let icon = appModel.menuBarIcon
    guard displayedStatusIcon != icon else { return }
    displayedStatusIcon = icon
    let image = NSImage(
      systemSymbolName: icon,
      accessibilityDescription: "MicMinder"
    )
    image?.isTemplate = true
    button.image = image
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self
    rebuild(menu)
    return menu
  }

  private func rebuild(_ menu: NSMenu) {
    menu.removeAllItems()
    menu.addItem(disabledItem(appModel.statusTitle(localizer: localizer)))
    menu.addItem(disabledItem(appModel.deviceTitle(localizer: localizer)))
    menu.addItem(disabledItem(appModel.lastActionTitle(localizer: localizer)))
    menu.addItem(.separator())

    menu.addItem(actionItem(
      title: localizer.text("menu.auto_control"),
      action: #selector(toggleAutoControl),
      state: appModel.autoControlEnabled ? .on : .off
    ))
    menu.addItem(actionItem(
      title: localizer.text("menu.fade_music"),
      action: #selector(toggleFadeMusic),
      state: appModel.fadeMusicEnabled ? .on : .off
    ))
    menu.addItem(actionItem(
      title: localizer.text("menu.launch_at_login"),
      action: #selector(toggleLaunchAtLogin),
      state: appModel.launchAtLoginEnabled ? .on : .off
    ))
    menu.addItem(.separator())

    let languageItem = NSMenuItem(title: localizer.text("menu.language"), action: nil, keyEquivalent: "")
    languageItem.submenu = makeLanguageMenu()
    menu.addItem(languageItem)
    menu.addItem(.separator())

    menu.addItem(actionItem(title: localizer.text("menu.refresh"), action: #selector(refresh)))
    menu.addItem(actionItem(title: localizer.text("menu.playback_permissions"), action: #selector(openPlaybackPermissions)))
    menu.addItem(actionItem(title: localizer.text("menu.github"), action: #selector(openGitHub)))
    menu.addItem(.separator())
    menu.addItem(disabledItem(versionTitle()))
    menu.addItem(actionItem(title: localizer.text("menu.quit"), action: #selector(quit)))
  }

  private func makeLanguageMenu() -> NSMenu {
    let menu = NSMenu()

    for language in AppLanguage.allCases {
      let item = actionItem(
        title: languageTitle(language),
        action: #selector(selectLanguage(_:)),
        state: localizer.language == language ? .on : .off
      )
      item.representedObject = language.rawValue
      menu.addItem(item)
    }

    return menu
  }

  private func disabledItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  private func actionItem(title: String, action: Selector, state: NSControl.StateValue = .off) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.state = state
    return item
  }

  private func languageTitle(_ language: AppLanguage) -> String {
    switch language {
    case .automatic:
      return localizer.text("language.automatic")
    case .zhHans:
      return localizer.text("language.zh_hans")
    case .en:
      return localizer.text("language.english")
    }
  }

  private func versionTitle() -> String {
    let rawVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let version = rawVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

    if let version, !version.isEmpty {
      return localizer.text("menu.version %@", version)
    }

    return localizer.text("menu.version %@", "dev")
  }

  @objc private func toggleAutoControl() {
    appModel.autoControlEnabled.toggle()
  }

  @objc private func toggleFadeMusic() { appModel.fadeMusicEnabled.toggle() }

  func applicationWillTerminate(_ notification: Notification) { appModel.prepareForTermination() }

  @objc private func toggleLaunchAtLogin() {
    appModel.launchAtLoginEnabled.toggle()
  }

  @objc private func selectLanguage(_ sender: NSMenuItem) {
    guard
      let rawLanguage = sender.representedObject as? String,
      let language = AppLanguage(rawValue: rawLanguage)
    else {
      return
    }

    localizer.language = language
  }

  @objc private func refresh() {
    appModel.refresh()
  }

  @objc private func openPlaybackPermissions() {
    presentPermissionConfirmationIfNeeded()
  }

  @objc private func openGitHub() {
    guard let url = URL(string: "https://github.com/Ginolino-dev/MicMinder") else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func presentPermissionConfirmationIfNeeded() {
    // Only explicit menu/button actions open this nonmodal window.
    DispatchQueue.main.async { [weak self] in self?.showPermissionWindow() }
  }

  private func showPermissionWindow(welcome: Bool = false) {
    if permissionWindowController == nil {
      permissionWindowController = PermissionAuthorizationWindowController(
        appModel: appModel,
        localizer: localizer
      )
    }

    permissionWindowController?.show(welcome: welcome)
  }
}

extension AppDelegate: NSMenuDelegate {
  func menuWillOpen(_ menu: NSMenu) {
    rebuild(menu)
  }
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
