import WelaCore
import XCTest

@testable import WelaSync

final class GoogleProviderTests: XCTestCase {
  let account = Account(id: "g", provider: .google, email: "me@gmail.com", displayName: "Me")
  let cal = CalendarInfo(accountId: "g", providerCalendarId: "me@gmail.com", name: "Me", providerColorHex: "#9fc6e7")

  static let items = """
    {"nextSyncToken": "SYNC1", "items": [
     {"id": "allday1", "status": "confirmed", "summary": "Holiday", "start": {"date": "2026-10-23"}, "end": {"date": "2026-10-24"}},
     {"id": "series_20261014T030000Z", "recurringEventId": "series", "status": "confirmed", "summary": "Standup (moved)",
      "start": {"dateTime": "2026-10-14T10:30:00+07:00"}, "end": {"dateTime": "2026-10-14T11:00:00+07:00"}, "etag": "\\"e1\\""},
     {"id": "cancel1", "status": "cancelled"},
     {"id": "invite1", "status": "confirmed", "summary": "Design sync",
      "start": {"dateTime": "2026-10-15T09:00:00Z"}, "end": {"dateTime": "2026-10-15T10:00:00Z"},
      "organizer": {"email": "boss@example.com"},
      "attendees": [{"email": "boss@example.com", "displayName": "Boss", "responseStatus": "accepted", "organizer": true},
                    {"email": "me@gmail.com", "self": true, "responseStatus": "needsAction"}]},
     {"id": "meet1", "status": "confirmed", "summary": "Call",
      "start": {"dateTime": "2026-10-16T09:00:00Z"}, "end": {"dateTime": "2026-10-16T09:30:00Z"},
      "conferenceData": {"entryPoints": [{"entryPointType": "phone", "uri": "tel:+123"}, {"entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij"}]}},
     {"id": "bday1", "status": "confirmed", "eventType": "birthday", "summary": "Somchai",
      "start": {"date": "2026-10-20"}, "end": {"date": "2026-10-21"}}
    ]}
    """

  private func provider(_ handler: @escaping @Sendable (URLRequest) throws -> Reply)
    -> (GoogleProvider, FakeTransport)
  {
    let t = FakeTransport(handler)
    return (GoogleProvider(client: makeClient(t)), t)
  }

