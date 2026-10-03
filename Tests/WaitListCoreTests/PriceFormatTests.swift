import XCTest
@testable import WaitListCore

final class PriceFormatTests: XCTestCase {
    private let sv = Locale(identifier: "sv_SE")
    private let en = Locale(identifier: "en_US")

    /// Locales covering every decimal separator, grouping style and digit script the parser has to handle.
    private let locales = ["en_US", "en_GB", "en_IN", "sv_SE", "nb_NO", "fi_FI", "de_DE", "de_CH", "fr_FR", "es_ES",
                           "pt_BR", "pl_PL", "ru_RU", "ja_JP", "he_IL", "ar_EG", "ar_SA", "fa_IR", "ps_AF", "my_MM",
                           "hi_IN", "bn_BD"].map(Locale.init(identifier:))

    // MARK: string

    func testWholeAmountsHaveNoDecimals() {
        XCTAssertEqual(PriceFormat.string(1299, currencyCode: "SEK", locale: sv), "1\u{00A0}299\u{00A0}kr")
        XCTAssertEqual(PriceFormat.string(dec("1299.00"), currencyCode: "SEK", locale: sv), "1\u{00A0}299\u{00A0}kr")
        XCTAssertEqual(PriceFormat.string(1299, currencyCode: "USD", locale: en), "$1,299")
    }

    func testFractionalAmountsKeepTheirDecimals() {
        XCTAssertEqual(PriceFormat.string(dec("19.99"), currencyCode: "SEK", locale: sv), "19,99\u{00A0}kr")
        XCTAssertEqual(PriceFormat.string(dec("1299.5"), currencyCode: "USD", locale: en), "$1,299.50")
    }

    // MARK: editable

    func testEditableUsesASCIIDigitsTheLocalesSeparatorAndNoGrouping() {
        XCTAssertEqual(PriceFormat.editable(dec("1234567.5"), locale: en), "1234567.5")
        XCTAssertEqual(PriceFormat.editable(dec("1234567.5"), locale: sv), "1234567,5")
        XCTAssertEqual(PriceFormat.editable(dec("1234567.5"), locale: Locale(identifier: "de_DE")), "1234567,5")
        XCTAssertEqual(PriceFormat.editable(dec("1234567.5"), locale: Locale(identifier: "ar_EG")), "1234567\u{066B}5")
        XCTAssertEqual(PriceFormat.editable(dec("1234567.5"), locale: Locale(identifier: "fa_IR")), "1234567\u{066B}5")
    }

    func testEditableHasNoDecimalsForWholeAmounts() {
        XCTAssertEqual(PriceFormat.editable(1299, locale: sv), "1299")
        XCTAssertEqual(PriceFormat.editable(dec("1299.00"), locale: sv), "1299")
        XCTAssertEqual(PriceFormat.editable(dec("19.90"), locale: sv), "19,9")
        XCTAssertEqual(PriceFormat.editable(0, locale: en), "0")
    }

    func testEditableNeverRounds() {
        XCTAssertEqual(PriceFormat.editable(dec("1.005"), locale: en), "1.005")
        XCTAssertEqual(PriceFormat.editable(dec("1.9999"), locale: sv), "1,9999")
        XCTAssertEqual(PriceFormat.editable(dec("0.0001"), locale: en), "0.0001")
    }

    func testEditableKeepsTheSign() {
        XCTAssertEqual(PriceFormat.editable(dec("-5.5"), locale: en), "-5.5")
        XCTAssertEqual(PriceFormat.editable(dec("-5.5"), locale: sv), "-5,5")
    }

    func testEditableOfNaNIsEmpty() {
        XCTAssertEqual(PriceFormat.editable(.nan, locale: en), "")
    }

    func testEditableRoundTripsThroughTheParserInEveryLocale() {
        let values = ["0", "1", "0.01", "0.5", "1.005", "1.0001", "19.99", "1299", "1299.5", "12345.67", "1234567.89",
                      "999999999999.9999", "-5.25"]
        for locale in locales {
            for text in values {
                let value = dec(text)
                let shown = PriceFormat.editable(value, locale: locale)
                XCTAssertTrue(shown.unicodeScalars.allSatisfy(\.isASCII) || shown.contains("\u{066B}"),
                              "\(locale.identifier): \(shown.debugDescription)")
                XCTAssertEqual(PriceInput.parse(shown, locale: locale), .value(value),
                               "\(locale.identifier): \(value) shown as \(shown.debugDescription)")
            }
        }
    }
}
