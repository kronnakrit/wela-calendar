import WelaCore
import XCTest

@testable import WelaUI

final class WidgetSnapshotTests: XCTestCase {
  private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
    c.firstWeekday = 1
    return c
  }
  private let work = CalendarInfo(
    accountId: "a", providerCalendarId: "w", name: "Work", providerColorHex: "#3D5A96")
  private let hidden = CalendarInfo(
    accountId: "a", providerCalendarId: "h", name: "Hidden", providerColorHex: "#5F8A5E",
    isVisible: false)

  private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
  }

  private func event(
    _ id: String, _ start: Date, minutes: Int = 60, calendar: CalendarInfo? = nil,
    status: EventStatus = .confirmed
  ) -> EventInstance {
    EventInstance(
      calendarId: (calendar ?? work).id, providerEventId: id, title: id, start: start,
      end: start.addingTimeInterval(TimeInterval(minutes * 60)), status: status)
  }

  private func snapshot(_ events: [EventInstance], now: Date) -> WidgetSnapshot {
    WidgetSnapshot.make(
      events: events, calendars: [work, hidden], hasAccounts: true, now: now, calendar: cal,
      locale: Locale(identifier: "en_US"), options: AgendaOptions(), timeTemplate: "Hm")
  }

  func testTodayDropsEndedHiddenAndCancelledEvents() {
    let events = [
      event("ended", at(14, 8)), event("now", at(14, 10)), event("later", at(14, 15)),
      event("hidden", at(14, 16), calendar: hidden),
      event("cancelled", at(14, 17), status: .cancelled),
      event("tomorrow", at(15, 9)), event("next week", at(25, 9)),
    ]
    let s = snapshot(events, now: at(14, 10, 20))
    XCTAssertEqual(s.today.items.map(\.title), ["now", "later"])
    XCTAssertEqual(s.days.map { $0.items.map(\.title) }, [["now", "later"], ["tomorrow"]])
    XCTAssertEqual(s.upNext?.title, "now")
    XCTAssertTrue(s.isNow(s.upNext!))
    XCTAssertEqual(s.dayLabel(s.days[1].day), "TOMORROW")
    XCTAssertEqual(s.timeRange(s.today.items[1]), "15:00–16:00")
    XCTAssertEqual(s.monthCells.count, 42)
    XCTAssertEqual(s.dots[cal.startOfDay(for: at(14, 0))], ["#3D5A96", "#3D5A96", "#3D5A96"])
  }

  func testUpNextMovesToTomorrowWhenTodayIsDone() {
    let s = snapshot([event("done", at(14, 8)), event("tomorrow", at(15, 9))], now: at(14, 20))
    XCTAssertTrue(s.today.items.isEmpty)
    XCTAssertEqual(s.upNext?.title, "tomorrow")
    XCTAssertFalse(s.isNow(s.upNext!))
  }

  func testRefreshDatesAreStartsEndsAndMidnight() {
    let events = [
      event("a", at(14, 9)), event("b", at(14, 15), minutes: 30),
      event("c", at(14, 17), status: .cancelled), event("far", at(16, 9)),
    ]
    let dates = WidgetSnapshot.refreshDates(events: events, now: at(14, 9, 30), calendar: cal)
    XCTAssertEqual(dates, [at(14, 10), at(14, 15), at(14, 15, 30), at(15, 0)])
  }

  func testTimelineHasOneSnapshotPerChange() {
    let events = [event("a", at(14, 9)), event("b", at(14, 15))]
    let timeline = WidgetSnapshot.timeline(
      events: events, calendars: [work], hasAccounts: true, now: at(14, 8), calendar: cal,
      locale: Locale(identifier: "en_US"), options: AgendaOptions(), timeTemplate: "Hm")
    XCTAssertEqual(
      timeline.map(\.date), [at(14, 8), at(14, 9), at(14, 10), at(14, 15), at(14, 16), at(15, 0)])
    XCTAssertEqual(timeline[2].today.items.map(\.title), ["b"])
    XCTAssertEqual(timeline.last?.today.items, [])
  }

  func testIntervalCoversGridAndLookAhead() {
    let now = at(30, 12)
    let interval = WidgetSnapshot.interval(now: now, calendar: cal)
    let grid = CalendarMath.monthGrid(for: now, calendar: cal, now: now)
    XCTAssertLessThanOrEqual(interval.start, grid.first!.date)
    XCTAssertGreaterThanOrEqual(interval.end, cal.date(byAdding: .day, value: 8, to: now)!)
  }

  @MainActor
  func testTimelineFromStore() throws {
    let store = try Store()
    try store.saveAccount(Account(id: "a", provider: .mock, email: "x", displayName: "x"))
    try store.saveCalendars([work])
    let now = Date()
    try store.upsertEvents([event("soon", now.addingTimeInterval(3600))])
    let settings = SettingsModel(defaults: UserDefaults(suiteName: "wela-\(UUID().uuidString)")!)
    let timeline = try WidgetSnapshot.timeline(store: store, settings: settings, now: now)
    XCTAssertTrue(timeline[0].hasAccounts)
    XCTAssertEqual(timeline[0].upNext?.title, "soon")
    XCTAssertFalse(WidgetSnapshot.empty().hasAccounts)
  }
}
