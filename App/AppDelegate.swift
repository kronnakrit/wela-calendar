import AppKit
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
  private let microsoft: MicrosoftAuth?
  private let google: GoogleAuth?

  init(store: Store, engine: SyncEngine, microsoft: MicrosoftAuth?, google: GoogleAuth?) {
    self.store = store
    self.engine = engine
    self.microsoft = microsoft
    self.google = google
  }

  func join(_ event: EventInstance) {
    guard let url = event.joinURL else { return }
    // Native app first (msteams:, zoommtg:), falling back to the https link.
    for candidate in JoinURLResolver.candidates(for: url, kind: event.conferenceKind) {
      let isWeb = candidate.scheme == "https" || candidate.scheme == "http"
      if isWeb || NSWorkspace.shared.urlForApplication(toOpen: candidate) != nil {
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
