import AppKit
import Combine
import KeyboardShortcuts
import WelaCore
import WelaSync
import WelaUI

extension KeyboardShortcuts.Name {
  /// Control-Option-C. Not Control-Option-Space, which macOS uses to switch input sources.
  static let togglePanel = Self("togglePanel", default: .init(.c, modifiers: [.control, .option]))
}

/// Bridges the UI protocols to the sync engine, sign-in and the system (opening join links).
final class AppActions: EventActions, AccountActions {
  private let store: Store
  private let engine: SyncEngine
  var onAccountAdded: (@MainActor () -> Void)?
  private let microsoft: MicrosoftAuth?
  private let google: GoogleAuth?

  init(store: Store, engine: SyncEngine, microsoft: MicrosoftAuth?, google: GoogleAuth?) {
    self.store = store
    self.engine = engine
    self.microsoft = microsoft
    self.google = google
  }

  func join(_ event: EventInstance) {
    guard let url = event.joinURL, url.scheme?.lowercased() == "https" else { return }
    // Native app first (msteams:, zoommtg:), falling back to the https link.
    for candidate in JoinURLResolver.candidates(for: url, kind: event.conferenceKind) {
      // Provider-supplied links are untrusted: only https and the app schemes we build ourselves.
      let scheme = candidate.scheme?.lowercased()
      guard scheme == "https" || scheme == "msteams" || scheme == "zoommtg" else { continue }
      if scheme == "https" || NSWorkspace.shared.urlForApplication(toOpen: candidate) != nil {
        NSWorkspace.shared.open(candidate)
        return
      }
    }
  }

  func respond(to event: EventInstance, with response: ResponseStatus) async throws {
    try await engine.respond(to: event, with: response)
  }

  func refresh() async { await engine.syncAll() }

  func addAccount(provider: ProviderKind) async throws {
    let account: Account
    switch provider {
    case .microsoft:
      guard let microsoft else {
        throw AuthError.notConfigured("The Microsoft client ID (MS_CLIENT_ID)")
      }
      account = try await microsoft.signIn()
    case .google:
      guard let google else {
        throw AuthError.notConfigured("The Google client ID (GOOGLE_CLIENT_ID)")
      }
      account = try await google.signIn()
    case .mock:
      return
    }
    try store.saveAccount(account)
    await MainActor.run { onAccountAdded?() }
    await engine.sync(account: account)
  }

  func reconnect(_ account: Account) async throws {
    try await addAccount(provider: account.provider)
  }

  /// Deletes the account's cached data and its tokens.
  func removeAccount(_ account: Account) async throws {
    microsoft?.signOut(account)
    google?.signOut(account)
    try store.deleteAccount(id: account.id)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var store: Store?
  private var viewModel: PanelViewModel?
  private var statusItem: StatusItemController?
  private var panel: PanelController?
  private var actions: AppActions?
  private let settingsWindow = SettingsWindowController()
  private let notifier = NotificationScheduler()
  private var notificationTask: Task<Void, Never>?
  private var settingsObserver: AnyCancellable?
  private var googleAuth: GoogleAuth?
  private var scheduler: SyncScheduler?
  private var wakeObserver: NSObjectProtocol?

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

    let microsoftAuth = Self.configured("MSClientID").flatMap { try? MicrosoftAuth(clientId: $0) }
    let googleAuth = Self.configured("GoogleClientID").flatMap { id in
      Self.configured("GoogleRedirectScheme").map { GoogleAuth(clientId: id, redirectScheme: $0) }
    }
    self.googleAuth = googleAuth
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
    // Real accounts sync from M3 / M4; mock data never syncs.
    let scheduler: SyncScheduler? = useMock ? nil : SyncScheduler(engine: engine)
    let actions = AppActions(
      store: store, engine: engine, microsoft: microsoftAuth, google: googleAuth)
    self.actions = actions
    self.scheduler = scheduler
    scheduler?.start()
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { _ in
      Task { await scheduler?.syncNow() }
    }

    let viewModel = PanelViewModel(store: store, actions: actions)
    viewModel.accountActions = actions
    viewModel.hotkeyDescription =
      KeyboardShortcuts.getShortcut(for: .togglePanel).map { String(describing: $0) } ?? ""
    viewModel.onOpenSettings = { [weak self, weak viewModel] in
      guard let self, let viewModel else { return }
      self.panel?.close()
      self.settingsWindow.show(viewModel: viewModel)
    }
    startNotifications(store: store, settings: viewModel.settings)
    actions.onAccountAdded = { [weak self] in self?.notifier.requestAuthorization() }
    scheduler?.onReachabilityChange = { [weak viewModel] online in
      Task { @MainActor in viewModel?.isOffline = !online }
    }
    viewModel.onQuit = { NSApp.terminate(nil) }
    let statusItem = StatusItemController()
    let panel = PanelController(viewModel: viewModel, statusButton: statusItem.button)
    statusItem.onClick = { [weak panel] in panel?.toggle() }
    KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak panel] in panel?.toggle() }

    self.viewModel = viewModel
    self.statusItem = statusItem
    self.panel = panel
  }

  private func startNotifications(store: Store, settings: SettingsModel) {
    notifier.configure()
    notifier.onJoin = { [weak self] id in
      if let event = try? store.event(id: id) { self?.actions?.join(event) }
    }
    let reload: @MainActor () async -> Void = { [notifier] in
      let now = Date()
      let events =
        (try? store.events(in: DateInterval(start: now.addingTimeInterval(-3600), duration: 3 * 86_400)))
        ?? []
      await notifier.reschedule(
        events: events, leadMinutes: settings.alertLeadMinutes,
        enabled: settings.notificationsEnabled)
    }
    // Settings changes re-plan too (objectWillChange fires before the value lands, so hop a turn).
    settingsObserver = settings.objectWillChange.sink { _ in
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(100))
        await reload()
      }
    }
    notificationTask = Task {
      // Re-plan whenever events change, and restart the observation every 30 minutes so the
      // 48-hour window keeps sliding on a long-running menu bar app.
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

  /// Redirect URL from the Google sign-in sheet.
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { googleAuth?.resume(with: url) }
  }

  /// A non-empty Info.plist value (filled from Config/Secrets.xcconfig).
  private static func configured(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty
    else { return nil }
    return value
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
