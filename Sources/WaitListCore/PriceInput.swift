import Foundation

/// What the user typed into the price field.
public enum PriceInput: Equatable, Sendable {
    case empty
    case value(Decimal)
    case invalid

    /// Largest number of integer digits accepted (leading zeros do not count): just under a trillion.
    public static let maxIntegerDigits = 12
    /// Largest number of decimals accepted (trailing zeros do not count).
    public static let maxFractionDigits = 4

    /// Reads a price the way people type or paste it.
    ///
    /// Clean-up first:
    /// - Digits from any script (Arabic-Indic "١٢٣", fullwidth "１２３") count as 0-9.
    /// - Invisible format characters (direction marks, zero-width space, BOM) are dropped. Every kind of space
    ///   (including no-break and narrow no-break space) counts as a space.
    /// - `'` and `’` are always thousands separators, as are U+066C and the locale's own grouping character
    ///   when that is not "." or ",". U+066B and the locale's own decimal character when that is not "." or ","
    ///   are always decimal separators.
    /// - Currency symbols and letters at either end are a label and ignored ("$", "SEK 20", "1299 kr"), along
    ///   with a period right after such letters ("kr. 20", "Rs.500", "20 kr."). One minus sign ("-" or "−")
    ///   may come before the number or its label ("-$5", "$-5", "kr -5").
    ///
    /// Then "." and "," are read by position, so the same text means the same amount wherever possible:
    /// - Both appear: the last one is the decimal separator ("1.234,56", "1,234.56"). It must appear once, and
    ///   the other one must separate groups of 3 digits.
    /// - One of them appears once: with 0-2 digits after it, it is the decimal separator ("19,99", "19.99",
    ///   "5."). With exactly 3 digits after it, it is the decimal separator if it is the locale's, otherwise a
    ///   thousands separator ("1,299" is 1299 in en_US and 1.299 in sv_SE). With 4 or more digits after it, it
    ///   must be the locale's decimal separator.
    /// - One of them appears more than once: thousands separators, and every group after the first must have
    ///   3 digits ("1,234,567"). Indian grouping ("12,34,567") is accepted too.
    /// - Spaces and apostrophes between digits are thousands separators; their group sizes are not checked.
    ///
    /// The result is `.invalid` for anything else: letters or symbols between digits (including scientific
    /// notation such as "1e5"), more than `maxIntegerDigits` integer digits, more than `maxFractionDigits`
    /// decimals, or no digits at all. A negative amount is returned as a negative value; the caller decides
    /// whether to accept it. Blank text (only spaces or invisible characters) is `.empty`.
    public static func parse(_ text: String, locale: Locale = .current) -> PriceInput {
        let tokens = tokenize(text, locale: locale)
        if tokens.allSatisfy({ $0 == .space }) { return .empty }

        guard let (isNegative, body) = stripLabelsAndSign(tokens),
              let separated = separate(body) else {
            return .invalid
        }
        guard let number = split(separated, locale: locale) else { return .invalid }

        let integer = String(number.integer.drop { $0 == "0" })
        var fraction = Substring(number.fraction)
        while fraction.last == "0" { fraction.removeLast() }
        guard integer.count <= maxIntegerDigits, fraction.count <= maxFractionDigits else { return .invalid }

        let posix = Locale(identifier: "en_US_POSIX")
        guard let magnitude = Decimal(string: "\(integer.isEmpty ? "0" : integer).\(fraction.isEmpty ? "0" : fraction)",
                                      locale: posix) else {
            return .invalid
        }
        // No negative zero: "-0" is just 0.
        return .value(isNegative && !magnitude.isZero ? -magnitude : magnitude)
    }

    // MARK: Tokens

    private enum Token: Equatable {
        case digit(Character)  // always ASCII 0-9
        case dot               // "." : decimal or grouping, decided by position
        case comma             // "," : decimal or grouping, decided by position
        case decimalMark       // only ever a decimal separator
        case groupMark         // only ever a grouping separator
        case space
        case minus
        case letter            // letters and combining marks: part of a label
        case currency          // currency symbols: part of a label
        case other

