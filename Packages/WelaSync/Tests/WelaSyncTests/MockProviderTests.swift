#if DEBUG
  import WelaCore
  import XCTest

  @testable import WelaSync

  final class MockProviderTests: XCTestCase {
    func testSeedsRealisticMonth() throws {
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
      let now = cal.date(
        from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 20))!
      let store = try Store()
      try MockProvider.seed(into: store, now: now, calendar: cal)

      XCTAssertEqual(try store.calendars().count, 4)
      let events = try store.events(
        in: DateInterval(start: cal.startOfDay(for: now), duration: 86_400))
      let agenda = AgendaBuilder.agenda(for: now, events: events, calendar: cal)
      XCTAssertGreaterThanOrEqual(agenda.timed.count, 4)
      XCTAssertTrue(agenda.timed.contains { $0.isCancelled })
      XCTAssertTrue(
        agenda.timed.contains {
          $0.event.start <= now && now < $0.event.end && $0.event.joinURL != nil
        })

      let all = try store.events(
        in: DateInterval(start: now.addingTimeInterval(-20 * 86_400), duration: 60 * 86_400))
      XCTAssertTrue(all.contains { $0.isBirthday })
      XCTAssertTrue(all.contains { $0.myResponse == .notResponded })
    }
  }
#endif
