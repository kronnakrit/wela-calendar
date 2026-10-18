import Foundation
import WelaCore

/// Google Calendar API v3. Authentication is injected through `HTTPClient`.
public struct GoogleProvider: CalendarProvider {
  public static let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

  let client: HTTPClient
  public var pastDays: Int = 90
  public var futureDays: Int = 365
  /// Try `timeMin` + `timeMax` first. If Google returns no `nextSyncToken` for a bounded
  /// request, the initial sync is repeated unbounded and trimmed locally (see DECISIONS.md).
  public var preferBoundedInitialSync = true

  public init(client: HTTPClient) { self.client = client }

  // MARK: Calendars

  public func listCalendars(account: Account) async throws -> [CalendarInfo] {
    let url = Self.baseURL.appendingPathComponent("users/me/calendarList")
    let (data, _) = try await client.send(URLRequest(url: url), account: account)
    let list = try JSONDecoder().decode(GoogleCalendarList.self, from: data)
    return list.items.map {
      CalendarInfo(
        accountId: account.id, providerCalendarId: $0.id,
        name: $0.summaryOverride ?? $0.summary ?? $0.id,
        providerColorHex: $0.backgroundColor ?? "#3D5A96",
        canEdit: $0.accessRole == "owner" || $0.accessRole == "writer")
    }
  }

  // MARK: Sync

  public func sync(account: Account, calendar: CalendarInfo, state: SyncState?, now: Date)
    async throws -> SyncResult
  {
    if let token = state?.syncToken, let state {
      do {
        let pages = try await fetchPages(
          calendar: calendar, account: account, query: [URLQueryItem(name: "syncToken", value: token)])
        var next = state
        next.syncToken = pages.syncToken ?? token
        next.lastSyncedAt = now
        var upserts: [EventInstance] = []
        var deleted: [String] = []
        for e in pages.events {
          if e.status == "cancelled" {
            deleted.append("\(calendar.id):\(e.id)")
          } else if let mapped = Self.map(e, calendar: calendar) {
            upserts.append(mapped)
          }
        }
        return SyncResult(upserts: upserts, deletedIds: deleted, newState: next, replacesAll: false)
      } catch SyncError.syncTokenExpired {
        // Token invalid (HTTP 410): clear it and redo the initial sync.
      }
    }
    return try await initialSync(account: account, calendar: calendar, now: now)
  }

  private func initialSync(account: Account, calendar: CalendarInfo, now: Date) async throws
    -> SyncResult
  {
    let start = now.addingTimeInterval(-Double(pastDays) * 86_400)
    let end = now.addingTimeInterval(Double(futureDays) * 86_400)
    func query(bounded: Bool) -> [URLQueryItem] {
      var q = [
        URLQueryItem(name: "timeMin", value: DateParsing.utcString(start)),
        URLQueryItem(name: "showDeleted", value: "true"),
      ]
      if bounded { q.append(URLQueryItem(name: "timeMax", value: DateParsing.utcString(end))) }
      return q
    }
    var pages = try await fetchPages(
      calendar: calendar, account: account, query: query(bounded: preferBoundedInitialSync))
    if pages.syncToken == nil && preferBoundedInitialSync {
      pages = try await fetchPages(calendar: calendar, account: account, query: query(bounded: false))
    }
    let events = pages.events.compactMap { e -> EventInstance? in
      guard e.status != "cancelled", let m = Self.map(e, calendar: calendar) else { return nil }
      // Unbounded fallback: drop anything outside the window.
      return (m.end >= start && m.start <= end) ? m : nil
    }
    let state = SyncState(
      calendarId: calendar.id, syncToken: pages.syncToken, windowStart: start, windowEnd: end,
      lastSyncedAt: now)
    return SyncResult(upserts: events, deletedIds: [], newState: state, replacesAll: true)
  }

  private func fetchPages(calendar: CalendarInfo, account: Account, query: [URLQueryItem])
    async throws -> (events: [GoogleEvent], syncToken: String?)
  {
    var events: [GoogleEvent] = []
    var pageToken: String?
    var syncToken: String?
    repeat {
      var comps = URLComponents(
        url: Self.baseURL.appendingPathComponent(
          "calendars/\(percentEncodePathComponent(calendar.providerCalendarId))/events"),
        resolvingAgainstBaseURL: false)!
      var items = [
        URLQueryItem(name: "singleEvents", value: "true"),
        URLQueryItem(name: "maxResults", value: "250"),
      ]
      items += query
      if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
      comps.queryItems = items
      let (data, _) = try await client.send(URLRequest(url: comps.url!), account: account)
      let page = try JSONDecoder().decode(GoogleEventPage.self, from: data)
      events += page.items ?? []
      pageToken = page.nextPageToken
      syncToken = page.nextSyncToken ?? syncToken
    } while pageToken != nil
    return (events, syncToken)
  }

  // MARK: RSVP

