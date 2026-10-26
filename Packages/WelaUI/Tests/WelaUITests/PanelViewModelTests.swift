import WelaCore
import XCTest

@testable import WelaUI

@MainActor
final class PanelViewModelTests: XCTestCase {
  private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
    c.firstWeekday = 1
    return c
  }

  private func makeVM() throws -> (PanelViewModel, Store) {
    let store = try Store()
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 20))!
    let vm = PanelViewModel(
      store: store, calendar: cal, locale: Locale(identifier: "en_US"), now: now)
    return (vm, store)
  }

  func testInitialState() throws {
    let (vm, _) = try makeVM()
    XCTAssertEqual(vm.gridCells.count, 42)
    XCTAssertEqual(vm.monthName, "October")
    XCTAssertEqual(vm.yearString, "2026")
    XCTAssertEqual(vm.agendaTitle.label, "TODAY")
    XCTAssertEqual(vm.todayWeekdayIndex, 3)
  }

  func testMonthAndDayNavigation() throws {
    let (vm, _) = try makeVM()
    vm.moveMonth(by: 1)
    XCTAssertEqual(vm.monthName, "November")
    XCTAssertEqual(cal.component(.day, from: vm.selectedDay), 1)
    vm.moveSelection(days: -1)  // 31 October: month follows the selection
    XCTAssertEqual(vm.monthName, "October")
    vm.goToToday()
    XCTAssertEqual(vm.agendaTitle.label, "TODAY")
  }

  func testTomorrowLabel() throws {
    let (vm, _) = try makeVM()
    vm.moveSelection(days: 1)
    XCTAssertEqual(vm.agendaTitle.label, "TOMORROW")
    vm.moveSelection(days: 1)
    XCTAssertEqual(vm.agendaTitle.label, "FRIDAY")
  }

  func testEventSelectionClampsAtEnds() async throws {
    let (vm, store) = try makeVM()
    let account = Account(id: "a", provider: .mock, email: "x", displayName: "x")
    let calInfo = CalendarInfo(
      accountId: "a", providerCalendarId: "c", name: "C", providerColorHex: "#3D5A96")
    try store.saveAccount(account)
    try store.saveCalendars([calInfo])
    let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))!
    try store.upsertEvents([
      EventInstance(
        calendarId: calInfo.id, providerEventId: "1", title: "One", start: start,
        end: start.addingTimeInterval(3600)),
      EventInstance(
        calendarId: calInfo.id, providerEventId: "2", title: "Two",
        start: start.addingTimeInterval(7200), end: start.addingTimeInterval(10800)),
    ])
    for _ in 0..<50 where vm.agendaItems.count < 2 { try await Task.sleep(nanoseconds: 50_000_000) }
    XCTAssertEqual(vm.agendaItems.count, 2)
    vm.moveEventSelection(by: 1)
    XCTAssertEqual(vm.selectedEventID, "\(calInfo.id):1")
    vm.moveEventSelection(by: 5)
    XCTAssertEqual(vm.selectedEventID, "\(calInfo.id):2")
    vm.moveEventSelection(by: -5)
    XCTAssertEqual(vm.selectedEventID, "\(calInfo.id):1")
  }

  func testOpenWidgetLinks() throws {
    let (vm, store) = try makeVM()
    let calInfo = CalendarInfo(
      accountId: "a", providerCalendarId: "c", name: "C", providerColorHex: "#3D5A96")
    try store.saveAccount(Account(id: "a", provider: .mock, email: "x", displayName: "x"))
    try store.saveCalendars([calInfo])
    let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
    try store.upsertEvents([
      EventInstance(
        calendarId: calInfo.id, providerEventId: "1", title: "One", start: start,
        end: start.addingTimeInterval(3600))
    ])

    vm.open(.event(id: "\(calInfo.id):1"))
    XCTAssertEqual(vm.monthName, "November")
    XCTAssertEqual(cal.component(.day, from: vm.selectedDay), 2)
    XCTAssertEqual(vm.detailEventID, "\(calInfo.id):1")

    vm.open(.day("2026-12-25"))
    XCTAssertEqual(vm.monthName, "December")
    XCTAssertEqual(cal.component(.day, from: vm.selectedDay), 25)
    XCTAssertNil(vm.detailEventID)

    vm.open(.event(id: "missing"))
    XCTAssertEqual(vm.monthName, "December")
  }
}
