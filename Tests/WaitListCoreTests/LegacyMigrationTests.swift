import XCTest
@testable import WaitListCore

final class LegacyMigrationTests: XCTestCase {
    private let calendar = TestDates.stockholm
    private let nineAM = DateComponents(hour: 9, minute: 0)
    private let now = TestDates.date(2026, 10, 3, 12, 0)

    /// Exactly what WaitList 1.x wrote: `JSONEncoder().encode([Product])`, dates as seconds since 2001-01-01.
    /// 813937330.5 is 2026-10-17 13:42:10.5 UTC, i.e. 15:42 in Stockholm.
    private let legacyJSON = """
    [{"id":"0B1E3C55-7A2D-4F61-9E0C-2B7D4C8A1F00","name":"Gorilla Sofa","deadline":813937330.5},\
    {"id":"9D8C7B6A-5F4E-4D3C-8B2A-1F0E9D8C7B6A","name":"Lamp","deadline":813000000}]
    """

    func testDecodeKeepsIdNameAndDayAndUsesConfiguredTime() throws {
        let items = try LegacyMigration.decode(legacyData: Data(legacyJSON.utf8), now: now, time: nineAM,
                                               calendar: calendar)

        XCTAssertEqual(items.count, 2)
        let sofa = try XCTUnwrap(items.first)
        XCTAssertEqual(sofa.id.uuidString, "0B1E3C55-7A2D-4F61-9E0C-2B7D4C8A1F00")
        XCTAssertEqual(sofa.name, "Gorilla Sofa")
        XCTAssertEqual(TestDates.parts(sofa.decideAt), [2026, 10, 17, 9, 0])
        XCTAssertEqual(sofa.createdAt, now)
        XCTAssertNil(sofa.price)
        XCTAssertNil(sofa.note)
        XCTAssertNil(sofa.outcome)
        XCTAssertNil(sofa.decidedAt)
        XCTAssertEqual(sofa.extensionCount, 0)
    }

    func testDecodeThrowsOnGarbage() {
        XCTAssertThrowsError(try LegacyMigration.decode(legacyData: Data("garbage".utf8), now: now, time: nineAM,
                                                        calendar: calendar))
    }

    func testLegacyItemsReadsFromDefaults() throws {
        let defaults = try makeTestDefaults()
        defaults.set(Data(legacyJSON.utf8), forKey: "products")

        let items = LegacyMigration.legacyItems(now: now, time: nineAM, defaults: defaults,
                                                containerPlistURL: nil, calendar: calendar)
        XCTAssertEqual(items.map(\.name), ["Gorilla Sofa", "Lamp"])
    }

    func testLegacyItemsReadsFromContainerPlist() throws {
        let defaults = try makeTestDefaults()
        let directory = try makeTempDirectory()
        let plistURL = directory.appendingPathComponent("com.cemalpturk.WaitList.plist")
        let plist: [String: Any] = ["products": Data(legacyJSON.utf8), "SomethingElse": 1]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try plistData.write(to: plistURL)

        let items = LegacyMigration.legacyItems(now: now, time: nineAM, defaults: defaults,
                                                containerPlistURL: plistURL, calendar: calendar)
        XCTAssertEqual(items.map(\.name), ["Gorilla Sofa", "Lamp"])
        XCTAssertEqual(TestDates.parts(items[0].decideAt), [2026, 10, 17, 9, 0])
    }

    func testLegacyItemsFallsBackToPlistWhenDefaultsHoldGarbage() throws {
        let defaults = try makeTestDefaults()
        defaults.set(Data("garbage".utf8), forKey: "products")
        let directory = try makeTempDirectory()
        let plistURL = directory.appendingPathComponent("legacy.plist")
        let plistData = try PropertyListSerialization.data(fromPropertyList: ["products": Data(legacyJSON.utf8)],
                                                           format: .xml, options: 0)
        try plistData.write(to: plistURL)

        let items = LegacyMigration.legacyItems(now: now, time: nineAM, defaults: defaults,
                                                containerPlistURL: plistURL, calendar: calendar)
        XCTAssertEqual(items.count, 2)
    }

    func testLegacyItemsReturnsEmptyForGarbageEverywhere() throws {
        let defaults = try makeTestDefaults()
        defaults.set(Data("garbage".utf8), forKey: "products")
        let directory = try makeTempDirectory()
        let plistURL = directory.appendingPathComponent("broken.plist")
        try Data("not a plist".utf8).write(to: plistURL)

        XCTAssertEqual(LegacyMigration.legacyItems(now: now, time: nineAM, defaults: defaults,
                                                   containerPlistURL: plistURL, calendar: calendar), [])
    }

    func testLegacyItemsReturnsEmptyWhenNothingExists() throws {
        let defaults = try makeTestDefaults()
        let directory = try makeTempDirectory()
        let missing = directory.appendingPathComponent("missing.plist")

        XCTAssertEqual(LegacyMigration.legacyItems(now: now, time: nineAM, defaults: defaults,
                                                   containerPlistURL: missing, calendar: calendar), [])
        XCTAssertEqual(LegacyMigration.legacyItems(now: now, time: nineAM, defaults: defaults,
                                                   containerPlistURL: nil, calendar: calendar), [])
    }

