import SwiftUI
import WelaCore

public struct PanelView: View {
  @ObservedObject var vm: PanelViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var focus: Field?
  private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

  enum Field { case main, search }

  public init(viewModel: PanelViewModel) { self.vm = viewModel }

  public var body: some View {
    ZStack {
      if let id = vm.detailEventID, let event = vm.event(id: id) {
        EventDetailView(vm: vm, event: event).transition(
          .move(edge: .trailing).combined(with: .opacity))
      } else {
        main.transition(.opacity)
      }
    }
    .animation(WelaAnimation.standard(reduceMotion: reduceMotion), value: vm.detailEventID)
    .environment(\.welaTextScale, vm.settings.textSize.scale)
    .frame(width: 340, height: 640)
    .background(Theme.page)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.rule, lineWidth: 1)
    )
    .background(shortcuts)
    .focusable()
    .focused($focus, equals: .main)
    .focusEffectDisabled()
    .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
    .onAppear { focus = .main }
    .onReceive(minuteTimer) { _ in vm.tick() }
    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WelaPanelDidOpen"))) {
      _ in
      focus = .main
    }
  }

  @ViewBuilder
  private var main: some View {
    if vm.accounts.isEmpty {
      FirstRunView(vm: vm)
    } else {
      calendarPanel
    }
  }

  private var calendarPanel: some View {
    VStack(spacing: 0) {
      SearchField(text: $vm.searchText, focus: $focus)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
      if let account = vm.accountNeedingSignIn {
        ReconnectBanner(account: account) { vm.reconnect(account) }
          .padding(.horizontal, 16).padding(.bottom, 6)
      }
      if vm.isSearching {
        SearchResultsList(vm: vm).padding(.horizontal, 10)
      } else {
        MonthHeader(vm: vm).padding(.horizontal, 16).padding(.bottom, 6)
        MonthGrid(vm: vm).padding(.horizontal, 10)
        Divider().overlay(Theme.rule).padding(.horizontal, 16).padding(.vertical, 8)
        AgendaHeader(vm: vm).padding(.horizontal, 16).padding(.bottom, 4)
        AgendaList(vm: vm).padding(.horizontal, 10)
      }
      Spacer(minLength: 0)
      if let text = vm.staleSyncText {
        Text(text).welaFont(11).foregroundStyle(Theme.softInk).padding(.bottom, 2)
      }
      FooterView(vm: vm).padding(.horizontal, 16).padding(.vertical, 10)
    }
  }

  /// Hidden buttons that carry the Command-key shortcuts.
  private var shortcuts: some View {
    Group {
      Button("Today") { vm.goToToday() }.keyboardShortcut("t", modifiers: .command)
      Button("Join") { vm.joinSelected() }.keyboardShortcut("j", modifiers: .command)
      Button("Pin") { vm.isPinned.toggle() }.keyboardShortcut("p", modifiers: [.command, .control])
    }
    .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
  }

  private func handle(_ press: KeyPress) -> KeyPress.Result {
    let shift = press.modifiers.contains(.shift)
    let command = press.modifiers.contains(.command)
    switch press.key {
    case .leftArrow:
      shift ? vm.moveSelection(days: -1) : vm.moveMonth(by: -1)
      return .handled
    case .rightArrow:
      shift ? vm.moveSelection(days: 1) : vm.moveMonth(by: 1)
      return .handled
    case .upArrow:
      shift ? vm.moveSelection(days: -7) : vm.moveEventSelection(by: -1)
      return .handled
    case .downArrow:
      shift ? vm.moveSelection(days: 7) : vm.moveEventSelection(by: 1)
      return .handled
    case .return:
      vm.openSelectedEvent()
      return .handled
    case .escape:
      if vm.detailEventID != nil {
        vm.closeDetail()
      } else if vm.isSearching {
        vm.searchText = ""
      } else {
        vm.onClose()
      }
      return .handled
    default:
      // Typing a printable character starts a search.
      if !command, !press.modifiers.contains(.control), !press.characters.isEmpty,
        press.characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
      {
        vm.searchText.append(press.characters)
        focus = .search
        return .handled
      }
      return .ignored
    }
  }
}

struct SearchField: View {
  @Binding var text: String
  var focus: FocusState<PanelView.Field?>.Binding

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(Theme.softInk).accessibilityHidden(true)
      TextField("Search events", text: $text)
        .textFieldStyle(.plain)
        .welaFont(13)
        .foregroundStyle(Theme.ink)
        .focused(focus, equals: .search)
        .accessibilityLabel("Search events")
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain).foregroundStyle(Theme.softInk).accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.field))
  }
}

