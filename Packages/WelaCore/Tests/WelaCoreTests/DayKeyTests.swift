import XCTest

@testable import WelaCore

final class DayKeyTests: XCTestCase {
  func testRoundTripInBangkok() {
    let tz = TimeZone(identifier: "Asia/Bangkok")!
    let d = DayKey.date(from: "2026-10-14", timeZone: tz)!
    XCTAssertEqual(DayKey.string(for: d, timeZone: tz), "2026-10-14")
    XCTAssertEqual(DayKey.string(for: d.addingTimeInterval(23 * 3600), timeZone: tz), "2026-10-14")
  }

  func testDaysBetween() {
    XCTAssertEqual(DayKey.daysBetween("2026-10-14", "2026-10-17"), 3)
    XCTAssertEqual(DayKey.daysBetween("2026-02-28", "2026-03-01"), 1)
  }
}
