import Combine
import Foundation
import SwiftUI
import WelaCore

/// User preferences, persisted in UserDefaults and applied live to the panel.
@MainActor
public final class SettingsModel: ObservableObject {
  public enum WeekStart: Int, CaseIterable, Identifiable {
    case system = 0
    case sunday = 1
    case monday = 2
    public var id: Int { rawValue }
    public var title: String {
      switch self {
      case .system: return "System"
      case .sunday: return "Sunday"
      case .monday: return "Monday"
      }
    }
  }
  public enum CalendarSystem: String, CaseIterable, Identifiable {
    case system, gregorian, buddhist
    public var id: String { rawValue }
    public var title: String {
      switch self {
      case .system: return "System"
      case .gregorian: return "Gregorian"
      case .buddhist: return "Buddhist"
      }
    }
  }
  public enum TimeFormat: String, CaseIterable, Identifiable {
    case system, h12, h24
    public var id: String { rawValue }
    public var title: String {
      switch self {
      case .system: return "System"
      case .h12: return "12-hour"
      case .h24: return "24-hour"
      }
    }
  }
  public enum TextSize: String, CaseIterable, Identifiable {
    case small, normal, large
    public var id: String { rawValue }
    public var title: String {
      switch self {
      case .small: return "Small"
      case .normal: return "Default"
      case .large: return "Large"
      }
    }
    public var scale: CGFloat {
      switch self {
      case .small: return 0.9
      case .normal: return 1
      case .large: return 1.15
      }
    }
  }

  private let defaults: UserDefaults

  @Published public var weekStart: WeekStart { didSet { save("weekStart", weekStart.rawValue) } }
  @Published public var calendarSystem: CalendarSystem {
    didSet { save("calendarSystem", calendarSystem.rawValue) }
  }
  @Published public var timeFormat: TimeFormat {
    didSet { save("timeFormat", timeFormat.rawValue) }
  }
  @Published public var textSize: TextSize { didSet { save("textSize", textSize.rawValue) } }
  @Published public var showCancelled: Bool { didSet { save("showCancelled", showCancelled) } }
  @Published public var showDeclined: Bool { didSet { save("showDeclined", showDeclined) } }
  @Published public var notificationsEnabled: Bool {
    didSet { save("notificationsEnabled", notificationsEnabled) }
  }
  @Published public var alertLeadMinutes: Int {
    didSet { save("alertLeadMinutes", alertLeadMinutes) }
  }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    weekStart = WeekStart(rawValue: defaults.integer(forKey: "weekStart")) ?? .system
    calendarSystem =
      CalendarSystem(rawValue: defaults.string(forKey: "calendarSystem") ?? "") ?? .system
    timeFormat = TimeFormat(rawValue: defaults.string(forKey: "timeFormat") ?? "") ?? .system
    textSize = TextSize(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .normal
    showCancelled = defaults.object(forKey: "showCancelled") as? Bool ?? true
    showDeclined = defaults.object(forKey: "showDeclined") as? Bool ?? false
    notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
    alertLeadMinutes = defaults.object(forKey: "alertLeadMinutes") as? Int ?? 10
  }

  private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }

  /// The calendar the panel should use, from the system calendar plus overrides.
  public func makeCalendar(base: Calendar = .current) -> Calendar {
    var cal: Calendar
    switch calendarSystem {
    case .system: cal = base
    case .gregorian: cal = Calendar(identifier: .gregorian)
    case .buddhist: cal = Calendar(identifier: .buddhist)
    }
    if calendarSystem != .system {
      cal.timeZone = base.timeZone
      cal.locale = base.locale
      cal.firstWeekday = base.firstWeekday
    }
    if weekStart != .system { cal.firstWeekday = weekStart.rawValue }
    return cal
  }

  public var agendaOptions: AgendaOptions {
    AgendaOptions(showDeclined: showDeclined, showCancelled: showCancelled)
  }

  /// Date format template for times of day.
  public var timeTemplate: String {
    switch timeFormat {
    case .system: return "jm"
    case .h12: return "hma"
    case .h24: return "Hm"
    }
  }
}
