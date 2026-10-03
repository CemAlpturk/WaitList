import Foundation
import Observation

/// A problem the user should be told about. The associated text is ready to show as is.
public enum StoreError: Error, Equatable {
    /// Saved items could not be loaded. If a backup of the unreadable file was made, its path is in the message.
    case loadFailed(String)
    /// Changes could not be saved. They are still shown in the app but will be lost on quit unless a later save works.
    case saveFailed(String)

    /// The user-presentable text.
    public var message: String {
        switch self {
        case .loadFailed(let message), .saveFailed(let message):
            return message
        }
    }
}

extension StoreError: LocalizedError {
    public var errorDescription: String? { message }
}

/// The app's list of items: the single source of truth for the UI.
///
/// Every change is saved right away. The current time (`now`) is stored rather than read from the clock,
/// so call `refresh()` whenever time may have moved on (popover opened, timer tick, wake from sleep).
@Observable @MainActor
public final class ItemStore {
    /// All items, in the order they were added.
    public private(set) var items: [Item]
    /// The time used to decide what is due. Updated by `refresh(now:)`.
    public private(set) var now: Date
    /// The most recent problem, or nil. Cleared by `clearError()` and by the next successful save.
    public private(set) var lastError: StoreError?

    /// Called after every change to `items` and after `refresh()`. Not called when a call changes nothing
    /// (for example an unknown id). The app reschedules notifications and updates the menubar badge here.
    @ObservationIgnored public var onChange: (() -> Void)?

    /// Calendar used for date math. Follows the system time zone by default; tests set a fixed one.
    @ObservationIgnored public var calendar: Calendar = .autoupdatingCurrent

    @ObservationIgnored private let persistence: any ItemPersistence
    @ObservationIgnored private let settings: AppSettings

    /// Set when the saved file could not be read and is still in place. While set, nothing is saved,
    /// so the user's existing file is never overwritten by an empty or partial list.
    @ObservationIgnored private var saveBlockedReason: String?

    /// Loads from persistence. If loading fails, starts empty and sets lastError. Then, if `settings.hasMigratedLegacyItems` is false, imports `legacyItems` (skipping any ids already present), saves, and sets the flag.
    public init(persistence: any ItemPersistence, settings: AppSettings, now: Date = Date(),
                legacyItems: (Date, DateComponents) -> [Item] = { LegacyMigration.legacyItems(now: $0, time: $1) }) {
        self.persistence = persistence
        self.settings = settings
        self.now = now
        self.items = []
        self.lastError = nil

        do {
            items = try persistence.load()
        } catch PersistenceError.corruptFile(let backupURL) {
            // The bad file was moved aside, so saving a fresh file is safe.
            lastError = .loadFailed(
                "WaitList could not read its saved items and started with an empty list. "
                + "The unreadable file was kept at \(backupURL.path).")
        } catch {
            // The file is still in place. Do not overwrite it.
            let reason = Self.describe(error)
            lastError = .loadFailed(
                "WaitList could not read its saved items: \(reason) "
                + "The file was not changed. Changes you make now will not be saved until WaitList is restarted.")
            saveBlockedReason = "Changes are not being saved because WaitList could not read its data file: \(reason)"
        }

        importLegacyItemsIfNeeded(legacyItems)
    }

    // MARK: Derived lists and totals

    /// Undecided items whose waiting period is over, oldest first.
    public var due: [Item] {
        items.filter { $0.isDue(at: now) }.sorted(by: Self.earlierDecideAt)
    }

    /// Undecided items still waiting, soonest first.
    public var waiting: [Item] {
        items.filter { $0.isWaiting(at: now) }.sorted(by: Self.earlierDecideAt)
    }

    /// Decided items, most recently decided first.
    public var history: [Item] {
        items.filter(\.isDecided).sorted(by: Self.laterDecidedAt)
    }

    /// Money not spent: the sum of the prices of skipped items (unknown prices count as 0).
    public var totalSaved: Decimal {
        total(of: .skipped)
    }

    /// Money spent: the sum of the prices of bought items (unknown prices count as 0).
    public var totalSpent: Decimal {
        total(of: .bought)
    }

    /// How many items were skipped.
    public var skippedCount: Int {
        items.filter { $0.outcome == .skipped }.count
    }

    /// How many items were bought.
    public var boughtCount: Int {
        items.filter { $0.outcome == .bought }.count
    }

