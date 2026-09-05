import Foundation
import Testing
@testable import TechCalcCore

/// `STAT CALC`: the summaries and the curve fits.
///
/// The numbers themselves are pinned by the R-sourced benchmark fixtures. This suite asserts the
/// structural properties instead — the TI's quartile rule, the coefficient ordering each model
/// promises, the frequency-list semantics, and that these functions and the `LIST MATH`
/// reductions are one implementation rather than two.
@Suite("Statistics")
struct StatisticsTests {

    private static let even = [12.0, 7, 3, 19, 25, 8, 14, 3, 11, 20]
    private static let odd = [4.0, 8, 15, 16, 23, 42, 8]

    // MARK: - Quartiles

    @Test("An odd-length sample excludes its own median from both halves")
    func quartileRuleOnOddCounts() throws {
        // Sorted: 4 8 8 15 16 23 42. The median 15 belongs to neither half, so Q1 is the median
        // of {4,8,8} and Q3 the median of {16,23,42}.
        let quartiles = try Statistics.quartiles(of: Self.odd.sorted())
        #expect(quartiles.q1 == 8)
        #expect(quartiles.median == 15)
        #expect(quartiles.q3 == 23)
    }

    @Test("An even-length sample splits cleanly in two")
    func quartileRuleOnEvenCounts() throws {
        // Sorted: 3 3 7 8 11 12 14 19 20 25.
        let quartiles = try Statistics.quartiles(of: Self.even.sorted())
        #expect(quartiles.q1 == 7)
        #expect(quartiles.median == 11.5)
        #expect(quartiles.q3 == 19)
    }

    // MARK: - One implementation, not two

    @Test("1-Var Stats and the LIST MATH reductions agree, because they are the same code")
    func summariesAgreeWithListMath() throws {
        let values = Self.even.map { Complex($0) }
        let summary = try Statistics.oneVar(Self.even)
        expectClose(summary.mean, try ListMath.mean(values).re, tolerance: 1e-15)
        expectClose(summary.sampleStandardDeviation, try ListMath.standardDeviation(values), tolerance: 1e-15)
        expectClose(summary.median, try ListMath.median(values), tolerance: 1e-15)
    }

    @Test("The population and sample deviations use the divisors the TI names them for")
    func deviationDivisors() throws {
        let summary = try Statistics.oneVar([2, 4, 4, 4, 5, 5, 7, 9])
        // Mean 5, squared error 32: σx is sqrt(32/8) = 2 and Sx is sqrt(32/7).
        expectClose(summary.populationStandardDeviation, 2, tolerance: 1e-14)
        expectClose(summary.sampleStandardDeviation, (32.0 / 7).squareRoot(), tolerance: 1e-14)
    }

    // MARK: - Frequencies

    @Test("A frequency list repeats each value, and must be whole and non-negative")
    func frequencyLists() throws {
        let weighted = try Statistics.oneVar([1, 2, 3], frequencies: [1, 2, 3])
        let expanded = try Statistics.oneVar([1, 2, 2, 3, 3, 3])
        #expect(weighted.n == 6)
        expectClose(weighted.mean, expanded.mean, tolerance: 1e-15)
        expectClose(weighted.sampleStandardDeviation, expanded.sampleStandardDeviation, tolerance: 1e-15)

        #expect(throws: TIError.domain) { try Statistics.expanded([1, 2], frequencies: [1, 1.5]) }
        #expect(throws: TIError.domain) { try Statistics.expanded([1, 2], frequencies: [1, -1]) }
        #expect(throws: TIError.dimensionMismatch) { try Statistics.expanded([1, 2], frequencies: [1]) }
    }

    // MARK: - Regression coefficient conventions

    @Test("The two linear forms differ only in which coefficient is the slope")
    func linearFormsSwapTheirCoefficients() throws {
        let x = [1.0, 2, 3, 4, 5]
        let y = [2.0, 4, 5, 4, 5]
        let axb = try Statistics.regression(.linearAXB, x, y)
        let abx = try Statistics.regression(.linearABX, x, y)
        #expect(axb.coefficients[0] == abx.coefficients[1])
        #expect(axb.coefficients[1] == abx.coefficients[0])
        expectClose(axb.correlation ?? .nan, abx.correlation ?? .nan, tolerance: 1e-15)
    }

