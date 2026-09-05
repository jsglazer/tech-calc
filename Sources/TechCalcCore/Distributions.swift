import Foundation

/// The TI `DISTR` menu, as pure functions.
///
/// Two conventions are fixed by the pre-build decisions and are asserted by fixtures:
///   * a two-tailed `cdf` integrates from `lower` to `upper`, left to right;
///   * a magnitude of `infinitySentinel` or more *is* infinity, and `lower > upper` raises
///     `ERR:DOMAIN` rather than returning a negative probability.
public enum Distributions {

    /// `1E99` is how the TI writes infinity on the entry line.
    public static let infinitySentinel = 1e99
    /// Convergence bar for every inverse. The inverses are root-finds, not closed forms.
    public static let inverseTolerance = 1e-12
    /// Hard cap on inverse iterations; exceeding it is `ERR:ITERATIONS`, never a silent answer.
    public static let maximumInverseIterations = 200

    /// Maps the entry-line sentinel onto an actual infinity, so the tail integrals below can be
    /// written once in terms of ±∞.
    static func resolveBound(_ value: Double) -> Double {
        if value >= infinitySentinel { return .infinity }
        if value <= -infinitySentinel { return -.infinity }
        return value
    }

    /// The shared left-to-right interval rule: `ERR:DOMAIN` when the bounds are inverted.
    static func interval(_ lower: Double, _ upper: Double) throws -> (lower: Double, upper: Double) {
        guard !lower.isNaN, !upper.isNaN else { throw TIError.domain }
        let low = resolveBound(lower)
        let high = resolveBound(upper)
        guard low <= high else { throw TIError.domain }
        return (low, high)
    }

    // MARK: - Normal

    public static func normalPDF(_ x: Double, mean: Double = 0, standardDeviation: Double = 1) throws -> Double {
        guard standardDeviation > 0, x.isFinite else { throw TIError.domain }
        let z = (x - mean) / standardDeviation
        return Foundation.exp(-0.5 * z * z) / (standardDeviation * (2 * Double.pi).squareRoot())
    }

    /// The standard normal CDF, from the error function expressed through the incomplete gamma.
    public static func standardNormalCDF(_ z: Double) throws -> Double {
        if z == 0 { return 0.5 }
        if z.isInfinite { return z > 0 ? 1 : 0 }
        let half = try SpecialFunctions.regularizedGammaP(0.5, 0.5 * z * z) / 2
        return z > 0 ? 0.5 + half : 0.5 - half
    }

    public static func normalCDF(
        lower: Double, upper: Double, mean: Double = 0, standardDeviation: Double = 1
    ) throws -> Double {
        guard standardDeviation > 0 else { throw TIError.domain }
        let bounds = try interval(lower, upper)
        let low = (bounds.lower - mean) / standardDeviation
        let high = (bounds.upper - mean) / standardDeviation
        return (try standardNormalCDF(high)) - (try standardNormalCDF(low))
    }

    /// `invNorm(area)` — the area is the probability to the *left*, as on the TI.
    public static func inverseNormal(
        area: Double, mean: Double = 0, standardDeviation: Double = 1
    ) throws -> Double {
        guard standardDeviation > 0 else { throw TIError.domain }
        guard area > 0, area < 1 else { throw TIError.domain }
        let z = try solve(
            target: area,
            lowerBracket: -40,
            upperBracket: 40,
            cdf: { try standardNormalCDF($0) },
            pdf: { try normalPDF($0) }
        )
        return mean + standardDeviation * z
    }

    // MARK: - Student t

    public static func tPDF(_ x: Double, degreesOfFreedom df: Double) throws -> Double {
        guard df > 0, x.isFinite else { throw TIError.domain }
        let logDensity = (try SpecialFunctions.logGamma((df + 1) / 2))
            - (try SpecialFunctions.logGamma(df / 2))
            - 0.5 * Foundation.log(df * Double.pi)
            - ((df + 1) / 2) * Foundation.log(1 + x * x / df)
        return Foundation.exp(logDensity)
    }

