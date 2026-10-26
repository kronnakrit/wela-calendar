import WelaCore
import XCTest

@testable import WelaSync

/// Scriptable provider for engine tests.
final class FakeProvider: CalendarProvider, @unchecked Sendable {
  enum RespondMode { case ok, offline, fail }

  private let lock = NSLock()
  private var _syncCalls = 0
  private var _active = 0
  private var _maxActive = 0
  private var _respondMode = RespondMode.ok
  private var _responded: [ResponseStatus] = []
  var calendars: [CalendarInfo]
  var events: [EventInstance]
  var delay: UInt64 = 0
  var syncError: Error?

  init(calendars: [CalendarInfo], events: [EventInstance]) {
    self.calendars = calendars
    self.events = events
  }

  var syncCalls: Int { lock.withLock { _syncCalls } }
  var maxActive: Int { lock.withLock { _maxActive } }
  var responded: [ResponseStatus] { lock.withLock { _responded } }
  var respondMode: RespondMode {
    get { lock.withLock { _respondMode } }
    set { lock.withLock { _respondMode = newValue } }
  }

  func listCalendars(account: Account) async throws -> [CalendarInfo] { calendars }

  func sync(account: Account, calendar: CalendarInfo, state: SyncState?, now: Date) async throws
    -> SyncResult
  {
    lock.withLock {
      _syncCalls += 1
      _active += 1
      _maxActive = max(_maxActive, _active)
    }
    defer { lock.withLock { _active -= 1 } }
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    if let syncError { throw syncError }
    return SyncResult(
      upserts: events.filter { $0.calendarId == calendar.id },
      deletedIds: [],
      newState: SyncState(calendarId: calendar.id, deltaLink: "d", lastSyncedAt: now),
      replacesAll: true)
  }

  func respond(
    account: Account, calendar: CalendarInfo, event: EventInstance, response: ResponseStatus
  ) async throws {
    switch respondMode {
    case .ok: lock.withLock { _responded.append(response) }
    case .offline: throw SyncError.offline
    case .fail: throw SyncError.http(status: 403, message: "forbidden")
    }
  }
}

final class SyncEngineTests: XCTestCase {
  let account = Account(id: "a", provider: .mock, email: "x@y.z", displayName: "X")
  let cal = CalendarInfo(
    accountId: "a", providerCalendarId: "c", name: "Work", providerColorHex: "#3D5A96")
  var store: Store!
  var provider: FakeProvider!
  var engine: SyncEngine!
  var event: EventInstance!

  override func setUpWithError() throws {
    store = try Store()
    try store.saveAccount(account)
    event = EventInstance(
      calendarId: cal.id, providerEventId: "e1", title: "Invite", start: testNow,
      end: testNow.addingTimeInterval(3600), myResponse: .notResponded)
    provider = FakeProvider(calendars: [cal], events: [event])
    engine = SyncEngine(store: store, providers: [.mock: provider], now: { testNow })
  }

  func testSyncStoresCalendarsAndEventsAndKeepsUserChoices() async throws {
    await engine.sync(account: account)
    XCTAssertEqual(try store.event(id: event.id)?.title, "Invite")
    XCTAssertEqual(try store.syncState(calendarId: cal.id)?.deltaLink, "d")

    try store.setCalendarVisibility(id: cal.id, isVisible: false)
    try store.setCalendarColor(id: cal.id, hex: "#123456")
    await engine.sync(account: account)
    let kept = try XCTUnwrap(try store.calendar(id: cal.id))
    XCTAssertFalse(kept.isVisible)
    XCTAssertEqual(kept.userColorHex, "#123456")
  }

  func testRemovedCalendarIsDeleted() async throws {
    await engine.sync(account: account)
    provider.calendars = []
    await engine.sync(account: account)
    XCTAssertNil(try store.calendar(id: cal.id))
    XCTAssertEqual(try store.eventCount(), 0)
  }

  func testSignInErrorKeepsCachedDataAndMarksAccount() async throws {
    await engine.sync(account: account)
    provider.syncError = SyncError.needsSignIn
    await engine.sync(account: account)
    XCTAssertEqual(try store.account(id: "a")?.status, .needsSignIn)
    XCTAssertEqual(try store.eventCount(), 1)
    provider.syncError = nil
    await engine.sync(account: account)
    XCTAssertEqual(try store.account(id: "a")?.status, .ok)
  }

  func testOfflineSyncLeavesAccountStatusAlone() async throws {
    await engine.sync(account: account)
    provider.syncError = SyncError.offline
    await engine.sync(account: account)
    XCTAssertEqual(try store.account(id: "a")?.status, .ok)
    XCTAssertEqual(try store.eventCount(), 1)
  }

  func testConcurrentSyncsOfTheSameAccountDoNotDoubleRun() async throws {
    provider.delay = 200_000_000
    async let first: Void = engine.sync(account: account)
    async let second: Void = engine.sync(account: account)
    _ = await (first, second)
    XCTAssertEqual(provider.syncCalls, 1)
    XCTAssertEqual(provider.maxActive, 1)
  }

  func testRSVPIsOptimisticAndSent() async throws {
    await engine.sync(account: account)
    let stored = try XCTUnwrap(try store.event(id: event.id))
    try await engine.respond(to: stored, with: .accepted)
    XCTAssertEqual(try store.event(id: event.id)?.myResponse, .accepted)
    XCTAssertEqual(provider.responded, [.accepted])
    XCTAssertTrue(try store.pendingOutbox().isEmpty)
  }

  func testOfflineRSVPIsQueuedThenSentOnReconnect() async throws {
    await engine.sync(account: account)
    let stored = try XCTUnwrap(try store.event(id: event.id))
    provider.respondMode = .offline
    try await engine.respond(to: stored, with: .declined)
    XCTAssertEqual(try store.event(id: event.id)?.myResponse, .declined)  // optimistic
    XCTAssertEqual(try store.pendingOutbox().count, 1)
    XCTAssertTrue(provider.responded.isEmpty)

    provider.respondMode = .ok  // back online
    let failures = await engine.flushOutbox()
    XCTAssertTrue(failures.isEmpty)
    XCTAssertEqual(provider.responded, [.declined])
    XCTAssertTrue(try store.pendingOutbox().isEmpty)
    XCTAssertEqual(try store.event(id: event.id)?.myResponse, .declined)
  }

  func testFailedRSVPRollsBack() async throws {
    await engine.sync(account: account)
    let stored = try XCTUnwrap(try store.event(id: event.id))
    provider.respondMode = .fail
    do {
      try await engine.respond(to: stored, with: .accepted)
      XCTFail("expected a failure")
    } catch {
      XCTAssertTrue(error is RSVPError)
    }
    XCTAssertEqual(try store.event(id: event.id)?.myResponse, .notResponded)
    XCTAssertTrue(try store.pendingOutbox().isEmpty)
  }
}
