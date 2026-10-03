import XCTest
import WaitListCore
@testable import WaitList

/// `Format.price`, `shortDate`, `time` and `editablePrice` use the current locale (their APIs take none),
/// so assertions about them look at digits and structure, never at separators, symbols or month names.
/// The suite passes under any locale; run it with `xcrun xctest -AppleLocale sv_SE ...` to check.
final class FormatTests: XCTestCase {
    private let system = TestCalendars.system
    private let stockholm = TestCalendars.stockholm

    private func item(created: Date, decideAt: Date, decidedAt: Date? = nil) -> Item {
        Item(name: "Thing", createdAt: created, decideAt: decideAt,
             outcome: decidedAt == nil ? nil : .skipped, decidedAt: decidedAt)
    }

    // MARK: days

    func testDaysUsesSingularOnlyForOne() {
        XCTAssertEqual(Format.days(1), "1 day")
        XCTAssertEqual(Format.days(0), "0 days")
        XCTAssertEqual(Format.days(2), "2 days")
        XCTAssertEqual(Format.days(14), "14 days")
        XCTAssertEqual(Format.days(365), "365 days")
        XCTAssertEqual(Format.days(1_000_000), "1000000 days")
        XCTAssertEqual(Format.days(Int.max), "\(Int.max) days")
    }

    func testDaysDoesNotClampNegativeCounts() {
        // Callers pass counts that are already clamped to >= 0 (Item.daysLeft / daysWaited).
        XCTAssertEqual(Format.days(-1), "-1 days")
    }

    // MARK: price

    func testWholeAmountsHaveNoDecimals() {
        XCTAssertEqual(digits(Format.price(1299, currencyCode: "SEK")), "1299")
        XCTAssertEqual(digits(Format.price(dec("1299.00"), currencyCode: "SEK")), "1299")
        XCTAssertEqual(digits(Format.price(1, currencyCode: "USD")), "1")
        XCTAssertEqual(digits(Format.price(0, currencyCode: "EUR")), "0")
        XCTAssertEqual(digits(Format.price(1_000_000, currencyCode: "SEK")), "1000000")
        XCTAssertEqual(digits(Format.price(dec("1E3"), currencyCode: "SEK")), "1000")
    }

    func testFractionalAmountsShowTwoDecimals() {
        XCTAssertEqual(digits(Format.price(dec("19.99"), currencyCode: "SEK")), "1999")
        XCTAssertEqual(digits(Format.price(dec("1299.5"), currencyCode: "SEK")), "129950")
        XCTAssertEqual(digits(Format.price(dec("0.5"), currencyCode: "USD")), "050")
        XCTAssertEqual(digits(Format.price(dec("1234567.89"), currencyCode: "EUR")), "123456789")
    }

    func testWholeAndFractionalAmountsLookDifferent() {
        XCTAssertNotEqual(Format.price(20, currencyCode: "SEK"), Format.price(dec("20.5"), currencyCode: "SEK"))
        XCTAssertLessThan(Format.price(20, currencyCode: "SEK").count, Format.price(dec("20.5"), currencyCode: "SEK").count)
    }

    func testPriceMentionsTheCurrency() {
        // The symbol depends on the locale ("kr", "SEK", "$", "US$"), but there is always one.
        for code in ["SEK", "USD", "EUR", "JPY"] {
            let text = Format.price(1299, currencyCode: code)
            XCTAssertTrue(text.contains { $0.isLetter || $0.isCurrencySymbol }, "\(code): \(text)")
        }
        XCTAssertNotEqual(Format.price(1299, currencyCode: "SEK"), Format.price(1299, currencyCode: "JPY"))
        XCTAssertNotEqual(Format.price(1299, currencyCode: "SEK"), Format.price(1299, currencyCode: "EUR"))
    }

    func testNegativeAmountsAreMarked() {
        let text = Format.price(-5, currencyCode: "SEK")
        XCTAssertEqual(digits(text), "5")
        XCTAssertTrue(text.contains("-") || text.contains("\u{2212}") || text.contains("("), text)
    }

    func testCurrenciesWithoutDecimalsRoundFractionalAmounts() {
        XCTAssertEqual(digits(Format.price(dec("19.99"), currencyCode: "JPY")), "20")
        XCTAssertEqual(digits(Format.price(1299, currencyCode: "JPY")), "1299")
    }

