import XCTest
@testable import WaitListCore

final class NotificationPlannerTests: XCTestCase {
    /// 2026-10-17 09:30 in Stockholm: half an hour after the usual 09:00 decision time.
    private let now = TestDates.date(2026, 10, 17, 9, 30)

    private func item(_ name: String, decideAt: Date, outcome: Outcome? = nil) -> Item {
        Item(name: name, createdAt: TestDates.date(2026, 10, 3, 10, 0), decideAt: decideAt, outcome: outcome,
             decidedAt: outcome == nil ? nil : TestDates.date(2026, 10, 17, 9, 15))
    }

    private func id(_ item: Item) -> String {
        NotificationPlan.requestIdentifier(for: item)
    }

    // MARK: schedule

    func testScheduleHoldsUndecidedItemsWhoseTimeIsStillAhead() {
        let waiting = item("Waiting", decideAt: TestDates.date(2026, 10, 18, 9, 0))
        let due = item("Due", decideAt: TestDates.date(2026, 10, 17, 9, 0))
        let decided = item("Decided", decideAt: TestDates.date(2026, 10, 20, 9, 0), outcome: .skipped)
        let exactlyNow = item("Exactly now", decideAt: now)

        let plan = NotificationPlanner.plan(items: [waiting, due, decided, exactlyNow], now: now,
                                            pendingIdentifiers: [], deliveredIdentifiers: [])

        XCTAssertEqual(plan.schedule, [waiting])
        XCTAssertEqual(plan.removePending, [])
        XCTAssertEqual(plan.removeDelivered, [])
    }

    // MARK: Pending requests

    /// The Mac slept through 09:00 and woke at 09:30: the 09:00 request may still be about to be delivered.
    func testPendingRequestForAnUndecidedItemIsNeverRemovedEvenAfterItsTime() {
        let overdue = item("Overdue", decideAt: TestDates.date(2026, 10, 17, 9, 0))
        let waiting = item("Waiting", decideAt: TestDates.date(2026, 10, 18, 9, 0))

        let plan = NotificationPlanner.plan(items: [overdue, waiting], now: now,
                                            pendingIdentifiers: [id(overdue), id(waiting)], deliveredIdentifiers: [])

        XCTAssertEqual(plan.removePending, [])
    }

    func testPendingRequestsForDecidedDeletedOrUnknownItemsAreRemoved() {
        let decided = item("Decided", decideAt: TestDates.date(2026, 10, 20, 9, 0), outcome: .bought)
        let deletedID = UUID().uuidString
        let kept = item("Kept", decideAt: TestDates.date(2026, 10, 20, 9, 0))

        let plan = NotificationPlanner.plan(items: [decided, kept], now: now,
                                            pendingIdentifiers: [id(decided), deletedID, id(kept), "something-else"],
                                            deliveredIdentifiers: [])

        XCTAssertEqual(plan.removePending, [id(decided), deletedID, "something-else"])
    }

    // MARK: Delivered notifications

    func testDeliveredNotificationForADueUndecidedItemIsKept() {
        let due = item("Due", decideAt: TestDates.date(2026, 10, 17, 9, 0))
        let plan = NotificationPlanner.plan(items: [due], now: now, pendingIdentifiers: [],
                                            deliveredIdentifiers: [id(due)])
        XCTAssertEqual(plan.removeDelivered, [])
    }

    /// "Wait 7 more days" in the popover: the item is waiting again, so the old notification (whose buttons
    /// would extend or decide it a second time) must go.
    func testDeliveredNotificationForAnItemThatIsWaitingAgainIsRemoved() {
        let extended = item("Extended", decideAt: TestDates.date(2026, 10, 24, 9, 0))
        let plan = NotificationPlanner.plan(items: [extended], now: now, pendingIdentifiers: [id(extended)],
                                            deliveredIdentifiers: [id(extended)])
        XCTAssertEqual(plan.removeDelivered, [id(extended)])
        XCTAssertEqual(plan.removePending, [], "the new reminder stays")
        XCTAssertEqual(plan.schedule, [extended])
    }

