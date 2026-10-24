import SwiftUI
import WelaCore

/// Widget sizes, mirrored from WidgetKit's families so these views (and their screenshot tests)
/// don't depend on WidgetKit. The widget extension maps `WidgetFamily` onto this.
public enum WidgetLayout: Sendable {
  case small, medium, large
  case accessoryRectangular, accessoryInline, accessoryCircular
  /// A small widget in StandBy (iPhone on its side while charging): no background, read from
  /// across the room, tinted red at night by the system.
  case standBy

  /// Small widgets are a single tap target; only medium and large can hold links.
  var allowsLinks: Bool { self == .medium || self == .large }
}

// MARK: Agenda widget

/// "Up next": what is on now and what comes after, Fantastical style.
public struct AgendaWidgetView: View {
  let snapshot: WidgetSnapshot
  let layout: WidgetLayout

  public init(snapshot: WidgetSnapshot, layout: WidgetLayout) {
    self.snapshot = snapshot
    self.layout = layout
  }

  public var body: some View {
    switch layout {
    case .accessoryInline: AgendaInline(snapshot: snapshot)
    case .accessoryRectangular: AgendaRectangular(snapshot: snapshot)
    case .accessoryCircular: DateCircular(snapshot: snapshot)
    case .standBy: AgendaStandBy(snapshot: snapshot)
    case .small, .medium, .large:
      if !snapshot.hasAccounts {
        WidgetSignInPrompt()
      } else if layout == .small {
        smallBody
      } else if layout == .medium {
        mediumBody
      } else {
        largeBody
      }
    }
  }

  private var smallBody: some View {
    VStack(alignment: .leading, spacing: 6) {
      DateBadge(snapshot: snapshot, size: 26)
      WidgetItemList(snapshot: snapshot, layout: layout, maxRows: 2, showsDayHeaders: false)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var mediumBody: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        DateBadge(snapshot: snapshot, size: 34)
        Text(snapshot.format(snapshot.date, "MMMM")).welaFont(12).foregroundStyle(Theme.softInk)
        Spacer(minLength: 0)
        Text(remainingText).welaFont(11).foregroundStyle(Theme.softInk).lineLimit(2)
      }
      .frame(width: 84, alignment: .leading)
      WidgetItemList(snapshot: snapshot, layout: layout, maxRows: 3, showsDayHeaders: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var largeBody: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("TODAY").welaFont(10.5, weight: .bold).tracking(0.8).foregroundStyle(Theme.redPen)
        Text(snapshot.format(snapshot.date, "EEEE d MMMM")).welaFont(15, serif: true)
          .foregroundStyle(Theme.ink)
        Spacer()
        Text(remainingText).welaFont(11).foregroundStyle(Theme.softInk)
      }
      Divider().overlay(Theme.rule)
      WidgetItemList(snapshot: snapshot, layout: layout, maxRows: 7, showsDayHeaders: true)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var remainingText: String {
    let n = snapshot.today.items.filter { !$0.isAllDay }.count
    switch n {
    case 0: return "Nothing left today"
    case 1: return "1 event left"
    default: return "\(n) events left"
    }
  }
}

/// Weekday in red pen over the day number, as on the panel.
struct DateBadge: View {
  let snapshot: WidgetSnapshot
  let size: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(snapshot.format(snapshot.date, "EEE").uppercased(with: snapshot.locale))
        .welaFont(10.5, weight: .bold).tracking(0.8).foregroundStyle(Theme.redPen)
      Text("\(snapshot.calendar.component(.day, from: snapshot.date))")
        .welaFont(size, weight: .semibold, serif: true).monospacedDigit()
        .foregroundStyle(Theme.ink)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Today's remaining events, then the next days' (with day headers when allowed).
struct WidgetItemList: View {
  let snapshot: WidgetSnapshot
  let layout: WidgetLayout
  let maxRows: Int
  let showsDayHeaders: Bool

  var body: some View {
    let sections = visibleSections
    VStack(alignment: .leading, spacing: 5) {
      if snapshot.today.items.isEmpty {
        Text("No more events today").welaFont(12).foregroundStyle(Theme.softInk)
      }
      ForEach(sections, id: \.day) { section in
        if showsDayHeaders && section.day != snapshot.today.day {
          Text(header(for: section.day)).welaFont(9.5, weight: .bold).tracking(0.6)
            .foregroundStyle(Theme.redPen).padding(.top, 2)
        }
        ForEach(section.items) { item in
          row(item, showsDay: !showsDayHeaders && section.day != snapshot.today.day)
        }
      }
    }
  }

