import Foundation

/// Renders evaluated values as the strings the TI-84 Plus CE would display.
///
/// TI parity is achieved *here*, at the display layer, not in the arithmetic: all computation
/// uses `Double`, and this formatter rounds to 10 significant digits and honours
/// NORMAL/SCI/ENG and FLOAT/fixed 0-9. Benchmark fixtures assert these strings for display
/// parity, alongside a 1e-9 relative tolerance on the raw values for numeric parity.
public struct DisplayFormatter: Sendable {
    /// The TI displays 10 significant digits.
    public static let significantDigits = 10

    /// NORMAL notation gives way to scientific at or above 1e10, and below 1e-3.
    static let normalUpperExponent = 10
    static let normalLowerExponent = -4

    public let mode: CalculatorMode

    public init(mode: CalculatorMode = .default) {
        self.mode = mode
    }

    // MARK: - Values

    public func string(for value: TIValue) -> String {
        switch value {
        case .real(let x):
            return string(forReal: x)
        case .complex(let z):
            return string(forComplex: z)
        case .list(let list):
            // The delimiters come from `ContainerSyntax`, the same place the tokenizer reads
            // them. Elements are separated by spaces, as the TI displays them.
            let elements = list.values.map { string(forComplex: $0) }.joined(separator: " ")
            return "\(ContainerSyntax.listOpen)\(elements)\(ContainerSyntax.listClose)"
        case .matrix(let matrix):
            let rows = (1...matrix.rows).map { row -> String in
                let cells = (1...matrix.columns).compactMap { column -> String? in
                    guard let element = try? matrix[tiRow: row, tiColumn: column] else { return nil }
                    return string(forComplex: element)
                }
                return "\(ContainerSyntax.matrixOpen)\(cells.joined(separator: " "))\(ContainerSyntax.matrixClose)"
            }
            return "\(ContainerSyntax.matrixOpen)\(rows.joined())\(ContainerSyntax.matrixClose)"
        case .string(let text):
            return text
        }
    }

    public func string(forComplex z: Complex) -> String {
        if z.isReal { return string(forReal: z.re) }
        switch mode.complex {
        case .polar:
            return string(forReal: z.magnitude) + "e^(" + string(forReal: z.argument) + "i)"
        case .real, .rectangular:
            let imaginary = string(forReal: z.im) + "i"
            if z.re == 0 { return imaginary }
            return string(forReal: z.re) + (z.im < 0 ? "" : "+") + imaginary
        }
    }

    // MARK: - Reals

    public func string(forReal value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-∞" : "∞" }

        let rounded = Self.roundToSignificantDigits(value, Self.significantDigits)
        if rounded == 0 { return zeroString() }

        let exponent = Self.decimalExponent(of: rounded)
        switch mode.notation {
        case .scientific:
            return scientificString(rounded, exponent: exponent)
        case .engineering:
            let engineeringExponent = Int((Double(exponent) / 3).rounded(.down)) * 3
            return scientificString(rounded, exponent: engineeringExponent)
        case .normal:
            if exponent >= Self.normalUpperExponent || exponent <= Self.normalLowerExponent {
                return scientificString(rounded, exponent: exponent)
            }
            return Self.stripLeadingZero(fixedPointString(rounded, exponent: exponent))
        }
    }

    private func zeroString() -> String {
        switch mode.decimals {
        case .float: return "0"
        case .fixed(let places): return places == 0 ? "0" : Self.stripLeadingZero(String(format: "%.\(places)f", 0.0))
        }
    }

    /// Plain decimal rendering, honouring FLOAT (trim to the significant digits) or fixed places.
    private func fixedPointString(_ value: Double, exponent: Int) -> String {
        switch mode.decimals {
        case .fixed(let places):
            return String(format: "%.\(places)f", value)
        case .float:
            let places = Swift.max(0, Swift.min(Self.significantDigits - 1 - exponent, 15))
            return Self.trimTrailingZeros(String(format: "%.\(places)f", value))
        }
    }

    /// `mantissa E exponent`, with the mantissa scaled so SCI gives one integer digit and ENG
    /// gives one to three.
    private func scientificString(_ value: Double, exponent: Int) -> String {
        let mantissa = Self.scaled(value, byPowerOfTen: -exponent)
        let mantissaText: String
        switch mode.decimals {
        case .fixed(let places):
            mantissaText = String(format: "%.\(places)f", mantissa)
        case .float:
            let integerDigits = Swift.max(1, Self.decimalExponent(of: mantissa) + 1)
            let places = Swift.max(0, Self.significantDigits - integerDigits)
            mantissaText = Self.trimTrailingZeros(String(format: "%.\(places)f", mantissa))
        }
        return Self.stripLeadingZero(mantissaText) + "E" + String(exponent)
    }

    // MARK: - Numeric helpers

    /// `floor(log10(|value|))`, corrected for the cases where `log10` lands just off a power of ten.
    static func decimalExponent(of value: Double) -> Int {
        guard value != 0, value.isFinite else { return 0 }
        let magnitude = Swift.abs(value)
        var exponent = Int(Foundation.log10(magnitude).rounded(.down))
        if scaled(magnitude, byPowerOfTen: -exponent) >= 10 { exponent += 1 }
        if scaled(magnitude, byPowerOfTen: -exponent) < 1 { exponent -= 1 }
        return exponent
    }

    /// Multiplies by a power of ten in two steps for large exponents, so `1e-320 * 1e320`
    /// does not pass through an infinite or denormal intermediate.
    static func scaled(_ value: Double, byPowerOfTen power: Int) -> Double {
        if power > 300 { return value * Foundation.pow(10.0, 300) * Foundation.pow(10.0, Double(power - 300)) }
        if power < -300 { return value * Foundation.pow(10.0, -300) * Foundation.pow(10.0, Double(power + 300)) }
        return value * Foundation.pow(10.0, Double(power))
    }

    public static func roundToSignificantDigits(_ value: Double, _ digits: Int) -> Double {
        guard value != 0, value.isFinite else { return value }
        let exponent = decimalExponent(of: value)
        let shift = digits - 1 - exponent
        let shifted = scaled(value, byPowerOfTen: shift)
        guard shifted.isFinite else { return value }
        return scaled(shifted.rounded(), byPowerOfTen: -shift)
    }

    // MARK: - String helpers

    static func trimTrailingZeros(_ text: String) -> String {
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed.isEmpty ? "0" : trimmed
    }

    /// The TI drops the integer zero: `.5`, not `0.5`.
    static func stripLeadingZero(_ text: String) -> String {
        if text.hasPrefix("0.") { return String(text.dropFirst()) }
        if text.hasPrefix("-0.") { return "-" + text.dropFirst(2) }
        return text
    }

    // MARK: - Fraction conversion

    /// `>Frac`: the rational form when one exists under the TI's 9999 denominator cap, otherwise
    /// the decimal unchanged.
    public func fractionString(forReal value: Double) -> String {
        guard let rational = Rational.reconstruct(value) else { return string(forReal: value) }
        if rational.denominator == 1 { return string(forReal: Double(rational.numerator)) }
        return "\(rational.numerator)/\(rational.denominator)"
    }

    public func fractionString(for value: TIValue) -> String {
        switch value {
        case .real(let x): fractionString(forReal: x)
        default: string(for: value)
        }
    }
}
