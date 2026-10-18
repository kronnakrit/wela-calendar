import Combine
import Foundation
import SwiftUI
import WelaCore

@MainActor
public final class PanelViewModel: ObservableObject {
  public let store: Store
  public let settings: SettingsModel
  /// Shown on the first-run screen, e.g. "Control-Option-C".
  public var hotkeyDescription = ""
  public weak var actions: EventActions?
  public weak var accountActions: AccountActions?
  public var calendar: Calendar { didSet { restartObservation() } }
  public var locale: Locale
  public var options = AgendaOptions() { didSet { objectWillChange.send() } }
  public var onClose: () -> Void = {}
  public var onOpenSettings: (() -> Void)?
  public var onQuit: (() -> Void)?

  @Published public var displayedMonth: Date { didSet { restartObservation() } }
  @Published public var selectedDay: Date
  @Published public var searchText = "" { didSet { updateSearch() } }
  @Published public private(set) var searchGroups: [SearchDayGroup] = []
  @Published public private(set) var events: [EventInstance] = []
  @Published public private(set) var calendars: [CalendarInfo] = []
  @Published public var now: Date
  @Published public var selectedEventID: String?
  @Published public var detailEventID: String?
  @Published public var isPinned = false
  @Published public private(set) var accounts: [Account] = []
  @Published public private(set) var lastSyncedAt: Date?
  @Published public var isOffline = false
  @Published public private(set) var rsvpError: String?

  private var eventsTask: Task<Void, Never>?
  private var calendarsTask: Task<Void, Never>?
  private var accountsTask: Task<Void, Never>?
  private var lastClosedAt: Date?
  private let rememberMonthFor: TimeInterval = 5 * 60

  private let baseCalendar: Calendar
  private var cancellables: Set<AnyCancellable> = []
  @Published public private(set) var connectError: String?

  public init(
    store: Store, actions: EventActions? = nil, calendar: Calendar = .current,
    locale: Locale = .current, now: Date = Date(), settings: SettingsModel? = nil
  ) {
    self.store = store
    self.settings = settings ?? SettingsModel()
    self.baseCalendar = calendar
    self.accounts = (try? store.accounts()) ?? []
    self.actions = actions
    self.calendar = calendar
    self.locale = locale
    self.now = now
    self.displayedMonth = now
    self.selectedDay = calendar.startOfDay(for: now)
    restartObservation()
    observeCalendars()
    observeAccounts()
    applySettings()
    self.settings.objectWillChange
      .sink { [weak self] _ in DispatchQueue.main.async { self?.applySettings() } }
      .store(in: &cancellables)
  }

  private func applySettings() {
    let cal = settings.makeCalendar(base: baseCalendar)
    if cal != calendar {
      calendar = cal
      selectedDay = cal.startOfDay(for: selectedDay)
    }
    options = settings.agendaOptions
    objectWillChange.send()
  }

  public func connect(_ provider: ProviderKind) {
    connectError = nil
    Task { [weak self] in
      do {
        try await self?.accountActions?.addAccount(provider: provider)
      } catch {
        self?.connectError = error.localizedDescription
      }
    }
  }

  public func remove(_ account: Account) {
    Task { [weak self] in try? await self?.accountActions?.removeAccount(account) }
  }

  public func setCalendarColor(_ id: String, hex: String?) {
    try? store.setCalendarColor(id: id, hex: hex)
  }

  deinit {
    eventsTask?.cancel()
    calendarsTask?.cancel()
    accountsTask?.cancel()
  }

  // MARK: Observation

  private func restartObservation() {
    eventsTask?.cancel()
    let cells = gridCells
    guard let first = cells.first?.date, let last = cells.last?.date else { return }
    let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
    let stream = store.observeEvents(in: DateInterval(start: first, end: max(first, end)))
    eventsTask = Task { [weak self] in
      for await events in stream {
        guard let self else { return }
        self.events = events
        self.lastSyncedAt = try? self.store.lastSyncedAt()
      }
    }
  }

