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
            ScreenHeader(title: "Settings", backTitle: "Back") {
                router.show(.list)
            }
            Divider()
            Form {
                Section("Waiting") {
                    LabeledContent("Default wait") {
                        HStack(spacing: 6) {
                            Text(Format.days(settings.defaultWaitDays))
                                .monospacedDigit()
                            Stepper("Default wait", value: $settings.defaultWaitDays, in: Scheduling.waitDaysRange)
                                .labelsHidden()
                        }
                    }
                }

                Section {
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    LabeledContent("Notifications") {
                        Text(permissionText)
                            .foregroundStyle(permission == .denied ? Color.orange : Color.secondary)
                    }
                    if permission == .denied {
                        Button("Open System Settings") { services.openNotificationSettings() }
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

                Section("Currency") {
                    Picker("Currency", selection: $settings.currencyCode) {
                        ForEach(currencyOptions, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .onChange(of: settings.currencyCode) {
                        // Notification text includes the price; reschedule with the new currency now.
                        store.refresh()
                    }
                }

                Section("General") {
                    Toggle("Launch at login", isOn: launchBinding)
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

                Section("Data") {
                    LabeledContent {
                        Button("Show in Finder") { services.revealDataFile() }
                            .disabled(services.dataFileURL == nil)
                    } label: {
                        Text(dataPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(services.dataFileURL?.path ?? dataPath)
                    }
                }

                Section("About") {
                    LabeledContent {
                        Button("Quit WaitList") { services.quit() }
                            .buttonStyle(.bordered)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WaitList \(AppInfo.version)")
                            Text("MIT License")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
        case .notDetermined: return "Not asked yet"
        case nil: return "…"
        }
    }

    private var dataPath: String {
        guard let url = services.dataFileURL else { return "Not saved (memory only)" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    private var currencyOptions: [CurrencyOption] {
        let options = CurrencyOption.common
        if options.contains(where: { $0.code == settings.currencyCode }) { return options }
        return (options + [CurrencyOption(code: settings.currencyCode)]).sorted { $0.code < $1.code }
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
