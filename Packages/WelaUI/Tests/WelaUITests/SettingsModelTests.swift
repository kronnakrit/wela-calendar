import XCTest

@testable import WelaUI

@MainActor
final class SettingsModelTests: XCTestCase {
  private func defaults() -> UserDefaults {
    let d = UserDefaults(suiteName: "wela-tests-\(UUID().uuidString)")!
    return d
  }

  func testDefaultsAndPersistence() {
    let d = defaults()
    let s = SettingsModel(defaults: d)
    XCTAssertEqual(s.weekStart, .system)
    XCTAssertTrue(s.showCancelled)
    XCTAssertFalse(s.showDeclined)
    XCTAssertEqual(s.alertLeadMinutes, 10)

    s.weekStart = .monday
    s.textSize = .large
    s.showDeclined = true
    let reloaded = SettingsModel(defaults: d)
    XCTAssertEqual(reloaded.weekStart, .monday)
    XCTAssertEqual(reloaded.textSize, .large)
    XCTAssertEqual(reloaded.textSize.scale, 1.15)
    XCTAssertTrue(reloaded.showDeclined)
  }

  func testCalendarOverrides() {
    let s = SettingsModel(defaults: defaults())
    s.calendarSystem = .buddhist
    s.weekStart = .monday
    let cal = s.makeCalendar(base: Calendar(identifier: .gregorian))
    XCTAssertEqual(cal.identifier, .buddhist)
    XCTAssertEqual(cal.firstWeekday, 2)
  }

  func testTimeTemplates() {
    let s = SettingsModel(defaults: defaults())
    XCTAssertEqual(s.timeTemplate, "jm")
    s.timeFormat = .h24
    XCTAssertEqual(s.timeTemplate, "Hm")
    s.timeFormat = .h12
    XCTAssertEqual(s.timeTemplate, "hma")
  }
}