  private func observeCalendars() {
    let stream = store.observeCalendars()
    calendarsTask = Task { [weak self] in
      for await calendars in stream {
        guard let self else { return }
        self.calendars = calendars
      }
    }
  }

  private func observeAccounts() {
    let stream = store.observeAccounts()
    accountsTask = Task { [weak self] in
      for await accounts in stream {
        guard let self else { return }
        self.accounts = accounts
        self.lastSyncedAt = try? self.store.lastSyncedAt()
      }
    }
  }

  // MARK: Lifecycle (called by the panel controller)

  public func panelWillOpen() {
    now = Date()
    if let closed = lastClosedAt, now.timeIntervalSince(closed) > rememberMonthFor {
      goToToday()
    } else if lastClosedAt == nil {
      goToToday()
    }
    searchText = ""
    detailEventID = nil
  }

  public func panelDidClose() {
    lastClosedAt = Date()
  }

  public func tick() { now = Date() }

  // MARK: Derived state

  public var gridCells: [DayCell] {
    CalendarMath.monthGrid(for: displayedMonth, calendar: calendar, now: now)
  }

  public var monthName: String {
    CalendarMath.monthName(for: displayedMonth, calendar: calendar, locale: locale)
  }
  public var yearString: String {
    CalendarMath.yearString(for: displayedMonth, calendar: calendar, locale: locale)
  }
  public var weekdaySymbols: [String] { CalendarMath.weekdaySymbols(calendar: calendar) }

  /// Index (in grid order) of today's weekday, to tint its label.
  public var todayWeekdayIndex: Int {
    (calendar.component(.weekday, from: now) - calendar.firstWeekday + 7) % 7
  }

  var visibleCalendarIDs: Set<String> { Set(calendars.filter(\.isVisible).map(\.id)) }

