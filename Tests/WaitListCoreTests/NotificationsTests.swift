import XCTest
@testable import WaitListCore

final class NotificationsTests: XCTestCase {
    private let calendar = TestDates.stockholm
    private let now = TestDates.date(2026, 10, 17, 9, 0)

    private func makeItem(name: String = "Gorilla Sofa", price: Decimal? = nil,
                          createdAt: Date = TestDates.date(2026, 10, 3, 10, 0)) -> Item {
        Item(name: name, price: price, createdAt: createdAt, decideAt: TestDates.date(2026, 10, 17, 9, 0))
    }

    func testIdentifiers() {
        let item = makeItem()
        XCTAssertEqual(NotificationPlan.requestIdentifier(for: item), item.id.uuidString)
        XCTAssertEqual(NotificationPlan.categoryIdentifier, "WAITLIST_DECISION")
        XCTAssertEqual(NotificationPlan.Action.allCases.map(\.rawValue),
                       ["WAITLIST_BOUGHT", "WAITLIST_SKIPPED", "WAITLIST_EXTEND"])
        XCTAssertEqual(NotificationPlan.extendDays, 7)
    }

    func testContentWithPrice() {
        let price = dec("1299")
        let content = NotificationPlan.content(for: makeItem(price: price), now: now, currencyCode: "SEK",
                                               calendar: calendar)
        let formatted = price.formatted(.currency(code: "SEK"))

        XCTAssertFalse(content.title.isEmpty)
        XCTAssertEqual(content.body, "You waited 14 days for “Gorilla Sofa” (\(formatted)). Still want it?")
    }

    func testContentWithoutPrice() {
        let content = NotificationPlan.content(for: makeItem(), now: now, currencyCode: "SEK", calendar: calendar)
        XCTAssertEqual(content.body, "You waited 14 days for “Gorilla Sofa”. Still want it?")
    }

    func testContentSingularDay() {
        let item = makeItem(createdAt: TestDates.date(2026, 10, 16, 20, 0))
        let content = NotificationPlan.content(for: item, now: now, currencyCode: "EUR", calendar: calendar)
        XCTAssertEqual(content.body, "You waited 1 day for “Gorilla Sofa”. Still want it?")
    }

    func testContentSameDay() {
        let item = makeItem(createdAt: TestDates.date(2026, 10, 17, 8, 0))
        let content = NotificationPlan.content(for: item, now: now, currencyCode: "EUR", calendar: calendar)
        XCTAssertEqual(content.body, "You added “Gorilla Sofa” today. Still want it?")
    }
}
