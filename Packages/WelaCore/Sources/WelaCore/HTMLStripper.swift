import Foundation

/// Converts the HTML bodies Microsoft Graph returns into plain text.
public enum HTMLStripper {
  public static func plainText(from html: String) -> String {
    var s = html
    s = replace(s, #"(?is)<(script|style|head)\b.*?</\1\s*>"#, "")
    s = transform(s, #"(?is)<a\s[^>]*?href\s*=\s*["']([^"']*)["'][^>]*>(.*?)</a\s*>"#) { m, ns in
      let href = ns.substring(with: m.range(at: 1))
      let text = replace(ns.substring(with: m.range(at: 2)), #"(?s)<[^>]+>"#, "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty || text == href ? href : "\(text) (\(href))"
    }
    s = replace(s, #"(?i)<br\s*/?>"#, "\n")
    s = replace(s, #"(?i)</(p|div|li|tr|h[1-6]|table)\s*>"#, "\n")
    s = replace(s, #"(?i)<li[^>]*>"#, "• ")
    s = replace(s, #"(?s)<[^>]*>"#, "")
    s = decodeEntities(s)
    s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
    s = s.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")
    s = replace(s, #"\n{3,}"#, "\n\n")
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let named: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘",
    "rdquo": "”", "ldquo": "“",
  ]

  private static func decodeEntities(_ input: String) -> String {
    transform(input, #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#) { m, ns in
      let body = ns.substring(with: m.range(at: 1))
      if body.hasPrefix("#x"), let v = UInt32(body.dropFirst(2), radix: 16),
        let u = Unicode.Scalar(v)
      {
        return String(Character(u))
      }
      if body.hasPrefix("#"), let v = UInt32(body.dropFirst()), let u = Unicode.Scalar(v) {
        return String(Character(u))
      }
      return named[body.lowercased()] ?? ns.substring(with: m.range)
    }
  }

  private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
    let range = NSRange(location: 0, length: (s as NSString).length)
    return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
  }

  private static func transform(
    _ s: String, _ pattern: String, _ f: (NSTextCheckingResult, NSString) -> String
  ) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
    let ns = s as NSString
    var out = ""
    var cursor = 0
    for m in re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) {
      out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
      out += f(m, ns)
      cursor = m.range.location + m.range.length
    }
    out += ns.substring(from: cursor)
    return out
  }
}
