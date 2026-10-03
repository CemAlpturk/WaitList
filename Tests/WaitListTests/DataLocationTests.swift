import XCTest
import WaitListCore
@testable import WaitList

final class DataLocationTests: XCTestCase {
    private func resolve(_ value: String?) -> DataLocation {
        DataLocation.resolve(environment: value.map { [DataLocation.environmentKey: $0] } ?? [:])
    }

    private func assertOverride(_ location: DataLocation, path expected: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard case .override(let url) = location else {
            return XCTFail("expected .override, got \(location)", file: file, line: line)
        }
        XCTAssertEqual(url.path, expected, file: file, line: line)
        XCTAssertTrue(url.isFileURL, file: file, line: line)
        XCTAssertFalse(url.hasDirectoryPath, file: file, line: line)
    }

    func testEnvironmentKeyIsTheDocumentedOne() {
        XCTAssertEqual(DataLocation.environmentKey, "WAITLIST_DATA_FILE")
    }

    // MARK: Override

    func testEnvironmentVariableOverridesTheDataFile() {
        let location = resolve("/opt/waitlist-test/items.json")
        assertOverride(location, path: "/opt/waitlist-test/items.json")
        XCTAssertEqual(location.fileURL?.path, "/opt/waitlist-test/items.json")
    }

    func testOverridePathIsTrimmed() {
        assertOverride(resolve("  /opt/waitlist-test/items.json \n"), path: "/opt/waitlist-test/items.json")
    }

    func testOverridePathExpandsTilde() {
        let expected = URL(fileURLWithPath: NSHomeDirectory() + "/waitlist-test.json").standardizedFileURL.path
        assertOverride(resolve("~/waitlist-test.json"), path: expected)
    }

    func testOverridePathIsStandardized() {
        assertOverride(resolve("/opt/a/../waitlist-test/./items.json"), path: "/opt/waitlist-test/items.json")
    }

    func testRelativeOverridePathBecomesAbsolute() {
        guard case .override(let url) = resolve("build/test.json") else { return XCTFail("expected .override") }
        XCTAssertTrue(url.path.hasPrefix("/"))
        XCTAssertTrue(url.path.hasSuffix("/build/test.json"))
    }

    func testOverridePathWithSpaces() {
        assertOverride(resolve("/opt/my data/items file.json"), path: "/opt/my data/items file.json")
    }

    func testOverrideIsNotCreatedOrTouchedByResolving() throws {
        let directory = try makeTempDirectory()
        let file = directory.appendingPathComponent("not-yet.json")
        _ = resolve(file.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    // MARK: Standard

    /// An empty or missing variable means the standard location. Resolving it creates
    /// ~/Library/Application Support/WaitList if missing, so the test only runs when that folder exists.
    func testMissingOrBlankVariableMeansTheStandardLocation() throws {
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
                                                              in: .userDomainMask).first)
        let folder = support.appendingPathComponent("WaitList", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path),
                          "would create \(folder.path); resolving the standard location is not tested here")

        for value in [nil, "", "   ", "\n\t "] {
            guard case .standard(let url) = resolve(value) else {
                return XCTFail("expected .standard for \(String(describing: value))")
            }
            XCTAssertEqual(url.lastPathComponent, "items.json")
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "WaitList")
            XCTAssertEqual(url.standardizedFileURL.path, folder.appendingPathComponent("items.json").standardizedFileURL.path)
        }
    }

    // MARK: fileURL

    func testFileURLOfEachCase() throws {
        let url = URL(fileURLWithPath: "/opt/x/items.json")
        XCTAssertEqual(DataLocation.standard(url).fileURL, url)
        XCTAssertEqual(DataLocation.override(url).fileURL, url)
        XCTAssertNil(DataLocation.unavailable(reason: "disk full").fileURL)
    }
}
