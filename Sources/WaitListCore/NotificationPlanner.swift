import Foundation

/// Decides which notification requests to add and remove, and what a tap on a notification does.
/// Pure: the app feeds in what the notification center holds and applies the result.
public enum NotificationPlanner {
    /// What to change in the notification center.
    public struct Plan: Equatable, Sendable {
        /// Undecided items whose decision time is still ahead: each needs a pending request.
        /// (The app skips items whose request is already pending with the same content.)
        public var schedule: [Item]
        /// Pending requests to cancel: ones for items that were decided or deleted, or unknown identifiers.
        public var removePending: [String]
        /// Delivered notifications to take out of Notification Center.
        public var removeDelivered: [String]

        public init(schedule: [Item], removePending: [String], removeDelivered: [String]) {
            self.schedule = schedule
            self.removePending = removePending
            self.removeDelivered = removeDelivered
        }
    }

    /// The plan for `items` at `now`. Pass the real clock (`Date()`), not a cached time, so a notification that
    /// is about to be delivered is never treated as stale.
    ///
    /// - A pending request is kept for every undecided item, even one whose time has passed: the system may
    ///   not have delivered it yet (for example the Mac was asleep), and removing it would lose the reminder.
    /// - A delivered notification is kept only while its item is undecided and due. Once the item is decided,
    ///   deleted, or waiting again ("wait longer"), the notification goes, so its buttons cannot act on it twice.
    public static func plan(items: [Item], now: Date, pendingIdentifiers: [String],
                            deliveredIdentifiers: [String]) -> Plan {
        let undecided = items.filter { !$0.isDecided }
        let undecidedIDs = Set(undecided.map(NotificationPlan.requestIdentifier(for:)))
        let dueIDs = Set(undecided.filter { $0.decideAt <= now }.map(NotificationPlan.requestIdentifier(for:)))
        return Plan(schedule: undecided.filter { $0.decideAt > now },
                    removePending: unique(pendingIdentifiers.filter { !undecidedIDs.contains($0) }),
                    removeDelivered: unique(deliveredIdentifiers.filter { !dueIDs.contains($0) }))
    }

    /// The system's identifier for a click on the notification itself (`UNNotificationDefaultActionIdentifier`).
    /// Spelled out so this module does not need UserNotifications; an app test checks the two match.
    public static let defaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"

    /// What to do in response to a notification.
    public enum Response: Equatable, Sendable {
        /// The notification itself was clicked: open the popover.
        case openPopover
        /// "Bought it" or "Skip it" on an item that is due.
        case decide(UUID, Outcome)
        /// "Wait N more days" on an item that is due.
        case extend(UUID, days: Int)
    }

    /// The response to `actionIdentifier` on the notification for `item` (nil if the item no longer exists).
    /// Buttons only act on an undecided item that is due at `now`: a button on an old notification for an item
    /// that was decided or given more time since does nothing. Returns nil for "nothing to do" (dismissal,
    /// unknown actions, stale buttons).
    public static func response(to actionIdentifier: String, item: Item?, now: Date) -> Response? {
        if actionIdentifier == defaultActionIdentifier {
            return .openPopover
        }
        guard let action = NotificationPlan.Action(rawValue: actionIdentifier),
              let item, item.isDue(at: now) else { return nil }
        switch action {
        case .bought: return .decide(item.id, .bought)
        case .skipped: return .decide(item.id, .skipped)
        case .extend: return .extend(item.id, days: NotificationPlan.extendDays)
        }
    }

    private static func unique(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.filter { seen.insert($0).inserted }
    }
}
