import SwiftUI
import WelaUI

@main
struct WelaMobileApp: App {
  @StateObject private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    let model = self.model
    WindowGroup {
      Group {
        if let viewModel = model.viewModel {
          MobileRootView(viewModel: viewModel)
        } else {
          Text(model.launchError ?? "Wela couldn't start.")
            .multilineTextAlignment(.center)
            .padding(32)
        }
      }
      .onOpenURL { model.handle($0) }
      .onChange(of: scenePhase, initial: true) { _, phase in model.scenePhaseChanged(phase) }
    }
    .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
      await model.backgroundRefresh()
    }
  }
}
