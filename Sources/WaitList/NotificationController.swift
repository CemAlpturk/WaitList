import AppKit
import os
import UserNotifications
import WaitListCore

/// Schedules one "still want it?" notification per waiting item and handles the buttons on it.
/// What to add and remove is decided by `NotificationPlanner` (WaitListCore); this class only talks to
/// the notification center.
///
/// Must be set as the notification center delegate before `applicationDidFinishLaunching` returns,
/// otherwise a tap that launches the app is lost. Responses that arrive before `attach` are queued.
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    /// What was scheduled for an item; if it is unchanged (and still pending) the request is not re-added.
    private struct Signature: Equatable {
        let fireDate: Date
        let timeZone: String
        let title: String
        let body: String
    }

    /// The parts of a response we need, extracted before hopping to the main actor.
    private struct Response: Sendable {
        let actionIdentifier: String
        let itemID: UUID?
    }

    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "Notifications")

    private weak var store: ItemStore?
    private weak var settings: AppSettings?
    private var openPopover: (() -> Void)?
    private var queuedResponses: [Response] = []

    /// Requests we added, by identifier.
    private var scheduled: [String: Signature] = [:]
    /// True while a sync pass runs; passes never overlap, so removals and additions happen in order.
    private var isSyncing = false
    /// Set when the store changed during a pass: one more pass runs right after it.
    private var needsSync = false

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
        Task { @MainActor in
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                scheduled = [:]
                reschedule()
            } catch {
                Self.log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Scheduling

    /// Brings the notification center in line with the store: a pending request for every waiting item,
    /// no requests for decided or deleted items, and delivered notifications only for items that are due.
    /// Returns at once; the work happens in a background pass, and calls during a pass are merged into one more.
    func reschedule() {
        needsSync = true
        guard !isSyncing else { return }
        isSyncing = true
        Task { @MainActor in
            while needsSync {
                needsSync = false
                await syncPass()
            }
            isSyncing = false
        }
    }

    private func syncPass() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)

        // Back on the main actor: read the store now, after the awaits, so the plan matches what it holds.
        guard let store else { return }
        let plan = NotificationPlanner.plan(items: store.items, now: Date(), pendingIdentifiers: pending,
                                            deliveredIdentifiers: delivered)
        if !plan.removePending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: plan.removePending)
        }
        if !plan.removeDelivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: plan.removeDelivered)
        }

        let currencyCode = settings?.currencyCode ?? AppSettings.defaultCurrencyCode
        let calendar = store.calendar
        let pendingSet = Set(pending)
        var desired: [String: Signature] = [:]
        var requests: [UNNotificationRequest] = []
        for item in plan.schedule {
            let identifier = NotificationPlan.requestIdentifier(for: item)
            let text = NotificationPlan.content(for: item, now: item.decideAt, currencyCode: currencyCode,
                                                calendar: calendar)
            // Whole seconds, rounded up, so the notification never fires before the item is due.
            let fireDate = Date(timeIntervalSinceReferenceDate: item.decideAt.timeIntervalSinceReferenceDate.rounded(.up))
            let signature = Signature(fireDate: fireDate, timeZone: calendar.timeZone.identifier,
                                      title: text.title, body: text.body)
            desired[identifier] = signature
            if scheduled[identifier] == signature, pendingSet.contains(identifier) { continue }
            requests.append(Self.request(identifier: identifier, itemID: item.id, title: text.title, body: text.body,
                                         fireDate: fireDate, calendar: calendar))
        }
        scheduled = desired

        // Adding a request with an existing identifier replaces it.
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                Self.log.error("Could not schedule a notification: \(error.localizedDescription, privacy: .public)")
                // Forget it so the next pass tries again.
                scheduled[request.identifier] = nil
            }
        }
    }

    private static func request(identifier: String, itemID: UUID, title: String, body: String, fireDate: Date,
                                calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationPlan.categoryIdentifier
        content.userInfo = ["itemID": itemID.uuidString]
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
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
        let item = response.itemID.flatMap(store.item)
        switch NotificationPlanner.response(to: response.actionIdentifier, item: item, now: store.now) {
        case .openPopover?:
            openPopover?()
        case .decide(let id, let outcome)?:
            store.decide(id, outcome)
        case .extend(let id, let days)?:
            store.extend(id, byDays: days)
        case nil:
            break  // dismissed, or a stale button for an item decided or given more time since
        }
    }
}
