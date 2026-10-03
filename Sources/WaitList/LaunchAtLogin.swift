import ServiceManagement

/// What the "Launch at login" toggle shows.
enum LaunchAtLoginState: Equatable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings › General › Login Items.
    case requiresApproval
}

/// Thin wrapper over `SMAppService.mainApp`.
///
/// Note: this only works reliably once WaitList.app lives in /Applications. Registering a copy that runs from
/// `build/` or Downloads can fail, or leave a login item pointing at a path that later disappears.
@MainActor
enum LaunchAtLogin {
    static var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
