import Foundation
import WelaCore

/// One event as a widget shows it.
public struct WidgetItem: Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let start: Date
  public let end: Date
  public let isAllDay: Bool
  public let location: String?
  public let colorHex: String
  public let hasJoin: Bool
  /// Not answered yet, or tentative: drawn with a dashed mark like the agenda.
  public let isTentative: Bool
  public let multiDayLabel: String?
}

public struct WidgetDay: Hashable, Sendable {
  public let day: Date
  public let items: [WidgetItem]
}

/// Everything a Wela widget draws at one moment. Built from the local store, so widgets never
/// touch the network.
public struct WidgetSnapshot: Hashable, Sendable {
  public let date: Date
  public let calendar: Calendar
  public let locale: Locale
  public let timeTemplate: String
  public let hasAccounts: Bool
  /// Today first (always present, possibly empty; timed events that have ended are dropped),
  /// then the following days that have events, up to a week ahead.
  public let days: [WidgetDay]
  public let monthCells: [DayCell]
  /// Dot colours per grid cell, keyed by the cell's date.
  public let dots: [Date: [String]]

  public var today: WidgetDay { days[0] }

  /// The event in progress, else the next one to start (today or later). All-day events count
  /// only when nothing timed is left.
  public var upNext: WidgetItem? {
    let timed = days.flatMap(\.items).filter { !$0.isAllDay }
    return timed.first ?? days.flatMap(\.items).first
  }

  public func isNow(_ item: WidgetItem) -> Bool {
    !item.isAllDay && item.start <= date && date < item.end
  }

  public func time(_ date: Date) -> String { format(date, timeTemplate) }

  public func timeRange(_ item: WidgetItem) -> String {
    item.isAllDay ? "All day" : "\(time(item.start))–\(time(item.end))"
  }

  public func format(_ date: Date, _ template: String) -> String {
    let f = DateFormatter()
    f.calendar = calendar
    f.locale = locale
    f.timeZone = calendar.timeZone
    f.setLocalizedDateFormatFromTemplate(template)
    return f.string(from: date)
  }

