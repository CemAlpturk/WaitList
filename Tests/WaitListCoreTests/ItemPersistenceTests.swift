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

    func testDefaultFileURLIsInApplicationSupport() throws {
        let url = try FileItemPersistence.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, "items.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "WaitList")
        XCTAssertTrue(url.path.contains("Application Support"), url.path)
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
