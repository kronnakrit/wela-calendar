import Foundation
import GRDB

public struct SearchDayGroup: Hashable, Sendable {
  public let day: Date
  public let events: [EventInstance]
}

/// Local SQLite cache. The UI reads only from here.
public final class Store: @unchecked Sendable {
  public let dbQueue: DatabaseQueue

  /// Pass `nil` for an in-memory database (tests, mock data).
  public init(path: String? = nil) throws {
    if let path {
      dbQueue = try DatabaseQueue(path: path)
    } else {
      dbQueue = try DatabaseQueue()
    }
    try Store.migrator.migrate(dbQueue)
  }

  // MARK: Migrations

  private static var migrator: DatabaseMigrator {
    var m = DatabaseMigrator()
    m.registerMigration("v1") { db in
      try db.create(table: "account") { t in
        t.column("id", .text).primaryKey()
        t.column("provider", .text).notNull()
        t.column("email", .text).notNull()
        t.column("displayName", .text).notNull()
        t.column("status", .text).notNull()
      }
      try db.create(table: "calendar") { t in
        t.column("id", .text).primaryKey()
        t.column("accountId", .text).notNull().references("account", onDelete: .cascade)
        t.column("providerCalendarId", .text).notNull()
        t.column("name", .text).notNull()
        t.column("providerColorHex", .text).notNull()
        t.column("userColorHex", .text)
        t.column("isVisible", .boolean).notNull()
        t.column("canEdit", .boolean).notNull()
      }
      try db.create(table: "event_instance") { t in
        t.column("id", .text).primaryKey()
        t.column("calendarId", .text).notNull().references("calendar", onDelete: .cascade)
        t.column("providerEventId", .text).notNull()
        t.column("seriesId", .text)
        t.column("title", .text).notNull()
        t.column("start", .datetime).notNull()
        t.column("end", .datetime).notNull()
        t.column("isAllDay", .boolean).notNull()
        t.column("startDay", .text)
        t.column("endDay", .text)
        t.column("originalTimeZone", .text)
        t.column("location", .text)
        t.column("notes", .text)
        t.column("organizerEmail", .text)
        t.column("attendees", .text).notNull()
        t.column("myResponse", .text).notNull()
        t.column("status", .text).notNull()
        t.column("joinURL", .text)
        t.column("conferenceKind", .text)
        t.column("isBirthday", .boolean).notNull()
        t.column("etag", .text)
        t.column("updatedAt", .datetime).notNull()
      }
      try db.create(index: "event_instance_start", on: "event_instance", columns: ["start"])
      try db.create(
        index: "event_instance_calendarId", on: "event_instance", columns: ["calendarId"])
      try db.create(table: "sync_state") { t in
        t.column("calendarId", .text).primaryKey().references("calendar", onDelete: .cascade)
        t.column("deltaLink", .text)
        t.column("syncToken", .text)
        t.column("windowStart", .datetime)
        t.column("windowEnd", .datetime)
        t.column("lastSyncedAt", .datetime)
      }
      try db.create(table: "outbox") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("accountId", .text).notNull().references("account", onDelete: .cascade)
        t.column("eventId", .text).notNull()
        t.column("action", .text).notNull()
        t.column("payload", .blob).notNull()
        t.column("createdAt", .datetime).notNull()
      }
      try db.create(virtualTable: "event_fts", using: FTS5()) { t in
        t.tokenizer = .unicode61()
        t.column("eventId").notIndexed()
        t.column("title")
        t.column("location")
        t.column("notes")
        t.column("attendees")
      }
    }
    return m
  }

  // MARK: Accounts and calendars

  public func saveAccount(_ account: Account) throws {
    try dbQueue.write { db in try account.save(db) }
  }

  public func accounts() throws -> [Account] {
    try dbQueue.read { db in try Account.order(Column("email")).fetchAll(db) }
  }

  /// Removes the account and everything cached for it (calendars, events, sync state, outbox).
  public func deleteAccount(id: String) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: """
          DELETE FROM event_fts WHERE eventId IN (
            SELECT e.id FROM event_instance e JOIN calendar c ON c.id = e.calendarId
            WHERE c.accountId = ?)
          """, arguments: [id])
      _ = try Account.deleteOne(db, key: id)  // cascades to calendars, events, state, outbox
    }
  }

  public func saveCalendars(_ calendars: [CalendarInfo]) throws {
    try dbQueue.write { db in for c in calendars { try c.save(db) } }
  }

  public func calendars() throws -> [CalendarInfo] {
    try dbQueue.read { db in try CalendarInfo.order(Column("name")).fetchAll(db) }
  }

  public func setCalendarVisibility(id: String, isVisible: Bool) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: "UPDATE calendar SET isVisible = ? WHERE id = ?", arguments: [isVisible, id])
    }
  }

  public func setCalendarColor(id: String, hex: String?) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: "UPDATE calendar SET userColorHex = ? WHERE id = ?", arguments: [hex, id])
    }
  }

  // MARK: Events

  public func upsertEvents(_ events: [EventInstance]) throws {
    try dbQueue.write { db in try Store.upsert(events, in: db) }
  }

  public func deleteEvents(ids: [String]) throws {
    try dbQueue.write { db in try Store.delete(ids: ids, in: db) }
  }

  /// Atomically replaces every cached event of a calendar (window roll / full resync), so
  /// observers never see an empty calendar in between.
  public func replaceEvents(calendarId: String, with events: [EventInstance]) throws {
    try dbQueue.write { db in
      try db.execute(
        sql: """
          DELETE FROM event_fts WHERE eventId IN (
            SELECT id FROM event_instance WHERE calendarId = ?)
          """, arguments: [calendarId])
      try db.execute(
        sql: "DELETE FROM event_instance WHERE calendarId = ?", arguments: [calendarId])
      try Store.upsert(events, in: db)
    }
  }

  public func event(id: String) throws -> EventInstance? {
    try dbQueue.read { db in try EventInstance.fetchOne(db, key: id) }
  }

  public func eventCount() throws -> Int {
    try dbQueue.read { db in try EventInstance.fetchCount(db) }
  }

  /// Events that may touch `interval`. Padded by two days so all-day events (stored at UTC
  /// midnight) are never missed; `AgendaBuilder` does the exact per-day filtering.
  public func events(in interval: DateInterval, calendarIds: Set<String>? = nil) throws
    -> [EventInstance]
  {
    try dbQueue.read { db in
      try Store.fetchEvents(db, interval: interval, calendarIds: calendarIds)
    }
  }

  public func observeEvents(in interval: DateInterval, calendarIds: Set<String>? = nil)
    -> AsyncStream<[EventInstance]>
  {
    let queue = dbQueue
    let observation = ValueObservation.tracking { db in
      try Store.fetchEvents(db, interval: interval, calendarIds: calendarIds)
    }
    return AsyncStream { continuation in
      let task = Task {
        do {
          for try await events in observation.values(in: queue) { continuation.yield(events) }
        } catch {}
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func observeCalendars() -> AsyncStream<[CalendarInfo]> {
    let queue = dbQueue
    let observation = ValueObservation.tracking { db in
      try CalendarInfo.order(Column("name")).fetchAll(db)
    }
    return AsyncStream { continuation in
      let task = Task {
        do {
          for try await value in observation.values(in: queue) { continuation.yield(value) }
        } catch {}
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: Search

  /// Full-text search over title, location, notes and attendees, grouped by day.
  public func search(
    _ query: String, in interval: DateInterval, calendarIds: Set<String>? = nil,
    calendar: Calendar
  ) throws -> [SearchDayGroup] {
    guard let match = Store.matchExpression(query) else { return [] }
    let found = try dbQueue.read { db in
      try EventInstance.fetchAll(
        db,
        sql: """
          SELECT e.* FROM event_fts JOIN event_instance e ON e.id = event_fts.eventId
          WHERE event_fts MATCH ? AND e.start >= ? AND e.start < ?
          ORDER BY e.start
          """, arguments: [match, interval.start, interval.end])
    }
    var groups: [Date: [EventInstance]] = [:]
    for e in found {
      if let ids = calendarIds, !ids.contains(e.calendarId) { continue }
      groups[e.firstDay(in: calendar), default: []].append(e)
    }
    return groups.keys.sorted().map { SearchDayGroup(day: $0, events: groups[$0]!) }
  }

  static func matchExpression(_ query: String) -> String? {
    let tokens = query.split(whereSeparator: { $0.isWhitespace }).map { token in
      "\"" + token.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
    }
    return tokens.isEmpty ? nil : tokens.joined(separator: " ")
  }

  // MARK: Sync state and outbox

  public func syncState(calendarId: String) throws -> SyncState? {
    try dbQueue.read { db in try SyncState.fetchOne(db, key: calendarId) }
  }

  public func saveSyncState(_ state: SyncState) throws {
    try dbQueue.write { db in try state.save(db) }
  }

  @discardableResult
  public func enqueue(_ item: OutboxItem) throws -> OutboxItem {
    try dbQueue.write { db in
      var copy = item
      try copy.insert(db)
      return copy
    }
  }

  public func pendingOutbox() throws -> [OutboxItem] {
    try dbQueue.read { db in try OutboxItem.order(Column("id")).fetchAll(db) }
  }

  public func removeOutboxItem(id: Int64) throws {
    try dbQueue.write { db in _ = try OutboxItem.deleteOne(db, key: id) }
  }

  // MARK: Internals

  private static let dayPadding: TimeInterval = 2 * 86_400

  static func fetchEvents(_ db: Database, interval: DateInterval, calendarIds: Set<String>?) throws
    -> [EventInstance]
  {
    var request = EventInstance.filter(
      Column("start") < interval.end.addingTimeInterval(dayPadding)
        && Column("end") > interval.start.addingTimeInterval(-dayPadding))
    if let ids = calendarIds {
      request = request.filter(ids.contains(Column("calendarId")))
    }
    return try request.order(Column("start")).fetchAll(db)
  }

  private static func upsert(_ events: [EventInstance], in db: Database) throws {
    for e in events {
      try e.save(db)
      try db.execute(sql: "DELETE FROM event_fts WHERE eventId = ?", arguments: [e.id])
      try db.execute(
        sql: """
          INSERT INTO event_fts(eventId, title, location, notes, attendees)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          e.id, e.title, e.location ?? "", e.notes ?? "",
          e.attendees.map { "\($0.name) \($0.email)" }.joined(separator: " "),
        ])
    }
  }

  private static func delete(ids: [String], in db: Database) throws {
    for id in ids {
      try db.execute(sql: "DELETE FROM event_fts WHERE eventId = ?", arguments: [id])
      _ = try EventInstance.deleteOne(db, key: id)
    }
  }
}
