#if os(macOS)
import SwiftUI
import WelaCore

public struct SettingsView: View {
  @ObservedObject var vm: PanelViewModel
  @ObservedObject var settings: SettingsModel
  let hotkeyRecorder: AnyView
  @Binding var launchAtLogin: Bool

  public init(
    viewModel: PanelViewModel, hotkeyRecorder: AnyView, launchAtLogin: Binding<Bool>
  ) {
    self.vm = viewModel
    self.settings = viewModel.settings
    self.hotkeyRecorder = hotkeyRecorder
    self._launchAtLogin = launchAtLogin
  }

  public var body: some View {
    TabView {
      general.tabItem { Label("General", systemImage: "gearshape") }
      accounts.tabItem { Label("Accounts", systemImage: "person.crop.circle") }
      calendars.tabItem { Label("Calendars", systemImage: "calendar") }
      notifications.tabItem { Label("Notifications", systemImage: "bell") }
    }
    .frame(width: 480, height: 380)
  }

  private var general: some View {
    Form {
      Toggle("Launch at login", isOn: $launchAtLogin)
      LabeledContent("Open shortcut") { hotkeyRecorder }
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
    .formStyle(.grouped)
  }

  private var accounts: some View {
    Form {
      Section {
        if vm.accounts.isEmpty { Text("No accounts yet").foregroundStyle(.secondary) }
        ForEach(vm.accounts) { account in
          HStack {
            VStack(alignment: .leading) {
              Text(account.email).font(.body)
              Text(statusText(account)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if account.status == .needsSignIn {
              Button("Reconnect") { vm.reconnect(account) }
            }
            Button("Remove", role: .destructive) { vm.remove(account) }
          }
        }
      }
      Section {
        HStack {
          Button("Add Microsoft account") { vm.connect(.microsoft) }
          Button("Add Google account") { vm.connect(.google) }
        }
        if let error = vm.connectError { Text(error).font(.caption).foregroundStyle(.red) }
      }
    }
    .formStyle(.grouped)
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

  private var calendars: some View {
    Form {
      ForEach(vm.accounts) { account in
        Section(account.email) {
          ForEach(vm.calendars.filter { $0.accountId == account.id }) { cal in
            HStack {
              Toggle(
                cal.name,
                isOn: Binding(get: { cal.isVisible }, set: { vm.setCalendarVisible(cal.id, $0) }))
              Spacer()
              ColorPicker(
                "",
                selection: Binding(
                  get: { Theme.calendarColor(hex: cal.effectiveColorHex) },
                  set: { vm.setCalendarColor(cal.id, hex: $0.hexString) }),
                supportsOpacity: false
              ).labelsHidden()
              if cal.userColorHex != nil {
                Button("Reset") { vm.setCalendarColor(cal.id, hex: nil) }.buttonStyle(.link)
              }
            }
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var notifications: some View {
    Form {
      Toggle("Alert before events", isOn: $settings.notificationsEnabled)
      Picker("Default alert time", selection: $settings.alertLeadMinutes) {
        ForEach([0, 5, 10, 15, 30, 60], id: \.self) { m in
          Text(m == 0 ? "At start" : "\(m) minutes before").tag(m)
        }
      }
      .disabled(!settings.notificationsEnabled)
      Text("Calendar-provided reminders are used when present.").font(.caption).foregroundStyle(
        .secondary)
    }
    .formStyle(.grouped)
  }
}
#endif
