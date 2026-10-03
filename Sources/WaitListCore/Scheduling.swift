import Foundation

/// Date math for waiting periods. All functions are pure: same input, same output.
public enum Scheduling {
    /// Allowed range for a waiting period, in days.
    public static let waitDaysRange = 1...365

    /// The decision instant for an item added at `now` with `waitDays` of waiting: that many days later, at the given time of day (hour/minute). `waitDays` is clamped to 1...365.
    public static func decideDate(from now: Date, waitDays: Int, time: DateComponents, calendar: Calendar = .current) -> Date {
        let days = min(max(waitDays, waitDaysRange.lowerBound), waitDaysRange.upperBound)
        // Calendar math keeps the wall-clock time across daylight saving changes.
        // The fallback (plain seconds) is only used if the calendar cannot answer, which should not happen.
        let later = calendar.date(byAdding: .day, value: days, to: now)
            ?? now.addingTimeInterval(TimeInterval(days) * 86_400)
        return retimed(later, to: time, calendar: calendar)
    }

    /// The same calendar day as `date`, but at the given time of day.
    /// A missing hour or minute counts as 0; out-of-range values are clamped (hour 0...23, minute 0...59).
    public static func retimed(_ date: Date, to time: DateComponents, calendar: Calendar = .current) -> Date {
        let hour = min(max(time.hour ?? 0, 0), 23)
        let minute = min(max(time.minute ?? 0, 0), 59)
        if let result = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
            return result
        }
        // Should not happen; fall back to plain arithmetic from the start of the day.
        let startOfDay = calendar.startOfDay(for: date)
        return startOfDay.addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
    }
}
