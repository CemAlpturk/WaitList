import XCTest
@testable import WaitList

@MainActor
final class AppServicesTests: XCTestCase {
    /// Counts what the closures were asked to do.
    private final class Calls {
        var openNotificationSettings = 0
        var openLoginItems = 0
        var quit = 0
        var setLaunchAtLogin: [Bool] = []
        var launchState = LaunchAtLoginState.disabled
        var permission = NotificationPermission.notDetermined
        var setterError: Error?
    }

    private func makeServices(_ calls: Calls, dataFileURL: URL? = nil, notice: String? = nil) -> AppServices {
        AppServices(
            dataFileURL: dataFileURL,
            notice: notice,
            notificationPermission: { calls.permission },
            openNotificationSettings: { calls.openNotificationSettings += 1 },
            launchAtLoginState: { calls.launchState },
            setLaunchAtLogin: { enabled in
                calls.setLaunchAtLogin.append(enabled)
                if let error = calls.setterError { throw error }
            },
            openLoginItemsSettings: { calls.openLoginItems += 1 },
            quit: { calls.quit += 1 })
    }

    // MARK: Forwarding

    func testEachActionCallsItsClosureExactlyOnce() throws {
        let calls = Calls()
        let services = makeServices(calls)

        services.openNotificationSettings()
        XCTAssertEqual(calls.openNotificationSettings, 1)
        XCTAssertEqual(calls.openLoginItems + calls.quit, 0)

        services.openLoginItemsSettings()
        XCTAssertEqual(calls.openLoginItems, 1)
        XCTAssertEqual(calls.quit, 0)

        services.quit()
        XCTAssertEqual(calls.quit, 1)
        XCTAssertEqual(calls.openNotificationSettings, 1)
        XCTAssertEqual(calls.openLoginItems, 1)

        try services.setLaunchAtLogin(true)
        try services.setLaunchAtLogin(false)
        XCTAssertEqual(calls.setLaunchAtLogin, [true, false])
    }

    func testLaunchAtLoginStateIsReadFreshEachTime() {
        let calls = Calls()
        let services = makeServices(calls)
        XCTAssertEqual(services.launchAtLoginState(), .disabled)
        calls.launchState = .requiresApproval
        XCTAssertEqual(services.launchAtLoginState(), .requiresApproval)
        calls.launchState = .enabled
        XCTAssertEqual(services.launchAtLoginState(), .enabled)
    }

    func testNotificationPermissionIsReadFreshEachTime() async {
        let calls = Calls()
        let services = makeServices(calls)
        var seen: [NotificationPermission] = []
        for permission in [NotificationPermission.notDetermined, .allowed, .denied] {
            calls.permission = permission
            seen.append(await services.notificationPermission())
        }
        XCTAssertEqual(seen, [.notDetermined, .allowed, .denied])
    }

    func testSetLaunchAtLoginPropagatesTheError() {
        let calls = Calls()
        calls.setterError = TestError(message: "not allowed")
        let services = makeServices(calls)
        XCTAssertThrowsError(try services.setLaunchAtLogin(true)) { error in
            XCTAssertEqual(error.localizedDescription, "not allowed")
        }
        XCTAssertEqual(calls.setLaunchAtLogin, [true], "the attempt was made")
    }

    // MARK: Stored properties

    func testDataFileURLAndNoticeComeFromTheInitializer() {
        let url = URL(fileURLWithPath: "/opt/x/items.json")
        let services = makeServices(Calls(), dataFileURL: url, notice: "Data folder missing")
        XCTAssertEqual(services.dataFileURL, url)
        XCTAssertEqual(services.notice, "Data folder missing")

        let bare = makeServices(Calls())
        XCTAssertNil(bare.dataFileURL)
        XCTAssertNil(bare.notice)
    }

    func testNoticeCanBeDismissedAndSetAgain() {
        let services = makeServices(Calls(), notice: "Something happened")
        services.notice = nil
        XCTAssertNil(services.notice)
        services.notice = "Again"
        XCTAssertEqual(services.notice, "Again")
    }

    func testRevealDataFileWithoutAFileDoesNothing() {
        // With a URL it would open Finder, so only the in-memory case is exercised.
        let services = makeServices(Calls(), dataFileURL: nil)
        services.revealDataFile()
        XCTAssertNil(services.dataFileURL)
    }

    // MARK: preview

    func testPreviewServicesAreInert() async throws {
        let services = AppServices.preview()
        XCTAssertNil(services.dataFileURL)
        XCTAssertNil(services.notice)
        let permission = await services.notificationPermission()
        XCTAssertEqual(permission, .allowed)
        XCTAssertEqual(services.launchAtLoginState(), .disabled)
        try services.setLaunchAtLogin(true)
        XCTAssertEqual(services.launchAtLoginState(), .disabled, "the preview setter does not change anything")
        services.openNotificationSettings()
        services.openLoginItemsSettings()
        services.quit()   // would terminate the app if this were the live service
    }

    func testPreviewServicesReportWhatTheyWereGiven() async {
        let url = URL(fileURLWithPath: "/opt/sample/items.json")
        for permission in [NotificationPermission.allowed, .denied, .notDetermined] {
            let services = AppServices.preview(dataFileURL: url, notice: "Heads up", permission: permission,
                                               launchAtLogin: .requiresApproval)
            let reported = await services.notificationPermission()
            XCTAssertEqual(reported, permission)
            XCTAssertEqual(services.launchAtLoginState(), .requiresApproval)
            XCTAssertEqual(services.dataFileURL, url)
            XCTAssertEqual(services.notice, "Heads up")
        }
    }
}
