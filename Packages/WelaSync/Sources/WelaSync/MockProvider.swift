#if DEBUG
  import Foundation
  import WelaCore

  /// Seeds the store with a realistic month of fake events. Debug builds only; enabled with
  /// the `-UseMockData` launch argument. Release builds never contain this code.
  public enum MockProvider {
    public static let accountId = "mock"
    public static let workId = "mock:work"
    public static let personalId = "mock:personal"
    public static let sharedId = "mock:shared"
    public static let holidaysId = "mock:holidays"

    public static func seed(into store: Store, now: Date = Date(), calendar: Calendar = .current)
      throws
    {
      try store.saveAccount(
        Account(id: accountId, provider: .mock, email: "demo@example.com", displayName: "Demo"))
      let cals = [
        CalendarInfo(
          accountId: accountId, providerCalendarId: "work", name: "Work",
          providerColorHex: "#3D5A96", canEdit: true),
        CalendarInfo(
          accountId: accountId, providerCalendarId: "personal", name: "Personal",
          providerColorHex: "#5F8A5E", canEdit: true),
        CalendarInfo(
          accountId: accountId, providerCalendarId: "shared", name: "Team (shared)",
          providerColorHex: "#7B5486"),
        CalendarInfo(
          accountId: accountId, providerCalendarId: "holidays", name: "Holidays & Birthdays",
          providerColorHex: "#BF8A2C"),
      ]
      try store.saveCalendars(cals)
      try store.upsertEvents(events(now: now, calendar: calendar))
    }

    static func events(now: Date, calendar: Calendar) -> [EventInstance] {
      let today = calendar.startOfDay(for: now)
      func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
      func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
      }
      func key(_ offset: Int) -> String { DayKey.string(for: day(offset), timeZone: calendar.timeZone) }

      let workTitles = [
        "OP Weekly Meeting", "Design review", "1:1 with Mali", "Sprint planning",
        "Customer call", "Roadmap sync", "Hiring panel", "Retro",
      ]
      let rooms: [String?] = ["Spark Room", "Studio B", "Room 4", nil, "Lakeview", nil]
      let personalTitles = ["Lunch with Nok", "Gym", "Dentist", "Thai class", "Dinner"]
      let sharedTitles = ["Team standup", "All hands", "Demo day"]
      let teams = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_mock/0")

      let workId = Self.workId, sharedId = Self.sharedId
      let personalId = Self.personalId, holidaysId = Self.holidaysId

      var out: [EventInstance] = []
      func add(
        _ id: String, _ cal: String, _ title: String, _ start: Date, _ minutes: Int,
        location: String? = nil, response: ResponseStatus = .accepted,
        status: EventStatus = .confirmed, join: Bool = false, attendees: [Attendee] = []
      ) {
        var e = EventInstance(
          calendarId: cal, providerEventId: id, title: title, start: start,
          end: start.addingTimeInterval(TimeInterval(minutes * 60)), location: location,
          organizerEmail: "boss@example.com", attendees: attendees, myResponse: response,
          status: status)
        if join {
          e.joinURL = teams
          e.conferenceKind = .teams
        }
        out.append(e)
      }

      for offset in -14...30 {
        let n = abs(offset)
        add(
          "w1-\(offset)", workId, workTitles[n % workTitles.count], at(offset, 9, 30), 60,
          location: rooms[n % rooms.count], join: n % 2 == 0)
        add(
          "s-\(offset)", sharedId, sharedTitles[n % sharedTitles.count], at(offset, 11), 30,
          join: true)
        add(
          "p-\(offset)", personalId, personalTitles[n % personalTitles.count], at(offset, 12, 30),
          60)
        add(
          "w2-\(offset)", workId, workTitles[(n + 3) % workTitles.count], at(offset, 15), 45,
          location: rooms[(n + 2) % rooms.count])
      }

      // Teams meeting in progress right now.
      add(
        "now", workId, "Weekly sync (in progress)", now.addingTimeInterval(-15 * 60), 45,
        join: true)
      // Cancelled meeting later today.
      add("cancelled", workId, "Budget review", at(0, 17), 60, location: "Room 4", status: .cancelled)
      // Invite that has not been answered.
      add(
        "invite", workId, "Design sync", at(1, 10), 60, response: .notResponded, join: true,
        attendees: [
          Attendee(name: "Mali Srisuk", email: "mali@example.com", response: .accepted),
          Attendee(name: "Demo", email: "demo@example.com", response: .notResponded),
        ])
      add("tentative", sharedId, "Offsite planning", at(2, 14), 90, response: .tentative)

      let birthday = EventInstance.allDay(
        calendarId: holidaysId, providerEventId: "bday", title: "Somchai's Birthday",
        startDay: key(2), endDay: key(3), isBirthday: true)
      let holiday = EventInstance.allDay(
        calendarId: holidaysId, providerEventId: "holiday", title: "Chulalongkorn Day",
        startDay: key(5), endDay: key(6))
      let trip = EventInstance.allDay(
        calendarId: personalId, providerEventId: "trip", title: "Chiang Mai trip",
        startDay: key(9), endDay: key(12))
      return out + [birthday, holiday, trip]
    }
  }
#endif
