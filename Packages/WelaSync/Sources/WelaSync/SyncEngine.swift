import Foundation
import WelaCore

public struct RSVPPayload: Codable, Hashable, Sendable {
  public var response: ResponseStatus
  public var previous: ResponseStatus
}

public struct RSVPFailure: Hashable, Sendable {
  public let eventId: String
  public let message: String
}

public enum RSVPError: Error, Equatable {
  case failed(String)
}

/// Syncs every account into the local store and sends queued writes. The UI never talks to a
/// provider directly: it reads the store and calls `respond`.
public actor SyncEngine {
  private let store: Store
  private let providers: [ProviderKind: CalendarProvider]
  private let now: @Sendable () -> Date
  private var inFlight: Set<String> = []
  private var flushing = false

  public init(
    store: Store, providers: [ProviderKind: CalendarProvider],
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.providers = providers
    self.now = now
  }

  // MARK: Sync

  public func syncAll() async {
    for account in (try? store.accounts()) ?? [] { await sync(account: account) }
    _ = await flushOutbox()
  }

  /// Syncs one account. Errors never clear cached data; they only change the account status.
  public func sync(account: Account) async {
    guard let provider = providers[account.provider] else { return }
    guard inFlight.insert("account:" + account.id).inserted else { return }
    defer { inFlight.remove("account:" + account.id) }
    do {
      let fetched = try await provider.listCalendars(account: account)
      let existing = Dictionary(
        uniqueKeysWithValues: ((try? store.calendars(accountId: account.id)) ?? []).map { ($0.id, $0) })
      let merged = fetched.map { cal -> CalendarInfo in
        var c = cal
        if let old = existing[cal.id] {
          c.isVisible = old.isVisible
          c.userColorHex = old.userColorHex
        }
        return c
      }
      try store.saveCalendars(merged)
      for gone in existing.keys where !merged.contains(where: { $0.id == gone }) {
        try store.deleteCalendar(id: gone)
      }
      for cal in merged { try await syncCalendar(account: account, calendar: cal, provider: provider) }
      setStatus(account.id, .ok)
    } catch SyncError.needsSignIn {
      setStatus(account.id, .needsSignIn)
    } catch SyncError.offline {
      // Offline is not an account error; keep showing cached data.
    } catch {
      setStatus(account.id, .error(String(describing: error)))
    }
  }

  private func syncCalendar(account: Account, calendar: CalendarInfo, provider: CalendarProvider)
    async throws
  {
    // Never run two syncs for the same calendar at once.
    guard inFlight.insert(calendar.id).inserted else { return }
    defer { inFlight.remove(calendar.id) }
    let state = try store.syncState(calendarId: calendar.id)
    let result = try await provider.sync(account: account, calendar: calendar, state: state, now: now())
    if result.replacesAll {
      try store.replaceEvents(calendarId: calendar.id, with: result.upserts)
    } else {
      try store.upsertEvents(result.upserts)
      try store.deleteEvents(ids: result.deletedIds)
    }
    try store.saveSyncState(result.newState)
  }

  private func setStatus(_ accountId: String, _ status: AccountStatus) {
    guard var account = try? store.account(id: accountId), account.status != status else { return }
    account.status = status
    try? store.saveAccount(account)
  }

  // MARK: RSVP and outbox

  /// Optimistically updates the store, queues the write and sends it when online. Throws
  /// `RSVPError` (after rolling the change back) if the provider rejects it. Offline is not an
  /// error: the item stays queued and is sent by a later `flushOutbox()`.
  public func respond(to event: EventInstance, with response: ResponseStatus) async throws {
    guard let calendar = try store.calendar(id: event.calendarId) else {
      throw RSVPError.failed("unknown calendar")
    }
    var optimistic = event
    optimistic.myResponse = response
    try store.upsertEvents([optimistic])
    let payload = try JSONEncoder().encode(RSVPPayload(response: response, previous: event.myResponse))
    try store.enqueue(
      OutboxItem(accountId: calendar.accountId, eventId: event.id, action: "rsvp", payload: payload, createdAt: now()))
    let failures = await flushOutbox()
    if let failure = failures.first(where: { $0.eventId == event.id }) {
      throw RSVPError.failed(failure.message)
    }
  }

  /// Sends queued writes in order. Returns the writes that failed permanently (already rolled back).
  @discardableResult
  public func flushOutbox() async -> [RSVPFailure] {
    guard !flushing else { return [] }
    flushing = true
    defer { flushing = false }
    var failures: [RSVPFailure] = []
    var stuck: Set<Int64> = []
    while let item = ((try? store.pendingOutbox()) ?? []).first(where: { !stuck.contains($0.id ?? -1) }) {
      guard let id = item.id else { break }
      switch await send(item) {
      case .sent:
        try? store.removeOutboxItem(id: id)
      case .retryLater:
        stuck.insert(id)
      case .failed(let message, let previous):
        if let previous, var event = try? store.event(id: item.eventId) {
          event.myResponse = previous
          try? store.upsertEvents([event])
        }
        try? store.removeOutboxItem(id: id)
        failures.append(RSVPFailure(eventId: item.eventId, message: message))
      }
    }
    return failures
  }

  private enum SendOutcome {
    case sent
    case retryLater
    case failed(String, previous: ResponseStatus?)
  }

  private func send(_ item: OutboxItem) async -> SendOutcome {
    guard item.action == "rsvp", let payload = try? JSONDecoder().decode(RSVPPayload.self, from: item.payload)
    else { return .failed("unsupported queued action", previous: nil) }
    guard let event = try? store.event(id: item.eventId),
      let calendar = try? store.calendar(id: event.calendarId),
      let account = try? store.account(id: calendar.accountId),
      let provider = providers[account.provider]
    else { return .failed("event no longer available", previous: nil) }
    do {
      try await provider.respond(account: account, calendar: calendar, event: event, response: payload.response)
      return .sent
    } catch SyncError.offline {
      return .retryLater
    } catch SyncError.needsSignIn {
      setStatus(account.id, .needsSignIn)
      return .retryLater
    } catch {
      return .failed(String(describing: error), previous: payload.previous)
    }
  }
}
