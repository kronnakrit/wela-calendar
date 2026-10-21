import XCTest

@testable import WelaCore

final class StoreTests: XCTestCase {
  let utc = makeCalendar(timeZone: "UTC")
  var store: Store!
  let account = Account(id: "a", provider: .microsoft, email: "me@example.com", displayName: "Me")
  let cal1 = CalendarInfo(
    accountId: "a", providerCalendarId: "1", name: "Work", providerColorHex: "#3D5A96",
    canEdit: true)
  let cal2 = CalendarInfo(
    accountId: "a", providerCalendarId: "2", name: "Home", providerColorHex: "#5F8A5E")

  override func setUpWithError() throws {
    store = try Store()
    try store.saveAccount(account)
    try store.saveCalendars([cal1, cal2])
  }

  private func event(
    _ id: String, cal: CalendarInfo? = nil, h: Int, title: String = "Standup",
    attendees: [Attendee] = []
  ) -> EventInstance {
    var e = timedEvent(
      id, calendar: (cal ?? cal1).id, start: date(2026, 10, 14, h, in: utc),
      end: date(2026, 10, 14, h + 1, in: utc), title: title)
    e.attendees = attendees
    e.joinURL = URL(string: "https://meet.google.com/abc-defg-hij")
    e.conferenceKind = .meet
    return e
  }

  private var october: DateInterval {
    DateInterval(start: date(2026, 10, 1, in: utc), end: date(2026, 11, 1, in: utc))
  }

  func testAccountAndCalendarRoundTrip() throws {
    XCTAssertEqual(try store.accounts(), [account])
    var withError = account
    withError.status = .error("boom")
    try store.saveAccount(withError)
    XCTAssertEqual(try store.accounts().first?.status, .error("boom"))
    XCTAssertEqual(Set(try store.calendars().map(\.id)), [cal1.id, cal2.id])
    try store.setCalendarVisibility(id: cal2.id, isVisible: false)
    XCTAssertEqual(try store.calendars().first { $0.id == cal2.id }?.isVisible, false)
    try store.setCalendarColor(id: cal1.id, hex: "#123456")
    XCTAssertEqual(try store.calendars().first { $0.id == cal1.id }?.effectiveColorHex, "#123456")
  }

  func testEventInsertUpdateDelete() throws {
    var e = event(
      "e1", h: 9,
      attendees: [Attendee(name: "Ada Lovelace", email: "ada@example.com", response: .accepted)])
    try store.upsertEvents([e])
    XCTAssertEqual(try store.event(id: e.id), e)

    e.title = "Renamed"
    e.myResponse = .tentative
    try store.upsertEvents([e])
    XCTAssertEqual(try store.eventCount(), 1)
    XCTAssertEqual(try store.event(id: e.id)?.title, "Renamed")
    XCTAssertEqual(try store.event(id: e.id)?.myResponse, .tentative)

    try store.deleteEvents(ids: [e.id])
    XCTAssertNil(try store.event(id: e.id))
    XCTAssertTrue(try store.search("Renamed", in: october, calendar: utc).isEmpty)
  }

  func testAllDayEventRoundTripKeepsDates() throws {
    let e = EventInstance.allDay(
      calendarId: cal1.id, providerEventId: "h", title: "Holiday", startDay: "2026-10-14",
      endDay: "2026-10-15")
    try store.upsertEvents([e])
    let loaded = try store.event(id: e.id)
    XCTAssertEqual(loaded?.startDay, "2026-10-14")
    XCTAssertEqual(loaded?.endDay, "2026-10-15")
    XCTAssertEqual(
      try store.events(
        in: DateInterval(start: date(2026, 10, 14, in: utc), end: date(2026, 10, 15, in: utc))
      ).count, 1)
  }

  func testRangeAndCalendarFilter() throws {
    try store.upsertEvents([event("a", h: 9), event("b", cal: cal2, h: 10)])
    let day = DateInterval(start: date(2026, 10, 14, in: utc), end: date(2026, 10, 15, in: utc))
    XCTAssertEqual(try store.events(in: day).count, 2)
    XCTAssertEqual(try store.events(in: day, calendarIds: [cal2.id]).map(\.providerEventId), ["b"])
    let nextMonth = DateInterval(start: date(2026, 12, 1, in: utc), end: date(2026, 12, 2, in: utc))
    XCTAssertTrue(try store.events(in: nextMonth).isEmpty)
  }

