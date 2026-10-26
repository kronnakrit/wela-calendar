import Foundation
import Network

/// Keeps the engine syncing: every `interval` seconds while running, and immediately when the
/// network returns. The app also calls `syncNow()` on wake and when the panel opens stale.
public final class SyncScheduler: @unchecked Sendable {
  private let engine: SyncEngine
  private let interval: TimeInterval
  private let monitor = NWPathMonitor()
  private let lock = NSLock()
  private var loop: Task<Void, Never>?
  public var onReachabilityChange: (@Sendable (Bool) -> Void)?

  public init(engine: SyncEngine, interval: TimeInterval = 60) {
    self.engine = engine
    self.interval = interval
  }

  public func start() {
    lock.lock()
    defer { lock.unlock() }
    guard loop == nil else { return }
    let engine = engine
    let nanos = UInt64(interval * 1_000_000_000)
    loop = Task {
      while !Task.isCancelled {
        await engine.syncAll()
        try? await Task.sleep(nanoseconds: nanos)
      }
    }
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      self?.onReachabilityChange?(online)
      if online { Task { await self?.syncNow() } }
    }
    monitor.start(queue: DispatchQueue.global(qos: .utility))
  }

  public func stop() {
    lock.lock()
    defer { lock.unlock() }
    loop?.cancel()
    loop = nil
    monitor.cancel()
  }

  public func syncNow() async { await engine.syncAll() }
}