    func testVeryLargeAmountsKeepEveryDigit() {
        XCTAssertEqual(digits(Format.price(dec("12345678901234567890"), currencyCode: "SEK")),
                       "12345678901234567890")
        XCTAssertEqual(digits(Format.price(dec("9007199254740993"), currencyCode: "SEK")), "9007199254740993")
        let thirtyEightNines = String(repeating: "9", count: 38)
        XCTAssertEqual(digits(Format.price(dec(thirtyEightNines), currencyCode: "SEK")), thirtyEightNines)
        XCTAssertEqual(digits(Format.price(dec(thirtyEightNines + ".5"), currencyCode: "USD")),
                       String(repeating: "9", count: 38))   // Decimal has 38 digits, so ".5" is rounded away
    }

    func testExtremeAmountsDoNotCrash() {
        XCTAssertFalse(Format.price(Decimal.greatestFiniteMagnitude, currencyCode: "SEK").isEmpty)
        XCTAssertFalse(Format.price(-Decimal.greatestFiniteMagnitude, currencyCode: "SEK").isEmpty)
        XCTAssertFalse(Format.price(Decimal.leastNonzeroMagnitude, currencyCode: "SEK").isEmpty)
        XCTAssertFalse(Format.price(Decimal.nan, currencyCode: "SEK").isEmpty)
    }

    func testUnusualCurrencyCodesStillFormatTheNumber() {
        XCTAssertEqual(digits(Format.price(5, currencyCode: "sek")), "5")   // case-insensitive
        XCTAssertEqual(digits(Format.price(5, currencyCode: "ZZZ")), "5")   // unknown code
        XCTAssertEqual(digits(Format.price(dec("5.5"), currencyCode: "XXX")), "550")
    }

    // MARK: editablePrice

    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    func testEditablePriceHasNoGrouping() {
        XCTAssertEqual(digits(Format.editablePrice(1_234_567)), "1234567")
        let text = Format.editablePrice(1_234_567)
        XCTAssertTrue(text.allSatisfy { $0.wholeNumberValue != nil }, "only digits, no separators: \(text)")
    }

    func testEditablePriceUsesTheLocalesDecimalSeparatorAndDropsTrailingZeros() {
        let separator = decimalSeparator
        XCTAssertEqual(digits(Format.editablePrice(1299)), "1299")
        XCTAssertEqual(Format.editablePrice(1299).count, 4, "no decimal separator for whole amounts")
        XCTAssertEqual(Format.editablePrice(dec("1299.00")).count, 4)
        XCTAssertEqual(digits(Format.editablePrice(dec("1299.5"))), "12995")
        XCTAssertTrue(Format.editablePrice(dec("1299.5")).contains(separator))
        XCTAssertEqual(Format.editablePrice(dec("1299.5")).count, 4 + separator.count + 1)
        XCTAssertEqual(digits(Format.editablePrice(dec("19.99"))), "1999")
        XCTAssertEqual(Format.editablePrice(dec("19.99")).count, 2 + separator.count + 2)
        XCTAssertEqual(digits(Format.editablePrice(dec("0.5"))), "05")
        XCTAssertEqual(digits(Format.editablePrice(0)), "0")
    }

    func testEditablePriceRoundsToTwoDecimals() {
        XCTAssertEqual(digits(Format.editablePrice(dec("1.004"))), "1")
        XCTAssertEqual(digits(Format.editablePrice(dec("1.006"))), "101")
        XCTAssertEqual(digits(Format.editablePrice(dec("1.999"))), "2")
    }

    func testEditablePriceOfNegativeAmountKeepsTheSign() {
        let text = Format.editablePrice(dec("-5.5"))
        XCTAssertEqual(digits(text), "55")
        XCTAssertTrue(text.contains("-") || text.contains("\u{2212}"), text)
    }

    func testEditablePriceParsesBackToTheSameValueInTheCurrentLocale() throws {
        // The Add/Edit screen fills the field with editablePrice and reads it back with PriceInput.parse(text).
        // Locales with non-ASCII digits (ar_EG, fa_IR) do not round-trip; see PriceInputTests. Negative prices
        // are left out: the screen refuses to save them, so they are never shown for editing.
        try XCTSkipIf(Decimal(123).formatted(.number.grouping(.never)) != "123", "locale uses non-ASCII digits")
        for text in ["0", "1", "0.01", "0.5", "19.99", "1299", "1299.5", "12345.67", "1234567.89",
                     "9999999999.99"] {
            let value = dec(text)
            XCTAssertEqual(PriceInput.parse(Format.editablePrice(value)), .value(value), text)
        }
    }

