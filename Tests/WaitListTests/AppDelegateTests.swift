import UserNotifications
import XCTest
import WaitListCore
@testable import WaitList

final class AppDelegateTests: XCTestCase {
    /// A notification tap (or reopening the app) shows the list, but never throws away an Add/Edit form.
    func testOpeningFromOutsideKeepsAnAddOrEditForm() {
        let item = Item(name: "Sofa", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                        decideAt: Date(timeIntervalSince1970: 1_701_000_000))
        XCTAssertNil(AppDelegate.screenToShowOnOpen(from: .add(editing: nil)))
        XCTAssertNil(AppDelegate.screenToShowOnOpen(from: .add(editing: item)))
        XCTAssertEqual(AppDelegate.screenToShowOnOpen(from: .list), .list)
        XCTAssertEqual(AppDelegate.screenToShowOnOpen(from: .settings), .list)
    }

    /// Core spells this identifier out so it does not import UserNotifications; it must match the system's.
    func testCoreKnowsTheSystemsDefaultActionIdentifier() {
        XCTAssertEqual(NotificationPlanner.defaultActionIdentifier, UNNotificationDefaultActionIdentifier)
        XCTAssertNotEqual(NotificationPlanner.defaultActionIdentifier, UNNotificationDismissActionIdentifier)
    }
}
