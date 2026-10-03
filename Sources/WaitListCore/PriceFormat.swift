import Foundation

/// How prices are shown. Shared by the app and the notification text so both always agree.
public enum PriceFormat {
    /// The amount in `currencyCode`, in the locale's style: "1 299 kr" for whole amounts (no ",00"),
    /// "19,99 kr" otherwise.
    public static func string(_ amount: Decimal, currencyCode: String, locale: Locale = .current) -> String {
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
        return isWhole(amount) ? amount.formatted(style.precision(.fractionLength(0))) : amount.formatted(style)
    }

    /// The amount as the user would type it, for an edit field: ASCII digits, the locale's decimal separator,
    /// every decimal the amount has (never rounded) and no trailing zeros, no grouping. "1299", "1299,5",
    /// "1.005". `PriceInput.parse(_:locale:)` reads it back to the same amount in the same locale.
    public static func editable(_ amount: Decimal, locale: Locale = .current) -> String {
        guard amount.isFinite else { return "" }
        // Decimal's description is plain ASCII with "." and no exponent, e.g. "-1299.5".
        var plain = amount.description
        if plain.contains(".") {
            while plain.hasSuffix("0") { plain.removeLast() }
            if plain.hasSuffix(".") { plain.removeLast() }
        }
        let separator = locale.decimalSeparator ?? "."
        return separator == "." ? plain : plain.replacingOccurrences(of: ".", with: separator)
    }

    /// True if the amount has no fractional part.
    static func isWhole(_ amount: Decimal) -> Bool {
        var input = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return rounded == amount
    }
}
