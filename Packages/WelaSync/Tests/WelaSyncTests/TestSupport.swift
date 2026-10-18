import Foundation
import WelaCore

@testable import WelaSync

struct Reply {
  var status = 200
  var headers: [String: String] = [:]
  var body = "{}"
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var _requests: [URLRequest] = []
  private let handler: @Sendable (URLRequest) throws -> Reply

  init(_ handler: @escaping @Sendable (URLRequest) throws -> Reply) { self.handler = handler }

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _requests
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lock.lock()
    _requests.append(request)
    lock.unlock()
    let reply = try handler(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
    return (Data(reply.body.utf8), response)
  }
}

struct StaticToken: AccessTokenProvider {
  func accessToken(for account: Account) async throws -> String { "tok" }
}

final class SleepLog: @unchecked Sendable {
  private let lock = NSLock()
  private var _values: [TimeInterval] = []
  var values: [TimeInterval] {
    lock.lock()
    defer { lock.unlock() }
    return _values
  }
  func add(_ v: TimeInterval) {
    lock.lock()
    _values.append(v)
    lock.unlock()
  }
}

func makeClient(_ transport: HTTPTransport, sleeps: SleepLog = SleepLog()) -> HTTPClient {
  HTTPClient(transport: transport, tokens: StaticToken(), sleep: { sleeps.add($0) })
}

let utc = TimeZone(identifier: "UTC")!
let testNow = ISO8601DateFormatter().date(from: "2026-10-14T03:00:00Z")!
func query(_ request: URLRequest, _ name: String) -> String? {
  URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
    .first { $0.name == name }?.value
}
