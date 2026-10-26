import SwiftUI
import WelaCore

/// iPhone (and narrow iPad Split View / Slide Over): the panel's month grid over the agenda,
/// filling the screen.
struct CompactCalendarLayout: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    VStack(spacing: 0) {
      MobileBanners(vm: vm)
      MonthHeader(vm: vm).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6)
      MonthGrid(vm: vm).padding(.horizontal, 10).monthSwipe(vm)
      Divider().overlay(Theme.rule).padding(.horizontal, 16).padding(.vertical, 8)
      AgendaHeader(vm: vm).padding(.horizontal, 16).padding(.bottom, 4)
      AgendaList(vm: vm).padding(.horizontal, 10)
      MobileStaleSync(vm: vm)
    }
  }
}

/// Full-width iPad: month on the left, the selected day's agenda on the right.
struct RegularCalendarLayout: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    GeometryReader { geo in
      HStack(alignment: .top, spacing: 0) {
        VStack(spacing: 0) {
          MobileBanners(vm: vm)
          MonthHeader(vm: vm).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
          MonthGrid(vm: vm).padding(.horizontal, 14).monthSwipe(vm)
          Spacer(minLength: 0)
          MobileStaleSync(vm: vm)
        }
        .frame(width: min(480, max(320, geo.size.width * 0.45)))
        Rectangle().fill(Theme.rule).frame(width: 1).ignoresSafeArea(edges: .bottom)
        VStack(spacing: 0) {
          AgendaHeader(vm: vm).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 6)
          AgendaList(vm: vm).padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }
}

struct MobileBanners: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    if let account = vm.accountNeedingSignIn {
      ReconnectBanner(account: account) { vm.reconnect(account) }
        .padding(.horizontal, 16).padding(.bottom, 6)
    }
  }
}

struct MobileStaleSync: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    if let text = vm.staleSyncText {
      Text(text).welaFont(11).foregroundStyle(Theme.softInk).padding(.vertical, 4)
    }
  }
}

/// First launch on iOS: connect an account. No hotkey step, unlike the Mac.
struct MobileFirstRunView: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Welcome to Wela").welaFont(28, weight: .semibold, serif: true)
          .foregroundStyle(Theme.ink)
        step(
          1, "Connect your calendars",
          "Sign in with the accounts you use. Events come straight from Microsoft or Google to "
            + "this device; there is no Wela server.")
        VStack(alignment: .leading, spacing: 10) {
          connectButton("Connect Microsoft", .microsoft)
          connectButton("Connect Google", .google)
        }
        if let error = vm.connectError {
          Text(error).welaFont(12).foregroundStyle(Theme.redPen)
        }
        step(2, "Choose calendars", "Pick which calendars show up from the filter button.")
        step(
          3, "Add a widget",
          "Touch and hold the Home Screen or Lock Screen, tap Edit, then add Wela's Up Next or "
            + "Month widget.")
      }
      .padding(24)
      .frame(maxWidth: 520, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
  }

  private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(n). \(title)").welaFont(15, weight: .semibold).foregroundStyle(Theme.ink)
      Text(detail).welaFont(13).foregroundStyle(Theme.softInk)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func connectButton(_ title: String, _ provider: ProviderKind) -> some View {
    Button {
      vm.connect(provider)
    } label: {
      Text(title).welaFont(14, weight: .semibold).foregroundStyle(Theme.onBlue)
        .frame(maxWidth: 280).padding(.vertical, 11)
        .background(Capsule().fill(Theme.blueInk))
    }
    .buttonStyle(.plain)
  }
}

extension View {
  /// Swipe left or right on the month grid to change month.
  func monthSwipe(_ vm: PanelViewModel) -> some View {
    simultaneousGesture(
      DragGesture(minimumDistance: 30).onEnded { value in
        let dx = value.translation.width
        guard abs(dx) > abs(value.translation.height) * 1.5, abs(dx) > 50 else { return }
        vm.moveMonth(by: dx < 0 ? 1 : -1)
      })
  }
}

/// Text scale for touch screens: the panel's sizes are tuned for the Mac, so iOS starts larger
/// and follows Dynamic Type.
func mobileTextScale(_ size: DynamicTypeSize, setting: CGFloat) -> CGFloat {
  let dynamic: CGFloat
  switch size {
  case .xSmall: dynamic = 0.88
  case .small: dynamic = 0.92
  case .medium: dynamic = 0.96
  case .large: dynamic = 1
  case .xLarge: dynamic = 1.08
  case .xxLarge: dynamic = 1.16
  case .xxxLarge: dynamic = 1.24
  default: dynamic = 1.36  // accessibility sizes
  }
  return min(1.6, 1.18 * dynamic * setting)
}

