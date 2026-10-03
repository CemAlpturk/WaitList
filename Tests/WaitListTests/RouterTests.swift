import Observation
import XCTest
import WaitListCore
@testable import WaitList

/// Set from observation callbacks, which are `@Sendable`.
private final class Flag: @unchecked Sendable {
    var isSet = false
}

@MainActor
final class RouterTests: XCTestCase {
    private let item = Item(name: "Sofa", price: 1299, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                            decideAt: Date(timeIntervalSince1970: 1_701_000_000))

    func testStartsOnTheListUnlessToldOtherwise() {
        XCTAssertEqual(Router().screen, .list)
        XCTAssertEqual(Router(screen: .settings).screen, .settings)
        XCTAssertEqual(Router(screen: .add(editing: nil)).screen, .add(editing: nil))
    }

    func testShowSwitchesScreenWithoutAnimation() {
        let router = Router()
        router.show(.settings, animated: false)
        XCTAssertEqual(router.screen, .settings)
        router.show(.add(editing: nil), animated: false)
        XCTAssertEqual(router.screen, .add(editing: nil))
        router.show(.list, animated: false)
        XCTAssertEqual(router.screen, .list)
    }

    func testShowSwitchesScreenWithAnimationToo() {
        // `animated` defaults to true; outside a window the value must still change straight away.
        let router = Router()
        router.show(.settings)
        XCTAssertEqual(router.screen, .settings)
        router.show(.list, animated: true)
        XCTAssertEqual(router.screen, .list)
    }

    func testShowingTheCurrentScreenChangesNothingAndNotifiesNoOne() {
        let router = Router(screen: .settings)
        let notified = Flag()
        withObservationTracking {
            _ = router.screen
        } onChange: {
            notified.isSet = true
        }
        router.show(.settings, animated: false)
        router.show(.settings, animated: true)
        XCTAssertFalse(notified.isSet, "re-showing the same screen must not re-trigger transitions")
        XCTAssertEqual(router.screen, .settings)
    }

    func testChangingScreenNotifiesObservers() {
        let router = Router()
        let notified = Flag()
        withObservationTracking {
            _ = router.screen
        } onChange: {
            notified.isSet = true
        }
        router.show(.add(editing: nil), animated: false)
        XCTAssertTrue(notified.isSet)
    }

    func testEditingAnItemIsADifferentScreenFromAddingOne() {
        let router = Router(screen: .add(editing: nil))
        router.show(.add(editing: item), animated: false)
        XCTAssertEqual(router.screen, .add(editing: item))
        XCTAssertNotEqual(router.screen, .add(editing: nil))
    }

    func testScreenEquality() {
        XCTAssertEqual(Screen.list, .list)
        XCTAssertEqual(Screen.settings, .settings)
        XCTAssertNotEqual(Screen.list, .settings)
        XCTAssertNotEqual(Screen.list, .add(editing: nil))
        XCTAssertEqual(Screen.add(editing: item), .add(editing: item))

        var renamed = item
        renamed.name = "Couch"
        XCTAssertNotEqual(Screen.add(editing: item), .add(editing: renamed), "same id, different contents")
        let other = Item(name: "Sofa", price: 1299, createdAt: item.createdAt, decideAt: item.decideAt)
        XCTAssertNotEqual(Screen.add(editing: item), .add(editing: other), "different id")
    }

    func testPopoverSizeMatchesWhatTheRootViewAndSnapshotsUse() {
        XCTAssertEqual(StatusItemController.popoverSize, NSSize(width: 340, height: 520))
        XCTAssertEqual(RootView().size, StatusItemController.popoverSize)
    }
}
