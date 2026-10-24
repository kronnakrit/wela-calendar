import Foundation

/// `wela://` deep links, used by the iOS widgets to open a day or an event in the app.
public enum WelaLink: Hashable, Sendable {
  /// Show this day ("yyyy-MM-dd", Gregorian) in the month grid and agenda.
  case day(String)
  /// Open an event's detail card.
  case event(id: String)
  /// Join an event's online meeting.
  case join(id: String)

  public static let scheme = "wela"

  /// Unreserved characters only, so ids with "&", "=", "+" or "/" survive the round trip.
  private static let allowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  public var url: URL {
    let parts: (host: String, name: String, value: String)
    switch self {
    case .day(let key): parts = ("day", "d", key)
    case .event(let id): parts = ("event", "id", id)
    case .join(let id): parts = ("join", "id", id)
    }
    let (host, name, value) = parts
    var c = URLComponents()
    c.scheme = Self.scheme
    c.host = host
    c.percentEncodedQuery =
      "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? "")"
    return c.url!
  }

  public init?(url: URL) {
    guard url.scheme?.lowercased() == Self.scheme,
      let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    func value(_ name: String) -> String? {
      let raw = c.percentEncodedQueryItems?.first { $0.name == name }?.value
      return raw?.removingPercentEncoding.flatMap { $0.isEmpty ? nil : $0 }
    }
    switch c.host?.lowercased() {
    case "day":
      guard let key = value("d"), DayKey.utcMidnight(key) != nil else { return nil }
      self = .day(key)
    case "event":
      guard let id = value("id") else { return nil }
      self = .event(id: id)
    case "join":
      guard let id = value("id") else { return nil }
      self = .join(id: id)
    default:
      return nil
    }
  }
}
