import Foundation
import XCTest
@testable import WaitListCore

/// Fixed calendar and date helpers so tests do not depend on the machine's time zone or clock.
enum TestDates {
    static let stockholm: Calendar = {
        guard let timeZone = TimeZone(identifier: "Europe/Stockholm") else {
            preconditionFailure("Europe/Stockholm time zone missing")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    /// A date in Europe/Stockholm local time.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                     _ second: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day,
                                        hour: hour, minute: minute, second: second)
        guard let date = stockholm.date(from: components) else {
            preconditionFailure("Invalid test date \(components)")
        }
        return date
    }

    /// Year, month, day, hour, minute of `date` in Europe/Stockholm local time.
    static func parts(_ date: Date) -> [Int] {
        let c = stockholm.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return [c.year ?? -1, c.month ?? -1, c.day ?? -1, c.hour ?? -1, c.minute ?? -1]
    }
}

/// A decimal from a string literal, exactly (Decimal(19.99) would go through Double and be inexact).
func dec(_ string: String) -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        preconditionFailure("Invalid decimal \(string)")
    }
    return value
}

struct TestError: Error, LocalizedError {
    var message = "disk full"
    var errorDescription: String? { message }
}

extension XCTestCase {
    /// A UserDefaults suite unique to this test, deleted when the test ends.
    func makeTestDefaults() throws -> UserDefaults {
        let suiteName = "WaitListCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            // removePersistentDomain leaves an empty plist in ~/Library/Preferences; delete it too.
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suiteName).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        return defaults
    }

    /// A fresh temporary directory, deleted when the test ends.
    func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaitListCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
