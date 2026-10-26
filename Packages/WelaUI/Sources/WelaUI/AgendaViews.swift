import SwiftUI
import WelaCore

struct AgendaHeader: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    let title = vm.agendaTitle
    let count = vm.agenda.count
    HStack(alignment: .firstTextBaseline) {
      Text(title.label).welaFont(10.5, weight: .bold).tracking(0.8).foregroundStyle(Theme.redPen)
      Text(title.date).welaFont(15, serif: true).foregroundStyle(Theme.ink)
      Spacer()
      Text(count == 1 ? "1 event" : "\(count) events").welaFont(11.5).foregroundStyle(Theme.softInk)
    }
    .accessibilityElement(children: .combine)
  }
}

struct StatusMark: View {
  let item: AgendaItem
  let color: Color

  var body: some View {
    Group {
      if item.isCancelled {
        Circle().strokeBorder(Theme.pencil, lineWidth: 1.5)
      } else if item.event.myResponse == .tentative || item.event.myResponse == .notResponded
        || item.event.status == .tentative
      {
        Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
      } else {
        Circle().fill(color)
      }
    }
    .frame(width: 11, height: 11)
    .accessibilityHidden(true)
  }
}

struct ConferenceIcon: View {
  let kind: ConferenceKind?

  var body: some View {
    Image(systemName: "video.fill").welaFont(11).foregroundStyle(Theme.softInk).accessibilityHidden(
      true)
  }
}

struct AgendaRow: View {
  @ObservedObject var vm: PanelViewModel
  let item: AgendaItem
  let isSelected: Bool
  /// Off in the now card, where the Join button takes the icon's place.
  var showsConferenceIcon = true

  var body: some View {
    let e = item.event
    let past = vm.isPast(item)
    let secondary = Theme.softInk
    HStack(alignment: .top, spacing: 10) {
      StatusMark(item: item, color: vm.color(for: e.calendarId)).padding(.top, 4)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(vm.timeRange(for: e)).welaFont(11.5).monospacedDigit().foregroundStyle(secondary)
          if let label = item.multiDayLabel {
            Text(label).welaFont(11.5).foregroundStyle(secondary)
          }
        }
        Text(e.title)
          .welaFont(13.5, weight: .medium)
          .strikethrough(item.isCancelled)
          .lineLimit(2)
          .foregroundStyle(past || item.isCancelled ? Theme.softInk : Theme.ink)
        if let line = detailLine(e) {
          Text(line).welaFont(11.5).lineLimit(1).foregroundStyle(secondary)
        }
      }
      Spacer(minLength: 4)
      if showsConferenceIcon && e.joinURL != nil && !item.isCancelled {
        ConferenceIcon(kind: e.conferenceKind)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 6)
    .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Theme.field : Color.clear))
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel(e, past: past))
    .accessibilityAddTraits(.isButton)
  }

  private func detailLine(_ e: EventInstance) -> String? {
    if let loc = e.location, !loc.isEmpty { return loc }
    switch e.conferenceKind {
    case .teams?: return "Microsoft Teams"
    case .meet?: return "Google Meet"
    case .zoom?: return "Zoom"
    case .webex?: return "Webex"
    default: return nil
    }
  }

  private func accessibilityLabel(_ e: EventInstance, past: Bool) -> String {
    var parts: [String] = []
    if e.isAllDay {
      parts.append("All day")
    } else {
      parts.append("\(vm.timeString(e.start)) to \(vm.timeString(e.end))")
    }
    parts.append(e.title)
    if let loc = e.location, !loc.isEmpty { parts.append(loc) }
    if item.isCancelled {
      parts.append("cancelled")
    } else {
      switch e.myResponse {
      case .accepted: parts.append("accepted")
      case .tentative: parts.append("tentative")
      case .notResponded: parts.append("not responded")
      case .declined: parts.append("declined")
      case .organizer, .none: break
      }
    }
    if let label = item.multiDayLabel { parts.append(label) }
    if past { parts.append("ended") }
    return parts.joined(separator: ", ")
  }
}