  public func respond(
    account: Account, calendar: CalendarInfo, event: EventInstance, response: ResponseStatus
  ) async throws {
    let status: String
    switch response {
    case .accepted: status = "accepted"
    case .tentative: status = "tentative"
    case .declined: status = "declined"
    default: throw SyncError.invalidResponse("cannot send \(response.rawValue)")
    }
    let url = Self.baseURL.appendingPathComponent(
      "calendars/\(percentEncodePathComponent(calendar.providerCalendarId))/events/\(percentEncodePathComponent(event.providerEventId))"
    )
    // Read-modify-write: fetch the current attendees and etag first.
    var etag: String?
    var attendees = try await currentAttendees(url: url, account: account, etag: &etag)
    for attempt in 0..<2 {
      for i in attendees.indices where (attendees[i]["self"] as? Bool) == true {
        attendees[i]["responseStatus"] = status
      }
      var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
      comps.queryItems = [URLQueryItem(name: "sendUpdates", value: "all")]
      var req = URLRequest(url: comps.url!)
      req.httpMethod = "PATCH"
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      if let etag { req.setValue(etag, forHTTPHeaderField: "If-Match") }
      req.httpBody = try JSONSerialization.data(withJSONObject: ["attendees": attendees])
      do {
        _ = try await client.send(req, account: account)
        return
      } catch SyncError.preconditionFailed where attempt == 0 {
        // Stale etag: re-fetch the event and retry once.
        attendees = try await currentAttendees(url: url, account: account, etag: &etag)
      }
    }
  }

  private func currentAttendees(url: URL, account: Account, etag: inout String?) async throws
    -> [[String: Any]]
  {
    let (data, _) = try await client.send(URLRequest(url: url), account: account)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SyncError.invalidResponse("event is not an object")
    }
    etag = object["etag"] as? String
    return object["attendees"] as? [[String: Any]] ?? []
  }

  // MARK: Mapping

  static func map(_ g: GoogleEvent, calendar: CalendarInfo) -> EventInstance? {
    let allDay = g.start?.date != nil
    let start: Date
    let end: Date
    var startDay: String?
    var endDay: String?
    if allDay, let s = g.start?.date {
      startDay = s
      // A date-only end is exclusive; default to a single day if missing.
      endDay =
        g.end?.date
        ?? DayKey.string(
          for: (DayKey.utcMidnight(s) ?? Date()).addingTimeInterval(86_400),
          timeZone: TimeZone(identifier: "UTC")!)
      start = DayKey.utcMidnight(s) ?? Date(timeIntervalSince1970: 0)
      end = endDay.flatMap(DayKey.utcMidnight) ?? start
    } else if let s = g.start?.dateTime.flatMap(DateParsing.parse) {
      start = s
      end = g.end?.dateTime.flatMap(DateParsing.parse) ?? s
    } else {
      return nil
    }

    let attendees = (g.attendees ?? []).map {
      Attendee(
        name: $0.displayName ?? $0.email ?? "", email: $0.email ?? "",
        response: Self.response($0.responseStatus))
    }
    let me = g.attendees?.first { $0.isSelf == true }
    let response: ResponseStatus
    if let me {
      response = Self.response(me.responseStatus)
    } else if g.organizer?.isSelf == true {
      response = .organizer
    } else {
      response = .none
    }

    let video = g.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
    let structured = (video ?? g.hangoutLink).flatMap(URL.init(string:))
    let join = JoinLinkParser.parse(
      structuredURL: structured, location: g.location, notes: g.description)

    return EventInstance(
      calendarId: calendar.id, providerEventId: g.id, seriesId: g.recurringEventId,
      title: (g.summary?.isEmpty == false ? g.summary : nil) ?? "(No title)", start: start, end: end,
      isAllDay: allDay, startDay: startDay, endDay: endDay, location: g.location,
      notes: g.description, organizerEmail: g.organizer?.email, attendees: attendees,
      myResponse: response, status: g.status == "tentative" ? .tentative : .confirmed,
      joinURL: join?.url, conferenceKind: join?.kind, isBirthday: g.eventType == "birthday",
      etag: g.etag, updatedAt: g.updated.flatMap(DateParsing.parse) ?? Date(timeIntervalSince1970: 0))
  }

  private static func response(_ raw: String?) -> ResponseStatus {
    switch raw {
    case "accepted": return .accepted
    case "tentative": return .tentative
    case "declined": return .declined
    default: return .notResponded  // needsAction
    }
  }
}

// MARK: DTOs

struct GoogleCalendarList: Decodable {
  struct Item: Decodable {
    let id: String
    let summary: String?
    let summaryOverride: String?
    let backgroundColor: String?
    let accessRole: String?
  }
  let items: [Item]
}

struct GoogleEventPage: Decodable {
  let items: [GoogleEvent]?
  let nextPageToken: String?
  let nextSyncToken: String?
}

struct GoogleEvent: Decodable {
  struct When: Decodable {
    let date: String?
    let dateTime: String?
    let timeZone: String?
  }
  struct Person: Decodable {
    let email: String?
    let displayName: String?
    let isSelf: Bool?
    let responseStatus: String?
    enum CodingKeys: String, CodingKey {
      case email, displayName, responseStatus
      case isSelf = "self"
    }
  }
  struct Conference: Decodable {
    struct EntryPoint: Decodable {
      let entryPointType: String?
      let uri: String?
    }
    let entryPoints: [EntryPoint]?
  }

  let id: String
  let status: String?
  let summary: String?
  let description: String?
  let location: String?
  let start: When?
  let end: When?
  let attendees: [Person]?
  let organizer: Person?
  let conferenceData: Conference?
  let hangoutLink: String?
  let eventType: String?
  let etag: String?
  let updated: String?
  let recurringEventId: String?
}
