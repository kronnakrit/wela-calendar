import Foundation

public struct DayCell: Identifiable, Hashable, Sendable {
  public let date: Date
  public let isInMonth: Bool
  public let isToday: Bool
  public var id: Date { date }
}

public enum CalendarMath {
  /// A 6×7 grid covering the month containing `month`. First weekday comes from `calendar`.
  public static func monthGrid(for month: Date, calendar: Calendar, now: Date = Date()) -> [DayCell] {
    guard let monthStart = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
    let weekday = calendar.component(.weekday, from: monthStart)
    let offset = (weekday - calendar.firstWeekday + 7) % 7
    guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart) else {
      return []
    }
    let monthComponents = calendar.dateComponents([.era, .year, .month], from: monthStart)
    return (0..<42).compactMap { i in
      guard let date = calendar.date(byAdding: .day, value: i, to: gridStart) else { return nil }
      let c = calendar.dateComponents([.era, .year, .month], from: date)
      return DayCell(
        date: date, isInMonth: c == monthComponents, isToday: calendar.isDate(date, inSameDayAs: now))
    }
  }

  /// Weekday symbols ordered from the calendar's first weekday (e.g. "S M T …").
  public static func weekdaySymbols(calendar: Calendar) -> [String] {
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let first = calendar.firstWeekday - 1
    return Array(symbols[first...] + symbols[..<first])
  }

  /// Month name only, e.g. "October" / "ตุลาคม".
  public static func monthName(for date: Date, calendar: Calendar, locale: Locale) -> String {
    format(date, "LLLL", calendar, locale)
  }

  /// Year in the calendar's own numbering, e.g. "2026" / "2569" (Buddhist Era).
  public static func yearString(for date: Date, calendar: Calendar, locale: Locale) -> String {
    format(date, "y", calendar, locale)
  }

  public static func monthTitle(for date: Date, calendar: Calendar, locale: Locale) -> String {
    "\(monthName(for: date, calendar: calendar, locale: locale)) \(yearString(for: date, calendar: calendar, locale: locale))"
  }

  private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar, _ locale: Locale)
    -> String
  {
    let f = DateFormatter()
    f.calendar = calendar
    f.locale = locale
    f.timeZone = calendar.timeZone
    f.dateFormat = pattern
    return f.string(from: date)
  }
}
