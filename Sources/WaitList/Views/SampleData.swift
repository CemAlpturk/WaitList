import Foundation
import WaitListCore

/// Made-up items for snapshots and previews. Never touches real data or the app's own preferences.
@MainActor
enum SampleData {
    /// A throwaway preferences domain, wiped before and after use.
    static let defaultsSuiteName = "com.cemalpturk.WaitList.samples"

    static func makeDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            preconditionFailure("Could not create sample defaults suite")
        }
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    static func discard(_ defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    /// Today at 08:15, so "today at 09:00" is still ahead and results do not depend on when snapshots run.
    static func referenceNow(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 8, minute: 15, second: 0, of: Date()) ?? Date()
    }

    enum Contents {
        case full
        case waitingOnly
        case historyOnly
        case empty
        /// One due and two waiting items.
        case few
    }

    /// A store over in-memory persistence. If `failingSave` is set, the next save throws it.
    static func store(_ contents: Contents, settings: AppSettings, now: Date,
                      calendar: Calendar = .current, failingSave: Error? = nil) -> ItemStore {
        let persistence = InMemoryItemPersistence(items: items(contents, now: now, calendar: calendar))
        persistence.failNextSave = failingSave
        let store = ItemStore(persistence: persistence, settings: settings, now: now, legacyItems: { _, _ in [] })
        store.calendar = calendar
        return store
    }

    static func items(_ contents: Contents, now: Date, calendar: Calendar) -> [Item] {
        /// `offset` days from today at `hour`:`minute`.
        func day(_ offset: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func price(_ text: String) -> Decimal? {
            Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        }

        let due = [
            Item(name: "Mechanical keyboard", price: price("1899"),
                 note: "The current one works fine, but the new switches sound nice.",
                 createdAt: day(-15, 21, 40), decideAt: day(-1)),
            Item(name: "Running jacket", price: price("1299"), note: "https://www.example.com/jackets/trail-shell",
                 createdAt: day(-8, 12, 5), decideAt: day(0, 7, 0)),
        ]
        let waiting = [
            Item(name: "Espresso grinder", price: price("2150"), createdAt: day(-13, 19, 30), decideAt: day(0)),
            Item(name: "Board game", createdAt: day(-6, 18, 0), decideAt: day(1)),
            Item(name: "Noise-cancelling headphones", price: price("3490"),
                 note: "https://www.example.com/audio/headphones-x2",
                 createdAt: day(-2, 22, 15), decideAt: day(12)),
        ]
        let history = [
            Item(name: "Smart watch", price: price("2490"), note: "https://www.example.com/watch",
                 createdAt: day(-20), decideAt: day(-6), outcome: .skipped, decidedAt: day(-3, 9, 4)),
            Item(name: "Desk lamp", price: price("220"),
                 createdAt: day(-12), decideAt: day(-5), outcome: .bought, decidedAt: day(-5, 18, 30)),
            Item(name: "Vinyl record", createdAt: day(-16), decideAt: day(-9), outcome: .skipped,
                 decidedAt: day(-9, 9, 10)),
            Item(name: "Sneakers", price: price("1100"),
                 createdAt: day(-45), decideAt: day(-31), outcome: .skipped, decidedAt: day(-30, 8, 0)),
        ]

        switch contents {
        case .full: return due + waiting + history
        case .waitingOnly: return waiting
        case .historyOnly: return history
        case .empty: return []
        case .few: return [due[0], waiting[0], waiting[2]]
        }
    }
}