    /// The left tail of Student's t, from the regularized incomplete beta.
    public static func tCDF(_ x: Double, degreesOfFreedom df: Double) throws -> Double {
        guard df > 0 else { throw TIError.domain }
        if x.isInfinite { return x > 0 ? 1 : 0 }
        let half = try SpecialFunctions.regularizedBeta(df / (df + x * x), df / 2, 0.5) / 2
        return x > 0 ? 1 - half : half
    }

    public static func tCDF(lower: Double, upper: Double, degreesOfFreedom df: Double) throws -> Double {
        let bounds = try interval(lower, upper)
        return (try tCDF(bounds.upper, degreesOfFreedom: df)) - (try tCDF(bounds.lower, degreesOfFreedom: df))
    }

    public static func inverseT(area: Double, degreesOfFreedom df: Double) throws -> Double {
        guard df > 0, area > 0, area < 1 else { throw TIError.domain }
        return try solve(
            target: area,
            lowerBracket: -1e4,
            upperBracket: 1e4,
            cdf: { try tCDF($0, degreesOfFreedom: df) },
            pdf: { try tPDF($0, degreesOfFreedom: df) }
        )
    }

    // MARK: - Chi-square

    public static func chiSquarePDF(_ x: Double, degreesOfFreedom df: Double) throws -> Double {
        guard df > 0 else { throw TIError.domain }
        guard x > 0 else { return 0 }
        let k = df / 2
        let logDensity = (k - 1) * Foundation.log(x) - x / 2
            - k * Foundation.log(2.0) - (try SpecialFunctions.logGamma(k))
        return Foundation.exp(logDensity)
    }

    public static func chiSquareCDF(_ x: Double, degreesOfFreedom df: Double) throws -> Double {
        guard df > 0 else { throw TIError.domain }
        if x <= 0 { return 0 }
        if x.isInfinite { return 1 }
        return try SpecialFunctions.regularizedGammaP(df / 2, x / 2)
    }

    public static func chiSquareCDF(lower: Double, upper: Double, degreesOfFreedom df: Double) throws -> Double {
        let bounds = try interval(lower, upper)
        return (try chiSquareCDF(bounds.upper, degreesOfFreedom: df))
            - (try chiSquareCDF(bounds.lower, degreesOfFreedom: df))
    }

    public static func inverseChiSquare(area: Double, degreesOfFreedom df: Double) throws -> Double {
        guard df > 0, area > 0, area < 1 else { throw TIError.domain }
        return try solve(
            target: area,
            lowerBracket: 0,
            upperBracket: Swift.max(1e3, df * 100),
            cdf: { try chiSquareCDF($0, degreesOfFreedom: df) },
            pdf: { try chiSquarePDF($0, degreesOfFreedom: df) }
        )
    }

    // MARK: - F

    public static func fPDF(_ x: Double, _ d1: Double, _ d2: Double) throws -> Double {
        guard d1 > 0, d2 > 0 else { throw TIError.domain }
        guard x > 0 else { return 0 }
        let logDensity = (d1 / 2) * Foundation.log(d1) + (d2 / 2) * Foundation.log(d2)
            + (d1 / 2 - 1) * Foundation.log(x)
            - ((d1 + d2) / 2) * Foundation.log(d2 + d1 * x)
            + (try SpecialFunctions.logGamma((d1 + d2) / 2))
            - (try SpecialFunctions.logGamma(d1 / 2))
            - (try SpecialFunctions.logGamma(d2 / 2))
        return Foundation.exp(logDensity)
    }

    public static func fCDF(_ x: Double, _ d1: Double, _ d2: Double) throws -> Double {
        guard d1 > 0, d2 > 0 else { throw TIError.domain }
        if x <= 0 { return 0 }
        if x.isInfinite { return 1 }
        return try SpecialFunctions.regularizedBeta(d1 * x / (d1 * x + d2), d1 / 2, d2 / 2)
    }

    public static func fCDF(lower: Double, upper: Double, _ d1: Double, _ d2: Double) throws -> Double {
        let bounds = try interval(lower, upper)
        return (try fCDF(bounds.upper, d1, d2)) - (try fCDF(bounds.lower, d1, d2))
    }

