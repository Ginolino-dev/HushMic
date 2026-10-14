import AppKit
import Combine

final class PlayerConnectionModel: ObservableObject {
  struct Status: Equatable {
    var authorized: Bool
    var enabled: Bool
    var denied: Bool
  }
  @Published private(set) var statuses: [String: Status] = [:]
  @Published private(set) var requesting: String?
  @Published private(set) var errorMessage: String?
  private var timer: Timer?
  private var observers = 0
  private let appModel: AppModel
  init(appModel: AppModel) { self.appModel = appModel; refresh() }
  func start() {
    observers += 1; refresh()
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
  }
  func stop() {
    observers = max(0, observers - 1)
    if observers == 0 { timer?.invalidate(); timer = nil }
  }
  func refresh() {
    var updated: [String: Status] = [:]
    for player in PermissionAuthorizationService.setupPlayers {
      updated[player.bundleIdentifier] = Status(
        authorized: PermissionAuthorizationService.hasAutomationPermission(for: player),
        enabled: PlayerControlSettings.shared.isEnabled(player.bundleIdentifier),
        denied: PermissionAuthorizationService.isDenied(player))
    }
    if updated != statuses { statuses = updated }
  }
  func setEnabled(_ enabled: Bool, player: ScriptableMediaPlayer) {
    errorMessage = nil
    if !enabled {
      appModel.prepareToDisablePlayer(player)
      PlayerControlSettings.shared.setEnabled(false, for: player.bundleIdentifier)
      appModel.refresh(); refresh(); return
    }
    if statuses[player.bundleIdentifier]?.authorized == true {
      PlayerControlSettings.shared.setEnabled(true, for: player.bundleIdentifier)
      appModel.refresh(); refresh(); return
    }
    if statuses[player.bundleIdentifier]?.denied == true {
      PermissionAuthorizationService.openSettings(); return
    }
    requesting = player.bundleIdentifier
    let authorize = { [weak self] in
      DispatchQueue.global(qos: .userInitiated).async {
        let granted = PermissionAuthorizationService.requestAutomationPermission(for: player)
        DispatchQueue.main.async {
          guard let self else { return }
          PlayerControlSettings.shared.setEnabled(granted, for: player.bundleIdentifier)
          self.requesting = nil
          if !granted { self.errorMessage = "Permission wasn’t granted. You can try again in System Settings." }
          self.appModel.refresh(); self.refresh()
        }
      }
    }
    if player.isRunning { authorize(); return }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) else {
      requesting = nil; errorMessage = "Install \(player.displayName) to connect it."; return
    }
    let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
      DispatchQueue.main.async {
        if error != nil { self?.requesting = nil; self?.errorMessage = "Couldn’t open \(player.displayName)." }
        else { authorize() }
      }
    }
  }
}
