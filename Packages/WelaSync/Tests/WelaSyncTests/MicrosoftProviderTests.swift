import WelaCore
import XCTest

@testable import WelaSync

final class MicrosoftProviderTests: XCTestCase {
  let account = Account(id: "ms", provider: .microsoft, email: "me@contoso.com", displayName: "Me")
  let cal = CalendarInfo(accountId: "ms", providerCalendarId: "CAL1", name: "Calendar", providerColorHex: "#3D5A96")

  static let page1 = """
    {"@odata.nextLink": "https://graph.microsoft.com/v1.0/next-page",
     "value": [
      {"id": "teams1", "subject": "OP Weekly", "isAllDay": false, "isCancelled": false, "isOrganizer": false,
       "start": {"dateTime": "2026-10-14T03:00:00.0000000", "timeZone": "UTC"},
       "end": {"dateTime": "2026-10-14T04:00:00.0000000", "timeZone": "UTC"},
       "location": {"displayName": "Spark Room"},
       "body": {"contentType": "html", "content": "<html><body><p>Agenda &amp; notes</p></body></html>"},
       "organizer": {"emailAddress": {"name": "Boss", "address": "boss@contoso.com"}},
       "attendees": [{"status": {"response": "accepted"}, "emailAddress": {"name": "Ada", "address": "ada@contoso.com"}}],
       "responseStatus": {"response": "tentativelyAccepted"},
       "onlineMeeting": {"joinUrl": "https://teams.microsoft.com/l/meetup-join/abc"},
       "onlineMeetingProvider": "teamsForBusiness",
       "seriesMasterId": "master1", "changeKey": "ck1", "lastModifiedDateTime": "2026-10-01T00:00:00.0000000Z"},
      {"id": "cancelled1", "subject": "Budget", "isCancelled": true, "isAllDay": false,
       "start": {"dateTime": "2026-10-14T05:00:00.0000000", "timeZone": "UTC"},
       "end": {"dateTime": "2026-10-14T06:00:00.0000000", "timeZone": "UTC"},
       "responseStatus": {"response": "none"}}
     ]}
    """
  static let page2 = """
    {"@odata.deltaLink": "https://graph.microsoft.com/v1.0/delta?token=ABC",
     "value": [
      {"id": "holiday1", "subject": "Chulalongkorn Day", "isAllDay": true,
       "start": {"dateTime": "2026-10-23T00:00:00.0000000", "timeZone": "UTC"},
       "end": {"dateTime": "2026-10-24T00:00:00.0000000", "timeZone": "UTC"},
       "responseStatus": {"response": "notResponded"}},
      {"id": "occ2", "subject": "Standup (moved)", "isAllDay": false, "seriesMasterId": "master2", "isOrganizer": true,
       "start": {"dateTime": "2026-10-15T02:30:00.0000000", "timeZone": "UTC"},
       "end": {"dateTime": "2026-10-15T03:00:00.0000000", "timeZone": "UTC"},
       "responseStatus": {"response": "organizer"}}
     ]}
    """

  private func provider(_ handler: @escaping @Sendable (URLRequest) throws -> Reply, sleeps: SleepLog = SleepLog())
    -> (MicrosoftProvider, FakeTransport)
  {
    let t = FakeTransport(handler)
    return (MicrosoftProvider(client: makeClient(t, sleeps: sleeps)), t)
  }

