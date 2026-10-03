import Foundation
import Observation

/// User preferences, saved in UserDefaults. Every change is saved immediately.
/// Out-of-range values are corrected on set, so the stored values are always usable.
@Observable @MainActor
public final class AppSettings {
    /// UserDefaults keys. Namespaced so they never clash with other data in the same domain.
    enum Keys {
        static let defaultWaitDays = "settings.defaultWaitDays"
        static let notificationHour = "settings.notificationHour"
        static let notificationMinute = "settings.notificationMinute"
        static let currencyCode = "settings.currencyCode"
        static let hasMigratedLegacyItems = "settings.hasMigratedLegacyItems"
    }

    /// Wait period suggested when adding an item, in days. Default 14, kept within 1...365.
    public var defaultWaitDays: Int {
        didSet {
            let clamped = Self.clamp(defaultWaitDays, to: Scheduling.waitDaysRange)
            if clamped != defaultWaitDays { defaultWaitDays = clamped }
            defaults.set(clamped, forKey: Keys.defaultWaitDays)
        }
    }

    /// Hour of day (0...23) when decisions become due and notifications fire. Default 9.
    public var notificationHour: Int {
        didSet {
            let clamped = Self.clamp(notificationHour, to: 0...23)
            if clamped != notificationHour { notificationHour = clamped }
            defaults.set(clamped, forKey: Keys.notificationHour)
        }
    }

    /// Minute of the hour (0...59) when decisions become due. Default 0.
    public var notificationMinute: Int {
        didSet {
            let clamped = Self.clamp(notificationMinute, to: 0...59)
            if clamped != notificationMinute { notificationMinute = clamped }
            defaults.set(clamped, forKey: Keys.notificationMinute)
        }
    }

    /// ISO 4217 currency code used to show prices, e.g. "SEK".
    /// Lowercase input is uppercased. Anything that is not 3 letters is replaced by `defaultCurrencyCode`.
    public var currencyCode: String {
        didSet {
            let normalized = Self.normalizedCurrencyCode(currencyCode) ?? Self.defaultCurrencyCode
            if normalized != currencyCode { currencyCode = normalized }
            defaults.set(normalized, forKey: Keys.currencyCode)
        }
    }

    /// True once items from WaitList 1.x have been imported (or there were none). Default false.
    public var hasMigratedLegacyItems: Bool {
        didSet {
            defaults.set(hasMigratedLegacyItems, forKey: Keys.hasMigratedLegacyItems)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Reads saved settings from `defaults`, using the defaults above for anything missing or invalid.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultWaitDays = Self.clamp(defaults.object(forKey: Keys.defaultWaitDays) as? Int ?? 14,
                                     to: Scheduling.waitDaysRange)
        notificationHour = Self.clamp(defaults.object(forKey: Keys.notificationHour) as? Int ?? 9, to: 0...23)
        notificationMinute = Self.clamp(defaults.object(forKey: Keys.notificationMinute) as? Int ?? 0, to: 0...59)
        currencyCode = defaults.string(forKey: Keys.currencyCode).flatMap(Self.normalizedCurrencyCode)
            ?? Self.defaultCurrencyCode
        hasMigratedLegacyItems = defaults.bool(forKey: Keys.hasMigratedLegacyItems)
    }

    /// hour + minute as DateComponents, for Scheduling.
    public var notificationTime: DateComponents {
        DateComponents(hour: notificationHour, minute: notificationMinute)
    }

    /// The currency of the user's region, or "USD" if the region has none.
    public nonisolated static var defaultCurrencyCode: String {
        Locale.current.currency.flatMap { normalizedCurrencyCode($0.identifier) } ?? "USD"
    }

    /// `code` trimmed and uppercased if it is exactly 3 ASCII letters, otherwise nil.
    nonisolated static func normalizedCurrencyCode(_ code: String) -> String? {
        let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isThreeLetters = upper.count == 3 && upper.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }
        return isThreeLetters ? upper : nil
    }

    private nonisolated static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