#if os(iOS)
  /// The iOS app's root: universal for iPhone and iPad, switching layout on the horizontal size
  /// class so it adapts to Split View, Slide Over, rotation and larger iPhones.
  public struct MobileRootView: View {
    @ObservedObject var vm: PanelViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsSettings = false
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    public init(viewModel: PanelViewModel) { self.vm = viewModel }

    public var body: some View {
      NavigationStack {
        content
          .background(Theme.page.ignoresSafeArea())
          .navigationBarTitleDisplayMode(.inline)
          .toolbarBackground(Theme.page, for: .navigationBar)
          .toolbar { toolbar }
      }
      .tint(Theme.blueInk)
      .environment(\.welaTextScale, mobileTextScale(typeSize, setting: vm.settings.textSize.scale))
      .sheet(isPresented: detailShown) { detailSheet }
      .sheet(isPresented: $showsSettings) { MobileSettingsView(vm: vm) }
      .onReceive(minuteTimer) { _ in vm.tick() }
    }

    @ViewBuilder
    private var content: some View {
      if vm.accounts.isEmpty {
        MobileFirstRunView(vm: vm)
      } else {
        Group {
          if vm.isSearching {
            SearchResultsList(vm: vm).padding(.horizontal, 12)
          } else if sizeClass == .regular {
            RegularCalendarLayout(vm: vm)
          } else {
            CompactCalendarLayout(vm: vm)
          }
        }
        .searchable(text: $vm.searchText, prompt: "Search events")
        .refreshable { await vm.refreshAndWait() }
      }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
      ToolbarItem(placement: .topBarLeading) {
        Button("Today") { vm.goToToday() }
          .disabled(vm.accounts.isEmpty)
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        if !vm.calendars.isEmpty {
          Menu {
            ForEach(vm.calendars) { cal in
              Toggle(
                cal.name,
                isOn: Binding(get: { cal.isVisible }, set: { vm.setCalendarVisible(cal.id, $0) }))
            }
          } label: {
            Image(
              systemName: vm.calendars.allSatisfy(\.isVisible)
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
          }
          .accessibilityLabel("Calendar filter")
        }
        Button {
          showsSettings = true
        } label: {
          Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
      }
    }

    private var detailShown: Binding<Bool> {
      Binding(
        get: { vm.detailEventID != nil },
        set: { if !$0 { vm.closeDetail() } })
    }

    @ViewBuilder
    private var detailSheet: some View {
      NavigationStack {
        ScrollView {
          if let id = vm.detailEventID, let event = vm.event(id: id) {
            EventDetailView(vm: vm, event: event, showsBackButton: false)
          }
        }
        .background(Theme.page.ignoresSafeArea())
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { vm.closeDetail() }
          }
        }
      }
      .tint(Theme.blueInk)
      .environment(\.welaTextScale, mobileTextScale(typeSize, setting: vm.settings.textSize.scale))
      .presentationDetents([.medium, .large])
    }
  }

  /// Settings as a sheet: the Mac window's tabs become sections.
  struct MobileSettingsView: View {
    @ObservedObject var vm: PanelViewModel
    @ObservedObject var settings: SettingsModel
    @Environment(\.dismiss) private var dismiss

    init(vm: PanelViewModel) {
      self.vm = vm
      self.settings = vm.settings
    }

    var body: some View {
      NavigationStack {
        Form {
          accounts
          calendars
          general
          notifications
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
      }
      .tint(Theme.blueInk)
    }

    private var accounts: some View {
      Section("Accounts") {
        ForEach(vm.accounts) { account in
          VStack(alignment: .leading, spacing: 2) {
            Text(account.email)
            Text(statusText(account)).font(.caption).foregroundStyle(.secondary)
          }
          .swipeActions {
            Button("Remove", role: .destructive) { vm.remove(account) }
          }
          .contextMenu {
            if account.status == .needsSignIn {
              Button("Reconnect") { vm.reconnect(account) }
            }
            Button("Remove", role: .destructive) { vm.remove(account) }
          }
        }
        Button("Add Microsoft account") { vm.connect(.microsoft) }
        Button("Add Google account") { vm.connect(.google) }
        if let error = vm.connectError { Text(error).font(.caption).foregroundStyle(.red) }
      }
    }

    private func statusText(_ a: Account) -> String {
      let provider =
        a.provider == .microsoft ? "Microsoft" : a.provider == .google ? "Google" : "Demo"
      switch a.status {
      case .ok: return provider
      case .needsSignIn: return "\(provider) · needs sign-in"
      case .error(let message): return "\(provider) · \(message)"
      }
    }

    @ViewBuilder
    private var calendars: some View {
      ForEach(vm.accounts) { account in
        Section(account.email) {
          ForEach(vm.calendars.filter { $0.accountId == account.id }) { cal in
            HStack {
              Toggle(
                cal.name,
                isOn: Binding(get: { cal.isVisible }, set: { vm.setCalendarVisible(cal.id, $0) }))
              ColorPicker(
                "",
                selection: Binding(
                  get: { Theme.calendarColor(hex: cal.effectiveColorHex) },
                  set: { vm.setCalendarColor(cal.id, hex: $0.hexString) }),
                supportsOpacity: false
              )
              .labelsHidden()
              .frame(width: 32)
            }
            .contextMenu {
              if cal.userColorHex != nil {
                Button("Reset colour") { vm.setCalendarColor(cal.id, hex: nil) }
              }
            }
          }
        }
      }
    }

    private var general: some View {
      Section("General") {
        Picker("First day of week", selection: $settings.weekStart) {
          ForEach(SettingsModel.WeekStart.allCases) { Text($0.title).tag($0) }
        }
        Picker("Calendar", selection: $settings.calendarSystem) {
          ForEach(SettingsModel.CalendarSystem.allCases) { Text($0.title).tag($0) }
        }
        Picker("Time format", selection: $settings.timeFormat) {
          ForEach(SettingsModel.TimeFormat.allCases) { Text($0.title).tag($0) }
        }
        Picker("Text size", selection: $settings.textSize) {
          ForEach(SettingsModel.TextSize.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Show cancelled events", isOn: $settings.showCancelled)
        Toggle("Show declined events", isOn: $settings.showDeclined)
      }
    }

    private var notifications: some View {
      Section {
        Toggle("Alert before events", isOn: $settings.notificationsEnabled)
        Picker("Default alert time", selection: $settings.alertLeadMinutes) {
          ForEach([0, 5, 10, 15, 30, 60], id: \.self) { m in
            Text(m == 0 ? "At start" : "\(m) minutes before").tag(m)
          }
        }
        .disabled(!settings.notificationsEnabled)
      } header: {
        Text("Notifications")
      } footer: {
        Text("Calendar-provided reminders are used when present.")
      }
    }
  }
#endif
