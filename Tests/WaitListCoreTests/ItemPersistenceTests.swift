import XCTest
@testable import WaitListCore

final class ItemPersistenceTests: XCTestCase {
    private func sampleItems() -> [Item] {
        [
            Item(name: "Gorilla Sofa", price: dec("19.99"), note: "https://example.com/sofa",
                 createdAt: TestDates.date(2026, 10, 3, 10, 15, 30),
                 decideAt: TestDates.date(2026, 10, 17, 9, 0)),
            Item(name: "Headphones", price: dec("5.01"), note: nil,
                 createdAt: TestDates.date(2026, 9, 1, 8, 0),
                 decideAt: TestDates.date(2026, 9, 15, 9, 0),
                 outcome: .skipped, decidedAt: TestDates.date(2026, 9, 16, 19, 30), extensionCount: 1),
        ]
    }

    private func contents(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // MARK: FileItemPersistence

    func testRoundTrip() throws {
        let directory = try makeTempDirectory()
        let persistence = FileItemPersistence(fileURL: directory.appendingPathComponent("items.json"))
        let items = sampleItems()

        try persistence.save(items)
        XCTAssertEqual(try persistence.load(), items)
    }

    func testFileFormatIsVersionedSortedJSON() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        try FileItemPersistence(fileURL: fileURL).save(sampleItems())

        let data = try Data(contentsOf: fileURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual((object["items"] as? [Any])?.count, 2)

        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"decideAt\" : \"2026-10-17T07:00:00Z\""), text)
        XCTAssertTrue(text.contains("\"price\" : 19.99"), text)
        XCTAssertTrue(text.contains("https://example.com/sofa"), text)
    }

    func testSaveCreatesMissingDirectory() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("nested/deeper/items.json")
        let persistence = FileItemPersistence(fileURL: fileURL)

        try persistence.save(sampleItems())
        XCTAssertEqual(try persistence.load().count, 2)
    }

    func testMissingFileLoadsAsEmpty() throws {
        let directory = try makeTempDirectory()
        let persistence = FileItemPersistence(fileURL: directory.appendingPathComponent("items.json"))
        XCTAssertEqual(try persistence.load(), [])
    }

    func testCorruptFileIsMovedAsideAndThrows() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        let garbage = Data("this is not json {".utf8)
        try garbage.write(to: fileURL)
        let persistence = FileItemPersistence(fileURL: fileURL)

        var backupURL: URL?
        XCTAssertThrowsError(try persistence.load()) { error in
            guard case PersistenceError.corruptFile(let url)? = error as? PersistenceError else {
                return XCTFail("Unexpected error \(error)")
            }
            backupURL = url
        }

        let backup = try XCTUnwrap(backupURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "original should be moved away")
        XCTAssertEqual(backup.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("items.corrupt-"), backup.lastPathComponent)
        XCTAssertEqual(backup.pathExtension, "json")
        // items.corrupt-yyyyMMdd-HHmmss.json
        XCTAssertEqual(backup.lastPathComponent.count, "items.corrupt-20261003-101530.json".count)
        XCTAssertEqual(try Data(contentsOf: backup), garbage, "backup must hold the user's original bytes")

        // The next load sees no file, and a save does not touch the backup.
        XCTAssertEqual(try persistence.load(), [])
        try persistence.save(sampleItems())
        XCTAssertEqual(try Data(contentsOf: backup), garbage)
        XCTAssertEqual(try persistence.load().count, 2)
    }

    func testWellFormedJSONWithBadItemsCountsAsCorrupt() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        try Data(#"{"version": 1, "items": [{"name": "no id or dates"}]}"#.utf8).write(to: fileURL)

        XCTAssertThrowsError(try FileItemPersistence(fileURL: fileURL).load()) { error in
            guard case PersistenceError.corruptFile? = error as? PersistenceError else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try contents(of: directory).count, 1)
    }

    func testTwoCorruptFilesInTheSameSecondGetDistinctBackups() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        let persistence = FileItemPersistence(fileURL: fileURL)

        try Data("first".utf8).write(to: fileURL)
        XCTAssertThrowsError(try persistence.load())
        try Data("second".utf8).write(to: fileURL)
        XCTAssertThrowsError(try persistence.load())

        let backups = try contents(of: directory).filter { $0.hasPrefix("items.corrupt-") }
        XCTAssertEqual(backups.count, 2, "\(backups)")
    }

    func testUnsupportedVersionThrowsAndLeavesFileUntouched() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        let future = Data(#"{"version": 2, "items": [], "somethingNew": true}"#.utf8)
        try future.write(to: fileURL)

        XCTAssertThrowsError(try FileItemPersistence(fileURL: fileURL).load()) { error in
            XCTAssertEqual(error as? PersistenceError, .unsupportedVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), future)
        XCTAssertEqual(try contents(of: directory), ["items.json"], "no backup should be made")
    }

    /// Checks the path only: calling `defaultFileURL()` would create the real
    /// ~/Library/Application Support/WaitList folder.
    func testDefaultFileURLIsInApplicationSupport() throws {
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
                                                              in: .userDomainMask).first)
        let url = FileItemPersistence.fileURL(inApplicationSupport: support)
        XCTAssertEqual(url.lastPathComponent, "items.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "WaitList")
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent(), support)
        XCTAssertTrue(url.path.hasSuffix("/Library/Application Support/WaitList/items.json"), url.path)
    }

    func testFileURLInApplicationSupportCreatesNothing() throws {
        let support = try makeTempDirectory()
        let url = FileItemPersistence.fileURL(inApplicationSupport: support)
        XCTAssertEqual(url.path, support.appendingPathComponent("WaitList/items.json").path)
        XCTAssertEqual(try contents(of: support), [])
    }

    // MARK: Lenient dates

    private func writeItemsFile(_ url: URL, createdAt: String, decideAt: String) throws {
        let json = """
        {"version": 1, "items": [{"id": "6F2C1B0E-4F0A-4C1E-9C55-3D8E7A0B1C2D", "name": "Hand edited",
          "createdAt": "\(createdAt)", "decideAt": "\(decideAt)"}]}
        """
        try Data(json.utf8).write(to: url)
    }

    func testDatesWithFractionalSecondsLoad() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        try writeItemsFile(fileURL, createdAt: "2026-10-03T08:00:00.250Z", decideAt: "2026-10-17T07:00:00.5Z")

        let item = try XCTUnwrap(try FileItemPersistence(fileURL: fileURL).load().first)

        XCTAssertEqual(item.createdAt, TestDates.date(2026, 10, 3, 10, 0).addingTimeInterval(0.25))
        XCTAssertEqual(item.decideAt, TestDates.date(2026, 10, 17, 9, 0).addingTimeInterval(0.5))
        XCTAssertEqual(try contents(of: directory), ["items.json"], "nothing was moved aside")
    }

    func testDatesWithAnOffsetLoad() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        try writeItemsFile(fileURL, createdAt: "2026-10-03T10:00:00+02:00", decideAt: "2026-10-17T09:00:00.000+02:00")

        let item = try XCTUnwrap(try FileItemPersistence(fileURL: fileURL).load().first)

        XCTAssertEqual(item.createdAt, TestDates.date(2026, 10, 3, 10, 0))
        XCTAssertEqual(item.decideAt, TestDates.date(2026, 10, 17, 9, 0))
    }

    func testSavedDatesAreStillWholeSecondsUTC() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        let item = Item(name: "Lamp", createdAt: TestDates.date(2026, 10, 3, 10, 0).addingTimeInterval(0.25),
                        decideAt: TestDates.date(2026, 10, 17, 9, 0))
        try FileItemPersistence(fileURL: fileURL).save([item])

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"createdAt\" : \"2026-10-03T08:00:00Z\""), text)
    }

    func testDatesThatAreNotISO8601StillMakeTheFileCorrupt() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("items.json")
        try writeItemsFile(fileURL, createdAt: "3 October 2026", decideAt: "2026-10-17T07:00:00Z")

        XCTAssertThrowsError(try FileItemPersistence(fileURL: fileURL).load()) { error in
            guard case PersistenceError.corruptFile? = error as? PersistenceError else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    // MARK: Unreadable file that cannot be moved

    func testCorruptFileInAReadOnlyFolderIsLeftInPlace() throws {
        let directory = try makeTempDirectory()
        let folder = directory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("items.json")
        let garbage = Data("this is not json {".utf8)
        try garbage.write(to: fileURL)
        // r-x: the file can be read, but nothing in the folder can be renamed.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }

        XCTAssertThrowsError(try FileItemPersistence(fileURL: fileURL).load()) { error in
            XCTAssertEqual(error as? PersistenceError, .corruptFileNotMoved(fileURL))
            XCTAssertTrue(error.localizedDescription.contains("left untouched"), error.localizedDescription)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), garbage)
        XCTAssertEqual(try contents(of: folder), ["items.json"])
    }

    // MARK: InMemoryItemPersistence

    func testInMemoryPersistenceSavesLoadsAndFailsOnce() throws {
        let persistence = InMemoryItemPersistence()
        XCTAssertEqual(try persistence.load(), [])

        let items = sampleItems()
        try persistence.save(items)
        XCTAssertEqual(try persistence.load(), items)

        persistence.failNextSave = TestError()
        XCTAssertThrowsError(try persistence.save([]))
        XCTAssertNil(persistence.failNextSave)
        XCTAssertEqual(persistence.items.count, 2, "a failed save must not change what is stored")

        try persistence.save([])
        XCTAssertEqual(persistence.items, [])
    }
}
