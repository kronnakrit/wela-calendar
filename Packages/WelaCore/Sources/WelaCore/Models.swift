import Foundation

public enum ProviderKind: String, Codable, Hashable, Sendable { case microsoft, google, mock }

public enum AccountStatus: Codable, Hashable, Sendable {
  case ok
  case needsSignIn
  case error(String)
}

public struct Account: Identifiable, Codable, Hashable, Sendable {
  public let id: String
  public let provider: ProviderKind
  public var email: String
  public var displayName: String
  public var status: AccountStatus

  public init(
    id: String, provider: ProviderKind, email: String, displayName: String,
    status: AccountStatus = .ok
  ) {
    self.id = id
    self.provider = provider
    self.email = email
    self.displayName = displayName
    self.status = status
  }
}

public struct CalendarInfo: Identifiable, Codable, Hashable, Sendable {
  /// "\(accountId):\(providerCalendarId)"
  public let id: String
  public let accountId: String
  public let providerCalendarId: String
  public var name: String
  public var providerColorHex: String
  public var userColorHex: String?
  public var isVisible: Bool
  public var canEdit: Bool

  public init(
    accountId: String, providerCalendarId: String, name: String, providerColorHex: String,
    userColorHex: String? = nil, isVisible: Bool = true, canEdit: Bool = false
  ) {
    self.id = "\(accountId):\(providerCalendarId)"
    self.accountId = accountId
    self.providerCalendarId = providerCalendarId
    self.name = name
    self.providerColorHex = providerColorHex
    self.userColorHex = userColorHex
    self.isVisible = isVisible
    self.canEdit = canEdit
  }

  public var effectiveColorHex: String { userColorHex ?? providerColorHex }
}

public enum ResponseStatus: String, Codable, Hashable, Sendable {
  case accepted, tentative, declined, notResponded, organizer, none
}

public enum EventStatus: String, Codable, Hashable, Sendable { case confirmed, tentative, cancelled }

public enum ConferenceKind: String, Codable, Hashable, Sendable { case teams, meet, zoom, webex, other }

public struct Attendee: Codable, Hashable, Sendable {
  public var name: String
  public var email: String
  public var response: ResponseStatus

  public init(name: String, email: String, response: ResponseStatus = .notResponded) {
    self.name = name
    self.email = email
    self.response = response
  }
}

public struct EventInstance: Identifiable, Codable, Hashable, Sendable {
  /// "\(calendarId):\(providerEventId)"
  public let id: String
  public let calendarId: String
  public let providerEventId: String
  public var seriesId: String?
  public var title: String
  /// UTC instants. For all-day events these are UTC midnight of `startDay` / `endDay`,
  /// kept only so range queries work; use `startDay` / `endDay` to place all-day events.
  public var start: Date
  public var end: Date
  public var isAllDay: Bool
  /// "yyyy-MM-dd" (Gregorian), all-day events only.
  public var startDay: String?
  /// Exclusive, all-day events only.
  public var endDay: String?
  public var originalTimeZone: String?
  public var location: String?
  /// Plain text; HTML already stripped.
  public var notes: String?
  public var organizerEmail: String?
  public var attendees: [Attendee]
  public var myResponse: ResponseStatus
  public var status: EventStatus
  public var joinURL: URL?
  public var conferenceKind: ConferenceKind?
  public var isBirthday: Bool
  public var etag: String?
  public var updatedAt: Date

  public init(
    calendarId: String, providerEventId: String, seriesId: String? = nil, title: String,
    start: Date, end: Date, isAllDay: Bool = false, startDay: String? = nil,
    endDay: String? = nil, originalTimeZone: String? = nil, location: String? = nil,
    notes: String? = nil, organizerEmail: String? = nil, attendees: [Attendee] = [],
    myResponse: ResponseStatus = .none, status: EventStatus = .confirmed, joinURL: URL? = nil,
    conferenceKind: ConferenceKind? = nil, isBirthday: Bool = false, etag: String? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 0)
  ) {
    self.id = "\(calendarId):\(providerEventId)"
    self.calendarId = calendarId
    self.providerEventId = providerEventId
    self.seriesId = seriesId
    self.title = title
    self.start = start
    self.end = end
    self.isAllDay = isAllDay
    self.startDay = startDay
    self.endDay = endDay
    self.originalTimeZone = originalTimeZone
    self.location = location
    self.notes = notes
    self.organizerEmail = organizerEmail
    self.attendees = attendees
    self.myResponse = myResponse
    self.status = status
    self.joinURL = joinURL
    self.conferenceKind = conferenceKind
    self.isBirthday = isBirthday
    self.etag = etag
    self.updatedAt = updatedAt
  }

  /// All-day event from provider date strings ("yyyy-MM-dd", end exclusive).
  public static func allDay(
    calendarId: String, providerEventId: String, title: String, startDay: String,
    endDay: String, isBirthday: Bool = false, status: EventStatus = .confirmed
  ) -> EventInstance {
    EventInstance(
      calendarId: calendarId, providerEventId: providerEventId, title: title,
      start: DayKey.utcMidnight(startDay) ?? Date(timeIntervalSince1970: 0),
      end: DayKey.utcMidnight(endDay) ?? Date(timeIntervalSince1970: 0), isAllDay: true,
      startDay: startDay, endDay: endDay, status: status, isBirthday: isBirthday)
  }

  /// The calendar day this event starts on in `calendar`'s time zone.
  public func firstDay(in calendar: Calendar) -> Date {
    if isAllDay, let startDay, let d = DayKey.date(from: startDay, timeZone: calendar.timeZone) {
      return d
    }
    return calendar.startOfDay(for: start)
  }
}

public struct SyncState: Codable, Hashable, Sendable {
  public let calendarId: String
  public var deltaLink: String?
  public var syncToken: String?
  public var windowStart: Date?
  public var windowEnd: Date?
  public var lastSyncedAt: Date?

  public init(
    calendarId: String, deltaLink: String? = nil, syncToken: String? = nil,
    windowStart: Date? = nil, windowEnd: Date? = nil, lastSyncedAt: Date? = nil
  ) {
    self.calendarId = calendarId
    self.deltaLink = deltaLink
    self.syncToken = syncToken
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.lastSyncedAt = lastSyncedAt
  }
}

public struct OutboxItem: Codable, Hashable, Sendable {
  public var id: Int64?
  public var accountId: String
  public var eventId: String
  public var action: String
  public var payload: Data
  public var createdAt: Date

  public init(
    id: Int64? = nil, accountId: String, eventId: String, action: String, payload: Data = Data(),
    createdAt: Date = Date()
  ) {
    self.id = id
    self.accountId = accountId
    self.eventId = eventId
    self.action = action
    self.payload = payload
    self.createdAt = createdAt
  }
}
