import XCTest
@testable import WaitList

final class LaunchOptionsTests: XCTestCase {
    private func parse(_ arguments: [String]) throws -> LaunchOptions {
        try LaunchOptions.parse(arguments)
    }

    private func assertUsageError(_ arguments: [String], contains fragment: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try LaunchOptions.parse(arguments), "\(arguments)", file: file, line: line) { error in
            XCTAssertTrue(error is LaunchOptions.UsageError, "\(error)", file: file, line: line)
            XCTAssertTrue(error.localizedDescription.contains(fragment),
                          "\(error.localizedDescription) should contain \(fragment)", file: file, line: line)
        }
    }

    // MARK: Defaults and unknown arguments

    func testNoArgumentsMeansNormalLaunch() throws {
        let options = try parse([])
        XCTAssertNil(options.snapshotDirectory)
        XCTAssertNil(options.debugAdd)
        XCTAssertFalse(options.debugDump)
    }

    func testUnknownArgumentsAreIgnored() throws {
        // Finder and Xcode add their own flags, e.g. -NSDocumentRevisionsDebugMode YES.
        let options = try parse(["-NSDocumentRevisionsDebugMode", "YES", "--unknown", "-psn_0_12345", "", "positional"])
        XCTAssertNil(options.snapshotDirectory)
        XCTAssertNil(options.debugAdd)
        XCTAssertFalse(options.debugDump)
    }

    func testFlagNamesAreCaseSensitive() throws {
        let options = try parse(["--DEBUG-DUMP-DATA", "--Snapshot", "/tmp/x"])
        XCTAssertFalse(options.debugDump)
        XCTAssertNil(options.snapshotDirectory)
    }

    // MARK: --debug-dump-data

    func testDebugDumpFlag() throws {
        XCTAssertTrue(try parse(["--debug-dump-data"]).debugDump)
        XCTAssertTrue(try parse(["--foo", "--debug-dump-data", "--bar"]).debugDump)
    }

    // MARK: --snapshot

    func testSnapshotDirectoryIsAnAbsoluteStandardizedDirectoryURL() throws {
        let url = try XCTUnwrap(try parse(["--snapshot", "/opt/waitlist-snaps"]).snapshotDirectory)
        XCTAssertEqual(url.path, "/opt/waitlist-snaps")
        XCTAssertTrue(url.isFileURL)
        XCTAssertTrue(url.hasDirectoryPath)

        let messy = try XCTUnwrap(try parse(["--snapshot", "/opt/a/../waitlist-snaps/./out/"]).snapshotDirectory)
        XCTAssertEqual(messy.path, "/opt/waitlist-snaps/out")
    }

    func testSnapshotDirectoryExpandsTilde() throws {
        let url = try XCTUnwrap(try parse(["--snapshot", "~/waitlist-snaps"]).snapshotDirectory)
        XCTAssertEqual(url.path, URL(fileURLWithPath: NSHomeDirectory() + "/waitlist-snaps").standardizedFileURL.path)
        XCTAssertFalse(url.path.contains("~"))
    }

    func testSnapshotRelativePathBecomesAbsolute() throws {
        let url = try XCTUnwrap(try parse(["--snapshot", "build/snaps"]).snapshotDirectory)
        XCTAssertTrue(url.path.hasPrefix("/"))
        XCTAssertTrue(url.path.hasSuffix("/build/snaps"))
    }

    func testSnapshotPathWithSpaces() throws {
        let url = try XCTUnwrap(try parse(["--snapshot", "/opt/my snaps/light and dark"]).snapshotDirectory)
        XCTAssertEqual(url.path, "/opt/my snaps/light and dark")
    }

    func testSnapshotWithoutDirectoryIsAUsageError() {
        assertUsageError(["--snapshot"], contains: "--snapshot needs an output directory")
        assertUsageError(["--debug-dump-data", "--snapshot"], contains: "--snapshot")
    }

    func testTheLastSnapshotFlagWins() throws {
        let url = try XCTUnwrap(try parse(["--snapshot", "/opt/one", "--snapshot", "/opt/two"]).snapshotDirectory)
        XCTAssertEqual(url.path, "/opt/two")
    }

    // MARK: --debug-add-due-in

    func testDebugAddParsesSecondsAndName() throws {
        let request = try XCTUnwrap(try parse(["--debug-add-due-in", "30", "Test"]).debugAdd)
        XCTAssertEqual(request.seconds, 30)
        XCTAssertEqual(request.name, "Test")
    }

    func testDebugAddNameIsTrimmedButOtherwiseKept() throws {
        XCTAssertEqual(try parse(["--debug-add-due-in", "5", "  Gorilla Sofa \n"]).debugAdd?.name, "Gorilla Sofa")
        XCTAssertEqual(try parse(["--debug-add-due-in", "5", "Two  words"]).debugAdd?.name, "Two  words")
        XCTAssertEqual(try parse(["--debug-add-due-in", "5", "Kaffekvarn ☕️ “fin”"]).debugAdd?.name,
                       "Kaffekvarn ☕️ “fin”")
    }

    func testDebugAddAcceptsFractionalNegativeAndExponentSeconds() throws {
        XCTAssertEqual(try parse(["--debug-add-due-in", "0.5", "x"]).debugAdd?.seconds, 0.5)
        XCTAssertEqual(try parse(["--debug-add-due-in", "0", "x"]).debugAdd?.seconds, 0)
        XCTAssertEqual(try parse(["--debug-add-due-in", "-60", "x"]).debugAdd?.seconds, -60, "already due")
        XCTAssertEqual(try parse(["--debug-add-due-in", "1e3", "x"]).debugAdd?.seconds, 1000)
        XCTAssertEqual(try parse(["--debug-add-due-in", "86400", "x"]).debugAdd?.seconds, 86_400)
    }

    func testDebugAddRejectsNonNumericOrNonFiniteSeconds() {
        let usage = "usage: --debug-add-due-in <seconds> <name>"
        for seconds in ["abc", "", "30s", "1,5", "nan", "NaN", "inf", "-inf", "infinity", "1e999"] {
            assertUsageError(["--debug-add-due-in", seconds, "Name"], contains: usage)
        }
    }

    func testDebugAddAcceptsUpToTenYearsEitherWay() throws {
        let tenYears = LaunchOptions.debugAddMaxSeconds
        XCTAssertEqual(tenYears, 315_576_000)
        XCTAssertEqual(try parse(["--debug-add-due-in", "315576000", "x"]).debugAdd?.seconds, tenYears)
        XCTAssertEqual(try parse(["--debug-add-due-in", "-315576000", "x"]).debugAdd?.seconds, -tenYears)
    }

    /// Larger values used to write dates the data file cannot hold (before year 0 for -1e12), so the next
    /// launch moved the whole file aside as unreadable. Main exits with 64 (EX_USAGE) on this error.
    func testDebugAddRejectsMoreThanTenYearsEitherWay() {
        for seconds in ["315576001", "-315576001", "1e12", "-1e12", "1e300", "-1.7e308"] {
            assertUsageError(["--debug-add-due-in", seconds, "Name"], contains: "within ±315576000 (10 years)")
        }
    }

    func testDebugAddWithMissingArgumentsIsAUsageError() {
        let usage = "usage: --debug-add-due-in <seconds> <name>"
        assertUsageError(["--debug-add-due-in"], contains: usage)
        assertUsageError(["--debug-add-due-in", "30"], contains: usage)
        assertUsageError(["--debug-dump-data", "--debug-add-due-in", "30"], contains: usage)
    }

    func testDebugAddWithBlankNameIsAUsageError() {
        for name in ["", " ", "\t\n", "\u{00A0}"] {
            assertUsageError(["--debug-add-due-in", "30", name], contains: "needs a non-empty name")
        }
    }

    func testTheLastDebugAddWins() throws {
        let request = try XCTUnwrap(try parse(["--debug-add-due-in", "1", "First", "--debug-add-due-in", "2", "Second"])
            .debugAdd)
        XCTAssertEqual(request.seconds, 2)
        XCTAssertEqual(request.name, "Second")
    }

    // MARK: Combinations

    func testFlagsCombineInAnyOrder() throws {
        let a = try parse(["--debug-add-due-in", "30", "Test", "--debug-dump-data"])
        XCTAssertEqual(a.debugAdd?.name, "Test")
        XCTAssertTrue(a.debugDump)
        let b = try parse(["--debug-dump-data", "--snapshot", "/opt/s", "--debug-add-due-in", "30", "Test"])
        XCTAssertEqual(b.debugAdd?.seconds, 30)
        XCTAssertTrue(b.debugDump)
        XCTAssertEqual(b.snapshotDirectory?.path, "/opt/s")
    }

    func testUnknownArgumentsBetweenFlagsDoNotDisturbThem() throws {
        let options = try parse(["-x", "--debug-add-due-in", "30", "Test", "-y", "--debug-dump-data", "z"])
        XCTAssertEqual(options.debugAdd?.name, "Test")
        XCTAssertTrue(options.debugDump)
    }

    func testFlagValuesAreConsumedEvenWhenTheyLookLikeFlags() throws {
        // `--debug-add-due-in 30 --debug-dump-data` adds an item *named* "--debug-dump-data" and does not dump.
        // Documents the positional behaviour; a missing name is not detected when another flag follows.
        let options = try parse(["--debug-add-due-in", "30", "--debug-dump-data"])
        XCTAssertEqual(options.debugAdd?.name, "--debug-dump-data")
        XCTAssertFalse(options.debugDump)

        let snapshot = try parse(["--snapshot", "--debug-dump-data"])
        XCTAssertEqual(snapshot.snapshotDirectory?.lastPathComponent, "--debug-dump-data")
        XCTAssertFalse(snapshot.debugDump)
    }

    func testAnErrorInAnyFlagFailsTheWholeParse() {
        assertUsageError(["--debug-dump-data", "--debug-add-due-in", "soon", "Test"], contains: "usage")
    }

    // MARK: Single instance

    func testOnlyRunsThatShowTheAppCheckForAnotherCopy() throws {
        XCTAssertTrue(try parse([]).launchesApp)
        XCTAssertTrue(try parse(["--debug-add-due-in", "30", "Test"]).launchesApp, "adds, then launches normally")
        XCTAssertFalse(try parse(["--snapshot", "/opt/s"]).launchesApp)
        XCTAssertFalse(try parse(["--debug-dump-data"]).launchesApp)
        XCTAssertFalse(try parse(["--debug-add-due-in", "30", "Test", "--debug-dump-data"]).launchesApp)
    }

    // MARK: UsageError

    func testUsageErrorCarriesItsMessage() {
        let error = LaunchOptions.UsageError("something is wrong")
        XCTAssertEqual(error.errorDescription, "something is wrong")
        XCTAssertEqual(error.localizedDescription, "something is wrong")
    }
}
