import Foundation
import WaitListCore

/// Short, friendly strings for the UI.
enum Format {
    /// "1 day", "2 days".
    static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    /// "1 299 kr" for whole amounts, "19,99 kr" otherwise (both in the user's locale).
    static func price(_ value: Decimal, currencyCode: String) -> String {
        let style = Decimal.FormatStyle.Currency(code: currencyCode)
        return isWhole(value) ? value.formatted(style.precision(.fractionLength(0))) : value.formatted(style)
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

    /// "Decide today at 09:00", "Decide tomorrow at 09:00", "12 days left · Fri 17 Oct".
    static func timeLeft(_ item: Item, now: Date, calendar: Calendar) -> String {
        let left = item.daysLeft(at: now, calendar: calendar)
        switch left {
        case 0: return "Decide today at \(time(item.decideAt))"
        case 1: return "Decide tomorrow at \(time(item.decideAt))"
        default: return "\(days(left)) left · \(shortDate(item.decideAt))"
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

    /// The price as the user would type it, for editing ("1299,5" / "1299.5").
    static func editablePrice(_ value: Decimal) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    private static func isWhole(_ value: Decimal) -> Bool {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return rounded == value
    }
}

/// What the user typed into the price field.
enum PriceInput: Equatable {
    case empty
    case value(Decimal)
    case invalid

    /// Lenient parsing: ignores spaces, currency symbols ("$", "€") and a leading or trailing currency
    /// label ("SEK 20", "1299 kr"), accepts the locale's grouping and decimal separators, and also "." or ","
    /// as a decimal separator. Letters between digits ("1e5") make it invalid.
    static func parse(_ text: String, locale: Locale = .current) -> PriceInput {
        var compact = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar.properties.generalCategory == .currencySymbol {
                continue
            }
            compact.append(scalar == "\u{2212}" ? "-" : scalar) // U+2212 minus sign
        }
        let cleaned = String(compact).trimmingCharacters(in: .letters)
        if cleaned.isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .invalid
        }

        let isNegative = cleaned.hasPrefix("-")
        var body = isNegative ? String(cleaned.dropFirst()) : cleaned
        guard !body.isEmpty, body.allSatisfy({ $0.isASCII && ($0.isNumber || ".,'".contains($0)) }) else {
            return .invalid
        }

        let decimalSeparator = locale.decimalSeparator ?? "."
        if let grouping = locale.groupingSeparator, grouping.count == 1, grouping != decimalSeparator,
           !grouping.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains) {
            body = body.replacingOccurrences(of: grouping, with: "")
        }
        body = body.replacingOccurrences(of: "'", with: "")
        if decimalSeparator != "." {
            body = body.replacingOccurrences(of: decimalSeparator, with: ".")
        }
        body = body.replacingOccurrences(of: ",", with: ".")

        guard body.filter({ $0 == "." }).count <= 1, body.contains(where: \.isNumber),
              let value = Decimal(string: body, locale: Locale(identifier: "en_US_POSIX")) else {
            return .invalid
        }
        return .value(isNegative ? -value : value)
    }
}
