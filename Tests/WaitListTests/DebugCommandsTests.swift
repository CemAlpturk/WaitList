import XCTest
import WaitListCore
@testable import WaitList

/// The `--debug-add-due-in` and `--debug-dump-data` commands, run against files in a temp directory.
/// stdout and stderr are captured so the tests stay quiet and can check the messages.
final class DebugCommandsTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private var persistence: FileItemPersistence { FileItemPersistence(fileURL: fileURL) }

    override func setUpWithError() throws {
        directory = try makeTempDirectory()
        fileURL = directory.appendingPathComponent("items.json")
    }

    private func sampleItems() -> [Item] {
        let calendar = TestCalendars.stockholm
        return [
            Item(name: "Gorilla Sofa", price: dec("1299.5"), note: "https://example.com/sofa/1",
                 createdAt: date(2025, 10, 1, 9, in: calendar), decideAt: date(2025, 10, 17, 9, in: calendar)),
            Item(name: "Watch", createdAt: date(2025, 9, 1, 9, in: calendar), decideAt: date(2025, 9, 15, 9, in: calendar),
                 outcome: .skipped, decidedAt: date(2025, 9, 10, 12, in: calendar), extensionCount: 2),
        ]
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".corrupt-") }
    }

    // MARK: addItem

    func testAddItemCreatesTheFileWithOneItemDueInTheGivenSeconds() throws {
        let before = Date()
        let (added, output) = try captureOutput {
            DebugCommands.addItem(named: "Test", dueIn: 90, location: .override(fileURL))
        }
        let after = Date()

        XCTAssertTrue(added)
        XCTAssertTrue(output.stdout.hasPrefix("Added “Test”, due "), output.stdout)
        XCTAssertTrue(output.stdout.contains(fileURL.path), output.stdout)
        XCTAssertEqual(output.stderr, "")

        let items = try persistence.load()
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.name, "Test")
        XCTAssertNil(item.price)
        XCTAssertNil(item.note)
        XCTAssertNil(item.outcome)
        XCTAssertEqual(item.extensionCount, 0)
        // Dates are stored as ISO 8601 with whole seconds.
        XCTAssertGreaterThanOrEqual(item.createdAt.timeIntervalSince(before), -1)
        XCTAssertLessThanOrEqual(item.createdAt.timeIntervalSince(after), 0)
        XCTAssertEqual(item.decideAt.timeIntervalSince(item.createdAt), 90, accuracy: 1)
        XCTAssertTrue(item.isWaiting(at: before))
        XCTAssertTrue(item.isDue(at: item.decideAt))
    }

    func testAddItemAppendsAfterExistingItemsAndLeavesThemAlone() throws {
        let existing = sampleItems()
        try persistence.save(existing)

        let (added, _) = try captureOutput {
            DebugCommands.addItem(named: "Third", dueIn: 30, location: .override(fileURL))
        }

        XCTAssertTrue(added)
        let items = try persistence.load()
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Array(items.prefix(2)), existing)
        XCTAssertEqual(items.last?.name, "Third")
        XCTAssertFalse(existing.map(\.id).contains(try XCTUnwrap(items.last).id))
    }

    func testAddingTwiceKeepsBothWithDistinctIDs() throws {
        _ = try captureOutput {
            _ = DebugCommands.addItem(named: "One", dueIn: 10, location: .override(fileURL))
            _ = DebugCommands.addItem(named: "Two", dueIn: 20, location: .override(fileURL))
        }
        let items = try persistence.load()
        XCTAssertEqual(items.map(\.name), ["One", "Two"])
        XCTAssertNotEqual(items[0].id, items[1].id)
    }

    func testAddItemWithNegativeSecondsIsDueImmediately() throws {
        _ = try captureOutput {
            DebugCommands.addItem(named: "Overdue", dueIn: -3_600, location: .override(fileURL))
        }
        let item = try XCTUnwrap(try persistence.load().first)
        XCTAssertTrue(item.isDue(at: Date()))
        XCTAssertLessThan(item.decideAt, item.createdAt)
    }

    func testAddItemKeepsUnicodeNamesIntact() throws {
        _ = try captureOutput {
            DebugCommands.addItem(named: "Kaffekvarn ☕️ “fin” \"quoted\"", dueIn: 5, location: .override(fileURL))
        }
        XCTAssertEqual(try persistence.load().first?.name, "Kaffekvarn ☕️ “fin” \"quoted\"")
    }

    func testAddItemWithoutADataFileFailsAndSaysWhy() throws {
        let (added, output) = try captureOutput {
            DebugCommands.addItem(named: "Test", dueIn: 30, location: .unavailable(reason: "no folder"))
        }
        XCTAssertFalse(added)
        XCTAssertEqual(output.stderr, "WaitList: no data file available, nothing added.\n")
        XCTAssertEqual(output.stdout, "")
    }

    func testAddItemToACorruptFileFailsAndKeepsTheOldFileAsBackup() throws {
        try Data("this is not json".utf8).write(to: fileURL)

        let (added, output) = try captureOutput {
            DebugCommands.addItem(named: "Test", dueIn: 30, location: .override(fileURL))
        }

        XCTAssertFalse(added)
        XCTAssertTrue(output.stderr.hasPrefix("WaitList: could not add debug item: "), output.stderr)
        XCTAssertEqual(output.stdout, "")
        let moved = try backups()
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(try XCTUnwrap(moved.first)),
                                  encoding: .utf8), "this is not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "nothing was written in its place")
    }

    func testAddItemRefusesAFileFromANewerVersionAndLeavesItUntouched() throws {
        let original = Data(#"{"version": 99, "items": []}"#.utf8)
        try original.write(to: fileURL)

        let (added, output) = try captureOutput {
            DebugCommands.addItem(named: "Test", dueIn: 30, location: .override(fileURL))
        }

        XCTAssertFalse(added)
        XCTAssertTrue(output.stderr.contains("newer version"), output.stderr)
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertEqual(try backups(), [])
    }

    func testAddItemReportsAnUnwritableLocation() throws {
        // A regular file where the parent folder should be: the folder cannot be created.
        let blocker = directory.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let target = blocker.appendingPathComponent("items.json")

        let (added, output) = try captureOutput {
            DebugCommands.addItem(named: "Test", dueIn: 30, location: .override(target))
        }

        XCTAssertFalse(added)
        XCTAssertTrue(output.stderr.hasPrefix("WaitList: could not add debug item: "), output.stderr)
    }

    /// A date before the year 0 would be written as "-29662-...", which the loader rejects, so the next launch
    /// would move the whole file (with the user's other items) aside. Such values are refused up front.
    func testAddItemRefusesDueTimesMoreThanTenYearsAway() throws {
        let existing = sampleItems()
        try persistence.save(existing)
        let before = try Data(contentsOf: fileURL)

        for seconds in [-1e12, 1e12, LaunchOptions.debugAddMaxSeconds + 1, -.infinity, .nan] {
            let (added, output) = try captureOutput {
                DebugCommands.addItem(named: "Ancient", dueIn: seconds, location: .override(fileURL))
            }
            XCTAssertFalse(added, "\(seconds)")
            XCTAssertEqual(output.stderr, "WaitList: due time out of range (more than 10 years away), nothing added.\n")
            XCTAssertEqual(output.stdout, "")
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), before, "the file is untouched")
        XCTAssertEqual(try persistence.load(), existing)
    }

    func testAddItemAtTheTenYearLimitCanBeReadBack() throws {
        for seconds in [LaunchOptions.debugAddMaxSeconds, -LaunchOptions.debugAddMaxSeconds] {
            let (added, _) = try captureOutput {
                DebugCommands.addItem(named: "Far", dueIn: seconds, location: .override(fileURL))
            }
            XCTAssertTrue(added)
        }
        XCTAssertEqual(try persistence.load().count, 2)
    }

    // MARK: dumpItems

    func testDumpPrintsTheItemsAsPrettyJSONAndReturnsZero() throws {
        let items = sampleItems()
        try persistence.save(items)
        let before = try Data(contentsOf: fileURL)

        let (code, output) = try captureOutput { DebugCommands.dumpItems(location: .override(fileURL)) }

        XCTAssertEqual(code, 0)
        XCTAssertEqual(output.stderr, "")
        XCTAssertTrue(output.stdout.hasSuffix("\n"))
        XCTAssertTrue(output.stdout.contains("\n  {\n    \"createdAt\""), "pretty printed, sorted keys:\n\(output.stdout)")

        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(array.compactMap { $0["name"] as? String }, ["Gorilla Sofa", "Watch"])
        XCTAssertEqual(array[0]["id"] as? String, items[0].id.uuidString)
        XCTAssertEqual(array[0]["note"] as? String, "https://example.com/sofa/1")
        XCTAssertEqual(array[0]["createdAt"] as? String, "2025-10-01T07:00:00Z", "ISO 8601, UTC")
        XCTAssertEqual(array[0]["decideAt"] as? String, "2025-10-17T07:00:00Z")
        XCTAssertEqual(array[0]["extensionCount"] as? Int, 0)
        XCTAssertNil(array[0]["outcome"])
        XCTAssertEqual(array[1]["outcome"] as? String, "skipped")
        XCTAssertEqual(array[1]["decidedAt"] as? String, "2025-09-10T10:00:00Z")
        XCTAssertEqual(array[1]["extensionCount"] as? Int, 2)

        XCTAssertEqual(try Data(contentsOf: fileURL), before, "dumping never changes the file")
    }

    func testDumpKeepsSlashesAndPriceReadable() throws {
        try persistence.save(sampleItems())
        let (_, output) = try captureOutput { DebugCommands.dumpItems(location: .override(fileURL)) }
        XCTAssertTrue(output.stdout.contains("\"https://example.com/sofa/1\""), "slashes are not escaped")
        XCTAssertTrue(output.stdout.contains("\"price\" : 1299.5"), output.stdout)
    }

    func testDumpOfAMissingFilePrintsAnEmptyListAndCreatesNothing() throws {
        let (code, output) = try captureOutput { DebugCommands.dumpItems(location: .override(fileURL)) }
        XCTAssertEqual(code, 0)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [Any])
        XCTAssertTrue(array.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDumpWithoutADataFileFailsAndSaysWhy() throws {
        let (code, output) = try captureOutput {
            DebugCommands.dumpItems(location: .unavailable(reason: "no folder"))
        }
        XCTAssertEqual(code, 1)
        XCTAssertEqual(output.stderr, "WaitList: no data file available.\n")
        XCTAssertEqual(output.stdout, "")
    }

    func testDumpOfACorruptFileFailsMentionsThePathAndMovesTheFileAside() throws {
        try Data("{ broken".utf8).write(to: fileURL)

        let (code, output) = try captureOutput { DebugCommands.dumpItems(location: .override(fileURL)) }

        XCTAssertEqual(code, 1)
        XCTAssertTrue(output.stderr.hasPrefix("WaitList: could not read \(fileURL.path): "), output.stderr)
        XCTAssertEqual(output.stdout, "")
        XCTAssertEqual(try backups().count, 1)
    }

    func testDumpOfAFileFromANewerVersionFailsAndLeavesItUntouched() throws {
        let original = Data(#"{"version": 2, "items": []}"#.utf8)
        try original.write(to: fileURL)

        let (code, output) = try captureOutput { DebugCommands.dumpItems(location: .override(fileURL)) }

        XCTAssertEqual(code, 1)
        XCTAssertTrue(output.stderr.contains("newer version"), output.stderr)
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    // MARK: Round trip

    func testWhatAddItemWritesDumpItemsCanRead() throws {
        _ = try captureOutput {
            DebugCommands.addItem(named: "Round trip", dueIn: 60, location: .override(fileURL))
        }
        let (code, output) = try captureOutput { DebugCommands.dumpItems(location: .override(fileURL)) }
        XCTAssertEqual(code, 0)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["name"] as? String, "Round trip")
    }
}