  @ViewBuilder
  private func row(_ item: WidgetItem, showsDay: Bool) -> some View {
    let content = WidgetRow(
      snapshot: snapshot, item: item, compact: layout == .small, showsDay: showsDay,
      showsJoin: layout.allowsLinks)
    if layout.allowsLinks {
      Link(destination: WelaLink.event(id: item.id).url) { content }
    } else {
      content
    }
  }

  private func header(for day: Date) -> String {
    "\(snapshot.dayLabel(day)) · \(snapshot.format(day, "d MMM"))"
  }

  /// Sections trimmed to `maxRows` rows in total; a day header costs about half a row.
  private var visibleSections: [WidgetDay] {
    var budget = Double(maxRows)
    var out: [WidgetDay] = []
    for section in snapshot.days {
      let isToday = section.day == snapshot.today.day
      if !isToday && showsDayHeaders { budget -= 0.5 }
      let take = max(0, min(section.items.count, Int(budget.rounded(.down))))
      if take == 0 { break }
      out.append(WidgetDay(day: section.day, items: Array(section.items.prefix(take))))
      budget -= Double(take)
    }
    return out
  }
}

struct WidgetRow: View {
  let snapshot: WidgetSnapshot
  let item: WidgetItem
  let compact: Bool
  let showsDay: Bool
  let showsJoin: Bool

  var body: some View {
    let color = Theme.calendarColor(hex: item.colorHex)
    let isNow = snapshot.isNow(item)
    HStack(alignment: .top, spacing: 6) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(item.isTentative ? color.opacity(0.45) : color)
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title)
          .welaFont(compact ? 12.5 : 13, weight: .medium)
          .lineLimit(compact ? 2 : 1)
          .foregroundStyle(Theme.ink)
        Text(subtitle(isNow: isNow))
          .welaFont(compact ? 10.5 : 11)
          .monospacedDigit()
          .lineLimit(1)
          .foregroundStyle(isNow ? Theme.blueInk : Theme.softInk)
      }
      Spacer(minLength: 0)
      if showsJoin && isNow && item.hasJoin {
        Link(destination: WelaLink.join(id: item.id).url) {
          Text("Join").welaFont(11, weight: .semibold).foregroundStyle(Theme.onBlue)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(Theme.blueInk))
        }
        .accessibilityLabel("Join \(item.title)")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }

  private func subtitle(isNow: Bool) -> String {
    var parts: [String] = []
    if showsDay { parts.append(snapshot.format(item.start, "EEE")) }
    if isNow {
      parts.append("Now · until \(snapshot.time(item.end))")
    } else if item.isAllDay {
      parts.append(item.multiDayLabel ?? "All day")
    } else {
      parts.append(compact ? snapshot.time(item.start) : snapshot.timeRange(item))
    }
    if !compact, let loc = item.location, !loc.isEmpty { parts.append(loc) }
    return parts.joined(separator: " · ")
  }
}

struct WidgetSignInPrompt: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Wela").welaFont(20, weight: .semibold, serif: true).foregroundStyle(Theme.ink)
      Text("Open Wela to connect your calendars.").welaFont(12).foregroundStyle(Theme.softInk)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// MARK: StandBy

private struct LiveTimesKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
  /// Countdowns tick live in widgets; screenshot tests turn this off to get fixed text.
  public var welaWidgetLiveTimes: Bool {
    get { self[LiveTimesKey.self] }
    set { self[LiveTimesKey.self] = newValue }
  }
}

