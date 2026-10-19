import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import WelaUI

private struct SettingsRoot: View {
  @ObservedObject var vm: PanelViewModel
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

  var body: some View {
    SettingsView(
      viewModel: vm, hotkeyRecorder: AnyView(KeyboardShortcuts.Recorder(for: .togglePanel)),
      launchAtLogin: Binding(
        get: { launchAtLogin },
        set: { newValue in
          do {
            if newValue {
              try SMAppService.mainApp.register()
            } else {
              try SMAppService.mainApp.unregister()
            }
            launchAtLogin = newValue
          } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
          }
        }))
  }
}

@MainActor
final class SettingsWindowController {
  private var window: NSWindow?

  func show(viewModel: PanelViewModel) {
    if window == nil {
      let w = NSWindow(
        contentViewController: NSHostingController(rootView: SettingsRoot(vm: viewModel)))
      w.title = "Wela Settings"
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.center()
      window = w
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
