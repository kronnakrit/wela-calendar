import BackgroundTasks
import Combine
import SwiftUI
import UIKit
import WelaCore
import WelaSync
import WelaUI
import WidgetKit

/// Wires the shared packages together for iOS: the store in the App Group container, sign-in,
/// the sync engine, notifications, widget reloads and background refresh.
@MainActor
final class AppModel: ObservableObject {
  nonisolated static var refreshTaskID: String {
    (Bundle.main.bundleIdentifier ?? "app.wela") + ".refresh"
  }

  let viewModel: PanelViewModel?
  let launchError: String?

  private var store: Store?
  private var engine: SyncEngine?
  private var scheduler: SyncScheduler?
  private var actions: AppActions?
  private var googleAuth: GoogleAuth?
  private let notifier = NotificationScheduler()
  private var notificationTask: Task<Void, Never>?
  private var observationTasks: [Task<Void, Never>] = []
  private var reloadTask: Task<Void, Never>?
  private var settingsObservers: Set<AnyCancellable> = []
  private let useMock = AppModel.useMockData

  init() {
    let useMock = Self.useMockData
    let store: Store
    do {
      store = try Self.makeStore(demo: useMock)
      #if DEBUG
        if useMock { try MockProvider.seed(into: store) }
      #endif
    } catch {
      viewModel = nil
      launchError = "Wela couldn't open its local database. \(error.localizedDescription)"
      return
    }
    SharedContainer.usesDemoStore = useMock

    let microsoftAuth = Self.configured("MSClientID").flatMap { try? MicrosoftAuth(clientId: $0) }
    let googleAuth = Self.configured("GoogleClientID").flatMap { id in
      Self.configured("GoogleRedirectScheme").map { GoogleAuth(clientId: id, redirectScheme: $0) }
    }
    let http = HTTPClient(
      transport: URLSession.shared,
      tokens: CompositeTokenProvider(microsoft: microsoftAuth, google: googleAuth))
    var providers: [ProviderKind: CalendarProvider] = [
      .microsoft: MicrosoftProvider(client: http), .google: GoogleProvider(client: http),
    ]
    #if DEBUG
      if useMock { providers[.mock] = MockCalendarProvider() }
    #endif
    let engine = SyncEngine(store: store, providers: providers)
    let actions = AppActions(
      store: store, engine: engine, microsoft: microsoftAuth, google: googleAuth)
    let settings = SettingsModel(defaults: SharedContainer.defaults)
    let viewModel = PanelViewModel(store: store, actions: actions, settings: settings)
    viewModel.accountActions = actions

    self.viewModel = viewModel
    self.launchError = nil
    self.store = store
    self.engine = engine
    self.actions = actions
    self.googleAuth = googleAuth

    // Mock data never syncs.
    if !useMock {
      let scheduler = SyncScheduler(engine: engine)
      scheduler.onReachabilityChange = { [weak viewModel] online in
        Task { @MainActor in viewModel?.isOffline = !online }
      }
      scheduler.start()
      self.scheduler = scheduler
    }
    actions.onAccountAdded = { [weak self] in self?.notifier.requestAuthorization() }
    startNotifications(store: store, settings: settings)
    startWidgetReloads(store: store, settings: settings)
  }

  // MARK: App lifecycle

  func scenePhaseChanged(_ phase: ScenePhase) {
    switch phase {
    case .active:
      Store.resume()
      viewModel?.appDidBecomeActive()
      if let scheduler { Task { await scheduler.syncNow() } }
    case .background:
      viewModel?.appDidEnterBackground()
      scheduleBackgroundRefresh()
      WidgetCenter.shared.reloadAllTimelines()
      // Release SQLite locks in the shared container before iOS suspends the app.
      Store.suspend()
    default:
      break
    }
  }

  /// `onOpenURL`: widget deep links and the OAuth redirects.
  func handle(_ url: URL) {
    if let link = WelaLink(url: url) {
      viewModel?.open(link)
    } else if MicrosoftAuth.handle(url) {
      return
    } else {
      googleAuth?.resume(with: url)
    }
  }

  // MARK: Background refresh

  /// Keeps widgets fresh while the app is closed. iOS decides when this actually runs.
  func scheduleBackgroundRefresh() {
    guard !useMock else { return }
    let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  func backgroundRefresh() async {
    scheduleBackgroundRefresh()
    guard let engine else { return }
    Store.resume()
    await engine.syncAll()
    WidgetCenter.shared.reloadAllTimelines()
    if UIApplication.shared.applicationState == .background { Store.suspend() }
  }

  // MARK: Widgets

  private func startWidgetReloads(store: Store, settings: SettingsModel) {
    let now = Date()
    let range = DateInterval(start: now.addingTimeInterval(-40 * 86_400), duration: 80 * 86_400)
    let events = store.observeEvents(in: range)
    let calendars = store.observeCalendars()
    let accounts = store.observeAccounts()
    observationTasks = [
      Task { [weak self] in for await _ in events { self?.reloadWidgetsSoon() } },
      Task { [weak self] in for await _ in calendars { self?.reloadWidgetsSoon() } },
      Task { [weak self] in for await _ in accounts { self?.reloadWidgetsSoon() } },
    ]
    settings.objectWillChange
      .sink { [weak self] _ in self?.reloadWidgetsSoon() }
      .store(in: &settingsObservers)
  }

  /// Coalesces bursts of changes (a sync writes many rows) into one reload.
  private func reloadWidgetsSoon() {
    reloadTask?.cancel()
    reloadTask = Task {
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  // MARK: Notifications

  private func startNotifications(store: Store, settings: SettingsModel) {
    notifier.configure()
    notifier.onJoin = { [weak self] id in
      if let event = try? store.event(id: id) { self?.actions?.join(event) }
    }
    let reload: @MainActor () async -> Void = { [notifier] in
      let now = Date()
      let events =
        (try? store.events(
          in: DateInterval(start: now.addingTimeInterval(-3600), duration: 3 * 86_400)))
        ?? []
      await notifier.reschedule(
        events: events, leadMinutes: settings.alertLeadMinutes,
        enabled: settings.notificationsEnabled)
    }
    // objectWillChange fires before the value lands, so hop a turn.
    settings.objectWillChange
      .sink { _ in
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(100))
          await reload()
        }
      }
      .store(in: &settingsObservers)
    notificationTask = Task {
      // Re-plan when events change; restart every 30 minutes so the 48-hour window slides.
      while !Task.isCancelled {
        let start = Date()
        let observer = Task {
          for await _ in store.observeEvents(
            in: DateInterval(start: start.addingTimeInterval(-3600), duration: 3 * 86_400))
          {
            await reload()
          }
        }
        try? await Task.sleep(for: .seconds(1800))
        observer.cancel()
      }
    }
  }

  // MARK: Setup helpers

  /// A non-empty Info.plist value (filled from Config/Secrets.xcconfig).
  private static func configured(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty
    else { return nil }
    return value
  }

  nonisolated private static var useMockData: Bool {
    #if DEBUG
      return CommandLine.arguments.contains("-UseMockData")
    #else
      return false
    #endif
  }

  private static func makeStore(demo: Bool) throws -> Store {
    try Store(path: SharedContainer.storeURL(demo: demo).path, observesSuspension: true)
  }
}
