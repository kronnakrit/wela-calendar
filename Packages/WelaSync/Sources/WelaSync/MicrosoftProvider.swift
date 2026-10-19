import Foundation
import WelaCore

/// Microsoft Graph (Microsoft 365 / Outlook.com). Authentication is injected through
/// `HTTPClient`, so this type never touches MSAL.
public struct MicrosoftProvider: CalendarProvider {
  public static let baseURL = URL(string: "https://graph.microsoft.com/v1.0")!
  static let prefer = "outlook.timezone=\"UTC\", odata.maxpagesize=100"
  static let inkColors = ["#3D5A96", "#5F8A5E", "#7B5486", "#BF8A2C"]
  /// Roll the window when less than this many days remain ahead.
  static let rollThresholdDays: TimeInterval = 358

  let client: HTTPClient
  public var pastDays: Int = 90
  public var futureDays: Int = 365

  public init(client: HTTPClient) { self.client = client }

  // MARK: Calendars

  public func listCalendars(account: Account) async throws -> [CalendarInfo] {
    let url = Self.baseURL.appendingPathComponent("me/calendars")
    let (data, _) = try await client.send(URLRequest(url: url), account: account)
    let list = try JSONDecoder().decode(GraphCalendarList.self, from: data)
    return list.value.enumerated().map { index, c in
      let hex =
        (c.hexColor?.isEmpty == false ? c.hexColor : nil) ?? Self.namedColors[c.color ?? ""]
        ?? Self.inkColors[index % Self.inkColors.count]
      return CalendarInfo(
        accountId: account.id, providerCalendarId: c.id, name: c.name ?? "Calendar",
        providerColorHex: hex, canEdit: c.canEdit ?? false)
    }
  }

  static let namedColors: [String: String] = [
    "lightBlue": "#3D5A96", "lightGreen": "#5F8A5E", "lightPurple": "#7B5486",
    "lightOrange": "#BF8A2C", "lightRed": "#B8402C",
  ]

  // MARK: Sync

  public func sync(account: Account, calendar: CalendarInfo, state: SyncState?, now: Date)
    async throws -> SyncResult
  {
    let windowOK =
      state?.windowEnd.map { $0.timeIntervalSince(now) >= Self.rollThresholdDays * 86_400 } ?? false
    if let link = state?.deltaLink, let state, windowOK, let url = URL(string: link) {
      do {
        let pages = try await fetchPages(from: url, account: account)
        var next = state
        next.deltaLink = pages.deltaLink ?? link
        next.lastSyncedAt = now
        var upserts: [EventInstance] = []
        var deleted: [String] = []
        for e in pages.events {
          if e.removed != nil {
            deleted.append("\(calendar.id):\(e.id)")
          } else {
            upserts.append(Self.map(e, calendar: calendar))
          }
        }
        return SyncResult(upserts: upserts, deletedIds: deleted, newState: next, replacesAll: false)
      } catch SyncError.syncTokenExpired {
        // Fall through to a fresh initial sync.
      }
    }
    return try await initialSync(account: account, calendar: calendar, now: now)
  }

  private func initialSync(account: Account, calendar: CalendarInfo, now: Date) async throws
    -> SyncResult
  {
    let start = now.addingTimeInterval(-Double(pastDays) * 86_400)
    let end = now.addingTimeInterval(Double(futureDays) * 86_400)
    var comps = URLComponents(
      url: encodedEndpoint(Self.baseURL, "me/calendars/\(percentEncodePathComponent(calendar.providerCalendarId))/calendarView/delta"),
      resolvingAgainstBaseURL: false)!
    comps.queryItems = [
      URLQueryItem(name: "startDateTime", value: DateParsing.utcString(start)),
      URLQueryItem(name: "endDateTime", value: DateParsing.utcString(end)),
    ]
    let pages = try await fetchPages(from: comps.url!, account: account)
    let events = pages.events.filter { $0.removed == nil }.map { Self.map($0, calendar: calendar) }
    let state = SyncState(
      calendarId: calendar.id, deltaLink: pages.deltaLink, windowStart: start, windowEnd: end,
      lastSyncedAt: now)
    return SyncResult(upserts: events, deletedIds: [], newState: state, replacesAll: true)
  }

  /// Follows `@odata.nextLink` until the `@odata.deltaLink` page. The same Prefer header is
  /// sent on every request, as Graph requires.
  private func fetchPages(from url: URL, account: Account) async throws -> (
    events: [GraphEvent], deltaLink: String?
  ) {
    var events: [GraphEvent] = []
    var next: URL? = url
    var delta: String?
    while let current = next {
      var req = URLRequest(url: current)
      req.setValue(Self.prefer, forHTTPHeaderField: "Prefer")
      let (data, _) = try await client.send(req, account: account)
      let page = try JSONDecoder().decode(GraphPage.self, from: data)
      events += page.value
      delta = page.deltaLink ?? delta
      next = page.nextLink.flatMap(URL.init(string:))
    }
    return (events, delta)
  }

  // MARK: RSVP

