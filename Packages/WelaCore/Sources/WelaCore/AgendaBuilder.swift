import Foundation

public struct AgendaOptions: Sendable {
  public var showDeclined: Bool
  public var showCancelled: Bool

  public init(showDeclined: Bool = false, showCancelled: Bool = true) {
    self.showDeclined = showDeclined
    self.showCancelled = showCancelled
  }
}

public struct AgendaItem: Identifiable, Hashable, Sendable {
  public let event: EventInstance
  public let isCancelled: Bool
  /// "Day 2 of 3" for multi-day events, nil otherwise.
  public let multiDayLabel: String?
  public var id: String { event.id }

  public init(event: EventInstance, isCancelled: Bool, multiDayLabel: String?) {
    self.event = event
    self.isCancelled = isCancelled
    self.multiDayLabel = multiDayLabel
  }
}

public struct Agenda: Hashable, Sendable {
  public var allDay: [AgendaItem]
  public var timed: [AgendaItem]
  public var isEmpty: Bool { allDay.isEmpty && timed.isEmpty }
  public var count: Int { allDay.count + timed.count }
}

public enum AgendaBuilder {
  public static func agenda(
    for day: Date, events: [EventInstance], visibleCalendarIds: Set<String>? = nil,
    options: AgendaOptions = AgendaOptions(), calendar: Calendar
  ) -> Agenda {
    let dayStart = calendar.startOfDay(for: day)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
      return Agenda(allDay: [], timed: [])
    }
    let key = DayKey.string(for: dayStart, timeZone: calendar.timeZone)

    var allDay: [AgendaItem] = []
    var timed: [AgendaItem] = []

    for e in events {
      if let ids = visibleCalendarIds, !ids.contains(e.calendarId) { continue }
      if e.myResponse == .declined && !options.showDeclined { continue }
      let cancelled = e.status == .cancelled
      if cancelled && !options.showCancelled { continue }

      if e.isAllDay {
        guard let s = e.startDay, let en = e.endDay, s <= key, key < en else { continue }
        let total = DayKey.daysBetween(s, en)
        let label = total > 1 ? "Day \(DayKey.daysBetween(s, key) + 1) of \(total)" : nil
        allDay.append(AgendaItem(event: e, isCancelled: cancelled, multiDayLabel: label))
      } else {
        let end = max(e.end, e.start)
        let overlaps =
          e.start < dayEnd && (end > dayStart || (end == e.start && e.start >= dayStart))
        guard overlaps else { continue }
        let firstDay = calendar.startOfDay(for: e.start)
        let last = end > e.start ? end.addingTimeInterval(-0.001) : e.start
        let lastDay = calendar.startOfDay(for: last)
        let total = (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1
        let label: String?
        if total > 1 {
          let index = (calendar.dateComponents([.day], from: firstDay, to: dayStart).day ?? 0) + 1
          label = "Day \(index) of \(total)"
        } else {
          label = nil
        }
        timed.append(AgendaItem(event: e, isCancelled: cancelled, multiDayLabel: label))
      }
    }

    // Birthdays after other all-day items; otherwise alphabetical.
    allDay.sort {
      if $0.event.isBirthday != $1.event.isBirthday { return !$0.event.isBirthday }
      return $0.event.title.localizedCaseInsensitiveCompare($1.event.title) == .orderedAscending
    }
    timed.sort {
      if $0.event.start != $1.event.start { return $0.event.start < $1.event.start }
      if $0.event.end != $1.event.end { return $0.event.end < $1.event.end }
      return $0.event.title.localizedCaseInsensitiveCompare($1.event.title) == .orderedAscending
    }
    return Agenda(allDay: allDay, timed: timed)
  }
}

public enum DotSummary {
  /// Up to `limit` calendar colours for a day, one per event, ordered by start time
  /// (all-day first). Cancelled events never get a dot; declined follow `options`.
  public static func dots(
    for day: Date, events: [EventInstance], calendarColors: [String: String],
    visibleCalendarIds: Set<String>? = nil, options: AgendaOptions = AgendaOptions(),
    calendar: Calendar, limit: Int = 4
  ) -> [String] {
    var opts = options
    opts.showCancelled = false
    let agenda = AgendaBuilder.agenda(
      for: day, events: events, visibleCalendarIds: visibleCalendarIds, options: opts,
      calendar: calendar)
    return (agenda.allDay + agenda.timed).prefix(limit).compactMap {
      calendarColors[$0.event.calendarId]
    }
  }
}