  func testInitialSyncMapsEventsAndFollowsPages() async throws {
    let (p, t) = provider { req in
      req.url!.absoluteString.hasSuffix("next-page") ? Reply(body: Self.page2) : Reply(body: Self.page1)
    }
    let r = try await p.sync(account: account, calendar: cal, state: nil, now: testNow)
    XCTAssertTrue(r.replacesAll)
    XCTAssertEqual(r.newState.deltaLink, "https://graph.microsoft.com/v1.0/delta?token=ABC")
    XCTAssertEqual(r.upserts.count, 4)

    let first = t.requests[0]
    XCTAssertTrue(first.url!.path.hasSuffix("/me/calendars/CAL1/calendarView/delta"))
    XCTAssertEqual(query(first, "startDateTime"), "2026-07-16T03:00:00Z")
    XCTAssertEqual(query(first, "endDateTime"), "2027-10-14T03:00:00Z")
    XCTAssertEqual(first.value(forHTTPHeaderField: "Prefer"), "outlook.timezone=\"UTC\", odata.maxpagesize=100")
    XCTAssertEqual(t.requests[1].value(forHTTPHeaderField: "Prefer"), first.value(forHTTPHeaderField: "Prefer"))
    XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "Bearer tok")

    let teams = try XCTUnwrap(r.upserts.first { $0.providerEventId == "teams1" })
    XCTAssertEqual(teams.id, "ms:CAL1:teams1")
    XCTAssertEqual(teams.start, testNow)
    XCTAssertEqual(teams.end, testNow.addingTimeInterval(3600))
    XCTAssertEqual(teams.joinURL?.absoluteString, "https://teams.microsoft.com/l/meetup-join/abc")
    XCTAssertEqual(teams.conferenceKind, .teams)
    XCTAssertEqual(teams.myResponse, .tentative)
    XCTAssertEqual(teams.notes, "Agenda & notes")
    XCTAssertEqual(teams.location, "Spark Room")
    XCTAssertEqual(teams.seriesId, "master1")
    XCTAssertEqual(teams.attendees.first?.response, .accepted)
    XCTAssertEqual(teams.organizerEmail, "boss@contoso.com")

    let cancelled = try XCTUnwrap(r.upserts.first { $0.providerEventId == "cancelled1" })
    XCTAssertEqual(cancelled.status, .cancelled)
    XCTAssertEqual(cancelled.myResponse, .notResponded)

    let holiday = try XCTUnwrap(r.upserts.first { $0.providerEventId == "holiday1" })
    XCTAssertTrue(holiday.isAllDay)
    XCTAssertEqual(holiday.startDay, "2026-10-23")
    XCTAssertEqual(holiday.endDay, "2026-10-24")

