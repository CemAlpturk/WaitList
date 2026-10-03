import Foundation
import WaitListCore

/// Short, friendly strings for the UI. Price input parsing lives in WaitListCore (`PriceInput`).
enum Format {
    /// "1 day", "2 days".
    static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    /// "1 299 kr" for whole amounts, "19,99 kr" otherwise (both in the user's locale).
    /// Same text as in notifications (`PriceFormat.string`).
    static func price(_ value: Decimal, currencyCode: String) -> String {
        PriceFormat.string(value, currencyCode: currencyCode)
    }

    /// "Fri 17 Oct" (order and punctuation follow the locale).
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "09:00" or "9:00 AM".
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "Waited 14 days", or "Added today".
    static func waited(_ item: Item, now: Date, calendar: Calendar) -> String {
        let days = item.daysWaited(at: now, calendar: calendar)
        return days == 0 ? "Added today" : "Waited \(Self.days(days))"
    }

    /// For a waiting item: "Ready today at 09:00", "Ready tomorrow at 09:00", "Ready in 12 days · Thu 15 Oct".
    static func timeLeft(_ item: Item, now: Date, calendar: Calendar) -> String {
        let left = item.daysLeft(at: now, calendar: calendar)
        switch left {
        case 0: return "Ready today at \(time(item.decideAt))"
        case 1: return "Ready tomorrow at \(time(item.decideAt))"
        default: return "Ready in \(days(left)) · \(shortDate(item.decideAt))"
        }
    }

    /// "Today", "Yesterday", "Fri 17 Oct", or "17 Oct 2025" for another year.
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return shortDate(date)
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// The price as the user would type it, for editing: "1299", "1299,5", "1.005" (ASCII digits, the locale's
    /// decimal separator, every decimal kept). `PriceInput.parse` reads it back to the same amount.
    static func editablePrice(_ value: Decimal) -> String {
        PriceFormat.editable(value)
    }
}
