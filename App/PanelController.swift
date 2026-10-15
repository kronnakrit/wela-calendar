import AppKit
import SwiftUI
import WelaUI

/// Borderless panel that can take keyboard focus without activating the app.
final class WelaPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    close()
  }
}

@MainActor
final class PanelController: NSObject {
  static let didOpen = Notification.Name("WelaPanelDidOpen")

  private let panel: WelaPanel
  private let viewModel: PanelViewModel
  private weak var statusButton: NSStatusBarButton?
  private var resignObserver: NSObjectProtocol?
  private var lastResignClose: Date = .distantPast

  var isVisible: Bool { panel.isVisible }

  init(viewModel: PanelViewModel, statusButton: NSStatusBarButton?) {
    self.viewModel = viewModel
    self.statusButton = statusButton
    panel = WelaPanel(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 640),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    super.init()
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let host = NSHostingView(rootView: PanelView(viewModel: viewModel))
    host.frame = NSRect(x: 0, y: 0, width: 340, height: 640)
    panel.contentView = host
    panel.setContentSize(NSSize(width: 340, height: 640))

    viewModel.onClose = { [weak self] in self?.close() }
    resignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.panelResignedKey() }
    }
  }

  deinit {
    if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
  }

  func toggle() {
    if panel.isVisible {
      close()
    } else if Date().timeIntervalSince(lastResignClose) > 0.25 {
      // Ignore the click that merely dismissed the panel via focus loss.
      show()
    }
  }

  func show() {
    viewModel.panelWillOpen()
    position()
    panel.makeKeyAndOrderFront(nil)
    NotificationCenter.default.post(name: Self.didOpen, object: nil)
  }

  func close() {
    guard panel.isVisible else { return }
    panel.orderOut(nil)
    viewModel.panelDidClose()
  }

  private func panelResignedKey() {
    guard !viewModel.isPinned else { return }
    lastResignClose = Date()
    close()
  }

  private func position() {
    let size = panel.frame.size
    var origin = NSPoint(x: 100, y: 100)
    var screen = NSScreen.main
    if let button = statusButton, let window = button.window {
      let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
      origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY - size.height - 6)
      screen = window.screen ?? screen
    }
    if let visible = screen?.visibleFrame {
      origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
      origin.y = max(origin.y, visible.minY + 8)
    }
    panel.setFrameOrigin(origin)
  }
}
