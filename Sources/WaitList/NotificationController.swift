import AppKit
import UserNotifications
import WaitListCore

/// Schedules one "still want it?" notification per waiting item and handles the buttons on it.
///
/// Must be set as the notification center delegate before `applicationDidFinishLaunching` returns,
/// otherwise a tap that launches the app is lost. Responses that arrive before `attach` are queued.
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    /// What was scheduled for an item; if it is unchanged we do not re-add the request.
    private struct Signature: Equatable {
        let fireDate: Date
        let timeZone: String
        let title: String
        let body: String
    }

    /// The parts of a response we need, extracted off the main actor.
    private struct Response: Sendable {
        let actionIdentifier: String
        let itemID: UUID?
    }

    private weak var store: ItemStore?
    private weak var settings: AppSettings?
    private var openPopover: (() -> Void)?
    private var queuedResponses: [Response] = []

    /// Requests we believe are pending, by identifier.
    private var scheduled: [String: Signature] = [:]
    /// Identifiers kept by the last cleanup pass, so a periodic refresh that changes nothing is cheap.
    private var lastCleanup: (pending: Set<String>, delivered: Set<String>)?

    private var center: UNUserNotificationCenter { .current() }

    // MARK: Setup

    /// Connects the controller to the app. Handles any responses that arrived before this.
    func attach(store: ItemStore, settings: AppSettings, openPopover: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.openPopover = openPopover
        let queued = queuedResponses
        queuedResponses = []
        queued.forEach(handle)
    }

    /// Registers the Skip / Bought / Wait buttons.
    func registerCategory() {
        let actions = [
            UNNotificationAction(identifier: NotificationPlan.Action.skipped.rawValue, title: "Skip it", options: []),
            UNNotificationAction(identifier: NotificationPlan.Action.bought.rawValue, title: "Bought it", options: []),
            UNNotificationAction(identifier: NotificationPlan.Action.extend.rawValue,
                                 title: "Wait \(NotificationPlan.extendDays) more days", options: []),
        ]
        let category = UNNotificationCategory(identifier: NotificationPlan.categoryIdentifier, actions: actions,
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Asks for permission (the system only prompts once). Once granted, schedules everything again,
    /// because requests added before the answer may have been rejected.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                NSLog("WaitList: notification authorization failed: \(error.localizedDescription)")
            }
            guard granted, let self else { return }
            Task { @MainActor in self.rescheduleFromScratch() }
        }
    }

    // MARK: Scheduling

    /// Makes pending requests match `store.waiting` and removes delivered notifications for items
    /// that are no longer due or waiting (decided or deleted).
    func reschedule(store: ItemStore) {
        let currencyCode = settings?.currencyCode ?? AppSettings.defaultCurrencyCode
        let calendar = store.calendar
        let timeZone = calendar.timeZone.identifier
        var desired: [String: Signature] = [:]

        for item in store.waiting {
            let identifier = NotificationPlan.requestIdentifier(for: item)
            let text = NotificationPlan.content(for: item, now: item.decideAt, currencyCode: currencyCode,
                                                calendar: calendar)
            // Whole seconds, rounded up, so the notification never fires before the item is due.
            let fireDate = Date(timeIntervalSinceReferenceDate: item.decideAt.timeIntervalSinceReferenceDate.rounded(.up))
            let signature = Signature(fireDate: fireDate, timeZone: timeZone, title: text.title, body: text.body)
            desired[identifier] = signature
            guard scheduled[identifier] != signature else { continue }

            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.categoryIdentifier = NotificationPlan.categoryIdentifier
            content.userInfo = ["itemID": item.id.uuidString]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                     from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request) { [weak self] error in
                guard let error, let self else { return }
                NSLog("WaitList: could not schedule notification: \(error.localizedDescription)")
                // Forget it so the next refresh tries again.
                Task { @MainActor in self.scheduled[identifier] = nil }
            }
        }
        scheduled = desired

        let keepPending = Set(desired.keys)
        let keepDelivered = keepPending.union(store.due.map(NotificationPlan.requestIdentifier(for:)))
        if let lastCleanup, lastCleanup.pending == keepPending, lastCleanup.delivered == keepDelivered {
            return
        }
        lastCleanup = (keepPending, keepDelivered)

        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { !keepPending.contains($0) }
            if !stale.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
            }
        }
        center.getDeliveredNotifications { notifications in
            let stale = notifications.map(\.request.identifier).filter { !keepDelivered.contains($0) }
            if !stale.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: stale)
            }
        }
    }

    private func rescheduleFromScratch() {
        scheduled = [:]
        lastCleanup = nil
        if let store { reschedule(store: store) }
    }

    // MARK: Settings support

    nonisolated func authorizationStatus() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return .allowed
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Opens WaitList's page in System Settings › Notifications (or the Notifications pane on older systems).
    func openSystemSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? AppInfo.bundleIdentifier
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// A notification fired while the app runs: show it, and refresh so the badge and list update now
    /// rather than at the next timer tick.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        await refreshStore()
        return [.banner, .sound, .list]
    }

    /// The async form: the system's completion handler is called when this returns.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let idString = (request.content.userInfo["itemID"] as? String) ?? request.identifier
        let parsed = Response(actionIdentifier: response.actionIdentifier, itemID: UUID(uuidString: idString))
        await handle(parsed)
    }

    private func refreshStore() {
        store?.refresh()
    }

    private func handle(_ response: Response) {
        guard let store else {
            queuedResponses.append(response)
            return
        }
        store.refresh()

        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            openPopover?()
            return
        }
        // Ignore stale buttons, e.g. on a notification for an item already decided in the popover.
        guard let action = NotificationPlan.Action(rawValue: response.actionIdentifier),
              let id = response.itemID,
              let item = store.item(id), !item.isDecided else { return }
        switch action {
        case .bought: store.decide(id, .bought)
        case .skipped: store.decide(id, .skipped)
        case .extend: store.extend(id, byDays: NotificationPlan.extendDays)
        }
    }
}