    /// PriceInput accepts any number of decimals but editablePrice shows at most two (Formatting.swift:58),
    /// so opening an item priced 1.005 and saving it unchanged would store 1.
    func testKnownIssueEditingAPriceWithMoreThanTwoDecimalsChangesIt() {
        let shown = Format.editablePrice(dec("1.005"))
        XCTExpectFailure("editablePrice rounds 1.005 to \(shown)") {
            XCTAssertEqual(PriceInput.parse(shown), .value(dec("1.005")))
        }
    }

    // MARK: shortDate and time

    func testShortDateShowsTheDayOfMonth() throws {
        // Persian and Islamic calendars number the days differently.
        try XCTSkipUnless([.gregorian, .buddhist, .japanese, .republicOfChina, .iso8601]
            .contains(Calendar.current.identifier), "\(Calendar.current.identifier) is not day-compatible with Gregorian")
        // Month and weekday may be names or numbers depending on the locale ("Fri 17 Oct", "10月17日(金)"),
        // so only check that the day number is there and that no year is.
        for (y, m, d) in [(2025, 10, 17), (2025, 1, 5), (2026, 12, 31), (2024, 2, 29)] {
            let text = Format.shortDate(date(y, m, d, 12, in: system))
            XCTAssertTrue(digits(text).contains(String(d)), "\(d): \(text)")
            XCTAssertFalse(digits(text).contains(String(y)), "no year: \(text)")
        }
    }

    func testShortDateIsTheSameForAnyTimeOfDay() {
        let morning = Format.shortDate(date(2025, 10, 17, 0, 0, in: system))
        XCTAssertEqual(morning, Format.shortDate(date(2025, 10, 17, 23, 59, in: system)))
        XCTAssertNotEqual(morning, Format.shortDate(date(2025, 10, 18, 0, 0, in: system)))
    }

    func testTimeShowsHourAndMinute() {
        XCTAssertTrue(digits(Format.time(date(2025, 10, 17, 9, 5, in: system))).hasSuffix("905"))
        let afternoon = digits(Format.time(date(2025, 10, 17, 13, 7, in: system)))
        XCTAssertTrue(["1307", "107"].contains(afternoon), "24-hour or 12-hour clock: \(afternoon)")
        XCTAssertNotEqual(Format.time(date(2025, 10, 17, 9, 0, in: system)),
                          Format.time(date(2025, 10, 17, 9, 1, in: system)))
        XCTAssertEqual(Format.time(date(2025, 10, 17, 9, 0, 0, in: system)),
                       Format.time(date(2025, 10, 17, 9, 0, 59, in: system)), "seconds are not shown")
    }

    // MARK: waited

    func testWaitedSaysAddedTodayOnTheSameDay() {
        let created = date(2025, 10, 17, 8, 0, in: stockholm)
        let thing = item(created: created, decideAt: date(2025, 10, 31, 9, in: stockholm))
        XCTAssertEqual(Format.waited(thing, now: created, calendar: stockholm), "Added today")
        XCTAssertEqual(Format.waited(thing, now: date(2025, 10, 17, 23, 59, in: stockholm), calendar: stockholm),
                       "Added today")
    }

    func testWaitedCountsCalendarDaysNotHours() {
        let thing = item(created: date(2025, 10, 17, 23, 59, in: stockholm),
                         decideAt: date(2025, 10, 31, 9, in: stockholm))
        XCTAssertEqual(Format.waited(thing, now: date(2025, 10, 18, 0, 1, in: stockholm), calendar: stockholm),
                       "Waited 1 day")
        XCTAssertEqual(Format.waited(thing, now: date(2025, 10, 19, 0, 1, in: stockholm), calendar: stockholm),
                       "Waited 2 days")
        XCTAssertEqual(Format.waited(thing, now: date(2025, 10, 31, 12, in: stockholm), calendar: stockholm),
                       "Waited 14 days")
    }

    func testWaitedStopsCountingOnceDecided() {
        let thing = item(created: date(2025, 10, 1, 12, in: stockholm),
                         decideAt: date(2025, 10, 15, 9, in: stockholm),
                         decidedAt: date(2025, 10, 4, 18, in: stockholm))
        XCTAssertEqual(Format.waited(thing, now: date(2026, 3, 1, in: stockholm), calendar: stockholm),
                       "Waited 3 days")
    }

