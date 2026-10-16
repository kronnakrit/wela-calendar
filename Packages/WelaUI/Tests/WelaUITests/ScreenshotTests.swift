#if DEBUG
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
      let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10, minute: 20))!

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
  }
#endif
