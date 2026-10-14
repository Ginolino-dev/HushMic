import AppKit
import SwiftUI

// Native window material follows the system appearance and accessibility settings.
final class GlassContentController<Content: View>: NSViewController {
  private let hosting: NSHostingController<Content>
  init(rootView: Content) {
    hosting = NSHostingController(rootView: rootView)
    super.init(nibName: nil, bundle: nil)
    addChild(hosting)
    preferredContentSize = hosting.view.fittingSize
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func loadView() {
    if #available(macOS 26, *) {
      let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: preferredContentSize))
      glass.style = .regular
      glass.cornerRadius = 20
      glass.contentView = hosting.view
      view = glass
    } else {
      let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: preferredContentSize))
      material.material = .popover
      material.blendingMode = .behindWindow
      material.state = .followsWindowActiveState
      material.wantsLayer = true
      material.layer?.cornerRadius = 20
      material.layer?.masksToBounds = true
      hosting.view.frame = material.bounds
      hosting.view.autoresizingMask = [.width, .height]
      material.addSubview(hosting.view)
      view = material
    }
  }
}