  var calendarColors: [String: String] {
    Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.effectiveColorHex) })
  }

  func color(for calendarId: String) -> Color {
    guard let cal = calendars.first(where: { $0.id == calendarId }) else { return Theme.softInk }
    return Theme.calendarColor(hex: cal.effectiveColorHex, desaturate: cal.userColorHex != nil)
  }

  func calendarName(for id: String) -> String { calendars.first { $0.id == id }?.name ?? "" }

  func agendaFor(_ day: Date) -> Agenda {
    AgendaBuilder.agenda(
      for: day, events: events, visibleCalendarIds: visibleCalendarIDs, options: options,
      calendar: calendar)
  }

  public var agenda: Agenda { agendaFor(selectedDay) }

  /// All-day items first, then timed; the order used for Up/Down navigation.
  var agendaItems: [AgendaItem] {
    let a = agenda
    return a.allDay + a.timed
  }

  var nowItem: AgendaItem? {
    guard calendar.isDate(selectedDay, inSameDayAs: now) else { return nil }
    return agenda.timed.first { !$0.isCancelled && $0.event.start <= now && now < $0.event.end }
  }

  /// The timed row the agenda scrolls to: the current event, else the next one.
  var focusItemID: String? {
    guard calendar.isDate(selectedDay, inSameDayAs: now) else { return nil }
    let timed = agenda.timed
    return (timed.first { $0.event.end > now } ?? timed.first)?.id
  }

  func dots(for day: Date) -> [Color] {
    DotSummary.dots(
      for: day, events: events, calendarColors: calendarColors,
      visibleCalendarIds: visibleCalendarIDs, options: options, calendar: calendar
    ).map { Theme.calendarColor(hex: $0) }
  }

  public var agendaTitle: (label: String, date: String) {
    let startOfToday = calendar.startOfDay(for: now)
    let diff = calendar.dateComponents([.day], from: startOfToday, to: selectedDay).day ?? 0
    let label: String
    switch diff {
    case 0: label = "TODAY"
    case 1: label = "TOMORROW"
    default: label = formatted(selectedDay, "EEEE").uppercased(with: locale)
    }
    return (label, formatted(selectedDay, "d MMMM"))
  }

  func formatted(_ date: Date, _ template: String) -> String {
    let f = DateFormatter()
    f.calendar = calendar
    f.locale = locale
    f.timeZone = calendar.timeZone
    f.setLocalizedDateFormatFromTemplate(template)
    return f.string(from: date)
  }

  func timeString(_ date: Date) -> String { formatted(date, settings.timeTemplate) }

  func timeRange(for event: EventInstance) -> String {
    event.isAllDay
      ? "All day"
      : "\(timeString(event.start))–\(timeString(event.end))"
  }

  func minutesLeft(_ event: EventInstance) -> Int {
    max(0, Int((event.end.timeIntervalSince(now) / 60).rounded(.up)))
  }

  func isPast(_ item: AgendaItem) -> Bool { !item.event.isAllDay && item.event.end <= now }

  // MARK: Navigation

  public func goToToday() {
    now = Date()
    displayedMonth = now
    selectedDay = calendar.startOfDay(for: now)
    selectedEventID = nil
  }

  public func moveMonth(by n: Int) {
    guard let m = calendar.date(byAdding: .month, value: n, to: displayedMonth) else { return }
    displayedMonth = m
    // Keep the selection inside the visible month.
    selectedDay = calendar.dateInterval(of: .month, for: m)?.start ?? calendar.startOfDay(for: m)
    selectedEventID = nil
  }

  public func moveSelection(days: Int) {
    guard let d = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
    select(day: d)
  }

  public func select(day: Date) {
    selectedDay = calendar.startOfDay(for: day)
    selectedEventID = nil
    if !calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
      displayedMonth = day
    }
  }

  public func moveEventSelection(by n: Int) {
    let items = agendaItems
    guard !items.isEmpty else { return }
    let current = items.firstIndex { $0.id == selectedEventID }
    let next: Int
    if let current {
      next = min(max(current + n, 0), items.count - 1)
    } else {
      next = n >= 0 ? 0 : items.count - 1
    }
    selectedEventID = items[next].id
  }

  public func openSelectedEvent() {
    if let id = selectedEventID { detailEventID = id }
  }

  public func joinSelected() {
    let item = agendaItems.first { $0.id == selectedEventID } ?? nowItem
    if let event = item?.event { join(event) }
  }

  public func join(_ event: EventInstance) {
    actions?.join(event)
  }

  public func closeDetail() { detailEventID = nil }

  func canRespond(to event: EventInstance) -> Bool {
    !event.attendees.isEmpty && event.myResponse != .organizer
  }

  /// Accept / Tentative / Decline. The row updates immediately; a failure rolls it back and
  /// shows a message for five seconds.
  public func respond(to event: EventInstance, with response: ResponseStatus) {
    Task { [weak self] in
      do {
        try await self?.actions?.respond(to: event, with: response)
      } catch {
        self?.rsvpError = "Couldn't send your response"
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        self?.rsvpError = nil
      }
    }
  }

  var accountNeedingSignIn: Account? { accounts.first { $0.status == .needsSignIn } }

  public func reconnect(_ account: Account) {
    Task { [weak self] in try? await self?.accountActions?.reconnect(account) }
  }

  /// "Last synced 14:05" when offline or an account is erroring; nil otherwise.
  var staleSyncText: String? {
    let erroring = accounts.contains {
      if case .error = $0.status { return true }
      return false
    }
    guard isOffline || erroring, let last = lastSyncedAt else { return nil }
    return "Last synced \(formatted(last, settings.timeTemplate))"
  }

  public func setCalendarVisible(_ id: String, _ visible: Bool) {
    try? store.setCalendarVisibility(id: id, isVisible: visible)
  }

  public func refresh() {
    Task { await actions?.refresh() }
  }

  // MARK: Search

  private func updateSearch() {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else {
      searchGroups = []
      return
    }
    let start = calendar.date(byAdding: .day, value: -90, to: now) ?? now
    let end = calendar.date(byAdding: .day, value: 365, to: now) ?? now
    searchGroups =
      (try? store.search(
        query, in: DateInterval(start: start, end: end), calendarIds: visibleCalendarIDs,
        calendar: calendar)) ?? []
  }

  var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

  func event(id: String) -> EventInstance? {
    events.first { $0.id == id } ?? (try? store.event(id: id))
  }
}
