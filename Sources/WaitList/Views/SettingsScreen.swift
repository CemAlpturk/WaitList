import AppKit
import SwiftUI
import WaitListCore

/// Preferences, notification status, data location and About.
struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ItemStore.self) private var store
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    @State private var permission: NotificationPermission?
    @State private var launchState: LaunchAtLoginState = .disabled
    @State private var launchError: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings", onBack: { router.show(.list) })
            Divider()
            Form {
                Section("General") {
                    Picker("Default wait", selection: $settings.defaultWaitDays) {
                        ForEach(defaultWaitOptions, id: \.self) { days in
                            Text(Format.days(days)).tag(days)
                        }
                    }

                    Picker("Currency", selection: $settings.currencyCode) {
                        let options = currencyOptions
                        ForEach(options.preferred, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                        if !options.preferred.isEmpty {
                            Divider()
                        }
                        ForEach(options.others, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    // No row label, so long names ("BAM – Bosnia-Herzegovina Convertible Mark") get the
                    // whole row. The negative padding cancels the pop-up's title inset so the text lines
                    // up with the other row labels.
                    .labelsHidden()
                    .padding(.leading, -11)
                    .onChange(of: settings.currencyCode) {
                        // Notification text includes the price; reschedule with the new currency now.
                        store.refresh()
                    }

                    Toggle("Open at Login", isOn: launchBinding)
                    if launchState == .requiresApproval {
                        LabeledContent {
                            Button("Open Login Items") { services.openLoginItemsSettings() }
                        } label: {
                            Text("Allow WaitList in Login Items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let launchError {
                        Text(launchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    LabeledContent("Notifications") {
                        Text(permissionText)
                            .foregroundStyle(permission == .denied ? Color.orange : Color.secondary)
                    }
                    if permission == .denied {
                        LabeledContent {
                            Button("Open System Settings") { services.openNotificationSettings() }
                        } label: {
                            Text("Needed for reminders")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text("Items become ready to decide at this time. Changing it moves upcoming decisions too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("About") {
                    LabeledContent {
                        Button("Quit WaitList") { services.quit() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WaitList \(AppInfo.version)")
                            Text("MIT License")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent {
                        Button("Show in Finder") { services.revealDataFile() }
                            .disabled(services.dataFileURL == nil)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Data file")
                            if services.dataFileURL == nil {
                                Text("Not saved (memory only)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .help(services.dataFileURL?.path ?? "Not saved (memory only)")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .task { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshStatus() }
        }
    }

    // MARK: Bindings

    /// Hour and minute of the notification time, as a Date today for the DatePicker.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.notificationHour, minute: settings.notificationMinute,
                                      second: 0, of: store.now) ?? store.now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                guard let hour = parts.hour, let minute = parts.minute,
                      hour != settings.notificationHour || minute != settings.notificationMinute else { return }
                settings.notificationHour = hour
                settings.notificationMinute = minute
                store.retimeUndecided(to: settings.notificationTime)
            })
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchState != .disabled },
            set: { enabled in
                do {
                    try services.setLaunchAtLogin(enabled)
                    launchError = nil
                } catch {
                    launchError = "Couldn't change this: \(error.localizedDescription)"
                }
                launchState = services.launchAtLoginState()
            })
    }

    // MARK: Helpers

    private func refreshStatus() async {
        launchState = services.launchAtLoginState()
        permission = await services.notificationPermission()
    }

    private var permissionText: String {
        switch permission {
        case .allowed: return "Allowed"
        case .denied: return "Not allowed"
        case .notDetermined: return "Not set up"
        case nil: return "…"
        }
    }

    /// The presets, plus the current value when it is something else (set before presets existed).
    private var defaultWaitOptions: [Int] {
        Set(WaitPresets.days + [settings.defaultWaitDays]).sorted()
    }

    /// The region's currency first, then the common ones (plus the current choice if it is unusual).
    private var currencyOptions: (preferred: [CurrencyOption], others: [CurrencyOption]) {
        let local = Locale.current.currency?.identifier.uppercased()
        var others = CurrencyOption.common.filter { $0.code != local }
        if settings.currencyCode != local, !others.contains(where: { $0.code == settings.currencyCode }) {
            others = (others + [CurrencyOption(code: settings.currencyCode)]).sorted { $0.code < $1.code }
        }
        return (local.map { [CurrencyOption(code: $0)] } ?? [], others)
    }
}

/// "SEK – Swedish Krona".
private struct CurrencyOption {
    let code: String
    let label: String

    init(code: String) {
        self.code = code
        if let name = Locale.current.localizedString(forCurrencyCode: code), name != code {
            label = "\(code) – \(name)"
        } else {
            label = code
        }
    }

    static let common: [CurrencyOption] = Set(Locale.commonISOCurrencyCodes)
        .sorted()
        .map(CurrencyOption.init(code:))
}
