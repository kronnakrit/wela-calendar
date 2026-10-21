import SwiftUI
import WelaCore
import WelaUI
import WidgetKit

@main
struct WelaWidgets: WidgetBundle {
  var body: some Widget {
    AgendaWidget()
    MonthWidget()
  }
}

struct AgendaWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WelaAgenda", provider: SnapshotProvider()) { entry in
      SnapshotEntryView(entry: entry, style: .agenda)
    }
    .configurationDisplayName("Up Next")
    .description("What's on now and what's coming up, with Join for online meetings.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
      .accessoryRectangular, .accessoryInline, .accessoryCircular,
    ])
  }
}

struct MonthWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "WelaMonth", provider: SnapshotProvider()) { entry in
      SnapshotEntryView(entry: entry, style: .month)
    }
    .configurationDisplayName("Month")
    .description("This month at a glance, with today ringed and a dot for each event.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
  }
}

struct SnapshotEntry: TimelineEntry {
  let snapshot: WidgetSnapshot
  var date: Date { snapshot.date }
}

/// Reads the app's database (read-only) from the App Group container. Widgets never sync;
/// the app reloads their timelines whenever its data changes.
struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(snapshot: .sample())
  }

  func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
    Task { @MainActor in
      let first = Self.load().first ?? .empty()
      // The widget gallery shows sample events until an account is connected.
      completion(SnapshotEntry(snapshot: context.isPreview && !first.hasAccounts ? .sample() : first))
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
    Task { @MainActor in
      // One entry per moment the widget changes (event starts and ends, midnight); WidgetKit
      // asks again after the last one.
      let entries = Self.load().map(SnapshotEntry.init)
      completion(Timeline(entries: entries, policy: .atEnd))
    }
  }

  @MainActor
  static func load(now: Date = Date()) -> [WidgetSnapshot] {
    let settings = SettingsModel(defaults: SharedContainer.defaults)
    let calendar = settings.makeCalendar(base: .current)
    guard let url = try? SharedContainer.storeURL(demo: SharedContainer.usesDemoStore),
      FileManager.default.fileExists(atPath: url.path),
      let store = try? Store(path: url.path, readOnly: true),
      let timeline = try? WidgetSnapshot.timeline(store: store, settings: settings, now: now),
      !timeline.isEmpty
    else { return [.empty(now: now, calendar: calendar)] }
    return timeline
  }
}

struct SnapshotEntryView: View {
  enum Style { case agenda, month }

  let entry: SnapshotEntry
  let style: Style
  @Environment(\.widgetFamily) private var family

  var body: some View {
    content
      .widgetURL(url)
      .containerBackground(for: .widget) { background }
  }

  @ViewBuilder
  private var content: some View {
    switch style {
    case .agenda: AgendaWidgetView(snapshot: entry.snapshot, layout: layout)
    case .month: MonthWidgetView(snapshot: entry.snapshot, layout: layout)
    }
  }

  @ViewBuilder
  private var background: some View {
    switch family {
    case .accessoryCircular: AccessoryWidgetBackground()
    case .accessoryRectangular, .accessoryInline: Color.clear
    default: Theme.page
    }
  }

  private var layout: WidgetLayout {
    switch family {
    case .systemSmall: return .small
    case .systemMedium: return .medium
    case .accessoryRectangular: return .accessoryRectangular
    case .accessoryInline: return .accessoryInline
    case .accessoryCircular: return .accessoryCircular
    default: return .large
    }
  }

  /// Small widgets are one tap target: the next event (agenda) or today (month).
  private var url: URL {
    if style == .agenda, let item = entry.snapshot.upNext, layout != .large, layout != .medium {
      return WelaLink.event(id: item.id).url
    }
    return entry.snapshot.dayLink
  }
}