/// Up Next for StandBy: one event, big, with a live countdown.
struct AgendaStandBy: View {
  let snapshot: WidgetSnapshot
  @Environment(\.welaWidgetLiveTimes) private var liveTimes

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if !snapshot.hasAccounts {
        Text("Wela").welaFont(26, weight: .semibold, serif: true).foregroundStyle(Theme.ink)
        Text("Open Wela to connect your calendars.").welaFont(14).foregroundStyle(Theme.softInk)
      } else if let item = snapshot.upNext {
        let isNow = snapshot.isNow(item)
        HStack(spacing: 6) {
          Circle().fill(Theme.calendarColor(hex: item.colorHex)).frame(width: 9, height: 9)
          Text(label(item, isNow: isNow))
            .welaFont(13, weight: .bold).tracking(1).foregroundStyle(Theme.redPen)
        }
        Text(item.title)
          .welaFont(24, weight: .semibold, serif: true)
          .lineLimit(3).minimumScaleFactor(0.7)
          .foregroundStyle(Theme.ink)
        Spacer(minLength: 0)
        Text(snapshot.timeRange(item)).welaFont(15, weight: .medium).monospacedDigit()
          .foregroundStyle(Theme.ink)
        if !item.isAllDay { countdown(item, isNow: isNow) }
      } else {
        Text("TODAY").welaFont(13, weight: .bold).tracking(1).foregroundStyle(Theme.redPen)
        Text("Nothing else coming up").welaFont(22, weight: .semibold, serif: true)
          .foregroundStyle(Theme.ink)
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .combine)
  }

  private func label(_ item: WidgetItem, isNow: Bool) -> String {
    if isNow { return "NOW" }
    let day = snapshot.dayLabel(item.start)
    return day == "TODAY" ? "NEXT" : day
  }

  @ViewBuilder
  private func countdown(_ item: WidgetItem, isNow: Bool) -> some View {
    let target = isNow ? item.end : item.start
    Group {
      if liveTimes {
        if isNow {
          Text("\(Text(target, style: .relative)) left")
        } else {
          Text("in \(Text(target, style: .relative))")
        }
      } else {
        let minutes = max(0, Int((target.timeIntervalSince(snapshot.date) / 60).rounded(.up)))
        Text(isNow ? "\(minutes) min left" : "in \(minutes) min")
      }
    }
    .welaFont(13, weight: .semibold).monospacedDigit()
    .foregroundStyle(isNow ? Theme.blueInk : Theme.softInk)
  }
}

// MARK: Lock screen

struct AgendaInline: View {
  let snapshot: WidgetSnapshot

  var body: some View {
    if let item = snapshot.upNext {
      if snapshot.isNow(item) {
        Text("Now: \(item.title)")
      } else if item.isAllDay {
        Text(item.title)
      } else {
        Text("\(snapshot.time(item.start)) \(item.title)")
      }
    } else {
      Text(snapshot.hasAccounts ? "No upcoming events" : "Wela")
    }
  }
}