  func testInitialSyncMapping() async throws {
    let (p, t) = provider { _ in Reply(body: Self.items) }
    let r = try await p.sync(account: account, calendar: cal, state: nil, now: testNow)
    XCTAssertTrue(r.replacesAll)
    XCTAssertEqual(r.newState.syncToken, "SYNC1")
    XCTAssertEqual(r.upserts.count, 5)  // cancelled instance excluded

    let req = t.requests[0]
    XCTAssertEqual(query(req, "singleEvents"), "true")
    XCTAssertEqual(query(req, "maxResults"), "250")
    XCTAssertEqual(query(req, "showDeleted"), "true")
    XCTAssertEqual(query(req, "timeMin"), "2026-07-16T03:00:00Z")
    XCTAssertEqual(query(req, "timeMax"), "2027-10-14T03:00:00Z")
    XCTAssertTrue(req.url!.absoluteString.contains("/calendars/me@gmail.com/events"))

    let allDay = try XCTUnwrap(r.upserts.first { $0.providerEventId == "allday1" })
    XCTAssertTrue(allDay.isAllDay)
    XCTAssertEqual(allDay.endDay, "2026-10-24")

    let moved = try XCTUnwrap(r.upserts.first { $0.providerEventId.hasPrefix("series_") })
    XCTAssertEqual(moved.seriesId, "series")
    XCTAssertEqual(moved.start, testNow.addingTimeInterval(0.5 * 3600))  // 10:30+07:00 = 03:30Z

    let invite = try XCTUnwrap(r.upserts.first { $0.providerEventId == "invite1" })
    XCTAssertEqual(invite.myResponse, .notResponded)
    XCTAssertEqual(invite.attendees.count, 2)

    let meet = try XCTUnwrap(r.upserts.first { $0.providerEventId == "meet1" })
    XCTAssertEqual(meet.joinURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
    XCTAssertEqual(meet.conferenceKind, .meet)

    XCTAssertEqual(r.upserts.first { $0.providerEventId == "bday1" }?.isBirthday, true)
  }

  func testIncrementalUsesSyncTokenOnlyAndDeletesCancelled() async throws {
    let (p, t) = provider { _ in
      Reply(body: "{\"nextSyncToken\": \"SYNC2\", \"items\": [{\"id\": \"cancel1\", \"status\": \"cancelled\"}]}")
    }
    let state = SyncState(calendarId: cal.id, syncToken: "SYNC1", windowStart: testNow, windowEnd: testNow.addingTimeInterval(365 * 86_400))
    let r = try await p.sync(account: account, calendar: cal, state: state, now: testNow)
    XCTAssertFalse(r.replacesAll)
    XCTAssertEqual(r.deletedIds, ["g:me@gmail.com:cancel1"])
    XCTAssertEqual(r.newState.syncToken, "SYNC2")
    let req = t.requests[0]
    XCTAssertEqual(query(req, "syncToken"), "SYNC1")
    XCTAssertEqual(query(req, "singleEvents"), "true")
    XCTAssertNil(query(req, "timeMin"))
    XCTAssertNil(query(req, "timeMax"))
  }

  func testGone410RedoesInitialSync() async throws {
    let (p, t) = provider { req in
      query(req, "syncToken") != nil ? Reply(status: 410) : Reply(body: Self.items)
    }
    let state = SyncState(calendarId: cal.id, syncToken: "STALE")
    let r = try await p.sync(account: account, calendar: cal, state: state, now: testNow)
    XCTAssertTrue(r.replacesAll)
    XCTAssertEqual(r.newState.syncToken, "SYNC1")
    XCTAssertEqual(t.requests.count, 2)
  }

  func testBoundedRequestWithoutTokenFallsBackToUnbounded() async throws {
    let (p, t) = provider { req in
      query(req, "timeMax") != nil
        ? Reply(body: "{\"items\": []}") : Reply(body: Self.items)
    }
    let r = try await p.sync(account: account, calendar: cal, state: nil, now: testNow)
    XCTAssertEqual(r.newState.syncToken, "SYNC1")
    XCTAssertEqual(t.requests.count, 2)
    XCTAssertNil(query(t.requests[1], "timeMax"))
  }

  func testPaginationFollowsNextPageToken() async throws {
    let (p, t) = provider { req in
      query(req, "pageToken") == "P2"
        ? Reply(body: "{\"nextSyncToken\": \"S\", \"items\": [{\"id\": \"b\", \"summary\": \"B\", \"start\": {\"date\": \"2026-10-20\"}, \"end\": {\"date\": \"2026-10-21\"}}]}")
        : Reply(body: "{\"nextPageToken\": \"P2\", \"items\": [{\"id\": \"a\", \"summary\": \"A\", \"start\": {\"date\": \"2026-10-19\"}, \"end\": {\"date\": \"2026-10-20\"}}]}")
    }
    let r = try await p.sync(account: account, calendar: cal, state: nil, now: testNow)
    XCTAssertEqual(r.upserts.map(\.providerEventId), ["a", "b"])
    XCTAssertEqual(r.newState.syncToken, "S")
    XCTAssertEqual(t.requests.count, 2)
  }

  func testRespondPatchesOnlySelfAttendeeWithEtagAndRetriesOn412() async throws {
    let patches = Counter()
    let (p, t) = provider { req in
      if req.httpMethod == "PATCH" {
        return patches.next() == 1 ? Reply(status: 412) : Reply(body: "{}")
      }
      return Reply(body: """
        {"etag": "\\"fresh\\"", "attendees": [{"email": "boss@example.com", "responseStatus": "declined"},
                                          {"email": "me@gmail.com", "self": true, "responseStatus": "needsAction"}]}
        """)
    }
    let event = EventInstance(calendarId: cal.id, providerEventId: "invite1", title: "x", start: testNow, end: testNow)
    try await p.respond(account: account, calendar: cal, event: event, response: .accepted)
    let patchRequests = t.requests.filter { $0.httpMethod == "PATCH" }
    XCTAssertEqual(patchRequests.count, 2)
    let last = try XCTUnwrap(patchRequests.last)
    XCTAssertEqual(last.value(forHTTPHeaderField: "If-Match"), "\"fresh\"")
    XCTAssertEqual(query(last, "sendUpdates"), "all")
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: last.httpBody!) as? [String: Any])
    let attendees = try XCTUnwrap(body["attendees"] as? [[String: Any]])
    XCTAssertEqual(attendees.map { $0["responseStatus"] as? String }, ["declined", "accepted"])
    XCTAssertEqual(attendees[0]["email"] as? String, "boss@example.com")
  }
}
