import WelaCore
import XCTest

@testable import WelaSync

final class SyncSchedulerTests: XCTestCase {
  func testLoopSyncsRepeatedlyUntilStopped() async throws {
    let store = try Store()
    let account = Account(id: "a", provider: .mock, email: "x", displayName: "x")
    try store.saveAccount(account)
    let cal = CalendarInfo(accountId: "a", providerCalendarId: "c", name: "C", providerColorHex: "#000000")
    let provider = FakeProvider(calendars: [cal], events: [])
    let engine = SyncEngine(store: store, providers: [.mock: provider])
    let scheduler = SyncScheduler(engine: engine, interval: 0.05)
    scheduler.start()
    try await Task.sleep(nanoseconds: 600_000_000)
    scheduler.stop()
    XCTAssertGreaterThanOrEqual(provider.syncCalls, 2)
    let after = provider.syncCalls
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertLessThanOrEqual(provider.syncCalls, after + 1)  // at most one in-flight pass finishing
  }
}