    func testDeliveredNotificationsForDecidedDeletedOrUnknownItemsAreRemoved() {
        let decided = item("Decided", decideAt: TestDates.date(2026, 10, 17, 9, 0), outcome: .skipped)
        let deletedID = UUID().uuidString
        let plan = NotificationPlanner.plan(items: [decided], now: now, pendingIdentifiers: [],
                                            deliveredIdentifiers: [id(decided), deletedID, "other"])
        XCTAssertEqual(plan.removeDelivered, [id(decided), deletedID, "other"])
    }

    func testDueMeansDueByTheGivenClock() {
        // Due one second from now: not yet, so a delivered notification for it would be stale.
        let almost = item("Almost", decideAt: now.addingTimeInterval(1))
        let plan = NotificationPlanner.plan(items: [almost], now: now, pendingIdentifiers: [],
                                            deliveredIdentifiers: [id(almost)])
        XCTAssertEqual(plan.removeDelivered, [id(almost)])

        let later = NotificationPlanner.plan(items: [almost], now: now.addingTimeInterval(1), pendingIdentifiers: [],
                                             deliveredIdentifiers: [id(almost)])
        XCTAssertEqual(later.removeDelivered, [])
    }

    func testDuplicateIdentifiersAreRemovedOnce() {
        let plan = NotificationPlanner.plan(items: [], now: now, pendingIdentifiers: ["a", "a", "b"],
                                            deliveredIdentifiers: ["c", "c"])
        XCTAssertEqual(plan.removePending, ["a", "b"])
        XCTAssertEqual(plan.removeDelivered, ["c"])
    }

    // MARK: Responses

    private let due = Item(name: "Due", createdAt: TestDates.date(2026, 10, 3, 10, 0),
                           decideAt: TestDates.date(2026, 10, 17, 9, 0))

    func testButtonsOnADueItemDecideOrExtendIt() {
        XCTAssertEqual(NotificationPlanner.response(to: "WAITLIST_BOUGHT", item: due, now: now),
                       .decide(due.id, .bought))
        XCTAssertEqual(NotificationPlanner.response(to: "WAITLIST_SKIPPED", item: due, now: now),
                       .decide(due.id, .skipped))
        XCTAssertEqual(NotificationPlanner.response(to: "WAITLIST_EXTEND", item: due, now: now),
                       .extend(due.id, days: NotificationPlan.extendDays))
    }

    func testClickingTheNotificationOpensThePopoverWhateverTheItem() {
        let identifier = NotificationPlanner.defaultActionIdentifier
        XCTAssertEqual(identifier, "com.apple.UNNotificationDefaultActionIdentifier")
        XCTAssertEqual(NotificationPlanner.response(to: identifier, item: due, now: now), .openPopover)
        XCTAssertEqual(NotificationPlanner.response(to: identifier, item: nil, now: now), .openPopover)
    }

    func testDismissAndUnknownActionsDoNothing() {
        XCTAssertNil(NotificationPlanner.response(to: "com.apple.UNNotificationDismissActionIdentifier", item: due,
                                                  now: now))
        XCTAssertNil(NotificationPlanner.response(to: "SOMETHING_ELSE", item: due, now: now))
        XCTAssertNil(NotificationPlanner.response(to: "", item: due, now: now))
    }

    func testButtonsForAMissingItemDoNothing() {
        XCTAssertNil(NotificationPlanner.response(to: "WAITLIST_BOUGHT", item: nil, now: now))
    }

    func testStaleButtonsDoNothing() {
        var decided = due
        decided.outcome = .skipped
        decided.decidedAt = now
        var extended = due
        extended.decideAt = TestDates.date(2026, 10, 24, 9, 0)
        for action in NotificationPlan.Action.allCases {
            XCTAssertNil(NotificationPlanner.response(to: action.rawValue, item: decided, now: now), action.rawValue)
            XCTAssertNil(NotificationPlanner.response(to: action.rawValue, item: extended, now: now), action.rawValue)
        }
    }
}
