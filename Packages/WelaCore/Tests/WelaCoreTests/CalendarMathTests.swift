import XCTest

@testable import WelaCore

final class CalendarMathTests: XCTestCase {
  func testOctober2026SundayFirst() {
    let cal = makeCalendar(timeZone: "Asia/Bangkok")
    let grid = CalendarMath.monthGrid(for: date(2026, 10, 14, in: cal), calendar: cal, now: date(2026, 10, 14, in: cal))
    XCTAssertEqual(grid.count, 42)
    XCTAssertEqual(grid.first?.date, date(2026, 9, 27, in: cal))
    XCTAssertEqual(grid.last?.date, date(2026, 11, 7, in: cal))
    XCTAssertEqual(grid.filter(\.isInMonth).count, 31)
    XCTAssertEqual(grid.filter(\.isToday).map(\.date), [date(2026, 10, 14, in: cal)])
  }

  func testMondayFirst() {
    let cal = makeCalendar(firstWeekday: 2, timeZone: "Asia/Bangkok")
    let grid = CalendarMath.monthGrid(for: date(2026, 10, 1, in: cal), calendar: cal)
    XCTAssertEqual(grid.first?.date, date(2026, 9, 28, in: cal))
    XCTAssertEqual(grid.last?.date, date(2026, 11, 8, in: cal))
  }

  func testBuddhistThaiTitle() {
    let cal = makeCalendar(identifier: .buddhist, locale: "th_TH", timeZone: "Asia/Bangkok")
    let d = date(2026, 10, 14, in: makeCalendar(timeZone: "Asia/Bangkok"))
    let locale = Locale(identifier: "th_TH")
    XCTAssertEqual(CalendarMath.yearString(for: d, calendar: cal, locale: locale), "2569")
    XCTAssertEqual(CalendarMath.monthTitle(for: d, calendar: cal, locale: locale), "ตุลาคม 2569")
  }

  func testGregorianYearIsNotBuddhist() {
    let cal = makeCalendar(timeZone: "Asia/Bangkok")
    let d = date(2026, 10, 14, in: cal)
    XCTAssertEqual(CalendarMath.monthTitle(for: d, calendar: cal, locale: Locale(identifier: "en_US")), "October 2026")
  }

  func testDSTMonthHasConsecutiveDays() {
    let cal = makeCalendar(timeZone: "America/New_York")
    let grid = CalendarMath.monthGrid(for: date(2026, 3, 15, in: cal), calendar: cal)
    XCTAssertEqual(grid.count, 42)
    XCTAssertEqual(grid.first?.date, date(2026, 3, 1, in: cal))
    XCTAssertEqual(grid.last?.date, date(2026, 4, 11, in: cal))
    for (a, b) in zip(grid, grid.dropFirst()) {
      XCTAssertEqual(cal.dateComponents([.day], from: a.date, to: b.date).day, 1)
    }
    // 8 March 2026 is the spring-forward day: it is only 23 hours long.
    let mar8 = grid.first { cal.component(.day, from: $0.date) == 8 && $0.isInMonth }!
    let mar9 = grid.first { cal.component(.day, from: $0.date) == 9 && $0.isInMonth }!
    XCTAssertEqual(mar9.date.timeIntervalSince(mar8.date), 23 * 3600)
  }

  func testWeekdaySymbolsStartAtFirstWeekday() {
    let cal = makeCalendar(firstWeekday: 2, timeZone: "UTC")
    XCTAssertEqual(CalendarMath.weekdaySymbols(calendar: cal).count, 7)
    XCTAssertEqual(CalendarMath.weekdaySymbols(calendar: cal).first, "Mon")
  }
}