  public func respond(
    account: Account, calendar: CalendarInfo, event: EventInstance, response: ResponseStatus
  ) async throws {
    let action: String
    switch response {
    case .accepted: action = "accept"
    case .tentative: action = "tentativelyAccept"
    case .declined: action = "decline"
    default: throw SyncError.invalidResponse("cannot send \(response.rawValue)")
    }
    let url = encodedEndpoint(Self.baseURL, "me/events/\(percentEncodePathComponent(event.providerEventId))/\(action)")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["sendResponse": true])
    _ = try await client.send(req, account: account)
  }

  // MARK: Mapping

  static func map(_ g: GraphEvent, calendar: CalendarInfo) -> EventInstance {
    let allDay = g.isAllDay ?? false
    let notes = g.body?.content.map { body -> String in
      (g.body?.contentType?.lowercased() == "html") ? HTMLStripper.plainText(from: body) : body
    }
    let location = g.location?.displayName.flatMap { $0.isEmpty ? nil : $0 }
    let structured = g.onlineMeeting?.joinUrl.flatMap(URL.init(string:))
    let providerKind: ConferenceKind? =
      g.onlineMeetingProvider.map { $0.lowercased().contains("teams") ? .teams : .other }
    let join = JoinLinkParser.parse(
      structuredURL: structured, structuredKind: providerKind, location: location, notes: notes)

    let start: Date
    let end: Date
    var startDay: String?
    var endDay: String?
    if allDay {
      let s = String((g.start?.dateTime ?? "").prefix(10))
      let e = String((g.end?.dateTime ?? "").prefix(10))
      startDay = s
      endDay = e
      start = DayKey.utcMidnight(s) ?? Date(timeIntervalSince1970: 0)
      end = DayKey.utcMidnight(e) ?? start
    } else {
      start = g.start?.dateTime.flatMap(DateParsing.parse) ?? Date(timeIntervalSince1970: 0)
      end = g.end?.dateTime.flatMap(DateParsing.parse) ?? start
    }

    let response: ResponseStatus
    if g.isOrganizer == true {
      response = .organizer
    } else {
      switch g.responseStatus?.response {
      case "accepted": response = .accepted
      case "tentativelyAccepted": response = .tentative
      case "declined": response = .declined
      case "organizer": response = .organizer
      case "none", "notResponded": response = .notResponded
      default: response = .none
      }
    }

    let attendees = (g.attendees ?? []).map {
      Attendee(
        name: $0.emailAddress?.name ?? $0.emailAddress?.address ?? "",
        email: $0.emailAddress?.address ?? "", response: attendeeResponse($0.status?.response))
    }

    return EventInstance(
      calendarId: calendar.id, providerEventId: g.id, seriesId: g.seriesMasterId,
      title: (g.subject?.isEmpty == false ? g.subject : nil) ?? "(No title)", start: start,
      end: end,
      isAllDay: allDay, startDay: startDay, endDay: endDay, location: location, notes: notes,
      organizerEmail: g.organizer?.emailAddress?.address, attendees: attendees,
      myResponse: response, status: (g.isCancelled ?? false) ? .cancelled : .confirmed,
      joinURL: join?.url, conferenceKind: join?.kind, etag: g.changeKey,
      updatedAt: g.lastModifiedDateTime.flatMap(DateParsing.parse) ?? Date(timeIntervalSince1970: 0)
    )
  }

  private static func attendeeResponse(_ raw: String?) -> ResponseStatus {
    switch raw {
    case "accepted": return .accepted
    case "tentativelyAccepted": return .tentative
    case "declined": return .declined
    case "organizer": return .organizer
    default: return .notResponded
    }
  }
}

// MARK: DTOs

struct GraphCalendarList: Decodable {
  struct Item: Decodable {
    let id: String
    let name: String?
    let hexColor: String?
    let color: String?
    let canEdit: Bool?
  }
  let value: [Item]
}

struct GraphPage: Decodable {
  let value: [GraphEvent]
  let nextLink: String?
  let deltaLink: String?
  enum CodingKeys: String, CodingKey {
    case value
    case nextLink = "@odata.nextLink"
    case deltaLink = "@odata.deltaLink"
  }
}

struct GraphEvent: Decodable {
  struct Removed: Decodable { let reason: String? }
  struct DateTimeZone: Decodable {
    let dateTime: String?
    let timeZone: String?
  }
  struct Location: Decodable { let displayName: String? }
  struct Body: Decodable {
    let contentType: String?
    let content: String?
  }
  struct EmailAddress: Decodable {
    let name: String?
    let address: String?
  }
  struct Recipient: Decodable { let emailAddress: EmailAddress? }
  struct Attendee: Decodable {
    struct Status: Decodable { let response: String? }
    let status: Status?
    let emailAddress: EmailAddress?
  }
  struct ResponseStatus: Decodable { let response: String? }
  struct OnlineMeeting: Decodable { let joinUrl: String? }

  let id: String
  let removed: Removed?
  let subject: String?
  let isAllDay: Bool?
  let isCancelled: Bool?
  let isOrganizer: Bool?
  let start: DateTimeZone?
  let end: DateTimeZone?
  let location: Location?
  let body: Body?
  let organizer: Recipient?
  let attendees: [Attendee]?
  let responseStatus: ResponseStatus?
  let onlineMeeting: OnlineMeeting?
  let onlineMeetingProvider: String?
  let seriesMasterId: String?
  let lastModifiedDateTime: String?
  let changeKey: String?

  enum CodingKeys: String, CodingKey {
    case id, subject, isAllDay, isCancelled, isOrganizer, start, end, location, body, organizer
    case attendees, responseStatus, onlineMeeting, onlineMeetingProvider, seriesMasterId
    case lastModifiedDateTime, changeKey
    case removed = "@removed"
  }
}