    let occ = try XCTUnwrap(r.upserts.first { $0.providerEventId == "occ2" })
    XCTAssertEqual(occ.seriesId, "master2")
    XCTAssertEqual(occ.myResponse, .organizer)
  }

  func testIncrementalSyncDeletesRemovedItemsWithSamePreferHeader() async throws {
    let body = """
      {"@odata.deltaLink": "https://graph.microsoft.com/v1.0/delta?token=NEW",
       "value": [{"id": "gone1", "@removed": {"reason": "deleted"}},
                 {"id": "teams1", "subject": "Renamed", "start": {"dateTime": "2026-10-14T03:00:00.0000000"}, "end": {"dateTime": "2026-10-14T04:00:00.0000000"}}]}
      """
    let (p, t) = provider { _ in Reply(body: body) }
    let state = SyncState(
      calendarId: cal.id, deltaLink: "https://graph.microsoft.com/v1.0/delta?token=OLD",
      windowStart: testNow.addingTimeInterval(-90 * 86_400), windowEnd: testNow.addingTimeInterval(365 * 86_400))
    let r = try await p.sync(account: account, calendar: cal, state: state, now: testNow)
    XCTAssertFalse(r.replacesAll)
    XCTAssertEqual(r.deletedIds, ["ms:CAL1:gone1"])
    XCTAssertEqual(r.upserts.map(\.title), ["Renamed"])
    XCTAssertEqual(r.newState.deltaLink, "https://graph.microsoft.com/v1.0/delta?token=NEW")
    XCTAssertEqual(r.newState.windowEnd, state.windowEnd)
    XCTAssertEqual(t.requests[0].url?.absoluteString, state.deltaLink)
    XCTAssertEqual(t.requests[0].value(forHTTPHeaderField: "Prefer"), "outlook.timezone=\"UTC\", odata.maxpagesize=100")
  }

  func testWindowRollTriggersFreshInitialSync() async throws {
    let (p, t) = provider { _ in Reply(body: "{\"@odata.deltaLink\": \"https://x/delta?t=2\", \"value\": []}") }
    let state = SyncState(
      calendarId: cal.id, deltaLink: "https://graph.microsoft.com/v1.0/delta?token=OLD",
      windowStart: testNow.addingTimeInterval(-90 * 86_400), windowEnd: testNow.addingTimeInterval(300 * 86_400))
    let r = try await p.sync(account: account, calendar: cal, state: state, now: testNow)
    XCTAssertTrue(r.replacesAll)
    XCTAssertTrue(t.requests[0].url!.path.hasSuffix("/calendarView/delta"))
    XCTAssertEqual(query(t.requests[0], "startDateTime"), "2026-07-16T03:00:00Z")
  }

  func testExpiredDeltaFallsBackToInitialSync() async throws {
    let (p, t) = provider { req in
      req.url!.absoluteString.contains("token=OLD")
        ? Reply(status: 410, body: "{}") : Reply(body: "{\"@odata.deltaLink\": \"https://x/delta?t=2\", \"value\": []}")
    }
    let state = SyncState(
      calendarId: cal.id, deltaLink: "https://graph.microsoft.com/v1.0/delta?token=OLD",
      windowStart: testNow, windowEnd: testNow.addingTimeInterval(365 * 86_400))
    let r = try await p.sync(account: account, calendar: cal, state: state, now: testNow)
    XCTAssertTrue(r.replacesAll)
    XCTAssertEqual(t.requests.count, 2)
  }

  func testRetryAfterIsHonouredAndCapped() async throws {
    let count = Counter()
    let sleeps = SleepLog()
    let (p, _) = provider(
      { _ in
        let n = count.next()
        if n == 1 { return Reply(status: 429, headers: ["Retry-After": "7"]) }
        if n == 2 { return Reply(status: 503, headers: ["Retry-After": "1000"]) }
        return Reply(body: "{\"@odata.deltaLink\": \"https://x/delta\", \"value\": []}")
      }, sleeps: sleeps)
    _ = try await p.sync(account: account, calendar: cal, state: nil, now: testNow)
    XCTAssertEqual(sleeps.values, [7, 300])
  }

  func testUnauthorizedMapsToNeedsSignIn() async {
    let (p, _) = provider { _ in Reply(status: 401) }
    do {
      _ = try await p.listCalendars(account: account)
      XCTFail("expected an error")
    } catch {
      XCTAssertEqual(error as? SyncError, .needsSignIn)
    }
  }

  func testListCalendarsFallsBackToInkColours() async throws {
    let (p, _) = provider { _ in
      Reply(body: """
        {"value": [{"id": "a", "name": "One", "hexColor": "", "canEdit": true},
                   {"id": "b", "name": "Two", "hexColor": "#112233", "canEdit": false}]}
        """)
    }
    let cals = try await p.listCalendars(account: account)
    XCTAssertEqual(cals.map(\.providerColorHex), ["#3D5A96", "#112233"])
    XCTAssertEqual(cals.map(\.canEdit), [true, false])
  }

  func testRespondPostsToTheRightAction() async throws {
    let (p, t) = provider { _ in Reply(status: 202, body: "") }
    let event = EventInstance(calendarId: cal.id, providerEventId: "teams1", title: "x", start: testNow, end: testNow)
    try await p.respond(account: account, calendar: cal, event: event, response: .tentative)
    let req = t.requests[0]
    XCTAssertEqual(req.httpMethod, "POST")
    XCTAssertTrue(req.url!.path.hasSuffix("/me/events/teams1/tentativelyAccept"))
    XCTAssertEqual(String(data: req.httpBody ?? Data(), encoding: .utf8)?.contains("\"sendResponse\":true"), true)
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var n = 0
  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    n += 1
    return n
  }
}