    /// The item with this id, or nil.
    public func item(_ id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    // MARK: Changes

    /// Adds a new item that becomes due `waitDays` days from `now` at the notification time.
    /// The name and note are trimmed; an empty note becomes nil. The UI should not allow a blank name.
    @discardableResult
    public func add(name: String, price: Decimal?, note: String?, waitDays: Int) -> Item {
        let decideAt = Scheduling.decideDate(from: now, waitDays: waitDays, time: settings.notificationTime,
                                             calendar: calendar)
        let item = Item(name: Self.trimmed(name), price: price, note: Self.cleanedNote(note),
                        createdAt: now, decideAt: decideAt)
        commit(items + [item])
        return item
    }

    /// Records the decision with `decidedAt = now`. Works for due and still-waiting items, and can switch
    /// a decided item to the other outcome. Deciding the same way twice keeps the original date.
    /// Does nothing for an unknown id.
    public func decide(_ id: UUID, _ outcome: Outcome) {
        let decidedAt = now
        updateItem(id) { item in
            guard item.outcome != outcome else { return }
            item.outcome = outcome
            item.decidedAt = decidedAt
        }
    }

    /// Clears the decision, so the item is due or waiting again.
    public func undoDecision(_ id: UUID) {
        updateItem(id) { item in
            item.outcome = nil
            item.decidedAt = nil
        }
    }

    /// "Wait longer": moves the decision `days` days past the later of the current decision time and now,
    /// at the notification time, and counts the extension. Only for undecided items.
    public func extend(_ id: UUID, byDays days: Int) {
        let currentNow = now
        let time = settings.notificationTime
        let calendar = calendar
        updateItem(id) { item in
            guard !item.isDecided else { return }
            let start = max(item.decideAt, currentNow)
            item.decideAt = Scheduling.decideDate(from: start, waitDays: days, time: time, calendar: calendar)
            item.extensionCount += 1
        }
    }

    /// Edits the name, price and note of any item. Text is trimmed like in `add`.
    /// A blank name is ignored (the old name is kept).
    public func update(_ id: UUID, name: String, price: Decimal?, note: String?) {
        let newName = Self.trimmed(name)
        let newNote = Self.cleanedNote(note)
        updateItem(id) { item in
            if !newName.isEmpty { item.name = newName }
            item.price = price
            item.note = newNote
        }
    }

    /// Removes the item for good.
    public func delete(_ id: UUID) {
        commit(items.filter { $0.id != id })
    }

    /// Removes all decided items. Waiting and due items are kept.
    public func clearHistory() {
        commit(items.filter { !$0.isDecided })
    }

    /// Keeps each undecided item's day but changes its time of day.
    /// Call this when the notification time setting changes.
    public func retimeUndecided(to time: DateComponents) {
        let calendar = calendar
        commit(items.map { item in
            guard !item.isDecided else { return item }
            var copy = item
            copy.decideAt = Scheduling.retimed(item.decideAt, to: time, calendar: calendar)
            return copy
        })
    }

    /// Updates `now` (so due/waiting are recomputed) and calls `onChange`.
    public func refresh(now: Date = Date()) {
        self.now = now
        onChange?()
    }

    /// Dismisses `lastError`.
    public func clearError() {
        lastError = nil
    }

    // MARK: Private

    private func importLegacyItemsIfNeeded(_ legacyItems: (Date, DateComponents) -> [Item]) {
        guard !settings.hasMigratedLegacyItems else { return }
        // Try again on a later launch rather than mixing old items into a list that cannot be saved.
        guard saveBlockedReason == nil else { return }

        var knownIDs = Set(items.map(\.id))
        var imported: [Item] = []
        for item in legacyItems(now, settings.notificationTime) where !knownIDs.contains(item.id) {
            knownIDs.insert(item.id)
            imported.append(item)
        }

        if imported.isEmpty {
            settings.hasMigratedLegacyItems = true
            return
        }
        items.append(contentsOf: imported)
        // Only mark as done once the imported items are safely on disk; otherwise retry next launch.
        if persist() {
            settings.hasMigratedLegacyItems = true
        }
    }

    /// Applies `change` to the item with `id` (if any) and commits the result.
    private func updateItem(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var newItems = items
        change(&newItems[index])
        commit(newItems)
    }

    /// Replaces `items`, saves, and calls `onChange`. Does nothing if nothing changed.
    private func commit(_ newItems: [Item]) {
        guard newItems != items else { return }
        items = newItems
        persist()
        onChange?()
    }

    /// Saves `items`. On failure keeps the in-memory list, sets `lastError` and returns false.
    @discardableResult
    private func persist() -> Bool {
        if let saveBlockedReason {
            lastError = .saveFailed(saveBlockedReason)
            return false
        }
        do {
            try persistence.save(items)
            // A successful save resolves an earlier save error, but a load error is kept so the user sees it.
            if case .saveFailed = lastError {
                lastError = nil
            }
            return true
        } catch {
            lastError = .saveFailed("WaitList could not save your changes: \(Self.describe(error))")
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        error.localizedDescription
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let text = trimmed(note)
        return text.isEmpty ? nil : text
    }

    private static func earlierDecideAt(_ a: Item, _ b: Item) -> Bool {
        if a.decideAt != b.decideAt { return a.decideAt < b.decideAt }
        return tieBreak(a, b)
    }

    private static func laterDecidedAt(_ a: Item, _ b: Item) -> Bool {
        let aDate = a.decidedAt ?? .distantPast
        let bDate = b.decidedAt ?? .distantPast
        if aDate != bDate { return aDate > bDate }
        return tieBreak(a, b)
    }

    /// Name, then id, so the order is stable and predictable.
    private static func tieBreak(_ a: Item, _ b: Item) -> Bool {
        switch a.name.localizedStandardCompare(b.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.id.uuidString < b.id.uuidString
        }
    }

    private func total(of outcome: Outcome) -> Decimal {
        items.reduce(Decimal(0)) { sum, item in
            item.outcome == outcome ? sum + (item.price ?? 0) : sum
        }
    }
}
