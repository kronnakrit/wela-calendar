import SwiftUI

@main
struct WelaApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // The status item and panel are added in M2; Settings arrives in M6.
    Settings { EmptyView() }
  }
}
