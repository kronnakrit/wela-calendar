import Foundation
import UserNotifications
import WelaCore

/// Schedules local alerts for the next 48 hours of events and handles Join / Snooze actions.
@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
  static let idPrefix = "wela.event."
  static let withJoin = "EVENT_JOIN"
  static let plain = "EVENT"
  static let joinAction = "JOIN"
  static let snoozeAction = "SNOOZE"
  static let horizon: TimeInterval = 48 * 3600
  static let maxPending = 60  // the system allows 64

  private let center = UNUserNotificationCenter.current()
  var onJoin: ((String) -> Void)?

  func configure() {
    center.delegate = self
    let join = UNNotificationAction(
      identifier: Self.joinAction, title: "Join", options: [.foreground])
    let snooze = UNNotificationAction(
      identifier: Self.snoozeAction, title: "Snooze 5 min", options: [])
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.withJoin, actions: [join, snooze], intentIdentifiers: []),
      UNNotificationCategory(identifier: Self.plain, actions: [snooze], intentIdentifiers: []),
    ])
  }

  /// Asked after the first account connects, not at launch.
  func requestAuthorization() {
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  func reschedule(events: [EventInstance], leadMinutes: Int, enabled: Bool, now: Date = Date())
    async
  {
    let pending = await center.pendingNotificationRequests()
    let ours = pending.map(\.identifier).filter {
      $0.hasPrefix(Self.idPrefix) && !$0.hasSuffix(".snooze")  // keep pending snoozes
    }
    center.removePendingNotificationRequests(withIdentifiers: ours)
    guard enabled else { return }
    let upcoming =
      events
      .filter {
        !$0.isAllDay && $0.status != .cancelled && $0.myResponse != .declined
          && $0.start > now && $0.start.timeIntervalSince(now) <= Self.horizon
      }
      .sorted { $0.start < $1.start }
    var scheduled = 0
    for event in upcoming {
      let fire = event.start.addingTimeInterval(-Double(leadMinutes) * 60)
      guard fire > now else { continue }
      if await schedule(event: event, after: fire.timeIntervalSince(now), now: now) == false {
        break
      }
      scheduled += 1
      if scheduled >= Self.maxPending { break }
    }
  }

  private func schedule(
    event: EventInstance, after delay: TimeInterval, now: Date, idSuffix: String = ""
  )
    async -> Bool
  {
    let content = UNMutableNotificationContent()
    content.title = event.title
    let time = event.start.formatted(date: .omitted, time: .shortened)
    content.body = [time, event.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(
      separator: " · ")
    content.sound = .default
    content.categoryIdentifier = event.joinURL != nil ? Self.withJoin : Self.plain
    content.userInfo = ["eventId": event.id]
    let request = UNNotificationRequest(
      identifier: Self.idPrefix + event.id + idSuffix, content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false))
    do {
      try await center.add(request)
      return true
    } catch {
      return false
    }
  }

  // MARK: UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard let id = response.notification.request.content.userInfo["eventId"] as? String else {
      return
    }
    let action = response.actionIdentifier
    await MainActor.run {
      switch action {
      case Self.joinAction:
        onJoin?(id)
      case Self.snoozeAction:
        let content = response.notification.request.content
        let request = UNNotificationRequest(
          identifier: Self.idPrefix + id + ".snooze", content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false))
        self.center.add(request)
      default:
        break
      }
    }
  }
}
