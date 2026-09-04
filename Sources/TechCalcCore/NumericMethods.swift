import Foundation

/// Iterative numerical routines.
///
/// Every loop here carries an explicit step limit and a defined convergence tolerance, and
/// throws `ERR:ITERATIONS` rather than spinning: a solver that can run unbounded would starve
/// the caller's thread and would make a test flaky.
public enum NumericMethods {
    /// Maximum Romberg refinement levels for `fnInt(`. Level 20 is 2^20 subintervals.
    public static let maximumIntegrationLevels = 20
    /// Relative convergence tolerance for `fnInt(`.
    public static let integrationTolerance = 1e-10
    /// The TI's default step for `nDeriv(`.
    public static let derivativeStep = 1e-3
    /// Upper bound on the term count of `Σ(`, so a mistyped range cannot hang the evaluator.
    public static let maximumSummationTerms = 1_000_000

    /// Romberg integration of `f` over `[lower, upper]`.
    public static func integrate(
        lower: Double,
        upper: Double,
        _ f: (Double) throws -> Double
    ) throws -> Double {
        guard lower.isFinite, upper.isFinite else { throw TIError.domain }
        if lower == upper { return 0 }
        if lower > upper { return -(try integrate(lower: upper, upper: lower, f)) }

        var table: [Double] = []
        var previousRow: [Double] = []
        var h = upper - lower
        var trapezoid = 0.5 * h * ((try f(lower)) + (try f(upper)))
        previousRow = [trapezoid]

        for level in 1...Self.maximumIntegrationLevels {
            // Refine the trapezoid rule by adding the midpoints of the previous level.
            let intervals = 1 << (level - 1)
            h /= 2
            var midpointSum = 0.0
            for index in 0..<intervals {
                midpointSum += try f(lower + (Double(index) * 2 + 1) * h)
            }
            trapezoid = 0.5 * trapezoid + h * midpointSum

            table = [trapezoid]
            var power = 1.0
            for column in 1...level {
                power *= 4
                let extrapolated = (power * table[column - 1] - previousRow[column - 1]) / (power - 1)
                table.append(extrapolated)
            }

            if level >= 3 {
                let best = table[level]
                let previousBest = previousRow[level - 1]
                let scale = Swift.max(1, Swift.abs(best))
                if Swift.abs(best - previousBest) <= Self.integrationTolerance * scale {
                    return best
                }
            }
            previousRow = table
        }

        throw TIError.iterations
    }

    /// Symmetric difference quotient, as `nDeriv(` uses. Fixed two-point stencil: no loop, and so
    /// no way for it to fail to terminate.
    public static func derivative(
        at x: Double,
        step: Double = NumericMethods.derivativeStep,
        _ f: (Double) throws -> Double
    ) throws -> Double {
        guard step != 0, step.isFinite, x.isFinite else { throw TIError.domain }
        return ((try f(x + step)) - (try f(x - step))) / (2 * step)
    }

    /// `Σ(expression, variable, start, end)` over an integer range, bounded by a term budget.
    public static func summation(
        from start: Int,
        through end: Int,
        _ term: (Int) throws -> Complex
    ) throws -> Complex {
        guard end >= start else { throw TIError.domain }
        let count = end - start + 1
        guard count <= Self.maximumSummationTerms else { throw TIError.iterations }

        var total = Complex.zero
        for index in start...end {
            total = total + (try term(index))
        }
        return total
    }
}