struct AgendaRectangular: View {
  let snapshot: WidgetSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let item = snapshot.upNext {
        Text(when(item)).font(.caption2.weight(.semibold)).lineLimit(1)
        Text(item.title).font(.headline).lineLimit(2)
        if let loc = item.location, !loc.isEmpty {
          Text(loc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
      } else {
        Text(snapshot.dayLabel(snapshot.date)).font(.caption2.weight(.semibold))
        Text(snapshot.hasAccounts ? "No upcoming events" : "Open Wela to connect calendars")
          .font(.headline).lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func when(_ item: WidgetItem) -> String {
    if snapshot.isNow(item) { return "NOW · UNTIL \(snapshot.time(item.end))" }
    let sameDay = snapshot.calendar.isDate(item.start, inSameDayAs: snapshot.date)
    let day = sameDay ? "" : snapshot.format(item.start, "EEE").uppercased() + " "
    return item.isAllDay ? day + "ALL DAY" : day + snapshot.time(item.start)
  }
}

struct DateCircular: View {
  let snapshot: WidgetSnapshot

  var body: some View {
    VStack(spacing: -2) {
      Text(snapshot.format(snapshot.date, "EEE").uppercased(with: snapshot.locale))
        .font(.system(size: 10, weight: .bold))
      Text("\(snapshot.calendar.component(.day, from: snapshot.date))")
        .font(.system(size: 22, weight: .semibold, design: .serif)).monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: Month widget

/// The month grid with today ringed in red pen, plus what is next on bigger sizes.
public struct MonthWidgetView: View {
  let snapshot: WidgetSnapshot
  let layout: WidgetLayout

  public init(snapshot: WidgetSnapshot, layout: WidgetLayout) {
    self.snapshot = snapshot
    self.layout = layout
  }

  public var body: some View {
    switch layout {
    case .small, .standBy:
      MiniMonth(snapshot: snapshot, showsDots: true, dense: true)
    case .medium:
      HStack(alignment: .top, spacing: 14) {
        MiniMonth(snapshot: snapshot, showsDots: true, dense: true).frame(width: 140)
        VStack(alignment: .leading, spacing: 4) {
          Text(snapshot.format(snapshot.date, "EEEE d").uppercased(with: snapshot.locale))
            .welaFont(10.5, weight: .bold).tracking(0.8).foregroundStyle(Theme.redPen)
          if snapshot.hasAccounts {
            WidgetItemList(snapshot: snapshot, layout: layout, maxRows: 3, showsDayHeaders: false)
          } else {
            Text("Open Wela to connect your calendars.").welaFont(12).foregroundStyle(
              Theme.softInk)
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    case .large:
      VStack(alignment: .leading, spacing: 8) {
        MiniMonth(snapshot: snapshot, showsDots: true, dense: false)
        Divider().overlay(Theme.rule)
        if snapshot.hasAccounts {
          WidgetItemList(snapshot: snapshot, layout: layout, maxRows: 3, showsDayHeaders: true)
        } else {
          Text("Open Wela to connect your calendars.").welaFont(12).foregroundStyle(Theme.softInk)
        }
        Spacer(minLength: 0)
      }
    case .accessoryRectangular, .accessoryInline, .accessoryCircular:
      AgendaWidgetView(snapshot: snapshot, layout: layout)
    }
  }
}

struct MiniMonth: View {
  let snapshot: WidgetSnapshot
  let showsDots: Bool
  /// Small and medium widgets: initials for weekdays, one dot per day.
  let dense: Bool

  var body: some View {
    let cal = snapshot.calendar
    let cells = snapshot.monthCells
    let rows = stride(from: 0, to: cells.count, by: 7).map {
      Array(cells[$0..<min($0 + 7, cells.count)])
    }
    VStack(alignment: .leading, spacing: dense ? 1 : 4) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(CalendarMath.monthName(for: snapshot.date, calendar: cal, locale: snapshot.locale))
          .welaFont(dense ? 13 : 20, weight: .semibold, serif: true).foregroundStyle(Theme.ink)
        if !dense {
          Text(CalendarMath.yearString(for: snapshot.date, calendar: cal, locale: snapshot.locale))
            .welaFont(20, weight: .semibold, serif: true).foregroundStyle(Theme.redPen)
        }
      }
      .padding(.bottom, dense ? 2 : 0)
      HStack(spacing: 0) {
        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
          Text(symbol)
            .welaFont(dense ? 8 : 10, weight: .semibold)
            .foregroundStyle(index == todayWeekdayIndex ? Theme.redPen : Theme.softInk)
            .frame(maxWidth: .infinity)
        }
      }
      ForEach(rows.indices, id: \.self) { r in
        HStack(spacing: 0) {
          ForEach(rows[r]) { cell in dayCell(cell) }
        }
        .background(
          RoundedRectangle(cornerRadius: dense ? 4 : 6).fill(
            rows[r].contains(where: \.isToday) ? Theme.highlighter : Color.clear))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func dayCell(_ cell: DayCell) -> some View {
    if dense {
      dayLabel(cell)
    } else {
      let key = DayKey.string(for: cell.date, timeZone: snapshot.calendar.timeZone)
      Link(destination: WelaLink.day(key).url) { dayLabel(cell) }
    }
  }

  private func dayLabel(_ cell: DayCell) -> some View {
    let dots = showsDots ? Array((snapshot.dots[cell.date] ?? []).prefix(dense ? 1 : 4)) : []
    return VStack(spacing: dense ? 0 : 2) {
      ZStack {
        if cell.isToday {
          Ellipse().stroke(Theme.redPen, lineWidth: dense ? 1.2 : 1.5)
            .frame(width: dense ? 17 : 28, height: dense ? 14 : 23)
            .rotationEffect(.degrees(-10))
        }
        Text("\(snapshot.calendar.component(.day, from: cell.date))")
          .welaFont(dense ? 9.5 : 13, weight: cell.isToday ? .semibold : .regular)
          .monospacedDigit()
          .foregroundStyle(
            cell.isInMonth ? (cell.isToday ? Theme.redPen : Theme.ink) : Theme.pencil)
      }
      .frame(height: dense ? 14 : 24)
      HStack(spacing: 2) {
        ForEach(dots.indices, id: \.self) { i in
          Circle().fill(Theme.calendarColor(hex: dots[i]))
            .frame(width: dense ? 3 : 4, height: dense ? 3 : 4)
        }
      }
      .frame(height: dense ? 3 : 5)
    }
    .frame(maxWidth: .infinity)
  }

  private var weekdaySymbols: [String] {
    let cal = snapshot.calendar
    let f = DateFormatter()
    f.locale = snapshot.locale
    f.calendar = cal
    let base: [String] =
      (dense ? f.veryShortStandaloneWeekdaySymbols : f.shortStandaloneWeekdaySymbols) ?? []
    guard base.count == 7 else { return base }
    let start = cal.firstWeekday - 1
    return (0..<7).map { base[(start + $0) % 7].uppercased(with: snapshot.locale) }
  }

  private var todayWeekdayIndex: Int {
    let cal = snapshot.calendar
    return (cal.component(.weekday, from: snapshot.date) - cal.firstWeekday + 7) % 7
  }
}
