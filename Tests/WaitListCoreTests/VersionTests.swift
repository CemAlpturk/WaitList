import XCTest
@testable import WaitListCore

final class VersionTests: XCTestCase {
    func testVersionIsSemver() {
        XCTAssertEqual(AppInfo.version.split(separator: ".").count, 3)
    }
}