    @Test("Polynomial coefficients come back highest power first")
    func polynomialCoefficientOrder() throws {
        // y = 2x² + 3x + 1 exactly, so the fit must recover (a, b, c) = (2, 3, 1).
        let x = [0.0, 1, 2, 3, 4]
        let y = x.map { 2 * $0 * $0 + 3 * $0 + 1 }
        let fit = try Statistics.regression(.quadratic, x, y)
        #expect(fit.coefficients.count == 3)
        expectClose(fit.coefficients[0], 2, tolerance: 1e-9)
        expectClose(fit.coefficients[1], 3, tolerance: 1e-9)
        expectClose(fit.coefficients[2], 1, tolerance: 1e-9)
        expectClose(fit.coefficientOfDetermination, 1, tolerance: 1e-9)
        // r is undefined for a model with more than two parameters, as on the TI.
        #expect(fit.correlation == nil)
    }

    @Test("Each model fills exactly as many coefficients as it declares")
    func coefficientCounts() throws {
        let x = [1.0, 2, 3, 4, 5, 6, 7]
        let y = [2.0, 4.1, 6.2, 7.9, 10.1, 12.2, 13.8]
        for model in RegressionModel.allCases {
            let fit = try Statistics.regression(model, x, y)
            #expect(fit.coefficients.count == model.coefficientCount, "\(model)")
        }
    }

    @Test("A perfect exponential and a perfect power law are recovered exactly")
    func transformedFitsRecoverTheirParameters() throws {
        let x = [1.0, 2, 3, 4, 5]
        let exponential = try Statistics.regression(.exponential, x, x.map { 3 * Foundation.pow(2.0, $0) })
        expectClose(exponential.coefficients[0], 3, tolerance: 1e-9)
        expectClose(exponential.coefficients[1], 2, tolerance: 1e-9)

        let power = try Statistics.regression(.power, x, x.map { 5 * Foundation.pow($0, 1.5) })
        expectClose(power.coefficients[0], 5, tolerance: 1e-9)
        expectClose(power.coefficients[1], 1.5, tolerance: 1e-9)
    }

    // MARK: - Errors

    @Test("Mismatched or undersized samples are TI errors, not silent answers")
    func regressionErrors() {
        #expect(throws: TIError.dimensionMismatch) {
            try Statistics.regression(.linearAXB, [1, 2, 3], [1, 2])
        }
        // A quartic needs five coefficients and so at least five points.
        #expect(throws: TIError.invalidDimension) {
            try Statistics.regression(.quartic, [1, 2, 3], [1, 2, 3])
        }
        // The transformed fits are undefined on non-positive values.
        #expect(throws: TIError.domain) {
            try Statistics.regression(.logarithmic, [0, 1, 2], [1, 2, 3])
        }
        #expect(throws: TIError.domain) {
            try Statistics.regression(.exponential, [1, 2, 3], [1, 0, 3])
        }
    }

    @Test("A rank-deficient fit surfaces as ERR:SINGULAR MAT from the shared elimination")
    func degenerateDesignIsSingular() {
        // Every x is the same, so the normal equations have no unique solution.
        #expect(throws: TIError.singularMatrix) {
            try Statistics.regression(.quadratic, [2, 2, 2, 2], [1, 2, 3, 4])
        }
    }

    // MARK: - Through the entry line

    @Test("The entry-line commands publish the same numbers the pure functions return")
    func commandsAndFunctionsAgree() throws {
        var calculator = Fixture.calculator()
        #expect(calculator.enter("{12,7,3,19,25,8,14,3,11,20}→L1").errorName == nil)
        #expect(calculator.enter("1-Var Stats(L1)").display == "Done")

        let expected = try Statistics.oneVar(Self.even)
        expectClose(try calculator.context.statistics.value(of: .meanX), expected.mean, tolerance: 1e-15)
        expectClose(try calculator.context.statistics.value(of: .sampleDeviationX),
                    expected.sampleStandardDeviation, tolerance: 1e-15)
        expectClose(try calculator.context.statistics.value(of: .firstQuartile), expected.firstQuartile)
    }

    @Test("Running a second command replaces the first command's results")
    func resultsAreReplacedNotMerged() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3,4}→L1")
        calculator.enter("{2,4,6,8}→L2")
        calculator.enter("2-Var Stats(L1,L2)")
        #expect(try calculator.context.statistics.value(of: .meanY) == 5)

        calculator.enter("1-Var Stats(L1)")
        // `ȳ` belongs to the two-variable summary; after a one-variable run it is gone.
        #expect(throws: TIError.undefined) { try calculator.context.statistics.value(of: .meanY) }
        #expect(try calculator.context.statistics.value(of: .meanX) == 2.5)
    }
}
