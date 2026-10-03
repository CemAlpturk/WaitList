import Foundation
import XCTest

/// Fixed calendars and date helpers so tests do not depend on the machine's clock.
///
/// `Format.shortDate` and `Format.time` render in the system time zone and locale (their APIs take neither),
/// so tests that look at those strings build their dates with `TestCalendars.system`, and only compare
/// digits, never month or weekday names. Tests that only count calendar days use fixed zones.
enum TestCalendars {
    /// Gregorian, in the machine's time zone.
    static let system: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static let stockholm = gregorian("Europe/Stockholm")
    static let utc = gregorian("UTC")
    static let auckland = gregorian("Pacific/Auckland")

    static func gregorian(_ identifier: String) -> Calendar {
        guard let timeZone = TimeZone(identifier: identifier) else {
            preconditionFailure("\(identifier) time zone missing")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// A date in `calendar`'s time zone.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
          in calendar: Calendar) -> Date {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    guard let date = calendar.date(from: components) else {
        preconditionFailure("Invalid test date \(components)")
    }
    return date
}

/// A decimal from a string literal, exactly (Decimal(19.99) would go through Double and be inexact).
func dec(_ string: String) -> Decimal {
    guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
        preconditionFailure("Invalid decimal \(string)")
    }
    return value
}

/// Only the decimal digits of `text`, as ASCII ("1 299,50 kr" -> "129950", Arabic-Indic digits included).
/// Lets tests check formatted output without depending on the locale's separators, currency symbol or digit
/// script. Numerals that are letters in disguise (CJK "五") are not digits.
func digits(_ text: String) -> String {
    text.filter { $0.unicodeScalars.first?.properties.numericType == .decimal }
        .compactMap(\.wholeNumberValue).map(String.init).joined()
}

struct TestError: Error, LocalizedError {
    var message = "disk full"
    var errorDescription: String? { message }
}

struct CapturedOutput {
    var stdout = ""
    var stderr = ""
}

extension XCTestCase {
    /// A UserDefaults store unique to this test. Its suite name is a path inside a temp directory, so the
    /// preferences plist is written there (and deleted with it) instead of into ~/Library/Preferences,
    /// where `removePersistentDomain` leaves a stale file behind.
    func makeTestDefaults() throws -> UserDefaults {
        let directory = try makeTempDirectory()
        let suiteName = directory.appendingPathComponent("defaults").path
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    /// A fresh temporary directory, deleted when the test ends.
    func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaitListTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    /// Runs `body` with the process's stdout and stderr redirected into files in a temp directory,
    /// and returns what it wrote. Do not assert inside `body`: failures would be swallowed with the output.
    func captureOutput<T>(_ body: () throws -> T) throws -> (result: T, output: CapturedOutput) {
        let directory = try makeTempDirectory()
        let outURL = directory.appendingPathComponent("stdout.txt")
        let errURL = directory.appendingPathComponent("stderr.txt")
        let flags = O_WRONLY | O_CREAT | O_TRUNC
        let outFD = open(outURL.path, flags, 0o600)
        let errFD = open(errURL.path, flags, 0o600)
        guard outFD >= 0, errFD >= 0 else {
            throw TestError(message: "could not open capture files")
        }

        fflush(stdout)
        fflush(stderr)
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        dup2(outFD, STDOUT_FILENO)
        dup2(errFD, STDERR_FILENO)

        let result = Result { try body() }

        fflush(stdout)
        fflush(stderr)
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        close(savedOut)
        close(savedErr)
        close(outFD)
        close(errFD)

        let output = CapturedOutput(stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
                                    stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "")
        return (try result.get(), output)
    }
}