    public static func inverseF(area: Double, _ d1: Double, _ d2: Double) throws -> Double {
        guard d1 > 0, d2 > 0, area > 0, area < 1 else { throw TIError.domain }
        return try solve(
            target: area,
            lowerBracket: 0,
            upperBracket: 1e8,
            cdf: { try fCDF($0, d1, d2) },
            pdf: { try fPDF($0, d1, d2) }
        )
    }

    // MARK: - Discrete

    public static func binomialPDF(trials n: Int, probability p: Double, successes k: Int) throws -> Double {
        guard n >= 0, p >= 0, p <= 1 else { throw TIError.domain }
        guard k >= 0, k <= n else { return 0 }
        if p == 0 { return k == 0 ? 1 : 0 }
        if p == 1 { return k == n ? 1 : 0 }
        let logProbability = (try SpecialFunctions.logBinomialCoefficient(n: n, k: k))
            + Double(k) * Foundation.log(p)
            + Double(n - k) * Foundation.log(1 - p)
        return Foundation.exp(logProbability)
    }

    /// The TI's `binomcdf(` is the cumulative probability of *at most* `k` successes.
    public static func binomialCDF(trials n: Int, probability p: Double, successes k: Int) throws -> Double {
        guard n >= 0, p >= 0, p <= 1 else { throw TIError.domain }
        if k < 0 { return 0 }
        if k >= n { return 1 }
        var total = 0.0
        for successes in 0...k {
            total += try binomialPDF(trials: n, probability: p, successes: successes)
        }
        return Swift.min(1, total)
    }

    public static func poissonPDF(mean: Double, successes k: Int) throws -> Double {
        guard mean > 0 else { throw TIError.domain }
        guard k >= 0 else { return 0 }
        let logProbability = Double(k) * Foundation.log(mean) - mean - (try SpecialFunctions.logFactorial(k))
        return Foundation.exp(logProbability)
    }

    public static func poissonCDF(mean: Double, successes k: Int) throws -> Double {
        guard mean > 0 else { throw TIError.domain }
        if k < 0 { return 0 }
        // Q(k+1, μ) is the exact closed form of the partial sum, so this needs no loop at all.
        return try SpecialFunctions.regularizedGammaQ(Double(k) + 1, mean)
    }

    /// The TI's geometric distribution counts trials *until* the first success, so its support
    /// starts at 1, not 0.
    public static func geometricPDF(probability p: Double, trial k: Int) throws -> Double {
        guard p > 0, p <= 1 else { throw TIError.domain }
        guard k >= 1 else { return 0 }
        return p * Foundation.pow(1 - p, Double(k - 1))
    }

    public static func geometricCDF(probability p: Double, trial k: Int) throws -> Double {
        guard p > 0, p <= 1 else { throw TIError.domain }
        guard k >= 1 else { return 0 }
        return 1 - Foundation.pow(1 - p, Double(k))
    }

    // MARK: - The one inverse solver

    /// Bracketed bisection with a Newton refinement, as the pre-build decisions specify: the
    /// bisection guarantees the bracket never widens, the Newton step is taken only when it stays
    /// inside that bracket, and the iteration count is hard-capped.
    ///
    /// Every inverse in this file routes through here, so there is exactly one convergence
    /// policy to audit rather than one per distribution.
    static func solve(
        target: Double,
        lowerBracket: Double,
        upperBracket: Double,
        cdf: (Double) throws -> Double,
        pdf: (Double) throws -> Double
    ) throws -> Double {
        var low = lowerBracket
        var high = upperBracket
        guard try cdf(low) <= target, try cdf(high) >= target else { throw TIError.domain }

        var x = (low + high) / 2
        for _ in 0..<maximumInverseIterations {
            let error = (try cdf(x)) - target
            if Swift.abs(error) < inverseTolerance { return x }
            if error < 0 { low = x } else { high = x }

            let density = try pdf(x)
            let newton = density > 0 ? x - error / density : Double.nan
            // Newton only when it lands strictly inside the current bracket; bisection otherwise.
            x = (newton.isFinite && newton > low && newton < high) ? newton : (low + high) / 2

            if high - low < inverseTolerance { return x }
        }
        throw TIError.iterations
    }
}