    func testWaitedNeverGoesNegative() {
        let thing = item(created: date(2025, 10, 20, 12, in: stockholm),
                         decideAt: date(2025, 11, 3, 9, in: stockholm))
        XCTAssertEqual(Format.waited(thing, now: date(2025, 10, 17, 12, in: stockholm), calendar: stockholm),
                       "Added today", "a clock set back after adding the item")
    }

    func testWaitedAcrossDaylightSavingChange() {
        // Europe/Stockholm: clocks went back on 2025-10-26, so that day has 25 hours.
        let thing = item(created: date(2025, 10, 25, 12, in: stockholm),
                         decideAt: date(2025, 11, 8, 9, in: stockholm))
        XCTAssertEqual(Format.waited(thing, now: date(2025, 10, 27, 12, in: stockholm), calendar: stockholm),
                       "Waited 2 days")
    }

    // MARK: timeLeft

    func testTimeLeftToday() {
        let now = date(2025, 10, 17, 8, 15, in: system)
        let decideAt = date(2025, 10, 17, 9, 0, in: system)
        let thing = item(created: date(2025, 10, 3, 9, in: system), decideAt: decideAt)
        XCTAssertEqual(Format.timeLeft(thing, now: now, calendar: system),
                       "Decide today at \(Format.time(decideAt))")
    }

    func testTimeLeftTomorrow() {
        let decideAt = date(2025, 10, 18, 9, 0, in: system)
        let thing = item(created: date(2025, 10, 3, 9, in: system), decideAt: decideAt)
        XCTAssertEqual(Format.timeLeft(thing, now: date(2025, 10, 17, 8, 15, in: system), calendar: system),
                       "Decide tomorrow at \(Format.time(decideAt))")
        // Calendar days, not 24-hour periods: one minute to midnight is still "tomorrow" for the next day.
        XCTAssertEqual(Format.timeLeft(thing, now: date(2025, 10, 17, 23, 59, in: system), calendar: system),
                       "Decide tomorrow at \(Format.time(decideAt))")
    }

    func testTimeLeftSeveralDays() {
        let decideAt = date(2025, 10, 29, 9, 0, in: system)
        let thing = item(created: date(2025, 10, 3, 9, in: system), decideAt: decideAt)
        XCTAssertEqual(Format.timeLeft(thing, now: date(2025, 10, 17, 8, 15, in: system), calendar: system),
                       "12 days left · \(Format.shortDate(decideAt))")
        XCTAssertEqual(Format.timeLeft(thing, now: date(2025, 10, 27, 23, 59, in: system), calendar: system),
                       "2 days left · \(Format.shortDate(decideAt))")
    }

    func testTimeLeftIsNeverSingularDays() {
        let thing = item(created: date(2025, 10, 3, 9, in: system), decideAt: date(2025, 12, 31, 9, in: system))
        for day in 1...28 {
            let text = Format.timeLeft(thing, now: date(2025, 12, day, 8, in: system), calendar: system)
            XCTAssertFalse(text.hasPrefix("1 day"), text)   // day 30 is "tomorrow", day 31 is "today"
            XCTAssertFalse(text.hasPrefix("0 day"), text)
        }
    }

    func testTimeLeftForOverdueItemSaysToday() {
        // daysLeft is clamped to 0. Overdue items show in the "ready to decide" section, not here.
        let decideAt = date(2025, 10, 10, 9, in: system)
        let thing = item(created: date(2025, 9, 26, 9, in: system), decideAt: decideAt)
        XCTAssertEqual(Format.timeLeft(thing, now: date(2025, 10, 17, 8, in: system), calendar: system),
                       "Decide today at \(Format.time(decideAt))")
    }

    // MARK: day

    func testDayToday() {
        let now = date(2025, 10, 17, 12, in: stockholm)
        XCTAssertEqual(Format.day(now, now: now, calendar: stockholm), "Today")
        XCTAssertEqual(Format.day(date(2025, 10, 17, 0, 0, in: stockholm), now: now, calendar: stockholm), "Today")
        XCTAssertEqual(Format.day(date(2025, 10, 17, 23, 59, 59, in: stockholm), now: now, calendar: stockholm),
                       "Today")
    }

    func testDayYesterday() {
        let now = date(2025, 10, 17, 0, 0, 30, in: stockholm)
        XCTAssertEqual(Format.day(date(2025, 10, 16, 23, 59, in: stockholm), now: now, calendar: stockholm),
                       "Yesterday", "one minute earlier, but the day before")
        XCTAssertEqual(Format.day(date(2025, 10, 16, 0, 0, in: stockholm), now: now, calendar: stockholm),
                       "Yesterday")
    }