/// The event in progress, lifted onto a card with time left and a Join pill.
struct NowCard: View {
  @ObservedObject var vm: PanelViewModel
  let item: AgendaItem
  let isSelected: Bool

  var body: some View {
    let e = item.event
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 0) {
        AgendaRow(vm: vm, item: item, isSelected: false, showsConferenceIcon: false)
        Text("\(vm.minutesLeft(e)) min left").welaFont(11.5, weight: .semibold)
          .foregroundStyle(Theme.blueInk)
          // Line up with the title column: row padding 6 + status mark 11 + spacing 10.
          .padding(.leading, 27).padding(.bottom, 8)
      }
      if e.joinURL != nil {
        // Vertically centred on the card's right edge.
        Button {
          vm.join(e)
        } label: {
          Text("Join").welaFont(12, weight: .semibold).foregroundStyle(Theme.onBlue)
            .padding(.horizontal, 16).padding(.vertical, 5)
            .background(Capsule().fill(Theme.blueInk))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Join \(e.title)")
        .padding(.trailing, 10)
      }
    }
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 10).fill(Theme.card)
        .overlay(
          RoundedRectangle(cornerRadius: 10).stroke(
            isSelected ? Theme.blueInk : Theme.rule, lineWidth: 1))
    )
  }
}

struct AgendaList: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    let agenda = vm.agenda
    let nowID = vm.nowItem?.id
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if agenda.isEmpty {
            Text("No events").welaFont(13).foregroundStyle(Theme.softInk)
              .frame(maxWidth: .infinity).padding(.top, 24)
          }
          ForEach(agenda.allDay) { item in row(item, nowID: nowID) }
          ForEach(agenda.timed) { item in row(item, nowID: nowID) }
        }
      }
      .onAppear { scrollToFocus(proxy) }
      .onChange(of: vm.selectedDay) { _, _ in scrollToFocus(proxy) }
      .onChange(of: vm.selectedEventID) { _, id in
        if let id { proxy.scrollTo(id) }
      }
    }
  }

  @ViewBuilder
  private func row(_ item: AgendaItem, nowID: String?) -> some View {
    VStack(spacing: 0) {
      if item.id == nowID {
        NowCard(vm: vm, item: item, isSelected: vm.selectedEventID == item.id).padding(.vertical, 4)
      } else {
        AgendaRow(vm: vm, item: item, isSelected: vm.selectedEventID == item.id)
        Divider().overlay(Theme.rule)
      }
    }
    .id(item.id)
    .onTapGesture {
      vm.selectedEventID = item.id
      vm.openSelectedEvent()
    }
  }

  private func scrollToFocus(_ proxy: ScrollViewProxy) {
    if let id = vm.focusItemID {
      DispatchQueue.main.async { proxy.scrollTo(id, anchor: .top) }
    }
  }
}

struct SearchResultsList: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if vm.searchGroups.isEmpty {
          Text("No results").welaFont(13).foregroundStyle(Theme.softInk)
            .frame(maxWidth: .infinity).padding(.top, 24)
        }
        ForEach(vm.searchGroups, id: \.day) { group in
          Text(vm.formatted(group.day, "EEEE d MMMM").uppercased(with: vm.locale))
            .welaFont(10.5, weight: .bold).tracking(0.8).foregroundStyle(Theme.redPen)
            .padding(.top, 10).padding(.bottom, 2)
          ForEach(group.events) { e in
            let item = AgendaItem(
              event: e, isCancelled: e.status == .cancelled, multiDayLabel: nil)
            AgendaRow(vm: vm, item: item, isSelected: vm.selectedEventID == e.id)
              .onTapGesture {
                vm.selectedEventID = e.id
                vm.openSelectedEvent()
              }
            Divider().overlay(Theme.rule)
          }
        }
      }
    }
  }
}
