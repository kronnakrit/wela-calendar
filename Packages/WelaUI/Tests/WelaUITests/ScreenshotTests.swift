#if DEBUG && os(macOS)
  import AppKit
  import SwiftUI
  import WelaCore
  import WelaSync
  import XCTest

  @testable import WelaUI

  /// Renders the panel with mock data to PNGs when WELA_SCREENSHOT_DIR is set (used by CI).
  @MainActor
  final class ScreenshotTests: XCTestCase {
    func testRenderPanelScreenshots() async throws {
      guard let dir = ProcessInfo.processInfo.environment["WELA_SCREENSHOT_DIR"] else {
        throw XCTSkip("WELA_SCREENSHOT_DIR not set")
      }
      try FileManager.default.createDirectory(
        atPath: dir, withIntermediateDirectories: true)
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
      let now = cal.date(
        from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 20))!

      for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let store = try Store()
        try MockProvider.seed(into: store, now: now, calendar: cal)
        let vm = PanelViewModel(
          store: store, calendar: cal, locale: Locale(identifier: "en_US"), now: now)
        try await Task.sleep(nanoseconds: 700_000_000)

        let host = NSHostingView(rootView: PanelView(viewModel: vm))
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 640)
        let window = NSWindow(
          contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("panel-\(name).png"))
      }
    }

    /// The iOS layouts and widgets, rendered on the Mac (same SwiftUI views, Mac fonts).
    func testRenderMobileAndWidgetScreenshots() async throws {
      guard let dir = ProcessInfo.processInfo.environment["WELA_SCREENSHOT_DIR"] else {
        throw XCTSkip("WELA_SCREENSHOT_DIR not set")
      }
      try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
      let now = cal.date(
        from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 20))!
      let locale = Locale(identifier: "en_US")

      for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let store = try Store()
        try MockProvider.seed(into: store, now: now, calendar: cal)
        let vm = PanelViewModel(store: store, calendar: cal, locale: locale, now: now)
        try await Task.sleep(nanoseconds: 700_000_000)

        let phone = CompactCalendarLayout(vm: vm)
          .environment(\.welaTextScale, mobileTextScale(.large, setting: 1))
          .background(Theme.page)
        try render(phone, size: NSSize(width: 390, height: 780), appearance, dir, "ios-phone-\(name)")
        let pad = RegularCalendarLayout(vm: vm)
          .environment(\.welaTextScale, mobileTextScale(.large, setting: 1))
          .background(Theme.page)
        try render(pad, size: NSSize(width: 1024, height: 720), appearance, dir, "ios-ipad-\(name)")

        let events = try store.events(in: WidgetSnapshot.interval(now: now, calendar: cal))
        let snapshot = WidgetSnapshot.make(
          events: events, calendars: try store.calendars(), hasAccounts: true, now: now,
          calendar: cal, locale: locale, options: AgendaOptions(), timeTemplate: "Hm")
        try render(
          WidgetGallery(snapshot: snapshot), size: NSSize(width: 800, height: 1010), appearance,
          dir, "ios-widgets-\(name)")
      }
    }

    private func render<V: View>(
      _ view: V, size: NSSize, _ appearance: NSAppearance.Name, _ dir: String, _ file: String
    ) throws {
      let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
      host.frame = NSRect(origin: .zero, size: size)
      let window = NSWindow(
        contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: appearance)
      window.contentView = host
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: rep)
      let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(file).png"))
    }
  }

  /// Every widget at its iPhone point size (6.1" phone), on a neutral board.
  private struct WidgetGallery: View {
    let snapshot: WidgetSnapshot

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top, spacing: 16) {
          tile(AgendaWidgetView(snapshot: snapshot, layout: .small), 170, 170)
          tile(MonthWidgetView(snapshot: snapshot, layout: .small), 170, 170)
          VStack(alignment: .leading, spacing: 12) {
            accessory(AgendaWidgetView(snapshot: snapshot, layout: .accessoryRectangular), 172, 76)
            accessory(AgendaWidgetView(snapshot: snapshot, layout: .accessoryInline), 260, 24)
            accessory(AgendaWidgetView(snapshot: snapshot, layout: .accessoryCircular), 76, 76)
          }
        }
        HStack(alignment: .top, spacing: 16) {
          tile(AgendaWidgetView(snapshot: snapshot, layout: .medium), 364, 170)
          tile(MonthWidgetView(snapshot: snapshot, layout: .medium), 364, 170)
        }
        HStack(alignment: .top, spacing: 16) {
          tile(AgendaWidgetView(snapshot: snapshot, layout: .large), 364, 382)
          tile(MonthWidgetView(snapshot: snapshot, layout: .large), 364, 382)
        }
        Spacer()
      }
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color.gray.opacity(0.35))
    }

    private func tile<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat) -> some View {
      v.padding(16).frame(width: w, height: h)
        .background(Theme.page)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func accessory<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat) -> some View {
      v.frame(width: w, height: h).foregroundStyle(.white)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }
#endif
