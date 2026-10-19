import XCTest

@testable import WelaCore

final class AgendaBuilderTests: XCTestCase {
  let bkk = makeCalendar(timeZone: "Asia/Bangkok")

  func testAllDayEventStaysOnItsDateInUTCPlus7() {
    let holiday = EventInstance.allDay(
      calendarId: "a:cal", providerEventId: "h", title: "Holiday", startDay: "2026-10-14",
      endDay: "2026-10-15")
    func agenda(_ day: Int) -> Agenda {
      AgendaBuilder.agenda(for: date(2026, 10, day, 12, in: bkk), events: [holiday], calendar: bkk)
    }
    XCTAssertEqual(agenda(13).count, 0)
    XCTAssertEqual(agenda(14).allDay.map(\.event.title), ["Holiday"])
    XCTAssertEqual(agenda(15).count, 0)
  }

  func testMultiDayAllDayLabels() {
    let trip = EventInstance.allDay(
      calendarId: "a:cal", providerEventId: "t", title: "Trip", startDay: "2026-10-14",
      endDay: "2026-10-17")
    let labels = (14...16).map { day in
      AgendaBuilder.agenda(for: date(2026, 10, day, in: bkk), events: [trip], calendar: bkk)
        .allDay.first?.multiDayLabel
    }
    XCTAssertEqual(labels, ["Day 1 of 3", "Day 2 of 3", "Day 3 of 3"])
    XCTAssertEqual(
      AgendaBuilder.agenda(for: date(2026, 10, 17, in: bkk), events: [trip], calendar: bkk).count, 0
    )
  }

  func testTimedEventSpanningMidnightAppearsOnBothDays() {
    let e = timedEvent(
      "late", start: date(2026, 10, 14, 23, 0, in: bkk), end: date(2026, 10, 15, 1, 0, in: bkk))
    let d14 = AgendaBuilder.agenda(for: date(2026, 10, 14, in: bkk), events: [e], calendar: bkk)
    let d15 = AgendaBuilder.agenda(for: date(2026, 10, 15, in: bkk), events: [e], calendar: bkk)
    XCTAssertEqual(d14.timed.first?.multiDayLabel, "Day 1 of 2")
    XCTAssertEqual(d15.timed.first?.multiDayLabel, "Day 2 of 2")
  }

  func testEventEndingAtMidnightDoesNotSpill() {
    let e = timedEvent(
      "x", start: date(2026, 10, 14, 22, 0, in: bkk), end: date(2026, 10, 15, 0, 0, in: bkk))
    XCTAssertEqual(
      AgendaBuilder.agenda(for: date(2026, 10, 15, in: bkk), events: [e], calendar: bkk).count, 0)
    XCTAssertNil(
      AgendaBuilder.agenda(for: date(2026, 10, 14, in: bkk), events: [e], calendar: bkk).timed
        .first?.multiDayLabel)
  }

  func testOrderingAllDayFirstThenTimedByStart() {
    let day = date(2026, 10, 14, in: bkk)
    let b = timedEvent(
      "b", start: date(2026, 10, 14, 11, in: bkk), end: date(2026, 10, 14, 12, in: bkk))
    let a = timedEvent(
      "a", start: date(2026, 10, 14, 9, in: bkk), end: date(2026, 10, 14, 10, in: bkk))
    let bday = EventInstance.allDay(
      calendarId: "a:cal", providerEventId: "bd", title: "Birthday", startDay: "2026-10-14",
      endDay: "2026-10-15", isBirthday: true)
    let hol = EventInstance.allDay(
      calendarId: "a:cal", providerEventId: "h", title: "Holiday", startDay: "2026-10-14",
      endDay: "2026-10-15")
    let ag = AgendaBuilder.agenda(for: day, events: [b, bday, a, hol], calendar: bkk)
    XCTAssertEqual(ag.allDay.map(\.event.title), ["Holiday", "Birthday"])
    XCTAssertEqual(ag.timed.map(\.event.title), ["a", "b"])
  }

  func testDeclinedHiddenByDefaultAndCancelledFlagged() {
    let day = date(2026, 10, 14, in: bkk)
    let s = date(2026, 10, 14, 9, in: bkk)
    let e = date(2026, 10, 14, 10, in: bkk)
    let declined = timedEvent("d", start: s, end: e, response: .declined)
    let cancelled = timedEvent("c", start: s, end: e, status: .cancelled)
    let ok = timedEvent("ok", start: s, end: e)
    let all = [declined, cancelled, ok]

    let byDefault = AgendaBuilder.agenda(for: day, events: all, calendar: bkk)
    XCTAssertEqual(Set(byDefault.timed.map(\.event.id)), ["a:cal:c", "a:cal:ok"])
    XCTAssertEqual(byDefault.timed.first { $0.event.providerEventId == "c" }?.isCancelled, true)

    let hideCancelled = AgendaBuilder.agenda(
      for: day, events: all, options: AgendaOptions(showCancelled: false), calendar: bkk)
    XCTAssertEqual(hideCancelled.timed.map(\.event.providerEventId), ["ok"])

    let showDeclined = AgendaBuilder.agenda(
      for: day, events: all, options: AgendaOptions(showDeclined: true), calendar: bkk)
    XCTAssertEqual(showDeclined.count, 3)
  }

  func testCalendarVisibilityFilter() {
    let s = date(2026, 10, 14, 9, in: bkk)
    let e = date(2026, 10, 14, 10, in: bkk)
    let one = timedEvent("1", calendar: "x:1", start: s, end: e)
    let two = timedEvent("2", calendar: "x:2", start: s, end: e)
    let ag = AgendaBuilder.agenda(
      for: s, events: [one, two], visibleCalendarIds: ["x:2"], calendar: bkk)
    XCTAssertEqual(ag.timed.map(\.event.providerEventId), ["2"])
  }

  func testDotsCappedAtFourOrderedByStartAndSkipCancelled() {
    let day = date(2026, 10, 14, in: bkk)
    var events: [EventInstance] = []
    for h in 8..<14 {
      events.append(
        timedEvent(
          "e\(h)", calendar: h % 2 == 0 ? "x:blue" : "x:green",
          start: date(2026, 10, 14, h, in: bkk), end: date(2026, 10, 14, h + 1, in: bkk)))
    }
    events.append(
      timedEvent(
        "gone", calendar: "x:red", start: date(2026, 10, 14, 7, in: bkk),
        end: date(2026, 10, 14, 8, in: bkk), status: .cancelled))
    let dots = DotSummary.dots(
      for: day, events: events, calendarColors: ["x:blue": "B", "x:green": "G", "x:red": "R"],
      calendar: bkk)
    XCTAssertEqual(dots, ["B", "G", "B", "G"])
  }
}