  /// "TODAY", "TOMORROW", or the weekday.
  public func dayLabel(_ day: Date) -> String {
    let diff =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: day)
      ).day ?? 0
    switch diff {
    case 0: return "TODAY"
    case 1: return "TOMORROW"
    default: return format(day, "EEEE").uppercased(with: locale)
    }
  }

  public var dayLink: URL {
    WelaLink.day(DayKey.string(for: date, timeZone: calendar.timeZone)).url
  }

  // MARK: Building

  public static let lookAheadDays = 7

  /// The store interval a snapshot (or a timeline of them starting at `now`) needs.
  public static func interval(now: Date, calendar: Calendar) -> DateInterval {
    let today = calendar.startOfDay(for: now)
    let cells = CalendarMath.monthGrid(for: now, calendar: calendar, now: now)
    let start = min(cells.first?.date ?? today, today)
    let gridEnd = cells.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0.date) }
    let aheadEnd = calendar.date(byAdding: .day, value: lookAheadDays + 2, to: today) ?? today
    return DateInterval(start: start, end: max(gridEnd ?? aheadEnd, aheadEnd))
  }

  public static func make(
    events: [EventInstance], calendars: [CalendarInfo], hasAccounts: Bool, now: Date,
    calendar: Calendar, locale: Locale, options: AgendaOptions, timeTemplate: String,
    dotsCache: [Date: [Date: [String]]]? = nil
  ) -> WidgetSnapshot {
    var opts = options
    opts.showCancelled = false  // widgets have no room for struck-through rows
    let visible = Set(calendars.filter(\.isVisible).map(\.id))
    let colors = Dictionary(
      calendars.map { ($0.id, $0.effectiveColorHex) }, uniquingKeysWith: { a, _ in a })
    let today = calendar.startOfDay(for: now)

    func items(on day: Date) -> [WidgetItem] {
      let agenda = AgendaBuilder.agenda(
        for: day, events: events, visibleCalendarIds: visible, options: opts, calendar: calendar)
      return (agenda.allDay + agenda.timed).map { item in
        let e = item.event
        return WidgetItem(
          id: e.id, title: e.title, start: e.start, end: e.end, isAllDay: e.isAllDay,
          location: e.location, colorHex: colors[e.calendarId] ?? "#6F685C",
          hasJoin: e.joinURL != nil,
          isTentative: e.myResponse == .tentative || e.myResponse == .notResponded
            || e.status == .tentative,
          multiDayLabel: item.multiDayLabel)
      }
    }

    var days = [
      WidgetDay(day: today, items: items(on: today).filter { $0.isAllDay || $0.end > now })
    ]
    for offset in 1...lookAheadDays {
      guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
      let list = items(on: day)
      if !list.isEmpty { days.append(WidgetDay(day: day, items: list)) }
    }

    let cells = CalendarMath.monthGrid(for: now, calendar: calendar, now: now)
    let dots =
      dotsCache?[today]
      ?? Dictionary(
        uniqueKeysWithValues: cells.map { cell in
          (
            cell.date,
            DotSummary.dots(
              for: cell.date, events: events, calendarColors: colors, visibleCalendarIds: visible,
              options: opts, calendar: calendar)
          )
        })

    return WidgetSnapshot(
      date: now, calendar: calendar, locale: locale, timeTemplate: timeTemplate,
      hasAccounts: hasAccounts, days: days, monthCells: cells, dots: dots)
  }

  /// Moments after `now` when what a widget shows changes: every start and end in the next
  /// 24 hours, and the next midnight. Capped so a busy day stays within WidgetKit's budget.
  public static func refreshDates(
    events: [EventInstance], now: Date, calendar: Calendar, limit: Int = 40
  ) -> [Date] {
    let horizon = now.addingTimeInterval(24 * 3600)
    var dates = Set<Date>()
    for e in events where !e.isAllDay && e.status != .cancelled {
      for d in [e.start, e.end] where d > now && d <= horizon { dates.insert(d) }
    }
    if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
      dates.insert(midnight)
    }
    return Array(dates.sorted().prefix(limit))
  }

  /// A timeline: a snapshot for `now` and for each refresh date.
  public static func timeline(
    events: [EventInstance], calendars: [CalendarInfo], hasAccounts: Bool, now: Date,
    calendar: Calendar, locale: Locale, options: AgendaOptions, timeTemplate: String
  ) -> [WidgetSnapshot] {
    var cache: [Date: [Date: [String]]] = [:]
    return ([now] + refreshDates(events: events, now: now, calendar: calendar)).map { date in
      let snapshot = make(
        events: events, calendars: calendars, hasAccounts: hasAccounts, now: date,
        calendar: calendar, locale: locale, options: options, timeTemplate: timeTemplate,
        dotsCache: cache)
      cache[calendar.startOfDay(for: date)] = snapshot.dots
      return snapshot
    }
  }

  /// Reads the store and settings and builds a timeline starting at `now`.
  @MainActor
  public static func timeline(store: Store, settings: SettingsModel, now: Date = Date())
    throws -> [WidgetSnapshot]
  {
    let calendar = settings.makeCalendar(base: .current)
    let events = try store.events(in: interval(now: now, calendar: calendar))
    return timeline(
      events: events, calendars: try store.calendars(),
      hasAccounts: !(try store.accounts()).isEmpty,
      now: now, calendar: calendar, locale: .current, options: settings.agendaOptions,
      timeTemplate: settings.timeTemplate)
  }

  /// Made-up events for the widget gallery preview (before any account is connected) and for
  /// screenshot tests.
  public static func sample(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
    let work = CalendarInfo(
      accountId: "sample", providerCalendarId: "work", name: "Work", providerColorHex: "#3D5A96")
    let personal = CalendarInfo(
      accountId: "sample", providerCalendarId: "personal", name: "Personal",
      providerColorHex: "#5F8A5E")
    let shared = CalendarInfo(
      accountId: "sample", providerCalendarId: "shared", name: "Team",
      providerColorHex: "#7B5486")
    let today = calendar.startOfDay(for: now)
    func at(_ day: Int, _ minutes: Int) -> Date {
      let d = calendar.date(byAdding: .day, value: day, to: today) ?? today
      return d.addingTimeInterval(TimeInterval(minutes * 60))
    }
    func event(
      _ id: String, _ cal: CalendarInfo, _ title: String, _ start: Date, _ minutes: Int,
      location: String? = nil, join: Bool = false, response: ResponseStatus = .accepted
    ) -> EventInstance {
      EventInstance(
        calendarId: cal.id, providerEventId: id, title: title, start: start,
        end: start.addingTimeInterval(TimeInterval(minutes * 60)), location: location,
        myResponse: response,
        joinURL: join ? URL(string: "https://teams.microsoft.com/l/meetup-join/sample") : nil,
        conferenceKind: join ? .teams : nil)
    }
    // Anchored to the current time so the preview always shows a meeting in progress.
    let minuteOfDay = Int(now.timeIntervalSince(today) / 60)
    let current = max(0, min(minuteOfDay - 15, 22 * 60))
    var events = [
      event("now", work, "Weekly sync", at(0, current), 45, join: true),
      event("next", shared, "Design review", at(0, current + 60), 60, location: "Spark Room"),
      event("lunch", personal, "Lunch with Nok", at(0, current + 150), 60),
      event("t1", work, "Sprint planning", at(1, 9 * 60 + 30), 60, location: "Studio B"),
      event("t2", shared, "Team standup", at(1, 11 * 60), 30, join: true, response: .notResponded),
      event("t3", personal, "Thai class", at(2, 18 * 60), 90),
    ]
    for offset in [-9, -6, -2, 3, 5, 8, 12] {
      events.append(event("x\(offset)", work, "Customer call", at(offset, 15 * 60), 45))
    }
    return make(
      events: events, calendars: [work, personal, shared], hasAccounts: true, now: now,
      calendar: calendar, locale: .current, options: AgendaOptions(), timeTemplate: "jm")
  }

  /// Shown before any account is connected, or when the store can't be read.
  public static func empty(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
    make(
      events: [], calendars: [], hasAccounts: false, now: now, calendar: calendar,
      locale: .current, options: AgendaOptions(), timeTemplate: "jm")
  }
}
