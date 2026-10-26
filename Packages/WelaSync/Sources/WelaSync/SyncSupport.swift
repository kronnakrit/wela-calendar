import Foundation
import WelaCore

public enum SyncError: Error, Equatable {
  case needsSignIn
  case offline
  case rateLimited(retryAfter: TimeInterval?)
  /// HTTP 410: the delta / sync token is no longer valid; do a fresh initial sync.
  case syncTokenExpired
  case preconditionFailed
  case http(status: Int, message: String)
  case invalidResponse(String)
}

public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw SyncError.invalidResponse("not an HTTP response")
    }
    return (data, http)
  }
}

/// Supplies a valid access token for an account. Implemented with MSAL / AppAuth in the app.
/// Throw `SyncError.needsSignIn` when interaction is required.
public protocol AccessTokenProvider: Sendable {
  func accessToken(for account: Account) async throws -> String
}

/// Adds the bearer token, retries 429 / 503 using Retry-After (exponential backoff, capped at
/// five minutes) and maps failures onto `SyncError`.
public struct HTTPClient: Sendable {
  public let transport: HTTPTransport
  public let tokens: AccessTokenProvider
  public let sleep: @Sendable (TimeInterval) async -> Void
  public let maxAttempts: Int
  public static let maxBackoff: TimeInterval = 300

  public init(
    transport: HTTPTransport, tokens: AccessTokenProvider, maxAttempts: Int = 6,
    sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
  ) {
    self.transport = transport
    self.tokens = tokens
    self.maxAttempts = maxAttempts
    self.sleep = sleep
  }

  public func send(_ request: URLRequest, account: Account) async throws -> (
    Data, HTTPURLResponse
  ) {
    var lastDelay: TimeInterval?
    for attempt in 0..<maxAttempts {
      var req = request
      let token = try await tokens.accessToken(for: account)
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      let data: Data
      let response: HTTPURLResponse
      do {
        (data, response) = try await transport.send(req)
      } catch let error as URLError where Self.offlineCodes.contains(error.code) {
        throw SyncError.offline
      }
      switch response.statusCode {
      case 200..<300:
        return (data, response)
      case 401:
        throw SyncError.needsSignIn
      case 410:
        throw SyncError.syncTokenExpired
      case 412:
        throw SyncError.preconditionFailed
      case 429, 503:
        let header = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        let delay = min(header ?? pow(2, Double(attempt)), Self.maxBackoff)
        lastDelay = delay
        if attempt < maxAttempts - 1 { await sleep(delay) }
      default:
        let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
        throw SyncError.http(status: response.statusCode, message: body)
      }
    }
    throw SyncError.rateLimited(retryAfter: lastDelay)
  }

  static let offlineCodes: Set<URLError.Code> = [
    .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
    .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed,
  ]
}

enum DateParsing {
  private static let fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  private static let plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  /// Parses RFC 3339 and Graph's zone-less UTC timestamps ("2026-10-14T03:00:00.0000000").
  static func parse(_ raw: String) -> Date? {
    guard let t = raw.firstIndex(of: "T") else { return nil }
    var s = raw
    if let dot = s.firstIndex(of: "."), dot > t {
      var end = s.index(after: dot)
      while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
      let digits = String(s[s.index(after: dot)..<end].prefix(3))
      let ms = digits.padding(toLength: 3, withPad: "0", startingAt: 0)
      s = String(s[..<dot]) + "." + ms + String(s[end...])
    }
    let tail = s[s.index(after: t)...]
    if !(tail.contains("Z") || tail.contains("+") || tail.contains("-")) { s += "Z" }
    return fractional.date(from: s) ?? plain.date(from: s)
  }

  static func utcString(_ date: Date) -> String { plain.string(from: date) }
}

func percentEncodePathComponent(_ s: String) -> String {
  var allowed = CharacterSet.urlPathAllowed
  allowed.remove(charactersIn: "/?#")
  return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

/// Appends an already percent-encoded path to `base`. `URL.appendingPathComponent` would escape
/// the `%` of ids that were encoded with `percentEncodePathComponent` a second time.
func encodedEndpoint(_ base: URL, _ encodedPath: String) -> URL {
  guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
    return base.appendingPathComponent(encodedPath)
  }
  components.percentEncodedPath += "/" + encodedPath
  return components.url ?? base
}