    // MARK: find

    func testFindReturnsItemsFromDefaultsOrPlist() throws {
        let defaults = try makeTestDefaults()
        defaults.set(Data(legacyJSON.utf8), forKey: "products")
        guard case .items(let fromDefaults) = LegacyMigration.find(now: now, time: nineAM, defaults: defaults,
                                                                    containerPlistURL: nil, calendar: calendar) else {
            return XCTFail("expected items")
        }
        XCTAssertEqual(fromDefaults.map(\.name), ["Gorilla Sofa", "Lamp"])

        let directory = try makeTempDirectory()
        let plistURL = directory.appendingPathComponent("legacy.plist")
        try PropertyListSerialization.data(fromPropertyList: ["products": Data(legacyJSON.utf8)], format: .binary,
                                           options: 0).write(to: plistURL)
        guard case .items(let fromPlist) = LegacyMigration.find(now: now, time: nineAM,
                                                                 defaults: try makeTestDefaults(),
                                                                 containerPlistURL: plistURL, calendar: calendar) else {
            return XCTFail("expected items")
        }
        XCTAssertEqual(fromPlist.count, 2)
    }

    func testFindReturnsNoneWhenNothingExistsOrTheDataIsDamaged() throws {
        let defaults = try makeTestDefaults()
        let directory = try makeTempDirectory()
        XCTAssertEqual(LegacyMigration.find(now: now, time: nineAM, defaults: defaults,
                                            containerPlistURL: directory.appendingPathComponent("missing.plist"),
                                            calendar: calendar), .none)
        XCTAssertEqual(LegacyMigration.find(now: now, time: nineAM, defaults: defaults,
                                            containerPlistURL: directory.appendingPathComponent("no/such/dir.plist"),
                                            calendar: calendar), .none)
        XCTAssertEqual(LegacyMigration.find(now: now, time: nineAM, defaults: defaults, containerPlistURL: nil,
                                            calendar: calendar), .none)

        let broken = directory.appendingPathComponent("broken.plist")
        try Data("not a plist".utf8).write(to: broken)
        XCTAssertEqual(LegacyMigration.find(now: now, time: nineAM, defaults: defaults, containerPlistURL: broken,
                                            calendar: calendar), .none, "damaged data will never import")

        let noProducts = directory.appendingPathComponent("other.plist")
        try PropertyListSerialization.data(fromPropertyList: ["SomethingElse": 1], format: .xml, options: 0)
            .write(to: noProducts)
        XCTAssertEqual(LegacyMigration.find(now: now, time: nineAM, defaults: defaults, containerPlistURL: noProducts,
                                            calendar: calendar), .none)
    }

    /// The 1.x container plist exists but cannot be read, as when the user denies macOS's
    /// "access data from other apps" prompt. Simulated with a file nobody may read.
    func testFindReportsAnUnreadablePlistSoTheImportIsRetried() throws {
        let directory = try makeTempDirectory()
        let plistURL = directory.appendingPathComponent("com.cemalpturk.WaitList.plist")
        try PropertyListSerialization.data(fromPropertyList: ["products": Data(legacyJSON.utf8)], format: .binary,
                                           options: 0).write(to: plistURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: plistURL.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
        }
        try XCTSkipIf((try? Data(contentsOf: plistURL)) != nil, "running with permission to read any file")

        let defaults = try makeTestDefaults()
        XCTAssertEqual(LegacyMigration.find(now: now, time: nineAM, defaults: defaults, containerPlistURL: plistURL,
                                            calendar: calendar), .unreadable)
        XCTAssertEqual(LegacyMigration.legacyItems(now: now, time: nineAM, defaults: defaults,
                                                   containerPlistURL: plistURL, calendar: calendar), [])
    }

    func testItemsInDefaultsWinOverAnUnreadablePlist() throws {
        let defaults = try makeTestDefaults()
        defaults.set(Data(legacyJSON.utf8), forKey: "products")
        let directory = try makeTempDirectory()
        let plistURL = directory.appendingPathComponent("locked.plist")
        try Data().write(to: plistURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: plistURL.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
        }

        guard case .items(let items) = LegacyMigration.find(now: now, time: nineAM, defaults: defaults,
                                                            containerPlistURL: plistURL, calendar: calendar) else {
            return XCTFail("expected items")
        }
        XCTAssertEqual(items.count, 2)
    }

    func testDefaultContainerPlistURL() {
        let path = LegacyMigration.defaultContainerPlistURL.path
        XCTAssertTrue(path.hasSuffix(
            "/Library/Containers/com.cemalpturk.WaitList/Data/Library/Preferences/com.cemalpturk.WaitList.plist"),
            path)
    }
}