        var isSeparator: Bool {
            switch self {
            case .dot, .comma, .decimalMark, .groupMark, .space: return true
            default: return false
            }
        }
    }

    private static func tokenize(_ text: String, locale: Locale) -> [Token] {
        let localeDecimal = singleScalar(locale.decimalSeparator)
        let localeGrouping = singleScalar(locale.groupingSeparator)
        var tokens: [Token] = []
        for scalar in text.unicodeScalars {
            let properties = scalar.properties
            switch scalar {
            case ".", "\u{FF0E}":
                tokens.append(.dot)
                continue
            case ",", "\u{FF0C}":
                tokens.append(.comma)
                continue
            case "\u{066B}":  // ARABIC DECIMAL SEPARATOR
                tokens.append(.decimalMark)
                continue
            case "'", "\u{2019}", "\u{066C}":  // apostrophes, ARABIC THOUSANDS SEPARATOR
                tokens.append(.groupMark)
                continue
            case "-", "\u{2212}", "\u{FE63}", "\u{FF0D}":  // hyphen-minus, MINUS SIGN, small and fullwidth forms
                tokens.append(.minus)
                continue
            default:
                break
            }
            if scalar == localeDecimal {
                tokens.append(.decimalMark)
            } else if properties.isWhitespace {
                tokens.append(.space)
            } else if scalar == localeGrouping {
                tokens.append(.groupMark)
            } else {
                switch properties.generalCategory {
                case .format:
                    continue  // invisible: direction marks, zero-width space, BOM
                case .decimalNumber:
                    if let value = Character(scalar).wholeNumberValue, (0...9).contains(value) {
                        tokens.append(.digit(Character(String(value))))
                    } else {
                        tokens.append(.other)
                    }
                case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                     .nonspacingMark, .spacingMark, .enclosingMark:
                    tokens.append(.letter)
                case .currencySymbol:
                    tokens.append(.currency)
                default:
                    tokens.append(.other)
                }
            }
        }
        return tokens
    }

    /// The locale's separator as a single scalar, unless it is "." or "," (those are read by position).
    private static func singleScalar(_ separator: String?) -> Unicode.Scalar? {
        guard let separator, separator != ".", separator != ",",
              separator.unicodeScalars.count == 1 else { return nil }
        return separator.unicodeScalars.first
    }

    // MARK: Steps

    /// Drops the label and spaces at both ends and takes off a leading minus. Returns nil if what is left
    /// contains anything but digits and separators, or no digit.
    private static func stripLabelsAndSign(_ tokens: [Token]) -> (isNegative: Bool, body: ArraySlice<Token>)? {
        var start = tokens.startIndex
        var end = tokens.endIndex
        var isNegative = false
        var afterLetter = false
        leading: while start < end {
            switch tokens[start] {
            case .space, .currency:
                afterLetter = false
            case .letter:
                afterLetter = true
            case .dot where afterLetter:  // "kr. 20": the period belongs to the abbreviation
                afterLetter = false
            case .minus where !isNegative:  // a second minus stays in the body, which makes it invalid
                isNegative = true
                afterLetter = false
            default:
                break leading
            }
            start += 1
        }
        while end > start {
            let last = tokens[end - 1]
            let isLabel = last == .space || last == .currency || last == .letter
            let isAbbreviationPeriod = last == .dot && end - 2 >= start && tokens[end - 2] == .letter
            guard isLabel || isAbbreviationPeriod else { break }
            end -= 1
        }
        let body = tokens[start..<end]
        guard body.contains(where: { if case .digit = $0 { return true } else { return false } }),
              body.allSatisfy({ if case .digit = $0 { return true } else { return $0.isSeparator } }) else {
            return nil
        }
        return (isNegative, body)
    }

