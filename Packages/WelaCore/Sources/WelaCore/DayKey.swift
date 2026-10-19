import Foundation

/// Helpers for provider date-only strings ("yyyy-MM-dd", always Gregorian).
public enum DayKey {
  private static func gregorian(_ tz: TimeZone) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal
  }

  public static func string(for date: Date, timeZone: TimeZone) -> String {
    let c = gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  /// Start of the given day in `timeZone`.
  public static func date(from key: String, timeZone: TimeZone) -> Date? {
    guard let c = components(key) else { return nil }
    return gregorian(timeZone).date(from: c)
  }

  public static func utcMidnight(_ key: String) -> Date? {
    date(from: key, timeZone: TimeZone(identifier: "UTC")!)
  }

  /// Whole days from `a` to `b` (b - a).
  public static func daysBetween(_ a: String, _ b: String) -> Int {
    guard let da = utcMidnight(a), let db = utcMidnight(b) else { return 0 }
    return Int((db.timeIntervalSince(da) / 86_400).rounded())
  }

  private static func components(_ key: String) -> DateComponents? {
    let parts = key.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
    else { return nil }
    return DateComponents(year: y, month: m, day: d)
  }
}
