import XCTest
@testable import WaitListCore

final class ItemTests: XCTestCase {
    private let calendar = TestDates.stockholm

    private func makeItem(createdAt: Date = TestDates.date(2026, 10, 3, 10, 0),
                          decideAt: Date = TestDates.date(2026, 10, 17, 9, 0),
                          note: String? = nil) -> Item {
        Item(name: "Sofa", note: note, createdAt: createdAt, decideAt: decideAt)
    }

    // MARK: Phase

    func testPhaseBoundaryExactlyAtDecideAtIsDue() {
        let decideAt = TestDates.date(2026, 10, 17, 9, 0)
        let item = makeItem(decideAt: decideAt)

        XCTAssertEqual(item.phase(at: decideAt.addingTimeInterval(-1)), .waiting)
        XCTAssertEqual(item.phase(at: decideAt), .due)
        XCTAssertEqual(item.phase(at: decideAt.addingTimeInterval(1)), .due)

        XCTAssertTrue(item.isWaiting(at: decideAt.addingTimeInterval(-1)))
        XCTAssertFalse(item.isDue(at: decideAt.addingTimeInterval(-1)))
        XCTAssertTrue(item.isDue(at: decideAt))
        XCTAssertFalse(item.isWaiting(at: decideAt))
    }

    func testDecidedItemIsNeitherDueNorWaiting() {
        var item = makeItem()
        item.outcome = .skipped
        item.decidedAt = TestDates.date(2026, 10, 5)
        let later = TestDates.date(2026, 12, 1)

        XCTAssertTrue(item.isDecided)
        XCTAssertEqual(item.phase(at: later), .decided(.skipped))
        XCTAssertEqual(item.phase(at: TestDates.date(2026, 10, 4)), .decided(.skipped))
        XCTAssertFalse(item.isDue(at: later))
        XCTAssertFalse(item.isWaiting(at: later))
    }

    // MARK: Day counts

    func testDaysLeftCountsCalendarDays() {
        let item = makeItem(decideAt: TestDates.date(2026, 10, 17, 9, 0))

        XCTAssertEqual(item.daysLeft(at: TestDates.date(2026, 10, 3, 8, 0), calendar: calendar), 14)
        // Late in the evening before: still one calendar day left.
        XCTAssertEqual(item.daysLeft(at: TestDates.date(2026, 10, 16, 23, 59), calendar: calendar), 1)
        // Same day, before the time: zero days left.
        XCTAssertEqual(item.daysLeft(at: TestDates.date(2026, 10, 17, 0, 1), calendar: calendar), 0)
    }

    func testDaysLeftIsNeverNegative() {
        let item = makeItem(decideAt: TestDates.date(2026, 10, 17, 9, 0))
        XCTAssertEqual(item.daysLeft(at: TestDates.date(2026, 10, 20, 12, 0), calendar: calendar), 0)
    }

    func testDaysWaitedUsesNowUntilDecided() {
        var item = makeItem(createdAt: TestDates.date(2026, 10, 1, 22, 0))

        XCTAssertEqual(item.daysWaited(at: TestDates.date(2026, 10, 3, 1, 0), calendar: calendar), 2)

        item.outcome = .bought
        item.decidedAt = TestDates.date(2026, 10, 5, 8, 0)
        // Once decided, the count stops at decidedAt regardless of now.
        XCTAssertEqual(item.daysWaited(at: TestDates.date(2026, 12, 24), calendar: calendar), 4)
    }

    func testDaysWaitedIsNeverNegative() {
        let item = makeItem(createdAt: TestDates.date(2026, 10, 5))
        XCTAssertEqual(item.daysWaited(at: TestDates.date(2026, 10, 1), calendar: calendar), 0)
    }

    // MARK: noteURL

    func testNoteURLAcceptsHTTPAndHTTPS() {
        XCTAssertEqual(makeItem(note: "https://example.com/sofa?id=1").noteURL,
                       URL(string: "https://example.com/sofa?id=1"))
        XCTAssertEqual(makeItem(note: "  http://example.com  \n").noteURL, URL(string: "http://example.com"))
        XCTAssertEqual(makeItem(note: "HTTPS://Example.com").noteURL, URL(string: "HTTPS://Example.com"))
    }

    func testNoteURLRejectsMissingSchemeOtherSchemesAndText() {
        XCTAssertNil(makeItem(note: "example.com/sofa").noteURL)
        XCTAssertNil(makeItem(note: "www.example.com").noteURL)
        XCTAssertNil(makeItem(note: "ftp://example.com/file").noteURL)
        XCTAssertNil(makeItem(note: "mailto:someone@example.com").noteURL)
        XCTAssertNil(makeItem(note: "Saw it at the shop downtown").noteURL)
        XCTAssertNil(makeItem(note: "https://").noteURL)
    }

    func testNoteURLIsNilForBlankOrMissingNote() {
        XCTAssertNil(makeItem(note: nil).noteURL)
        XCTAssertNil(makeItem(note: "").noteURL)
        XCTAssertNil(makeItem(note: "   \n ").noteURL)
    }

    // MARK: Codable

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testCodableRoundTripKeepsEveryField() throws {
        let item = Item(name: "Gorilla Sofa", price: dec("19.99"), note: "https://example.com",
                        createdAt: TestDates.date(2026, 10, 3, 10, 15, 30),
                        decideAt: TestDates.date(2026, 10, 17, 9, 0),
                        outcome: .skipped, decidedAt: TestDates.date(2026, 10, 18, 12, 0),
                        extensionCount: 2)

        let data = try encoder().encode(item)
        let decoded = try decoder().decode(Item.self, from: data)

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.price, dec("19.99"))
    }

    func testCodableRoundTripOfUndecidedItemWithoutOptionals() throws {
        let item = Item(name: "Lamp", createdAt: TestDates.date(2026, 10, 3), decideAt: TestDates.date(2026, 10, 10))
        let decoded = try decoder().decode(Item.self, from: try encoder().encode(item))
        XCTAssertEqual(decoded, item)
    }

    func testDecodingToleratesMissingOptionalFieldsAndExtensionCount() throws {
        let json = """
        {
          "id": "6F2C1B0E-4F0A-4C1E-9C55-3D8E7A0B1C2D",
          "name": "Old item",
          "createdAt": "2026-10-03T08:00:00Z",
          "decideAt": "2026-10-17T07:00:00Z"
        }
        """
        let item = try decoder().decode(Item.self, from: Data(json.utf8))

        XCTAssertEqual(item.id.uuidString, "6F2C1B0E-4F0A-4C1E-9C55-3D8E7A0B1C2D")
        XCTAssertEqual(item.name, "Old item")
        XCTAssertNil(item.price)
        XCTAssertNil(item.note)
        XCTAssertNil(item.outcome)
        XCTAssertNil(item.decidedAt)
        XCTAssertEqual(item.extensionCount, 0)
        XCTAssertEqual(TestDates.parts(item.decideAt), [2026, 10, 17, 9, 0])
    }

    func testDecodingFailsWithoutRequiredFields() {
        let json = #"{"id": "6F2C1B0E-4F0A-4C1E-9C55-3D8E7A0B1C2D", "name": "No dates"}"#
        XCTAssertThrowsError(try decoder().decode(Item.self, from: Data(json.utf8)))
    }
}