struct FooterView: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    HStack {
      Menu {
        Button("Refresh now") { vm.refresh() }
        Toggle("Pin panel", isOn: $vm.isPinned)
        if let openSettings = vm.onOpenSettings { Button("Settings…", action: openSettings) }
        Divider()
        Button("Quit Wela") { vm.onQuit?() }
      } label: {
        Image(systemName: "line.3.horizontal").frame(width: 24, height: 24)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("Menu")
      Spacer()
      Menu {
        ForEach(vm.calendars) { cal in
          Toggle(
            cal.name,
            isOn: Binding(get: { cal.isVisible }, set: { vm.setCalendarVisible(cal.id, $0) }))
        }
      } label: {
        HStack(spacing: 4) {
          Text(vm.calendars.allSatisfy(\.isVisible) ? "All Calendars" : "Some Calendars")
            .welaFont(12, weight: .medium)
          Image(systemName: "chevron.down").welaFont(9, weight: .bold)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(Theme.field))
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("Calendar filter")
      Spacer()
      Button {
        vm.onOpenSettings?()
      } label: {
        Image(systemName: "gearshape").frame(width: 24, height: 24)
      }
      .buttonStyle(.plain).foregroundStyle(Theme.softInk)
      .disabled(vm.onOpenSettings == nil)
      .accessibilityLabel("Settings")
    }
    .foregroundStyle(Theme.softInk)
  }
}

struct FirstRunView: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Welcome to Wela").welaFont(26, weight: .semibold, serif: true).foregroundStyle(
        Theme.ink)
      step(
        1, "Connect your calendars",
        "Sign in with the accounts you use. Events are fetched straight to this Mac.")
      HStack(spacing: 10) {
        connectButton("Connect Microsoft", .microsoft)
        connectButton("Connect Google", .google)
      }
      if let error = vm.connectError {
        Text(error).welaFont(11.5).foregroundStyle(Theme.redPen)
      }
      step(2, "Choose calendars", "Pick which calendars show up from the filter at the bottom.")
      step(
        3, "Set your shortcut",
        vm.hotkeyDescription.isEmpty
          ? "Open the panel from anywhere with a global shortcut."
          : "Press \(vm.hotkeyDescription) to open the panel from anywhere.")
      Spacer()
      HStack {
        Spacer()
        FooterView(vm: vm)
      }
    }
    .padding(20)
  }

  private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("\(n). \(title)").welaFont(14, weight: .semibold).foregroundStyle(Theme.ink)
      Text(detail).welaFont(12).foregroundStyle(Theme.softInk)
    }
  }

  private func connectButton(_ title: String, _ provider: ProviderKind) -> some View {
    Button {
      vm.connect(provider)
    } label: {
      Text(title).welaFont(12, weight: .semibold).foregroundStyle(Theme.onBlue)
        .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(Theme.blueInk))
    }
    .buttonStyle(.plain)
  }
}

struct ReconnectBanner: View {
  let account: Account
  let action: () -> Void

  var body: some View {
    HStack {
      Text("\(account.email) needs you to sign in").welaFont(12).foregroundStyle(Theme.ink)
        .lineLimit(1)
      Spacer()
      Button("Reconnect", action: action).buttonStyle(.plain).welaFont(12, weight: .semibold)
        .foregroundStyle(Theme.blueInk)
    }
    .padding(.horizontal, 10).padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.highlighter))
    .accessibilityElement(children: .combine)
  }
}

/// Minimal detail pane; the full card (RSVP, attendees, notes links) arrives in M5.
struct EventDetailView: View {
  @ObservedObject var vm: PanelViewModel
  let event: EventInstance

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        vm.closeDetail()
      } label: {
        Label("Back", systemImage: "chevron.left").welaFont(12)
      }
      .buttonStyle(.plain).foregroundStyle(Theme.softInk)
      Text(event.title).welaFont(20, weight: .semibold, serif: true).foregroundStyle(Theme.ink)
      Text("\(vm.formatted(event.start, "EEEE d MMMM")) · \(vm.timeRange(for: event))")
        .welaFont(12).foregroundStyle(Theme.softInk)
      HStack(spacing: 6) {
        Circle().fill(vm.color(for: event.calendarId)).frame(width: 8, height: 8)
        Text(vm.calendarName(for: event.calendarId)).welaFont(12).foregroundStyle(Theme.softInk)
      }
      if let loc = event.location, !loc.isEmpty {
        Label(loc, systemImage: "mappin.and.ellipse").welaFont(12).foregroundStyle(Theme.softInk)
      }
      if event.joinURL != nil {
        Button {
          vm.join(event)
        } label: {
          Text("Join").welaFont(12, weight: .semibold).foregroundStyle(Theme.onBlue)
            .padding(.horizontal, 18).padding(.vertical, 6).background(
              Capsule().fill(Theme.blueInk))
        }
        .buttonStyle(.plain)
      }
      if vm.canRespond(to: event) {
        HStack(spacing: 8) {
          ForEach(
            [
              ("Accept", ResponseStatus.accepted), ("Tentative", .tentative),
              ("Decline", .declined),
            ],
            id: \.0
          ) { label, response in
            Button {
              vm.respond(to: event, with: response)
            } label: {
              Text(label).welaFont(12, weight: event.myResponse == response ? .bold : .regular)
                .foregroundStyle(Theme.ink).padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                  Capsule().fill(event.myResponse == response ? Theme.highlighter : Theme.field))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label) invitation")
          }
        }
        if let message = vm.rsvpError {
          Text(message).welaFont(11.5).foregroundStyle(Theme.redPen)
        }
      }
      if !event.attendees.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(event.attendees, id: \.email) { a in
            Text("\(a.name) · \(a.response.rawValue)").welaFont(12).foregroundStyle(Theme.softInk)
          }
        }
      }
      if let notes = event.notes, !notes.isEmpty {
        Text(notes).welaFont(12).foregroundStyle(Theme.ink).lineLimit(8)
      }
      Spacer()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
