import Foundation

/// Turns a meeting link into the URLs to try, native app first. The caller opens the first
/// candidate whose scheme has an installed handler and falls back to the https link.
public enum JoinURLResolver {
  public static func candidates(for url: URL, kind: ConferenceKind? = nil) -> [URL] {
    let kind = kind ?? JoinLinkParser.kind(for: url)
    var out: [URL] = []
    switch kind {
    case .teams:
      if url.host == "teams.microsoft.com" || url.host == "teams.live.com",
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
      {
        comps.scheme = "msteams"
        comps.host = nil
        if let native = comps.url?.absoluteString.replacingOccurrences(of: "msteams:///", with: "msteams:/"),
          let u = URL(string: native)
        {
          out.append(u)
        }
      }
    case .zoom:
      let parts = url.pathComponents  // ["/", "j", "123456789"]
      if parts.count >= 3, parts[1] == "j", Int(parts[2]) != nil,
        var comps = URLComponents(string: "zoommtg://zoom.us/join")
      {
        var items = [URLQueryItem(name: "confno", value: parts[2])]
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .first(where: { $0.name == "pwd" })?.value
        {
          items.append(URLQueryItem(name: "pwd", value: pwd))
        }
        comps.queryItems = items
        if let u = comps.url { out.append(u) }
      }
    default:
      break
    }
    out.append(url)
    return out
  }
}
