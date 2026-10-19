import Foundation

public struct JoinLink: Hashable, Sendable {
  public let url: URL
  public let kind: ConferenceKind
}

public enum JoinLinkParser {
  private static let patterns: [(ConferenceKind, NSRegularExpression)] = {
    let tail = #"[^\s<>"]+"#
    let defs: [(ConferenceKind, String)] = [
      (.teams, #"https://teams\.microsoft\.com/l/meetup-join/"# + tail),
      (.teams, #"https://teams\.live\.com/meet/"# + tail),
      (.meet, #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#),
      (.zoom, #"https://([a-z0-9-]+\.)?zoom\.us/(j|my|w)/"# + tail),
      (.webex, #"https://[a-z0-9-]+\.webex\.com/"# + tail),
    ]
    return defs.compactMap { kind, p in
      (try? NSRegularExpression(pattern: p, options: [.caseInsensitive])).map { (kind, $0) }
    }
  }()

  private static let trailing = CharacterSet(charactersIn: ">)\"'.,;")

  public static func kind(for url: URL) -> ConferenceKind {
    let host = (url.host ?? "").lowercased()
    if host == "teams.microsoft.com" || host == "teams.live.com" { return .teams }
    if host == "meet.google.com" { return .meet }
    if host == "zoom.us" || host.hasSuffix(".zoom.us") { return .zoom }
    if host.hasSuffix(".webex.com") || host == "webex.com" { return .webex }
    return .other
  }

  /// Precedence: provider's structured field, then location, then notes.
  public static func parse(
    structuredURL: URL? = nil, structuredKind: ConferenceKind? = nil, location: String?,
    notes: String?
  ) -> JoinLink? {
    if let url = structuredURL {
      return JoinLink(url: url, kind: structuredKind ?? kind(for: url))
    }
    for text in [location, notes] {
      if let text, let link = firstLink(in: text) { return link }
    }
    return nil
  }

  static func firstLink(in text: String) -> JoinLink? {
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    var best: (range: NSRange, kind: ConferenceKind)?
    for (kind, regex) in patterns {
      guard let m = regex.firstMatch(in: text, options: [], range: full) else { continue }
      if best == nil || m.range.location < best!.range.location { best = (m.range, kind) }
    }
    guard let best else { return nil }
    var s = ns.substring(with: best.range)
    while let last = s.unicodeScalars.last, trailing.contains(last) { s.removeLast() }
    guard let url = URL(string: s) else { return nil }
    return JoinLink(url: url, kind: best.kind)
  }
}
