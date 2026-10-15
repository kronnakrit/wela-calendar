import AppKit
import KeyboardShortcuts
import WelaCore
import WelaSync
import WelaUI

extension KeyboardShortcuts.Name {
  /// Control-Option-C. Not Control-Option-Space, which macOS uses to switch input sources.
  static let togglePanel = Self("togglePanel", default: .init(.c, modifiers: [.control, .option]))
}

/// Minimal actions until the sync engine exists (M5).
final class LocalEventActions: EventActions {
  func join(_ event: EventInstance) {
    if let url = event.joinURL { NSWorkspace.shared.open(url) }
  }

  func respond(to event: EventInstance, with response: ResponseStatus) async throws {}
  func refresh() async {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var store: Store?
  private var viewModel: PanelViewModel?
  private var statusItem: StatusItemController?
  private var panel: PanelController?
  private let actions = LocalEventActions()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    // Unit tests host the app; don't build UI there.
    if NSClassFromString("XCTestCase") != nil { return }

    let useMock = Self.useMockData
    do {
      let store = try Self.makeStore(inMemory: useMock)
      #if DEBUG
        if useMock { try MockProvider.seed(into: store) }
      #endif
      self.store = store
    } catch {
      NSLog("Wela: could not open the local store: \(error.localizedDescription)")
      return
    }
    guard let store else { return }

    let viewModel = PanelViewModel(store: store, actions: actions)
    viewModel.onQuit = { NSApp.terminate(nil) }
    let statusItem = StatusItemController()
    let panel = PanelController(viewModel: viewModel, statusButton: statusItem.button)
    statusItem.onClick = { [weak panel] in panel?.toggle() }
    KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak panel] in panel?.toggle() }

    self.viewModel = viewModel
    self.statusItem = statusItem
    self.panel = panel
  }

  private static var useMockData: Bool {
    #if DEBUG
      return CommandLine.arguments.contains("-UseMockData")
    #else
      return false
    #endif
  }

  private static func makeStore(inMemory: Bool) throws -> Store {
    if inMemory { return try Store() }
    let dir = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent("Wela", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try Store(path: dir.appendingPathComponent("wela.sqlite").path)
  }
}
