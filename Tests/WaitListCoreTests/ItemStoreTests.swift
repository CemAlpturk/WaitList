import XCTest
@testable import WaitListCore

/// Persistence whose load always fails with the given error. Counts save attempts.
private final class FailingLoadPersistence: ItemPersistence {
    let error: Error
    private(set) var saveCount = 0
    init(error: Error) { self.error = error }
    func load() throws -> [Item] { throw error }
    func save(_ items: [Item]) throws { saveCount += 1 }
}

@MainActor
final class ItemStoreTests: XCTestCase {
    private let start = TestDates.date(2026, 10, 3, 10, 0)

    private struct Fixture {
        let store: ItemStore
        let persistence: InMemoryItemPersistence
        let settings: AppSettings
        let changes: ChangeCounter
    }

    private final class ChangeCounter {
        var count = 0
    }

    /// A store with in-memory persistence, test-only settings, the Stockholm calendar and no legacy data.
    private func makeFixture(items: [Item] = [], now: Date? = nil) throws -> Fixture {
        let persistence = InMemoryItemPersistence(items: items)
        let settings = AppSettings(defaults: try makeTestDefaults())
        let store = ItemStore(persistence: persistence, settings: settings, now: now ?? start,
                              legacyItems: { _, _ in [] })
        store.calendar = TestDates.stockholm
        let changes = ChangeCounter()
        store.onChange = { changes.count += 1 }
        return Fixture(store: store, persistence: persistence, settings: settings, changes: changes)
    }

    // MARK: Add and phases

    func testAddCreatesWaitingItem() throws {
        let f = try makeFixture()

        let item = f.store.add(name: "  Gorilla Sofa \n", price: dec("19.99"), note: "   ", waitDays: 14)

        XCTAssertEqual(item.name, "Gorilla Sofa")
        XCTAssertNil(item.note)
        XCTAssertEqual(item.price, dec("19.99"))
        XCTAssertEqual(item.createdAt, start)
        XCTAssertEqual(item.decideAt, TestDates.date(2026, 10, 17, 9, 0))
        XCTAssertEqual(item.extensionCount, 0)
        XCTAssertEqual(f.store.items, [item])
        XCTAssertEqual(f.store.waiting, [item])
        XCTAssertEqual(f.store.due, [])
        XCTAssertEqual(f.store.history, [])
        XCTAssertEqual(f.persistence.items, [item])
        XCTAssertEqual(f.changes.count, 1)
        XCTAssertNil(f.store.lastError)
    }

    func testAddUsesNotificationTimeAndTrimsNote() throws {
        let f = try makeFixture()
        f.settings.notificationHour = 18
        f.settings.notificationMinute = 30

        let item = f.store.add(name: "Lamp", price: nil, note: "  https://example.com  ", waitDays: 3)

        XCTAssertEqual(item.decideAt, TestDates.date(2026, 10, 6, 18, 30))
        XCTAssertEqual(item.note, "https://example.com")
        XCTAssertNil(item.price)
    }

