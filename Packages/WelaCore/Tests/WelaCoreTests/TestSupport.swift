import Foundation

@testable import WelaCore

func makeCalendar(
  id: String = "UTC", firstWeekday: Int = 1, identifier: Calendar.Identifier = .gregorian,
  locale: String = "en_US", timeZone: String
) -> Calendar {
  var c = Calendar(identifier: identifier)
  c.timeZone = TimeZone(identifier: timeZone)!
  c.locale = Locale(identifier: locale)
  c.firstWeekday = firstWeekday
  return c
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in cal: Calendar) -> Date {
  cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func timedEvent(
  _ id: String, calendar calId: String = "a:cal", start: Date, end: Date, title: String? = nil,
  response: ResponseStatus = .accepted, status: EventStatus = .confirmed
) -> EventInstance {
  EventInstance(
    calendarId: calId, providerEventId: id, title: title ?? id, start: start, end: end,
    myResponse: response, status: status)
}
