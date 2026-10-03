import Foundation

/// Identifiers and text for the "still want it?" notification.
/// This file only produces strings; the app turns them into real notifications.
public enum NotificationPlan {
    /// Category for decision notifications (the one with Bought / Skip / Wait buttons).
    public static let categoryIdentifier = "WAITLIST_DECISION"

    /// The buttons on a decision notification. The raw value is the action identifier.
    public enum Action: String, CaseIterable, Sendable {
        case bought = "WAITLIST_BOUGHT"
        case skipped = "WAITLIST_SKIPPED"
        case extend = "WAITLIST_EXTEND"
    }

    /// How many days the "wait longer" button adds.
    public static let extendDays = 7

    /// One notification per item, so the item's id is the request identifier.
    public static func requestIdentifier(for item: Item) -> String {
        item.id.uuidString
    }

    /// Title/body for the "still want it?" notification. Body mentions the name, the days waited and the price when known, e.g. "You waited 14 days for “Gorilla Sofa” (1 299 kr). Still want it?"
    public static func content(for item: Item, now: Date, currencyCode: String,
                               calendar: Calendar = .current) -> (title: String, body: String) {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let days = item.daysWaited(at: now, calendar: calendar)

        var subject = "“\(name)”"
        if let price = item.price {
            subject += " (\(price.formatted(.currency(code: currencyCode))))"
        }

        let waited: String
        switch days {
        case 0: waited = "You added \(subject) today."
        case 1: waited = "You waited 1 day for \(subject)."
        default: waited = "You waited \(days) days for \(subject)."
        }
        return (title: "Time to decide", body: "\(waited) Still want it?")
    }
}