    func testDayYesterdayAcrossYearEnd() {
        let now = date(2026, 1, 1, 8, in: stockholm)
        XCTAssertEqual(Format.day(date(2025, 12, 31, 23, 59, in: stockholm), now: now, calendar: stockholm),
                       "Yesterday")
    }

    func testDayYesterdayAcrossDaylightSavingChanges() {
        // 2025-03-30 has 23 hours and 2025-10-26 has 25 in Europe/Stockholm.
        let spring = date(2025, 3, 30, 12, in: stockholm)
        XCTAssertEqual(Format.day(date(2025, 3, 29, 12, in: stockholm), now: spring, calendar: stockholm), "Yesterday")
        XCTAssertEqual(Format.day(date(2025, 3, 31, 0, 30, in: stockholm), now: date(2025, 3, 31, 0, 40, in: stockholm),
                                  calendar: stockholm), "Today")
        let autumn = date(2025, 10, 26, 12, in: stockholm)
        XCTAssertEqual(Format.day(date(2025, 10, 25, 12, in: stockholm), now: autumn, calendar: stockholm), "Yesterday")
        XCTAssertNotEqual(Format.day(date(2025, 10, 24, 12, in: stockholm), now: autumn, calendar: stockholm), "Yesterday")
    }

    func testDayEarlierInTheSameYearUsesTheShortDate() {
        let now = date(2025, 10, 17, 12, in: system)
        let earlier = date(2025, 10, 5, 9, in: system)
        let text = Format.day(earlier, now: now, calendar: system)
        XCTAssertEqual(text, Format.shortDate(earlier))
        XCTAssertNotEqual(text, "Today")
        XCTAssertNotEqual(text, "Yesterday")
        XCTAssertEqual(Format.day(date(2025, 1, 1, in: system), now: now, calendar: system),
                       Format.shortDate(date(2025, 1, 1, in: system)))
    }

    func testDayTwoDaysAgoIsNotYesterday() {
        let now = date(2025, 10, 17, 12, in: system)
        XCTAssertEqual(Format.day(date(2025, 10, 15, 12, in: system), now: now, calendar: system),
                       Format.shortDate(date(2025, 10, 15, 12, in: system)))
    }

    /// The year is four more digits than the short date ("17 Oct 2025" vs "Fri 17 Oct"); which year number
    /// appears depends on the locale's calendar (2568 in th_TH), so only the digit count is compared.
    private func assertShowsYear(_ text: String, for date: Date, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(digits(text).count, digits(Format.shortDate(date)).count + 4, text, file: file, line: line)
        XCTAssertNotEqual(text, Format.shortDate(date), file: file, line: line)
    }

    func testDayInAnotherYearShowsTheYear() {
        let now = date(2026, 3, 1, 12, in: system)
        let past = date(2025, 10, 17, 12, in: system)
        assertShowsYear(Format.day(past, now: now, calendar: system), for: past)
        let farPast = date(2019, 2, 3, 12, in: system)
        assertShowsYear(Format.day(farPast, now: now, calendar: system), for: farPast)
    }

    func testDayInTheFutureIsNotTodayOrYesterday() {
        let now = date(2025, 10, 17, 12, in: system)
        let tomorrow = date(2025, 10, 18, 12, in: system)
        XCTAssertEqual(Format.day(tomorrow, now: now, calendar: system), Format.shortDate(tomorrow))
        let nextYear = date(2026, 1, 2, 12, in: system)
        assertShowsYear(Format.day(nextYear, now: now, calendar: system), for: nextYear)
    }

    func testDayUsesTheGivenCalendarsTimeZone() {
        // 08:00 and 12:00 UTC on 2025-10-17 are the same day in UTC, but in Auckland (UTC+13 then)
        // they are 21:00 on the 17th and 01:00 on the 18th.
        let earlier = date(2025, 10, 17, 8, in: TestCalendars.utc)
        let now = date(2025, 10, 17, 12, in: TestCalendars.utc)
        XCTAssertEqual(Format.day(earlier, now: now, calendar: TestCalendars.utc), "Today")
        XCTAssertEqual(Format.day(earlier, now: now, calendar: TestCalendars.auckland), "Yesterday")
    }
}
