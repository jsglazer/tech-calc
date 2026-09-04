import Foundation
import Testing
@testable import TechCalcCore

/// Display parity: TI parity is asserted on the formatted string, not on the raw Double.
@Suite("Display formatting")
struct DisplayFormatterTests {

    private func formatter(
        notation: NotationMode = .normal,
        decimals: DecimalMode = .float,
        complex: ComplexMode = .real
    ) -> DisplayFormatter {
        DisplayFormatter(mode: CalculatorMode(notation: notation, decimals: decimals, complex: complex))
    }

    @Test("NORMAL FLOAT shows up to 10 significant digits and drops the leading zero")
    func normalFloat() {
        let f = formatter()
        #expect(f.string(forReal: 0) == "0")
        #expect(f.string(forReal: 42) == "42")
        #expect(f.string(forReal: -42.5) == "-42.5")
        #expect(f.string(forReal: 0.5) == ".5")
        #expect(f.string(forReal: -0.5) == "-.5")
        #expect(f.string(forReal: 1.0 / 3.0) == ".3333333333")
        #expect(f.string(forReal: 2.0 / 3.0) == ".6666666667")
        #expect(f.string(forReal: Double.pi) == "3.141592654")
        #expect(f.string(forReal: 0.001) == ".001")
    }

    @Test("NORMAL falls back to scientific at 1e10 and below 1e-3")
    func normalFallsBackToScientific() {
        let f = formatter()
        #expect(f.string(forReal: 1e10) == "1E10")
        #expect(f.string(forReal: 1e-4) == "1E-4")
        #expect(f.string(forReal: 123456789012) == "1.23456789E11")
        #expect(f.string(forReal: 9999999999) == "9999999999")
    }

    @Test("SCI notation gives one integer digit")
    func scientific() {
        let f = formatter(notation: .scientific)
        #expect(f.string(forReal: 123.456) == "1.23456E2")
        #expect(f.string(forReal: 0.00123) == "1.23E-3")
        #expect(f.string(forReal: -5) == "-5E0")
    }

    @Test("ENG notation gives an exponent that is a multiple of three")
    func engineering() {
        let f = formatter(notation: .engineering)
        #expect(f.string(forReal: 123456) == "123.456E3")
        #expect(f.string(forReal: 0.0000123) == "12.3E-6")
        #expect(f.string(forReal: 5) == "5E0")
    }

    @Test("Fixed decimals 0-9 are honoured in every notation")
    func fixedDecimals() {
        #expect(formatter(decimals: .fixed(2)).string(forReal: Double.pi) == "3.14")
        #expect(formatter(decimals: .fixed(0)).string(forReal: 2.7) == "3")
        #expect(formatter(decimals: .fixed(4)).string(forReal: 1) == "1.0000")
        #expect(formatter(notation: .scientific, decimals: .fixed(2)).string(forReal: 123.456) == "1.23E2")
        // The clamp keeps an out-of-range setting from reaching the formatter.
        #expect(DecimalMode.fixedClamped(12) == .fixed(9))
        #expect(DecimalMode.fixedClamped(-3) == .fixed(0))
    }

    @Test("Rounding to 10 significant digits happens before formatting")
    func significantDigitRounding() {
        expectClose(DisplayFormatter.roundToSignificantDigits(1.23456789012345, 10), 1.234567890)
        #expect(formatter().string(forReal: 0.1 + 0.2) == ".3")
        #expect(formatter().string(forReal: 1e100 / 3) == "3.333333333E99")
    }

    @Test("Complex presentation follows the complex mode")
    func complexPresentation() {
        let rectangular = formatter(complex: .rectangular)
        #expect(rectangular.string(forComplex: Complex(3, 4)) == "3+4i")
        #expect(rectangular.string(forComplex: Complex(3, -4)) == "3-4i")
        #expect(rectangular.string(forComplex: Complex(0, 2)) == "2i")
        #expect(rectangular.string(forComplex: Complex(5, 0)) == "5")

        let polar = formatter(complex: .polar)
        #expect(polar.string(forComplex: Complex(0, 2)) == "2e^(1.570796327i)")
    }

    @Test("▸Frac reconstructs a rational up to denominator 9999, otherwise leaves the decimal")
    func fractionConversion() {
        let f = formatter()
        #expect(f.fractionString(forReal: 0.75) == "3/4")
        #expect(f.fractionString(forReal: 1.0 / 3.0) == "1/3")
        #expect(f.fractionString(forReal: -5.0 / 8.0) == "-5/8")
        #expect(f.fractionString(forReal: 4) == "4")
        #expect(f.fractionString(forReal: 1.0 / 9999.0) == "1/9999")
        // No rational within the cap: pi and 1/10000 fall through to the decimal.
        #expect(f.fractionString(forReal: Double.pi) == "3.141592654")
        #expect(Rational.reconstruct(1.0 / 10000.0) == nil)
        #expect(Rational.maxDenominator == 9999)
    }

    @Test("The ▸Frac and ▸Dec marks override the answer mode for one entry")
    func conversionMarksOverrideAnswerMode() {
        #expect(Fixture.display("3/4▸Frac") == "3/4")
        #expect(Fixture.display("3/4") == ".75")

        let fractionMode = CalculatorMode(answer: .fraction)
        #expect(Fixture.display("3/4", mode: fractionMode) == "3/4")
        #expect(Fixture.display("3/4▸Dec", mode: fractionMode) == ".75")
    }

    @Test("▸Rect and ▸Polar change presentation without changing the value")
    func complexConversionMarks() throws {
        let rectangular = CalculatorMode(complex: .rectangular)
        #expect(Fixture.display("i▸Polar", mode: rectangular) == "1e^(1.570796327i)")
        #expect(Fixture.display("i▸Rect", mode: rectangular) == "1i")
        #expect(try Fixture.value("i▸Polar", mode: rectangular) == .complex(Complex.i))
    }
}
