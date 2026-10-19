import Foundation
import WelaCore

public struct SyncResult: Sendable {
  public var upserts: [EventInstance]
  public var deletedIds: [String]
  public var newState: SyncState
  /// True after an initial sync or window roll: `upserts` is the complete set for the calendar
  /// and replaces the cache in a single transaction.
  public var replacesAll: Bool

  public init(
    upserts: [EventInstance], deletedIds: [String], newState: SyncState, replacesAll: Bool
  ) {
    self.upserts = upserts
    self.deletedIds = deletedIds
    self.newState = newState
    self.replacesAll = replacesAll
  }
}

public protocol CalendarProvider: Sendable {
  func listCalendars(account: Account) async throws -> [CalendarInfo]
  func sync(account: Account, calendar: CalendarInfo, state: SyncState?, now: Date) async throws
    -> SyncResult
  func respond(
    account: Account, calendar: CalendarInfo, event: EventInstance, response: ResponseStatus
  ) async throws
}
