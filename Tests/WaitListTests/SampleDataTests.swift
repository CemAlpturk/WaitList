import XCTest
import WaitListCore
@testable import WaitList

/// Snapshots (`--snapshot`) depend on these sample stores having the right shape.
@MainActor
final class SampleDataTests: XCTestCase {
    private let calendar = TestCalendars.stockholm
    /// A Friday morning, like `SampleData.referenceNow`: 08:15, so "today at 09:00" is still ahead.
    private var now: Date { date(2025, 10, 17, 8, 15, in: calendar) }

    private func makeStore(_ contents: SampleData.Contents, failingSave: Error? = nil) throws -> ItemStore {
        let settings = AppSettings(defaults: try makeTestDefaults())
        return SampleData.store(contents, settings: settings, now: now, calendar: calendar, failingSave: failingSave)
    }

    func testFullStoreHasDueWaitingAndHistoryItems() throws {
        let store = try makeStore(.full)
        XCTAssertEqual(store.items.count, 9)
        XCTAssertEqual(store.due.count, 2)
        XCTAssertEqual(store.waiting.count, 3)
        XCTAssertEqual(store.history.count, 4)
        XCTAssertEqual(store.skippedCount, 3)
        XCTAssertEqual(store.boughtCount, 1)
        XCTAssertEqual(store.totalSaved, 3_590)   // 2490 + 1100, the vinyl record has no price
        XCTAssertEqual(store.totalSpent, 220)
        XCTAssertNil(store.lastError)
    }

    func testOtherContentsHaveTheRightShape() throws {
        let waitingOnly = try makeStore(.waitingOnly)
        XCTAssertEqual([waitingOnly.due.count, waitingOnly.waiting.count, waitingOnly.history.count], [0, 3, 0])

        let historyOnly = try makeStore(.historyOnly)
        XCTAssertEqual([historyOnly.due.count, historyOnly.waiting.count, historyOnly.history.count], [0, 0, 4])

        let empty = try makeStore(.empty)
        XCTAssertTrue(empty.items.isEmpty)

        let few = try makeStore(.few)
        XCTAssertEqual([few.due.count, few.waiting.count, few.history.count], [1, 2, 0])
    }

    func testSampleItemsAreDeterministicApartFromIDs() {
        let first = SampleData.items(.full, now: now, calendar: calendar)
        let second = SampleData.items(.full, now: now, calendar: calendar)
        XCTAssertEqual(first.map(\.name), second.map(\.name))
        XCTAssertEqual(first.map(\.decideAt), second.map(\.decideAt))
        XCTAssertEqual(first.map(\.price), second.map(\.price))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count, "every item has its own id")
        XCTAssertEqual(Set(first.map(\.name)).count, first.count, "names are distinct")
    }

    func testSampleItemsAreRelativeToNow() {
        let later = calendar.date(byAdding: .day, value: 10, to: now) ?? now
        let a = SampleData.items(.full, now: now, calendar: calendar)
        let b = SampleData.items(.full, now: later, calendar: calendar)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(calendar.dateComponents([.day], from: x.decideAt, to: y.decideAt).day, 10, x.name)
        }
    }

    func testSampleItemsAreInTheRightPhases() {
        let phases = SampleData.items(.full, now: now, calendar: calendar).map { $0.phase(at: now) }
        XCTAssertEqual(phases.filter { $0 == .due }.count, 2)
        XCTAssertEqual(phases.filter { $0 == .waiting }.count, 3)
        XCTAssertEqual(phases.filter { $0 == .decided(.skipped) }.count, 3)
        XCTAssertEqual(phases.filter { $0 == .decided(.bought) }.count, 1)
    }

    func testSampleLinksAreValidURLs() {
        let withLinks = SampleData.items(.full, now: now, calendar: calendar).filter { $0.note != nil }
        XCTAssertFalse(withLinks.isEmpty)
        XCTAssertGreaterThanOrEqual(withLinks.compactMap(\.noteURL).count, 3)
    }

    func testReferenceNowIsTodayAtQuarterPastEight() {
        let reference = SampleData.referenceNow(calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: reference)
        XCTAssertEqual([parts.hour, parts.minute, parts.second], [8, 15, 0])
        XCTAssertTrue(calendar.isDate(reference, inSameDayAs: Date()))
    }

    func testFailingSaveIsKeptForTheNextChange() throws {
        // The "list-error" snapshot builds the store, then adds an item and expects the save error to show.
        let store = try makeStore(.few, failingSave: TestError(message: "disk full"))
        XCTAssertNil(store.lastError, "creating the store must not use up the failure")

        store.add(name: "Camera strap", price: 349, note: nil, waitDays: 14)

        XCTAssertEqual(store.items.count, 4, "the item stays in memory")
        guard case .saveFailed(let message)? = store.lastError else {
            return XCTFail("expected a save error, got \(String(describing: store.lastError))")
        }
        XCTAssertTrue(message.contains("disk full"), message)
    }

    func testStoreUsesTheGivenCalendarAndSkipsLegacyImport() throws {
        let settings = AppSettings(defaults: try makeTestDefaults())
        let store = SampleData.store(.empty, settings: settings, now: now, calendar: calendar)
        XCTAssertEqual(store.calendar.timeZone, calendar.timeZone)
        XCTAssertEqual(store.now, now)
        XCTAssertTrue(store.items.isEmpty, "no 1.x items are imported into sample stores")
    }
}