    /// The body as digit runs and the single separators between them. Spaces and apostrophes are merged into
    /// one grouping mark, which is dropped next to "." and "," ("1 ,5"). Returns nil for two separators in a row
    /// or a grouping mark at either end.
    private static func separate(_ body: ArraySlice<Token>) -> (runs: [String], separators: [Token])? {
        // Spaces inside the body are grouping marks; collapse runs of them.
        var merged: [Token] = []
        for token in body {
            let normalized = token == .space ? Token.groupMark : token
            if normalized == .groupMark, merged.last == .groupMark { continue }
            merged.append(normalized)
        }
        // A grouping mark next to a decimal-capable separator is just spacing.
        func isDecimalCapable(_ token: Token?) -> Bool {
            token == .dot || token == .comma || token == .decimalMark
        }
        var cleaned: [Token] = []
        for (index, token) in merged.enumerated() {
            if token == .groupMark {
                let before: Token? = index > 0 ? merged[index - 1] : nil
                let after: Token? = index + 1 < merged.count ? merged[index + 1] : nil
                if isDecimalCapable(before) || isDecimalCapable(after) { continue }
                if before == nil || after == nil { return nil }
            }
            cleaned.append(token)
        }

        var runs = [""]
        var separators: [Token] = []
        for token in cleaned {
            if case .digit(let digit) = token {
                runs[runs.count - 1].append(digit)
            } else {
                runs.append("")
                separators.append(token)
            }
        }
        return (runs, separators)
    }

    /// Decides which separator (if any) is the decimal one, checks the grouping, and returns the digits.
    private static func split(_ separated: (runs: [String], separators: [Token]), locale: Locale)
        -> (integer: String, fraction: String)? {
        let (runs, separators) = separated
        let decimalMarks = separators.indices.filter { separators[$0] == .decimalMark }
        let dots = separators.indices.filter { separators[$0] == .dot }
        let commas = separators.indices.filter { separators[$0] == .comma }

        var decimalIndex: Int?
        if decimalMarks.count > 1 {
            return nil
        } else if let mark = decimalMarks.first {
            decimalIndex = mark
        } else if let lastDot = dots.last, let lastComma = commas.last {
            let last = max(lastDot, lastComma)
            guard (last == lastDot ? dots : commas).count == 1 else { return nil }
            decimalIndex = last
        } else if dots.count + commas.count == 1, let index = (dots + commas).first {
            // Only one "." or "," in the whole number: the digits after it decide.
            let digitsAfter = runs[index + 1].count
            let isLocaleDecimal = (separators[index] == .dot ? "." : ",") == (locale.decimalSeparator ?? ".")
            switch digitsAfter {
            case 0...2: decimalIndex = index
            case 3: decimalIndex = isLocaleDecimal ? index : nil
            default:
                guard isLocaleDecimal else { return nil }
                decimalIndex = index
            }
        }
        // Otherwise "." or "," appears more than once (all grouping), or neither appears.

        // The decimal separator must be the last separator; everything before it is grouping.
        let groupingEnd: Int
        if let decimalIndex {
            guard decimalIndex == separators.count - 1 else { return nil }
            groupingEnd = decimalIndex
        } else {
            groupingEnd = separators.count
        }
        for index in 0..<groupingEnd where runs[index].isEmpty || runs[index + 1].isEmpty {
            return nil  // a grouping separator needs digits on both sides
        }
        for kind in [Token.dot, .comma] {
            let sizes = (0..<groupingEnd).filter { separators[$0] == kind }.map { runs[$0 + 1].count }
            guard isValidGrouping(sizes) else { return nil }
        }

        let integerRuns = runs[0...groupingEnd]
        let fraction = decimalIndex == nil ? "" : runs[groupingEnd + 1]
        return (integerRuns.joined(), fraction)
    }

    /// Group sizes after each "." or "," used for grouping: all 3 ("1,234,567"), or Indian lakh/crore
    /// grouping where every group but the last has 2 digits ("12,34,567").
    private static func isValidGrouping(_ sizes: [Int]) -> Bool {
        if sizes.allSatisfy({ $0 == 3 }) { return true }
        return sizes.count >= 2 && sizes.last == 3 && sizes.dropLast().allSatisfy { $0 == 2 }
    }
}