  func testFullTextSearchFindsAttendeeName() throws {
    try store.upsertEvents([
      event(
        "a", h: 9, title: "Planning",
        attendees: [Attendee(name: "Grace Hopper", email: "grace@navy.mil")]),
      event("b", h: 11, title: "Lunch"),
    ])
    let groups = try store.search("hop", in: october, calendar: utc)
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups.first?.events.map(\.providerEventId), ["a"])
    XCTAssertEqual(groups.first?.day, date(2026, 10, 14, in: utc))
    XCTAssertEqual(
      try store.search("lunch", in: october, calendarIds: [cal2.id], calendar: utc).count, 0)
    XCTAssertTrue(try store.search("   ", in: october, calendar: utc).isEmpty)
  }

  func testSearchToleratesQuotes() throws {
    try store.upsertEvents([event("a", h: 9, title: "Say \"hi\"")])
    XCTAssertNoThrow(try store.search("\"hi", in: october, calendar: utc))
  }

  func testReplaceEventsSwapsCalendarContents() throws {
    try store.upsertEvents([event("old", h: 9), event("other", cal: cal2, h: 9)])
    try store.replaceEvents(calendarId: cal1.id, with: [event("new", h: 10)])
    XCTAssertEqual(Set(try store.events(in: october).map(\.providerEventId)), ["new", "other"])
  }

  func testSyncStateAndOutbox() throws {
    let state = SyncState(
      calendarId: cal1.id, deltaLink: "https://graph/delta?token=1",
      windowStart: date(2026, 7, 1, in: utc), windowEnd: date(2027, 10, 1, in: utc))
    try store.saveSyncState(state)
    XCTAssertEqual(try store.syncState(calendarId: cal1.id)?.deltaLink, state.deltaLink)

    let queued = try store.enqueue(
      OutboxItem(accountId: "a", eventId: "x", action: "accept", payload: Data([1, 2])))
    XCTAssertNotNil(queued.id)
    XCTAssertEqual(try store.pendingOutbox().map(\.payload), [Data([1, 2])])
    try store.removeOutboxItem(id: queued.id!)
    XCTAssertTrue(try store.pendingOutbox().isEmpty)
  }

  func testDeleteAccountRemovesEverything() throws {
    try store.upsertEvents([event("a", h: 9, title: "Searchable")])
    try store.saveSyncState(SyncState(calendarId: cal1.id, syncToken: "t"))
    try store.enqueue(OutboxItem(accountId: "a", eventId: "x", action: "accept"))
    try store.deleteAccount(id: "a")
    XCTAssertTrue(try store.accounts().isEmpty)
    XCTAssertTrue(try store.calendars().isEmpty)
    XCTAssertEqual(try store.eventCount(), 0)
    XCTAssertNil(try store.syncState(calendarId: cal1.id))
    XCTAssertTrue(try store.pendingOutbox().isEmpty)
    XCTAssertTrue(try store.search("Searchable", in: october, calendar: utc).isEmpty)
  }

  func testObserveEventsEmitsUpdates() async throws {
    var iterator = store.observeEvents(in: october).makeAsyncIterator()
    let initial = await iterator.next()
    XCTAssertEqual(initial?.count, 0)
    try store.upsertEvents([event("a", h: 9)])
    let updated = await iterator.next()
    XCTAssertEqual(updated?.count, 1)
  }

  func testReadOnlyStoreSeesWritesAndRejectsWrites() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("wela-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let writer = try Store(path: path, observesSuspension: true)
    try writer.saveAccount(account)
    try writer.saveCalendars([cal1])
    try writer.upsertEvents([event("a", h: 9)])

    let reader = try Store(path: path, readOnly: true)
    XCTAssertEqual(try reader.accounts(), [account])
    XCTAssertEqual(try reader.events(in: october).map(\.providerEventId), ["a"])
    XCTAssertThrowsError(try reader.upsertEvents([event("b", h: 10)]))

    try writer.upsertEvents([event("b", h: 10)])
    XCTAssertEqual(try reader.events(in: october).count, 2)
  }

  func testReadOnlyStoreNeedsAnExistingFile() {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("wela-missing-\(UUID().uuidString).sqlite").path
    XCTAssertThrowsError(try Store(path: path, readOnly: true))
  }
}
