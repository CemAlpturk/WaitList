import XCTest
@testable import WaitListCore

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
            for text in ["", " ", "   ", "\t", "\n", " \n ", "\u{00A0}", "\u{202F}", "\u{200B}", "\u{200E} \u{FEFF}"] {
                XCTAssertEqual(PriceInput.parse(text, locale: locale), .empty, "\(text.debugDescription)")
            }
        }
    }

    func testDefaultLocaleOverloadHandlesLocaleIndependentInput() {
        // No locale argument: uses Locale.current, so only input that means the same everywhere.
        XCTAssertEqual(PriceInput.parse(""), .empty)
        XCTAssertEqual(PriceInput.parse("1299"), .value(1299))
        XCTAssertEqual(PriceInput.parse(" 42 "), .value(42))
        XCTAssertEqual(PriceInput.parse("19,99"), .value(dec("19.99")))
        XCTAssertEqual(PriceInput.parse("19.99"), .value(dec("19.99")))
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

    // MARK: Rule: one "." or "," with 1-2 digits after it is the decimal separator, in every locale

    func testOneSeparatorWithOneOrTwoDigitsAfterIsDecimalEverywhere() {
        for locale in [en, sv, de] {
            assertValue("19.99", locale, "19.99")
            assertValue("19,99", locale, "19.99")
            assertValue("1299.5", locale, "1299.5")
            assertValue("1299,5", locale, "1299.5")
            assertValue("0,5", locale, "0.5")
            assertValue(".5", locale, "0.5")
            assertValue(",5", locale, "0.5")
            assertValue("0.50", locale, "0.5")
        }
    }

    func testTrailingSeparatorIsADecimalSeparatorWithNoDecimals() {
        for locale in [en, sv, de] {
            assertValue("5.", locale, "5")
            assertValue("5,", locale, "5")
        }
    }

    // MARK: Rule: exactly 3 digits after a single separator

    func testThreeDigitsAfterTheLocalesDecimalSeparatorAreDecimals() {
        assertValue("1.299", en, "1.299")
        assertValue("0.001", en, "0.001")
        assertValue("1,299", sv, "1.299")
        assertValue("0,001", sv, "0.001")
        assertValue("1,299", de, "1.299")
    }

    func testThreeDigitsAfterTheOtherSeparatorMeanGrouping() {
        assertValue("1,299", en, "1299")
        assertValue("1.299", sv, "1299")
        assertValue("1.299", de, "1299")
        assertValue("-1,299", en, "-1299")
    }

    // MARK: Rule: 4 or more digits after a single separator

    func testFourOrMoreDigitsNeedTheLocalesDecimalSeparator() {
        assertValue("1.2999", en, "1.2999")
        assertValue("1,2999", sv, "1.2999")
        assertValue("1,2999", de, "1.2999")
        assertInvalid("1,2999", en)
        assertInvalid("1.2999", sv)
        assertInvalid("1.2999", de)
        assertInvalid("12,34567", en)
    }

    // MARK: Rule: both "." and "," appear

    func testWhenBothAppearTheLastIsTheDecimalSeparator() {
        for locale in [en, sv, de] {
            assertValue("1,299.50", locale, "1299.5")
            assertValue("1.299,50", locale, "1299.5")
            assertValue("1,234,567.89", locale, "1234567.89")
            assertValue("1.234.567,89", locale, "1234567.89")
            assertValue("1.234,5", locale, "1234.5")
            assertValue("1,234.567", locale, "1234.567")
        }
    }

    func testWhenBothAppearTheOtherMustSeparateGroupsOfThree() {
        for locale in [en, sv, de] {
            assertInvalid("1.23,45", locale)
            assertInvalid("1,2345.6", locale)
            assertInvalid("1.2,3", locale)
            assertInvalid("1.23.4,5", locale)
        }
    }

    func testWhenBothAppearTheDecimalSeparatorMustAppearOnce() {
        for locale in [en, sv, de] {
            assertInvalid("1.234,567.89", locale)    // "." last, but twice
            assertInvalid("1,234.567,89", locale)
            assertInvalid("1.5,5.5", locale)
        }
    }

    // MARK: Rule: one separator appearing more than once is grouping

    func testRepeatedSeparatorIsGroupingInEveryLocale() {
        for locale in [en, sv, de] {
            assertValue("1,234,567", locale, "1234567")
            assertValue("1.234.567", locale, "1234567")
            assertValue("1,000,000", locale, "1000000")
        }
    }

    func testRepeatedSeparatorNeedsGroupsOfThree() {
        for locale in [en, sv, de] {
            assertInvalid("1.2.3", locale)
            assertInvalid("1,2,3", locale)
            assertInvalid("1,234,56", locale)
            assertInvalid("1.2345.678", locale)
        }
    }

    func testIndianGroupingIsAccepted() {
        assertValue("12,34,567", en, "1234567")
        assertValue("12,34,567.89", en, "1234567.89")
        assertValue("1,00,00,000", en, "10000000")
        assertInvalid("12,34,56", en)      // the last group must have 3 digits
        assertInvalid("1,234,56,789", en)  // 2-digit groups only before the last
    }

    func testTwoSeparatorsInARowAreInvalid() {
        for locale in [en, sv, de] {
            assertInvalid("1..2", locale)
            assertInvalid("1,,2", locale)
            assertInvalid("1.,2", locale)
            assertInvalid("1,.2", locale)
        }
    }

    // MARK: Spaces and apostrophes

    func testSpacesBetweenDigitsAreGrouping() {
        assertValue("1 299", sv, "1299")
        assertValue("1 299,50", sv, "1299.5")          // regular space
        assertValue("1\u{00A0}299,50", sv, "1299.5")    // no-break space (sv_SE's own grouping separator)
        assertValue("1\u{202F}299,50", sv, "1299.5")    // narrow no-break space
        assertValue("1 234 567,89", sv, "1234567.89")
        assertValue("1   299", sv, "1299")               // spaces are collapsed
        assertValue(" 1 299 ", en, "1299")
        assertValue("1 2 3", en, "123")                  // group sizes are not checked for spaces
    }

    func testSpaceGroupingWithACommaDecimalWorksInEnglishToo() {
        assertValue("1 299,50", en, "1299.5")
        assertValue("19,99", en, "19.99")
        assertValue("1299,5", en, "1299.5")
    }

    func testDotDecimalWorksInGermanToo() {
        assertValue("19.99", de, "19.99")
        assertValue(".5", de, "0.5")
        assertValue("1 299.50", de, "1299.5")
    }

    func testSpacesNextToADecimalSeparatorAreIgnored() {
        assertValue("1 ,5", sv, "1.5")
        assertValue("1. 5", en, "1.5")
    }

    func testApostropheGroupingIsAcceptedInEveryLocale() {
        assertValue("1'299", en, "1299")
        assertValue("1'299.50", en, "1299.5")
        assertValue("1'299,50", sv, "1299.5")
        assertValue("1'234'567", de, "1234567")
    }

    func testTypographicApostropheIsGrouping() {
        let swiss = Locale(identifier: "de_CH")
        assertValue("1\u{2019}299.50", swiss, "1299.5")
        assertValue("1\u{2019}234\u{2019}567", en, "1234567")
        assertValue("1\u{2019}299,50", sv, "1299.5")
    }

    func testAGroupingMarkAtEitherEndIsInvalid() {
        assertInvalid("'5", en)
        assertInvalid("5'", en)
    }

    // MARK: Normalisation

    func testNonASCIIDigitsAreReadAsDigits() {
        assertValue("\u{0661}\u{0662}\u{0663}", en, "123")            // Arabic-Indic digits
        assertValue("\u{06F1}\u{06F2}\u{06F3}", en, "123")            // Extended Arabic-Indic (Persian)
        assertValue("\u{FF11}\u{FF12}\u{FF13}", en, "123")            // fullwidth digits
        assertValue("\u{0967}\u{0968}\u{0969}.\u{096B}", en, "123.5")  // Devanagari
        assertValue("\u{FF11}\u{FF12}\u{FF0E}\u{FF15}", en, "12.5")    // fullwidth digits and full stop
    }

    func testNumeralsThatAreNotDecimalDigitsAreInvalid() {
        assertInvalid("五", en)        // CJK numeral (a letter, so a label: nothing left)
        assertInvalid("1五2", en)
        assertInvalid("①②", en)       // circled digits
        assertInvalid("1²", en)        // superscript
    }

    func testInvisibleFormatCharactersAreIgnored() {
        for mark in ["\u{200E}", "\u{200F}", "\u{200B}", "\u{FEFF}", "\u{2066}", "\u{061C}"] {
            assertValue("\(mark)1299", en, "1299")
            assertValue("$1,299.50\(mark)", en, "1299.5")
            assertValue("1\(mark)299", en, "1299")
        }
    }

    func testArabicSeparatorsAreUnambiguous() {
        // U+066B is always a decimal separator and U+066C always grouping, whatever the locale.
        for locale in [en, sv, de, Locale(identifier: "ar_EG")] {
            assertValue("\u{0661}\u{0662}\u{0669}\u{0669}\u{066B}\u{0665}", locale, "1299.5")
            assertValue("\u{0661}\u{066C}\u{0662}\u{0669}\u{0669}\u{066B}\u{0665}", locale, "1299.5")
            assertValue("1\u{066C}299", locale, "1299")
            assertInvalid("1\u{066B}2\u{066B}3", locale)
        }
    }

    func testLocaleFormattedArabicAndPersianNumbersParse() {
        for id in ["ar_EG", "ar_SA", "fa_IR", "ps_AF"] {
            let locale = Locale(identifier: id)
            for text in ["1299.5", "-1234567.89", "0.01", "1299"] {
                let value = dec(text)
                for grouping in [Decimal.FormatStyle.Configuration.Grouping.never, .automatic] {
                    let shown = value.formatted(.number.grouping(grouping).precision(.fractionLength(0...2)).locale(locale))
                    XCTAssertEqual(PriceInput.parse(shown, locale: locale), .value(value),
                                   "\(id): \(value) shown as \(shown.debugDescription)")
                }
            }
        }
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
        assertValue("$.50", en, "0.5")    // a period after a symbol is a decimal point
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

    func testAbbreviationPeriodsAreNotDecimalPoints() {
        assertValue("kr. 20", sv, "20")
        assertValue("kr.20", sv, "20")
        assertValue("Rs. 500", en, "500")
        assertValue("Rs.500", en, "500")
        assertValue("20 kr.", sv, "20")
        assertValue("1.299 kr.", de, "1299")
        assertValue("Fr. 1'299.50", Locale(identifier: "de_CH"), "1299.5")
        assertValue("-Rs. 5", en, "-5")
    }

    func testLettersBetweenDigitsAreInvalid() {
        assertInvalid("12 kr 34", sv)
        assertInvalid("12abc34", en)
        assertInvalid("1k5", en)
    }

    func testLettersAtTheEdgesAreTreatedAsLabels() {
        assertValue("1e", en, "1")
        assertValue("e5", en, "5")
        assertValue("5 USD", en, "5")
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
            assertValue("-19,99", locale, "-19.99")
        }
        assertValue("-5.25", en, "-5.25")
        assertValue("-5,25", sv, "-5.25")
        assertValue("\u{2212}5", en, "-5")             // U+2212 MINUS SIGN, which sv_SE formats with
        assertValue("\u{2212}1\u{00A0}299,50", sv, "-1299.5")
        assertValue("-1,299.50", en, "-1299.5")
        assertValue("\u{FF0D}5", en, "-5")             // fullwidth hyphen-minus
    }

    func testNegativeZeroIsZero() {
        assertValue("-0", en, "0")
        assertValue("-0.00", en, "0")
        XCTAssertEqual(PriceInput.parse("-0", locale: en), .value(0))
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
                         "€", "$", "$€", "-$", "∞", "½", "0x10", "1_000", "1/2", "1:50", "(5)", "5%", "1#",
                         "kr.", "Rs."] {
                XCTAssertEqual(PriceInput.parse(text, locale: locale), .invalid,
                               "\(text.debugDescription) in \(locale.identifier)")
            }
        }
    }

    // MARK: Bounds

    func testAtMostTwelveIntegerDigits() {
        XCTAssertEqual(PriceInput.maxIntegerDigits, 12)
        assertValue("999999999999", en, "999999999999")
        assertValue("999,999,999,999.99", en, "999999999999.99")
        assertInvalid("1000000000000", en)
        assertInvalid("1,000,000,000,000", en)
        assertInvalid(String(repeating: "9", count: 38), en)
        assertInvalid("1" + String(repeating: "0", count: 200), en)
        assertInvalid("1" + String(repeating: "0", count: 5_000), en)
    }

    func testLeadingZerosDoNotCountTowardsTheLimit() {
        assertValue("0000000000000001", en, "1")
    }

    func testAtMostFourDecimals() {
        XCTAssertEqual(PriceInput.maxFractionDigits, 4)
        assertValue("1.005", en, "1.005")
        assertValue("0.0001", en, "0.0001")
        assertValue("1,2345", sv, "1.2345")
        assertInvalid("0.00001", en)
        assertInvalid("0.000001", en)
        assertInvalid("1,23456", sv)
    }

    func testTrailingZerosDoNotCountTowardsTheLimit() {
        assertValue("1.50000", en, "1.5")
        assertValue("2,000000", sv, "2")
    }

    func testLargestAcceptedAmountIsExact() {
        // 16 significant digits fit Decimal exactly (a Double would round the last digit).
        assertValue("999999999999.9999", en, "999999999999.9999")
        assertValue("900719925474.0993", en, "900719925474.0993")
    }

    // MARK: Locale matrix

    func testParsesWhatTheLocaleFormatsForCommonLocales() {
        let locales = ["en_US", "en_GB", "en_IN", "sv_SE", "nb_NO", "da_DK", "fi_FI", "de_DE", "de_CH", "fr_FR",
                       "pt_BR", "es_ES", "it_IT", "nl_NL", "pl_PL", "ru_RU", "ja_JP", "hi_IN", "he_IL", "ar_EG",
                       "fa_IR", "my_MM"]
        let values = ["0", "1", "19.99", "1299", "1299.5", "12345.67", "1234567.89", "0.01", "-5.25", "-1299"]
        for id in locales {
            let locale = Locale(identifier: id)
            for text in values {
                let value = dec(text)
                for grouping in [Decimal.FormatStyle.Configuration.Grouping.never, .automatic] {
                    let shown = value.formatted(.number.grouping(grouping).precision(.fractionLength(0...2))
                        .locale(locale))
                    XCTAssertEqual(PriceInput.parse(shown, locale: locale), .value(value),
                                   "\(id): \(value) shown as \(shown.debugDescription)")
                }
            }
        }
    }

    func testParsesLocaleCurrencyStrings() {
        for (id, code) in [("en_US", "USD"), ("sv_SE", "SEK"), ("de_DE", "EUR"), ("de_CH", "CHF"), ("fr_FR", "EUR"),
                           ("en_IN", "INR"), ("ja_JP", "JPY"), ("ar_EG", "EGP")] {
            let locale = Locale(identifier: id)
            for text in ["1299", "19.99", "1234567.5"] where !(code == "JPY" && text.contains(".")) {
                let value = dec(text)
                let shown = PriceFormat.string(value, currencyCode: code, locale: locale)
                XCTAssertEqual(PriceInput.parse(shown, locale: locale), .value(value),
                               "\(id): \(value) shown as \(shown.debugDescription)")
            }
        }
    }
}
