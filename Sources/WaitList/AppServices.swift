import AppKit
import Observation

/// Notification permission as the Settings screen shows it.
enum NotificationPermission: Sendable {
    case allowed
    case denied
    case notDetermined
}

/// Everything the views need from the system (notifications, login items, files, quitting),
/// injected so snapshots and previews never touch the real system.
@Observable @MainActor
final class AppServices {
    /// An app-level problem that is not a store error, e.g. the data folder could not be created.
    /// Shown in the same banner style as `ItemStore.lastError`; set to nil to dismiss.
    var notice: String?
    /// Where items are saved, or nil when running in memory only.
    let dataFileURL: URL?

    private let permissionProvider: @MainActor () async -> NotificationPermission
    private let notificationSettingsOpener: @MainActor () -> Void
    private let launchStateProvider: @MainActor () -> LaunchAtLoginState
    private let launchSetter: @MainActor (Bool) throws -> Void
    private let loginItemsOpener: @MainActor () -> Void
    private let quitter: @MainActor () -> Void

    init(dataFileURL: URL?,
         notice: String? = nil,
         notificationPermission: @escaping @MainActor () async -> NotificationPermission,
         openNotificationSettings: @escaping @MainActor () -> Void,
         launchAtLoginState: @escaping @MainActor () -> LaunchAtLoginState,
         setLaunchAtLogin: @escaping @MainActor (Bool) throws -> Void,
         openLoginItemsSettings: @escaping @MainActor () -> Void,
         quit: @escaping @MainActor () -> Void) {
        self.dataFileURL = dataFileURL
        self.notice = notice
        self.permissionProvider = notificationPermission
        self.notificationSettingsOpener = openNotificationSettings
        self.launchStateProvider = launchAtLoginState
        self.launchSetter = setLaunchAtLogin
        self.loginItemsOpener = openLoginItemsSettings
        self.quitter = quit
    }

    /// The real thing.
    static func live(dataFileURL: URL?, notice: String?, notifications: NotificationController) -> AppServices {
        AppServices(
            dataFileURL: dataFileURL,
            notice: notice,
            notificationPermission: { await notifications.authorizationStatus() },
            openNotificationSettings: { notifications.openSystemSettings() },
            launchAtLoginState: { LaunchAtLogin.state },
            setLaunchAtLogin: { try LaunchAtLogin.setEnabled($0) },
            openLoginItemsSettings: { LaunchAtLogin.openSystemSettings() },
            quit: { NSApp.terminate(nil) })
    }

    /// Inert stand-in for snapshots and previews.
    static func preview(dataFileURL: URL? = nil, notice: String? = nil,
                        permission: NotificationPermission = .allowed,
                        launchAtLogin: LaunchAtLoginState = .disabled) -> AppServices {
        AppServices(
            dataFileURL: dataFileURL,
            notice: notice,
            notificationPermission: { permission },
            openNotificationSettings: {},
            launchAtLoginState: { launchAtLogin },
            setLaunchAtLogin: { _ in },
            openLoginItemsSettings: {},
            quit: {})
    }

    func notificationPermission() async -> NotificationPermission {
        await permissionProvider()
    }

    func openNotificationSettings() {
        notificationSettingsOpener()
    }

    func launchAtLoginState() -> LaunchAtLoginState {
        launchStateProvider()
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        try launchSetter(enabled)
    }

    func openLoginItemsSettings() {
        loginItemsOpener()
    }

    func quit() {
        quitter()
    }

    /// Selects the data file in Finder, or opens its folder if the file does not exist yet.
    func revealDataFile() {
        guard let url = dataFileURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