    func testRefreshPastDecideAtMakesItemDue() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)

        f.store.refresh(now: item.decideAt.addingTimeInterval(-1))
        XCTAssertEqual(f.store.waiting.map(\.id), [item.id])

        f.store.refresh(now: item.decideAt)
        XCTAssertEqual(f.store.now, item.decideAt)
        XCTAssertEqual(f.store.due.map(\.id), [item.id])
        XCTAssertEqual(f.store.waiting, [])
        XCTAssertEqual(f.changes.count, 3) // add + 2 refreshes
    }

    func testDueAndWaitingAreSortedByDecideAt() throws {
        let f = try makeFixture()
        let late = f.store.add(name: "Late", price: nil, note: nil, waitDays: 10)
        let early = f.store.add(name: "Early", price: nil, note: nil, waitDays: 2)
        let middle = f.store.add(name: "Middle", price: nil, note: nil, waitDays: 5)

        XCTAssertEqual(f.store.waiting.map(\.id), [early.id, middle.id, late.id])

        f.store.refresh(now: TestDates.date(2026, 12, 1))
        XCTAssertEqual(f.store.due.map(\.id), [early.id, middle.id, late.id])
    }

    func testItemLookup() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)
        XCTAssertEqual(f.store.item(item.id), item)
        XCTAssertNil(f.store.item(UUID()))
    }

    // MARK: Decide and totals

    func testDecideMovesToHistoryWithExactTotalsAndCounts() throws {
        let f = try makeFixture()
        let a = f.store.add(name: "A", price: dec("19.99"), note: nil, waitDays: 1)
        let b = f.store.add(name: "B", price: dec("5.01"), note: nil, waitDays: 1)
        let c = f.store.add(name: "C", price: nil, note: nil, waitDays: 1)
        let d = f.store.add(name: "D", price: dec("0.1"), note: nil, waitDays: 1)
        let e = f.store.add(name: "E", price: dec("0.2"), note: nil, waitDays: 1)
        let waitingItem = f.store.add(name: "Still waiting", price: dec("100"), note: nil, waitDays: 30)

        let decisionTime = TestDates.date(2026, 10, 5, 12, 0)
        f.store.refresh(now: decisionTime)
        f.store.decide(a.id, .skipped)
        f.store.decide(b.id, .skipped)
        f.store.decide(c.id, .skipped)
        f.store.decide(d.id, .bought)
        f.store.decide(e.id, .bought)

        XCTAssertEqual(f.store.item(a.id)?.outcome, .skipped)
        XCTAssertEqual(f.store.item(a.id)?.decidedAt, decisionTime)
        XCTAssertEqual(f.store.totalSaved, dec("25.00"))
        XCTAssertEqual("\(f.store.totalSaved)", "25")
        // 0.1 + 0.2 is 0.30000000000000004 in Double; Decimal must be exact.
        XCTAssertEqual(f.store.totalSpent, dec("0.3"))
        XCTAssertEqual("\(f.store.totalSpent)", "0.3")
        XCTAssertEqual(f.store.skippedCount, 3)
        XCTAssertEqual(f.store.boughtCount, 2)
        XCTAssertEqual(Set(f.store.history.map(\.id)), [a.id, b.id, c.id, d.id, e.id])
        XCTAssertEqual(f.store.due, [])
        XCTAssertEqual(f.store.waiting.map(\.id), [waitingItem.id])
        XCTAssertEqual(f.persistence.items, f.store.items)
    }

    func testHistoryIsMostRecentlyDecidedFirst() throws {
        let f = try makeFixture()
        let first = f.store.add(name: "First", price: nil, note: nil, waitDays: 1)
        let second = f.store.add(name: "Second", price: nil, note: nil, waitDays: 1)
        let tieB = f.store.add(name: "Tie B", price: nil, note: nil, waitDays: 1)
        let tieA = f.store.add(name: "Tie A", price: nil, note: nil, waitDays: 1)

        f.store.refresh(now: TestDates.date(2026, 10, 5))
        f.store.decide(first.id, .bought)
        f.store.refresh(now: TestDates.date(2026, 10, 6))
        f.store.decide(second.id, .skipped)
        f.store.refresh(now: TestDates.date(2026, 10, 7))
        f.store.decide(tieB.id, .skipped)
        f.store.decide(tieA.id, .skipped)

        XCTAssertEqual(f.store.history.map(\.name), ["Tie A", "Tie B", "Second", "First"])
    }

    func testDecideIsAllowedEarlyAndCanSwitchOutcome() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: dec("10"), note: nil, waitDays: 14)

        f.store.decide(item.id, .skipped) // still waiting: deciding early is fine
        XCTAssertEqual(f.store.item(item.id)?.phase(at: f.store.now), .decided(.skipped))

        f.store.refresh(now: TestDates.date(2026, 10, 4))
        f.store.decide(item.id, .bought)
        XCTAssertEqual(f.store.item(item.id)?.outcome, .bought)
        XCTAssertEqual(f.store.item(item.id)?.decidedAt, TestDates.date(2026, 10, 4))
        XCTAssertEqual(f.store.totalSaved, 0)
        XCTAssertEqual(f.store.totalSpent, dec("10"))
    }

    func testDecidingTheSameWayTwiceKeepsOriginalDateAndDoesNotNotify() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 1)
        f.store.decide(item.id, .skipped)
        let changesAfterFirstDecision = f.changes.count

        f.store.refresh(now: TestDates.date(2026, 10, 20))
        f.store.decide(item.id, .skipped)

        XCTAssertEqual(f.store.item(item.id)?.decidedAt, start)
        XCTAssertEqual(f.changes.count, changesAfterFirstDecision + 1) // only the refresh
    }

    func testDecideUnknownIdIsNoOp() throws {
        let f = try makeFixture()
        f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 1)
        let before = f.store.items

        f.store.decide(UUID(), .bought)

        XCTAssertEqual(f.store.items, before)
        XCTAssertEqual(f.changes.count, 1)
    }

    func testUndoDecision() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: dec("19.99"), note: nil, waitDays: 1)
        f.store.refresh(now: TestDates.date(2026, 10, 5))
        f.store.decide(item.id, .skipped)
        XCTAssertEqual(f.store.totalSaved, dec("19.99"))

        f.store.undoDecision(item.id)

        let undone = try XCTUnwrap(f.store.item(item.id))
        XCTAssertNil(undone.outcome)
        XCTAssertNil(undone.decidedAt)
        XCTAssertEqual(f.store.due.map(\.id), [item.id])
        XCTAssertEqual(f.store.history, [])
        XCTAssertEqual(f.store.totalSaved, 0)
        XCTAssertEqual(f.store.skippedCount, 0)
        XCTAssertEqual(f.persistence.items, f.store.items)
    }

    // MARK: Extend

    func testExtendFromDueStartsFromNow() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 14) // due 2026-10-17 09:00
        f.store.refresh(now: TestDates.date(2026, 10, 19, 12, 0))
        XCTAssertEqual(f.store.due.map(\.id), [item.id])

        f.store.extend(item.id, byDays: 7)

        let extended = try XCTUnwrap(f.store.item(item.id))
        // 7 days after now (not after the old date), at 09:00 local, across the 2026-10-25 DST change.
        XCTAssertEqual(extended.decideAt, TestDates.date(2026, 10, 26, 9, 0))
        XCTAssertEqual(extended.extensionCount, 1)
        XCTAssertEqual(f.store.waiting.map(\.id), [item.id])
        XCTAssertEqual(f.store.due, [])
        XCTAssertEqual(f.persistence.items, f.store.items)
    }

    func testExtendWhileWaitingStartsFromDecideAt() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 14) // 2026-10-17 09:00

        f.store.extend(item.id, byDays: 7)
        f.store.extend(item.id, byDays: 7)

        let extended = try XCTUnwrap(f.store.item(item.id))
        XCTAssertEqual(extended.decideAt, TestDates.date(2026, 10, 31, 9, 0))
        XCTAssertEqual(extended.extensionCount, 2)
    }

    func testExtendIgnoresDecidedItems() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 1)
        f.store.decide(item.id, .bought)
        let before = try XCTUnwrap(f.store.item(item.id))
        let changes = f.changes.count

        f.store.extend(item.id, byDays: 7)

        XCTAssertEqual(f.store.item(item.id), before)
        XCTAssertEqual(f.changes.count, changes)
    }

    // MARK: Update, delete, clear

    func testUpdateEditsFields() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: dec("100"), note: "old", waitDays: 14)

        f.store.update(item.id, name: "  Gorilla Sofa ", price: dec("1299"), note: " https://example.com ")
        var updated = try XCTUnwrap(f.store.item(item.id))
        XCTAssertEqual(updated.name, "Gorilla Sofa")
        XCTAssertEqual(updated.price, dec("1299"))
        XCTAssertEqual(updated.note, "https://example.com")
        XCTAssertEqual(updated.decideAt, item.decideAt)
        XCTAssertEqual(f.persistence.items, f.store.items)

        f.store.update(item.id, name: "   ", price: nil, note: "  ")
        updated = try XCTUnwrap(f.store.item(item.id))
        XCTAssertEqual(updated.name, "Gorilla Sofa", "a blank name keeps the old one")
        XCTAssertNil(updated.price)
        XCTAssertNil(updated.note)
    }

    func testUpdateWorksOnDecidedItems() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 1)
        f.store.decide(item.id, .skipped)

        f.store.update(item.id, name: "Sofa", price: dec("500"), note: nil)

        XCTAssertEqual(f.store.totalSaved, dec("500"))
        XCTAssertEqual(f.store.item(item.id)?.outcome, .skipped)
    }

    func testDelete() throws {
        let f = try makeFixture()
        let keep = f.store.add(name: "Keep", price: nil, note: nil, waitDays: 1)
        let remove = f.store.add(name: "Remove", price: nil, note: nil, waitDays: 1)

        f.store.delete(remove.id)
        XCTAssertEqual(f.store.items.map(\.id), [keep.id])
        XCTAssertEqual(f.persistence.items.map(\.id), [keep.id])
        XCTAssertEqual(f.changes.count, 3)

        f.store.delete(UUID())
        XCTAssertEqual(f.changes.count, 3, "deleting an unknown id changes nothing")
    }

    func testClearHistoryKeepsUndecided() throws {
        let f = try makeFixture()
        let waitingItem = f.store.add(name: "Waiting", price: nil, note: nil, waitDays: 30)
        let dueItem = f.store.add(name: "Due", price: nil, note: nil, waitDays: 1)
        let bought = f.store.add(name: "Bought", price: dec("1"), note: nil, waitDays: 1)
        let skipped = f.store.add(name: "Skipped", price: dec("2"), note: nil, waitDays: 1)
        f.store.refresh(now: TestDates.date(2026, 10, 10))
        f.store.decide(bought.id, .bought)
        f.store.decide(skipped.id, .skipped)

        f.store.clearHistory()

        XCTAssertEqual(Set(f.store.items.map(\.id)), [waitingItem.id, dueItem.id])
        XCTAssertEqual(f.store.history, [])
        XCTAssertEqual(f.store.totalSaved, 0)
        XCTAssertEqual(f.persistence.items, f.store.items)

        let changes = f.changes.count
        f.store.clearHistory()
        XCTAssertEqual(f.changes.count, changes, "clearing an empty history changes nothing")
    }

    func testRetimeUndecidedKeepsDayAndSkipsDecided() throws {
        let f = try makeFixture()
        let a = f.store.add(name: "A", price: nil, note: nil, waitDays: 2)   // 2026-10-05 09:00
        let b = f.store.add(name: "B", price: nil, note: nil, waitDays: 30)  // 2026-11-02 09:00 (after DST)
        let decided = f.store.add(name: "C", price: nil, note: nil, waitDays: 1)
        f.store.decide(decided.id, .skipped)
        let decidedBefore = try XCTUnwrap(f.store.item(decided.id))

        f.store.retimeUndecided(to: DateComponents(hour: 18, minute: 30))

        XCTAssertEqual(f.store.item(a.id)?.decideAt, TestDates.date(2026, 10, 5, 18, 30))
        XCTAssertEqual(f.store.item(b.id)?.decideAt, TestDates.date(2026, 11, 2, 18, 30))
        XCTAssertEqual(f.store.item(decided.id), decidedBefore)
        XCTAssertEqual(f.persistence.items, f.store.items)
    }

    /// At 10:00 the user moves the reminder from 09:00 to 18:00: an item that became due at 09:00 stays due.
    func testRetimeLeavesItemsThatAreAlreadyDue() throws {
        let dueToday = Item(name: "Due today", createdAt: TestDates.date(2026, 9, 19, 9, 0),
                            decideAt: TestDates.date(2026, 10, 3, 9, 0))
        let dueLastWeek = Item(name: "Due last week", createdAt: TestDates.date(2026, 9, 1, 9, 0),
                               decideAt: TestDates.date(2026, 9, 26, 9, 0))
        let tomorrow = Item(name: "Tomorrow", createdAt: TestDates.date(2026, 9, 20, 9, 0),
                            decideAt: TestDates.date(2026, 10, 4, 9, 0))
        let f = try makeFixture(items: [dueToday, dueLastWeek, tomorrow])   // now: 2026-10-03 10:00

        f.store.retimeUndecided(to: DateComponents(hour: 18, minute: 0))

        XCTAssertEqual(f.store.item(dueToday.id), dueToday)
        XCTAssertEqual(f.store.item(dueLastWeek.id), dueLastWeek)
        XCTAssertEqual(f.store.due.map(\.id), [dueLastWeek.id, dueToday.id])
        XCTAssertEqual(f.store.item(tomorrow.id)?.decideAt, TestDates.date(2026, 10, 4, 18, 0))
    }

    /// At 10:00 the user moves the reminder from 18:00 to 09:00: an item due at 18:00 today would become due
    /// at once (with no notification), so it keeps 18:00. Later items move to 09:00.
    func testRetimeNeverMakesAWaitingItemDueAtOnce() throws {
        let laterToday = Item(name: "Later today", createdAt: TestDates.date(2026, 9, 19, 18, 0),
                              decideAt: TestDates.date(2026, 10, 3, 18, 0))
        let tomorrow = Item(name: "Tomorrow", createdAt: TestDates.date(2026, 9, 20, 18, 0),
                            decideAt: TestDates.date(2026, 10, 4, 18, 0))
        let f = try makeFixture(items: [laterToday, tomorrow])   // now: 2026-10-03 10:00

        f.store.retimeUndecided(to: DateComponents(hour: 9, minute: 0))

        XCTAssertEqual(f.store.item(laterToday.id), laterToday)
        XCTAssertEqual(f.store.waiting.map(\.id), [laterToday.id, tomorrow.id])
        XCTAssertEqual(f.store.due, [])
        XCTAssertEqual(f.store.item(tomorrow.id)?.decideAt, TestDates.date(2026, 10, 4, 9, 0))

        // Retiming to a time still ahead today does move it.
        f.store.retimeUndecided(to: DateComponents(hour: 11, minute: 30))
        XCTAssertEqual(f.store.item(laterToday.id)?.decideAt, TestDates.date(2026, 10, 3, 11, 30))
    }

    func testRetimeUsesTheStoredNow() throws {
        let f = try makeFixture()
        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 1)   // 2026-10-04 09:00
        f.store.refresh(now: TestDates.date(2026, 10, 4, 10, 0))                  // due since 09:00

        f.store.retimeUndecided(to: DateComponents(hour: 18, minute: 0))

        XCTAssertEqual(f.store.item(item.id)?.decideAt, TestDates.date(2026, 10, 4, 9, 0))
        XCTAssertEqual(f.store.due.map(\.id), [item.id])
    }

    // MARK: Errors

    func testSaveFailureKeepsChangeSetsErrorAndStillNotifies() throws {
        let f = try makeFixture()
        f.persistence.failNextSave = TestError(message: "disk full")

        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)

        XCTAssertEqual(f.store.items, [item], "in-memory change is kept")
        XCTAssertEqual(f.persistence.items, [], "nothing was saved")
        XCTAssertEqual(f.changes.count, 1)
        guard case .saveFailed(let message)? = f.store.lastError else {
            return XCTFail("Expected saveFailed, got \(String(describing: f.store.lastError))")
        }
        XCTAssertEqual(message, "Your changes aren't saved yet. disk full. Quitting now would lose them.")

        // The next successful save writes everything and clears the save error.
        let second = f.store.add(name: "Lamp", price: nil, note: nil, waitDays: 3)
        XCTAssertEqual(f.persistence.items, [item, second])
        XCTAssertNil(f.store.lastError)
    }

    func testClearError() throws {
        let f = try makeFixture()
        f.persistence.failNextSave = TestError()
        f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)
        XCTAssertNotNil(f.store.lastError)

        f.store.clearError()
        XCTAssertNil(f.store.lastError)
    }

    func testInitWithFailingPersistenceStartsEmptyAndDoesNotOverwrite() throws {
        let persistence = FailingLoadPersistence(error: TestError(message: "permission denied"))
        let settings = AppSettings(defaults: try makeTestDefaults())
        var legacyCalls = 0
        let store = ItemStore(persistence: persistence, settings: settings, now: start,
                              legacyItems: { _, _ in legacyCalls += 1; return [] })

        XCTAssertEqual(store.items, [])
        guard case .loadFailed(let message)? = store.lastError else {
            return XCTFail("Expected loadFailed, got \(String(describing: store.lastError))")
        }
        XCTAssertTrue(message.contains("permission denied"), message)
        XCTAssertEqual(legacyCalls, 0, "no legacy import into a list that cannot be saved")
        XCTAssertFalse(settings.hasMigratedLegacyItems)

        // Changes stay in memory, but the unreadable file is never overwritten.
        store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertEqual(store.lastError, .saveFailed("Your changes aren't saved yet. WaitList won't overwrite its "
                                                    + "data file because it couldn't read it. Quitting now would lose them."))
    }

    func testSaveErrorMessageKeepsTheReasonsOwnPunctuation() throws {
        let f = try makeFixture()
        f.persistence.failNextSave = TestError(message: "The volume is full.")
        f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)
        XCTAssertEqual(f.store.lastError?.message,
                       "Your changes aren't saved yet. The volume is full. Quitting now would lose them.")
    }

    func testInitWithCorruptFileReportsBackupPathAndCanSave() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        try Data("{ broken".utf8).write(to: fileURL)
        let persistence = FileItemPersistence(fileURL: fileURL)
        let settings = AppSettings(defaults: try makeTestDefaults())
        settings.hasMigratedLegacyItems = true

        let store = ItemStore(persistence: persistence, settings: settings, now: start, legacyItems: { _, _ in [] })

        XCTAssertEqual(store.items, [])
        guard case .loadFailed(let message)? = store.lastError else {
            return XCTFail("Expected loadFailed, got \(String(describing: store.lastError))")
        }
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("items.corrupt-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(message.contains(try XCTUnwrap(backups.first)), message)

        // The bad file is safely aside, so saving works, and the load message stays visible.
        store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)
        XCTAssertEqual(try persistence.load().count, 1)
        XCTAssertEqual(store.lastError, .loadFailed(message))
    }

    func testInitWithNewerFileVersionNeverOverwritesIt() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        let future = Data(#"{"version": 7, "items": []}"#.utf8)
        try future.write(to: fileURL)
        let settings = AppSettings(defaults: try makeTestDefaults())
        settings.hasMigratedLegacyItems = true

        let store = ItemStore(persistence: FileItemPersistence(fileURL: fileURL), settings: settings, now: start,
                              legacyItems: { _, _ in [] })
        guard case .loadFailed? = store.lastError else {
            return XCTFail("Expected loadFailed, got \(String(describing: store.lastError))")
        }

        store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)
        XCTAssertEqual(try Data(contentsOf: fileURL), future)
    }

    func testInitWithAnUnmovableCorruptFileNeverOverwritesIt() throws {
        let directory = try makeTempDirectory()
        let folder = directory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("items.json")
        let garbage = Data("{ broken".utf8)
        try garbage.write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        let settings = AppSettings(defaults: try makeTestDefaults())
        settings.hasMigratedLegacyItems = true

        let store = ItemStore(persistence: FileItemPersistence(fileURL: fileURL), settings: settings, now: start,
                              legacyItems: { _, _ in [] })
        guard case .loadFailed(let message)? = store.lastError else {
            return XCTFail("Expected loadFailed, got \(String(describing: store.lastError))")
        }
        XCTAssertTrue(message.contains("left untouched"), message)

        store.add(name: "Sofa", price: nil, note: nil, waitDays: 14)
        XCTAssertEqual(store.items.count, 1, "kept in memory")
        guard case .saveFailed? = store.lastError else {
            return XCTFail("Expected saveFailed, got \(String(describing: store.lastError))")
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), garbage)
    }

    // MARK: Legacy import

    func testLegacyImportHappensOnceAndSkipsDuplicateIds() throws {
        let existing = Item(name: "Already here", createdAt: start, decideAt: TestDates.date(2026, 10, 10, 9, 0))
        let persistence = InMemoryItemPersistence(items: [existing])
        let defaults = try makeTestDefaults()
        let settings = AppSettings(defaults: defaults)

        let duplicate = Item(id: existing.id, name: "Old copy", createdAt: start, decideAt: start)
        let newOne = Item(name: "From 1.x", createdAt: start, decideAt: TestDates.date(2026, 10, 12, 9, 0))
        var calls = 0
        var receivedTime: DateComponents?
        let legacy: (Date, DateComponents) -> [Item] = { _, time in
            calls += 1
            receivedTime = time
            return [duplicate, newOne, newOne]
        }

        let store = ItemStore(persistence: persistence, settings: settings, now: start, legacyItems: legacy)

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(receivedTime, DateComponents(hour: 9, minute: 0))
        XCTAssertEqual(store.items.map(\.name), ["Already here", "From 1.x"])
        XCTAssertEqual(persistence.items, store.items, "imported items are saved")
        XCTAssertTrue(settings.hasMigratedLegacyItems)
        XCTAssertNil(store.lastError)

        // A second launch does not import again.
        let secondStore = ItemStore(persistence: persistence, settings: AppSettings(defaults: defaults), now: start,
                                    legacyItems: legacy)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(secondStore.items.count, 2)
    }

    func testLegacyImportWithNothingToImportSetsFlagWithoutSaving() throws {
        let persistence = InMemoryItemPersistence()
        persistence.failNextSave = TestError() // would surface as an error if a save happened
        let settings = AppSettings(defaults: try makeTestDefaults())

        let store = ItemStore(persistence: persistence, settings: settings, now: start, legacyItems: { _, _ in [] })

        XCTAssertTrue(settings.hasMigratedLegacyItems)
        XCTAssertNil(store.lastError)
        XCTAssertNotNil(persistence.failNextSave, "no save was attempted")
    }

    func testUnreadableLegacyDataLeavesTheFlagOffSoTheNextLaunchRetries() throws {
        let persistence = InMemoryItemPersistence()
        let defaults = try makeTestDefaults()
        let settings = AppSettings(defaults: defaults)

        let store = ItemStore(persistence: persistence, settings: settings, now: start,
                              legacyImport: { _, _ in .unreadable })

        XCTAssertEqual(store.items, [])
        XCTAssertNil(store.lastError)
        XCTAssertFalse(settings.hasMigratedLegacyItems)

        // Next launch: the data can be read now, and is imported.
        let legacyItem = Item(name: "From 1.x", createdAt: start, decideAt: TestDates.date(2026, 10, 12, 9, 0))
        let nextLaunch = ItemStore(persistence: persistence, settings: AppSettings(defaults: defaults), now: start,
                                   legacyImport: { _, _ in .items([legacyItem]) })
        XCTAssertEqual(nextLaunch.items, [legacyItem])
        XCTAssertTrue(AppSettings(defaults: defaults).hasMigratedLegacyItems)
    }

    func testLegacyImportResultNoneSetsTheFlag() throws {
        let settings = AppSettings(defaults: try makeTestDefaults())
        _ = ItemStore(persistence: InMemoryItemPersistence(), settings: settings, now: start,
                      legacyImport: { _, _ in .none })
        XCTAssertTrue(settings.hasMigratedLegacyItems)
    }

    func testLegacyImportIsRetriedIfSavingFails() throws {
        let persistence = InMemoryItemPersistence()
        persistence.failNextSave = TestError()
        let settings = AppSettings(defaults: try makeTestDefaults())
        let legacyItem = Item(name: "From 1.x", createdAt: start, decideAt: start)

        let store = ItemStore(persistence: persistence, settings: settings, now: start,
                              legacyItems: { _, _ in [legacyItem] })

        XCTAssertEqual(store.items, [legacyItem])
        XCTAssertFalse(settings.hasMigratedLegacyItems, "flag stays off so the next launch tries again")
        guard case .saveFailed? = store.lastError else {
            return XCTFail("Expected saveFailed, got \(String(describing: store.lastError))")
        }
    }

    // MARK: onChange

    func testOnChangeCallCounts() throws {
        let f = try makeFixture()
        XCTAssertEqual(f.changes.count, 0, "init does not call onChange")

        let item = f.store.add(name: "Sofa", price: nil, note: nil, waitDays: 1)
        XCTAssertEqual(f.changes.count, 1)
        f.store.refresh(now: TestDates.date(2026, 10, 5))
        XCTAssertEqual(f.changes.count, 2)
        f.store.refresh(now: TestDates.date(2026, 10, 5))
        XCTAssertEqual(f.changes.count, 3, "refresh always notifies")
        f.store.decide(item.id, .skipped)
        XCTAssertEqual(f.changes.count, 4)
        f.store.undoDecision(item.id)
        XCTAssertEqual(f.changes.count, 5)
        f.store.undoDecision(item.id)
        XCTAssertEqual(f.changes.count, 5, "undoing an undecided item changes nothing")
        f.store.extend(item.id, byDays: 7)
        XCTAssertEqual(f.changes.count, 6)
        f.store.update(item.id, name: "Sofa", price: nil, note: nil)
        XCTAssertEqual(f.changes.count, 6, "an update with identical values changes nothing")
        f.store.update(item.id, name: "Couch", price: nil, note: nil)
        XCTAssertEqual(f.changes.count, 7)
        f.store.retimeUndecided(to: DateComponents(hour: 9, minute: 0))
        XCTAssertEqual(f.changes.count, 7, "retiming to the same time changes nothing")
        f.store.retimeUndecided(to: DateComponents(hour: 10, minute: 0))
        XCTAssertEqual(f.changes.count, 8)
        f.store.delete(item.id)
        XCTAssertEqual(f.changes.count, 9)
        f.store.clearError()
        XCTAssertEqual(f.changes.count, 9)
    }
}
