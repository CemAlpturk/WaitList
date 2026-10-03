import XCTest
@testable import WaitList

/// `PriceInput.parse` takes a locale, so these tests pin it (en_US: "." decimal, "," grouping;
/// sv_SE: "," decimal, no-break space grouping; de_DE: "," decimal, "." grouping).
final class PriceInputTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private let sv = Locale(identifier: "sv_SE")
    private let de = Locale(identifier: "de_DE")

    private func assertValue(_ text: String, _ locale: Locale, _ expected: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(PriceInput.parse(text, locale: locale), .value(dec(expected)),
                       "\(text.debugDescription) in \(locale.identifier)", file: file, line: line)
    }

    private func assertInvalid(_ text: String, _ locale: Locale,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(PriceInput.parse(text, locale: locale), .invalid,
                       "\(text.debugDescription) in \(locale.identifier)", file: file, line: line)
    }

    // MARK: Empty

    func testEmptyAndBlankInputIsEmpty() {
        for locale in [en, sv, de] {
            for text in ["", " ", "   ", "\t", "\n", " \n ", "\u{00A0}", "\u{202F}"] {
                XCTAssertEqual(PriceInput.parse(text, locale: locale), .empty, "\(text.debugDescription)")
            }
        }
    }

    func testDefaultLocaleOverloadHandlesLocaleIndependentInput() {
        // No locale argument: uses Locale.current, so only input that means the same everywhere.
        XCTAssertEqual(PriceInput.parse(""), .empty)
        XCTAssertEqual(PriceInput.parse("1299"), .value(1299))
        XCTAssertEqual(PriceInput.parse(" 42 "), .value(42))
        XCTAssertEqual(PriceInput.parse("abc"), .invalid)
        XCTAssertEqual(PriceInput.parse("1e5"), .invalid)
    }

    // MARK: Plain numbers

    func testWholeNumbers() {
        for locale in [en, sv, de] {
            assertValue("0", locale, "0")
            assertValue("1", locale, "1")
            assertValue("1299", locale, "1299")
            assertValue("007", locale, "7")
            assertValue("  1299  ", locale, "1299")
            assertValue("\t1299\n", locale, "1299")
        }
    }

    func testDotAndCommaBothWorkAsDecimalInCommaDecimalLocale() {
        assertValue("1299.5", sv, "1299.5")
        assertValue("1299,5", sv, "1299.5")
        assertValue("19.99", sv, "19.99")
        assertValue("19,99", sv, "19.99")
        assertValue("0,5", sv, "0.5")
        assertValue(".5", sv, "0.5")
        assertValue(",5", sv, "0.5")
        assertValue("5.", sv, "5")
        assertValue("5,", sv, "5")
        assertValue("0,001", sv, "0.001")
    }

    func testDotDecimalInDotDecimalLocale() {
        assertValue("1299.5", en, "1299.5")
        assertValue("19.99", en, "19.99")
        assertValue("0.50", en, "0.5")
        assertValue(".5", en, "0.5")
        assertValue("5.", en, "5")
    }

    func testCommaDecimalInGermanLocale() {
        assertValue("19,99", de, "19.99")
        assertValue("1299,5", de, "1299.5")
        assertValue("0,5", de, "0.5")
    }

    func testMoreThanOneDecimalSeparatorIsInvalid() {
        assertInvalid("1.2.3", en)
        assertInvalid("1..2", en)
        assertInvalid("1,2,3", sv)
        assertInvalid("1.2,3", sv)
    }

    // MARK: Thousands separators and spaces

    func testLocaleGroupingSeparators() {
        assertValue("1,299", en, "1299")
        assertValue("1,299.50", en, "1299.5")
        assertValue("1,234,567.89", en, "1234567.89")
        assertValue("1.299", de, "1299")
        assertValue("1.299,50", de, "1299.5")
        assertValue("1.234.567,89", de, "1234567.89")
    }

    func testSpacesAreIgnoredWhereverTheyAre() {
        assertValue("1 299", sv, "1299")
        assertValue("1 299,50", sv, "1299.5")          // regular space
        assertValue("1\u{00A0}299,50", sv, "1299.5")    // no-break space (sv_SE's own grouping separator)
        assertValue("1\u{202F}299,50", sv, "1299.5")    // narrow no-break space
        assertValue("1 234 567,89", sv, "1234567.89")
        assertValue(" 1 299 ", en, "1299")
        assertValue("1 2 3", en, "123")
    }

    func testApostropheGroupingIsAcceptedInEveryLocale() {
        assertValue("1'299", en, "1299")
        assertValue("1'299.50", en, "1299.5")
        assertValue("1'299,50", sv, "1299.5")
        assertValue("1'234'567", de, "1234567")
    }

    // MARK: Currency symbols and labels

    func testCurrencySymbolsAreIgnored() {
        assertValue("$19.99", en, "19.99")
        assertValue("$ 19.99", en, "19.99")
        assertValue("19.99$", en, "19.99")
        assertValue("€19,99", sv, "19.99")
        assertValue("19,99 €", sv, "19.99")
        assertValue("£5", en, "5")
        assertValue("¥1000", en, "1000")
        assertValue("₹ 1,299", en, "1299")
        assertValue("$1,299.00", en, "1299")
    }

    func testCurrencyLabelsBeforeOrAfterTheNumberAreIgnored() {
        assertValue("1299 kr", sv, "1299")
        assertValue("1299kr", sv, "1299")
        assertValue("kr 1299", sv, "1299")
        assertValue("SEK 20", sv, "20")
        assertValue("20 SEK", sv, "20")
        assertValue("sek20", sv, "20")
        assertValue("USD 1,299.50", en, "1299.5")
        assertValue("1 299,50 kr", sv, "1299.5")
        assertValue("kr 1 299,50", sv, "1299.5")
        assertValue("SEK $20", en, "20")
    }

    func testLettersBetweenDigitsAreInvalid() {
        assertInvalid("12 kr 34", sv)
        assertInvalid("12abc34", en)
        assertInvalid("1k5", en)
    }

    // MARK: Negative numbers

    /// Negative input is parsed, not rejected: the Add/Edit screen flags `.value(v)` with `v < 0`
    /// ("The price can't be negative.") and blocks saving.
    func testNegativeNumbersParseAsNegativeValues() {
        for locale in [en, sv, de] {
            assertValue("-5", locale, "-5")
            assertValue("- 5", locale, "-5")
            assertValue("-$5", locale, "-5")
            assertValue("$-5", locale, "-5")
            assertValue("kr -5", locale, "-5")
        }
        assertValue("-5.25", en, "-5.25")
        assertValue("-5,25", sv, "-5.25")
        assertValue("\u{2212}5", en, "-5")             // U+2212 MINUS SIGN, which sv_SE formats with
        assertValue("\u{2212}1\u{00A0}299,50", sv, "-1299.5")
        assertValue("-1,299.50", en, "-1299.5")
    }

    func testNegativeZeroIsZero() {
        assertValue("-0", en, "0")
        assertValue("-0.00", en, "0")
    }

    func testMisplacedOrExtraSignsAreInvalid() {
        for locale in [en, sv] {
            assertInvalid("--5", locale)
            assertInvalid("5-", locale)
            assertInvalid("5 -", locale)
            assertInvalid("+5", locale)
            assertInvalid("-", locale)
            assertInvalid("- -", locale)
            assertInvalid("1-2", locale)
        }
    }

    // MARK: Rejected input

    func testScientificNotationIsInvalid() {
        for locale in [en, sv, de] {
            assertInvalid("1e5", locale)
            assertInvalid("1E5", locale)
            assertInvalid("1.5e3", locale)
            assertInvalid("2e-3", locale)
            assertInvalid("1e+5", locale)
            assertInvalid("1e5kr", locale)
        }
    }

    func testTextAndPunctuationOnlyIsInvalid() {
        for locale in [en, sv, de] {
            for text in ["abc", "kr", "SEK", "free", "NaN", "Infinity", "inf", "-", ".", ",", "..", ",,", "'",
                         "€", "$", "$€", "-$", "∞", "½", "0x10", "1_000", "1/2", "1:50", "(5)", "5%", "1#"] {
                XCTAssertEqual(PriceInput.parse(text, locale: locale), .invalid,
                               "\(text.debugDescription) in \(locale.identifier)")
            }
        }
    }

    func testNonASCIIDigitsAreInvalid() {
        assertInvalid("\u{0661}\u{0662}\u{0663}", en)          // Arabic-Indic digits
        assertInvalid("\u{FF11}\u{FF12}\u{FF13}", en)          // fullwidth digits
    }

    // MARK: Very large and very small values

    func testVeryLargeValuesAreAcceptedWithoutAnUpperBound() {
        // Decimal holds 38 significant digits exactly.
        let thirtyEightNines = String(repeating: "9", count: 38)
        assertValue(thirtyEightNines, en, thirtyEightNines)
        assertValue("12345678901234567890", en, "12345678901234567890")
        assertValue("9007199254740993", en, "9007199254740993")          // 2^53 + 1, not representable as Double
        assertValue("1" + String(repeating: "0", count: 100), en, "1" + String(repeating: "0", count: 100))
        assertValue("1,000,000,000,000", en, "1000000000000")
    }

    func testValuesBeyondDecimalRangeAreInvalid() {
        // Decimal's exponent range ends near 1e166; Decimal(string:) returns nil beyond it.
        assertInvalid("1" + String(repeating: "0", count: 200), en)
        assertInvalid("1" + String(repeating: "0", count: 5_000), en)
    }

    func testManyDecimalPlacesAreKept() {
        assertValue("1.005", en, "1.005")
        assertValue("0.000001", en, "0.000001")
    }

    // MARK: Leading and trailing letters

    /// Letters at either end count as a currency label, so a stray "e" does not make the input invalid.
    func testLettersAtTheEdgesAreTreatedAsLabels() {
        assertValue("1e", en, "1")
        assertValue("e5", en, "5")
        assertValue("5 USD", en, "5")
    }

    // MARK: Locale matrix

    /// The string `Format.editablePrice` would produce, or a grouped one, in `locale`.
    private func formatted(_ value: Decimal, _ locale: Locale, grouping: Decimal.FormatStyle.Configuration.Grouping)
        -> String {
        value.formatted(.number.grouping(grouping).precision(.fractionLength(0...2)).locale(locale))
    }

    func testParsesWhatTheLocaleFormatsForCommonLocales() {
        let locales = ["en_US", "en_GB", "en_IN", "sv_SE", "nb_NO", "da_DK", "fi_FI", "de_DE", "de_CH", "fr_FR",
                       "pt_BR", "es_ES", "it_IT", "nl_NL", "pl_PL", "ru_RU", "ja_JP", "hi_IN"]
        let values = ["0", "1", "19.99", "1299", "1299.5", "12345.67", "1234567.89", "0.01", "-5.25", "-1299"]
        for id in locales {
            let locale = Locale(identifier: id)
            for text in values {
                let value = dec(text)
                for grouping in [Decimal.FormatStyle.Configuration.Grouping.never, .automatic] {
                    let shown = formatted(value, locale, grouping: grouping)
                    XCTAssertEqual(PriceInput.parse(shown, locale: locale), .value(value),
                                   "\(id): \(value) shown as \(shown.debugDescription)")
                }
            }
        }
    }

    // MARK: Known issues (XCTExpectFailure turns into a failure once the parser is fixed)

    /// Formatting.swift:98-102 strips the locale's grouping separator before the decimal logic runs,
    /// so a comma typed as a decimal separator is read as grouping in locales that group with ",".
    func testKnownIssueCommaDecimalIsReadAsGroupingInEnglishLocale() {
        XCTExpectFailure("',' is stripped as the en_US grouping separator: '19,99' parses as 1999") {
            XCTAssertEqual(PriceInput.parse("19,99", locale: en), .value(dec("19.99")))
            XCTAssertEqual(PriceInput.parse("1299,5", locale: en), .value(dec("1299.5")))
        }
    }

    /// Same problem the other way round: "." is grouping in de_DE.
    func testKnownIssueDotDecimalIsReadAsGroupingInGermanLocale() {
        XCTExpectFailure("'.' is stripped as the de_DE grouping separator: '19.99' parses as 1999") {
            XCTAssertEqual(PriceInput.parse("19.99", locale: de), .value(dec("19.99")))
            XCTAssertEqual(PriceInput.parse(".5", locale: de), .value(dec("0.5")))
        }
    }

    /// Formatting.swift:87: letters are trimmed from both ends but the abbreviation's period stays,
    /// leaving ".20", which is 0.2.
    func testKnownIssueAbbreviationWithPeriodBeforeNumberBecomesFraction() {
        XCTExpectFailure("'kr. 20' parses as 0.2 because the label's period is kept") {
            XCTAssertEqual(PriceInput.parse("kr. 20", locale: sv), .value(dec("20")))
            XCTAssertEqual(PriceInput.parse("Rs. 500", locale: en), .value(dec("500")))
        }
    }

    /// Formatting.swift:81-85 only drops whitespace and currency symbols. Invisible format characters, as
    /// found in text copied from web pages and in he_IL's formatted negative numbers, make the input invalid.
    func testKnownIssueInvisibleDirectionMarksMakeInputInvalid() {
        XCTExpectFailure("U+200E / U+200F / U+200B / U+FEFF are not ignored") {
            for mark in ["\u{200E}", "\u{200F}", "\u{200B}", "\u{FEFF}", "\u{2066}"] {
                XCTAssertEqual(PriceInput.parse("\(mark)1299", locale: en), .value(dec("1299")), mark.debugDescription)
                XCTAssertEqual(PriceInput.parse("$1,299.50\(mark)", locale: en), .value(dec("1299.5")),
                               mark.debugDescription)
            }
        }
    }

    /// Formatting.swift:94 rejects every non-ASCII character, including the typographic apostrophe U+2019
    /// that CLDR (and most Swiss users) use as the thousands separator. Apple's de_CH data uses ASCII "'"
    /// on current macOS, so formatted output still parses; pasted "1\u{2019}299.50" does not.
    func testKnownIssueTypographicApostropheGroupingIsInvalid() {
        XCTExpectFailure("U+2019 is not accepted as a grouping separator") {
            XCTAssertEqual(PriceInput.parse("1\u{2019}299.50", locale: Locale(identifier: "de_CH")),
                           .value(dec("1299.5")))
        }
    }

    /// Formatting.swift:94 only accepts ASCII digits, but `Format.editablePrice` formats in the current
    /// locale, so in ar_EG / fa_IR the edit screen is pre-filled with text the parser calls invalid.
    func testKnownIssueNonASCIIDigitsFromLocaleFormattingAreRejected() {
        let arabic = Locale(identifier: "ar_EG")
        let shown = formatted(dec("1299.5"), arabic, grouping: .never)
        XCTAssertNotEqual(shown, "1299.5", "ar_EG should format with non-ASCII digits")
        XCTExpectFailure("ar_EG output such as \(shown) is not parseable") {
            XCTAssertEqual(PriceInput.parse(shown, locale: arabic), .value(dec("1299.5")))
        }
    }
}
