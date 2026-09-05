import Foundation

/// Which tail the alternative hypothesis occupies, in the TI's own encoding: the entry-line
/// commands take `0` for `≠`, `-1` for `<` and `1` for `>`.
public enum Alternative: Int, Equatable, Sendable, CaseIterable {
    case twoSided = 0
    case less = -1
    case greater = 1

    public init(code: Int) throws {
        guard let alternative = Alternative(rawValue: code) else { throw TIError.domain }
        self = alternative
    }
}

/// A one-sample test of a mean against a hypothesised value.
public struct MeanTestResult: Equatable, Sendable {
    public let statistic: Double
    public let pValue: Double
    /// Present for a t procedure, absent for a z procedure.
    public let degreesOfFreedom: Double?
    public let mean: Double
    public let sampleDeviation: Double?
    public let n: Double
}

/// A two-sample test of two means.
public struct TwoMeanTestResult: Equatable, Sendable {
    public let statistic: Double
    public let pValue: Double
    public let degreesOfFreedom: Double?
    public let mean1: Double
    public let mean2: Double
    public let deviation1: Double?
    public let deviation2: Double?
    public let n1: Double
    public let n2: Double
    /// The pooled deviation, present only when the pooled option was taken.
    public let pooledDeviation: Double?
}

/// A test of one or two proportions.
public struct ProportionTestResult: Equatable, Sendable {
    public let statistic: Double
    public let pValue: Double
    public let proportion: Double
    public let proportion1: Double?
    public let proportion2: Double?
    public let n1: Double
    public let n2: Double?
}

/// A chi-square test — goodness of fit, or independence in a two-way table.
public struct ChiSquareTestResult: Equatable, Sendable {
    public let statistic: Double
    public let pValue: Double
    public let degreesOfFreedom: Double
    /// The expected-count table, which the independence test computes and the TI stores in `[E]`.
    public let expected: [[Double]]
}

/// A two-sample test of two variances.
public struct VarianceTestResult: Equatable, Sendable {
    public let statistic: Double
    public let pValue: Double
    public let deviation1: Double
    public let deviation2: Double
    public let n1: Double
    public let n2: Double
}

/// The t test on a regression slope.
public struct LinRegTestResult: Equatable, Sendable {
    public let statistic: Double
    public let pValue: Double
    public let degreesOfFreedom: Double
    public let intercept: Double
    public let slope: Double
    /// The residual standard deviation, the TI's `s`.
    public let residualDeviation: Double
    public let correlation: Double
}

/// A confidence interval.
public struct ConfidenceInterval: Equatable, Sendable {
    public let lower: Double
    public let upper: Double
    public let pointEstimate: Double
    public let degreesOfFreedom: Double?
    public let n: Double
    public let n2: Double?

    public var marginOfError: Double { (upper - lower) / 2 }
}

/// The `STAT TESTS` menu, as pure functions.
///
/// Each procedure takes plain numbers and returns a result struct. The entry-line command form
/// and the form-style UI screens are two callers of the function below; no statistical logic
/// lives in a view, and there is never a second implementation to keep in step.
public enum Inference {

    // MARK: - Tail probabilities

    /// The p-value of a statistic against a symmetric reference distribution.
    ///
    /// Both the normal and the t procedures reach their p-value through here, so the tail
    /// convention is defined once.
    static func pValue(
        statistic: Double, alternative: Alternative, leftTail: (Double) throws -> Double
    ) throws -> Double {
        let left = try leftTail(statistic)
        switch alternative {
        case .less: return left
        case .greater: return 1 - left
        case .twoSided: return 2 * Swift.min(left, 1 - left)
        }
    }

    static func normalP(_ z: Double, _ alternative: Alternative) throws -> Double {
        try pValue(statistic: z, alternative: alternative) { try Distributions.standardNormalCDF($0) }
    }

    static func studentP(_ t: Double, _ df: Double, _ alternative: Alternative) throws -> Double {
        try pValue(statistic: t, alternative: alternative) {
            try Distributions.tCDF($0, degreesOfFreedom: df)
        }
    }

    // MARK: - One-sample means

    /// `Z-Test`: a mean against `μ0` with a known population deviation.
    public static func zTest(
        hypothesisedMean mu0: Double, populationDeviation sigma: Double,
        mean: Double, n: Double, alternative: Alternative
    ) throws -> MeanTestResult {
        guard sigma > 0, n >= 1 else { throw TIError.domain }
        let z = (mean - mu0) / (sigma / n.squareRoot())
        return MeanTestResult(
            statistic: z, pValue: try normalP(z, alternative), degreesOfFreedom: nil,
            mean: mean, sampleDeviation: sigma, n: n
        )
    }

    /// `T-Test`: a mean against `μ0` with the deviation estimated from the sample.
    public static func tTest(
        hypothesisedMean mu0: Double, mean: Double, sampleDeviation sx: Double,
        n: Double, alternative: Alternative
    ) throws -> MeanTestResult {
        guard sx > 0, n >= 2 else { throw TIError.domain }
        let df = n - 1
        let t = (mean - mu0) / (sx / n.squareRoot())
        return MeanTestResult(
            statistic: t, pValue: try studentP(t, df, alternative), degreesOfFreedom: df,
            mean: mean, sampleDeviation: sx, n: n
        )
    }

    // MARK: - Two-sample means

    public static func twoSampleZTest(
        deviation1 sigma1: Double, deviation2 sigma2: Double,
        mean1: Double, n1: Double, mean2: Double, n2: Double,
        alternative: Alternative
    ) throws -> TwoMeanTestResult {
        guard sigma1 > 0, sigma2 > 0, n1 >= 1, n2 >= 1 else { throw TIError.domain }
        let standardError = (sigma1 * sigma1 / n1 + sigma2 * sigma2 / n2).squareRoot()
        let z = (mean1 - mean2) / standardError
        return TwoMeanTestResult(
            statistic: z, pValue: try normalP(z, alternative), degreesOfFreedom: nil,
            mean1: mean1, mean2: mean2, deviation1: sigma1, deviation2: sigma2,
            n1: n1, n2: n2, pooledDeviation: nil
        )
    }

    /// The Welch–Satterthwaite degrees of freedom, which is what the TI's unpooled
    /// `2-SampTTest` reports and is a mandatory fixture case.
    public static func welchDegreesOfFreedom(
        _ s1: Double, _ n1: Double, _ s2: Double, _ n2: Double
    ) throws -> Double {
        guard n1 >= 2, n2 >= 2 else { throw TIError.domain }
        let a = s1 * s1 / n1
        let b = s2 * s2 / n2
        let numerator = (a + b) * (a + b)
        let denominator = a * a / (n1 - 1) + b * b / (n2 - 1)
        guard denominator > 0 else { throw TIError.domain }
        return numerator / denominator
    }

    public static func twoSampleTTest(
        mean1: Double, deviation1 s1: Double, n1: Double,
        mean2: Double, deviation2 s2: Double, n2: Double,
        alternative: Alternative, pooled: Bool
    ) throws -> TwoMeanTestResult {
        guard s1 > 0, s2 > 0, n1 >= 2, n2 >= 2 else { throw TIError.domain }
        let df: Double
        let standardError: Double
        var pooledDeviation: Double?

        if pooled {
            df = n1 + n2 - 2
            let variance = ((n1 - 1) * s1 * s1 + (n2 - 1) * s2 * s2) / df
            pooledDeviation = variance.squareRoot()
            standardError = (variance * (1 / n1 + 1 / n2)).squareRoot()
        } else {
            df = try welchDegreesOfFreedom(s1, n1, s2, n2)
            standardError = (s1 * s1 / n1 + s2 * s2 / n2).squareRoot()
        }

        let t = (mean1 - mean2) / standardError
        return TwoMeanTestResult(
            statistic: t, pValue: try studentP(t, df, alternative), degreesOfFreedom: df,
            mean1: mean1, mean2: mean2, deviation1: s1, deviation2: s2,
            n1: n1, n2: n2, pooledDeviation: pooledDeviation
        )
    }

    // MARK: - Proportions

    public static func onePropZTest(
        hypothesisedProportion p0: Double, successes x: Double, n: Double, alternative: Alternative
    ) throws -> ProportionTestResult {
        guard p0 > 0, p0 < 1, n >= 1, x >= 0, x <= n else { throw TIError.domain }
        let phat = x / n
        let z = (phat - p0) / (p0 * (1 - p0) / n).squareRoot()
        return ProportionTestResult(
            statistic: z, pValue: try normalP(z, alternative),
            proportion: phat, proportion1: nil, proportion2: nil, n1: n, n2: nil
        )
    }

    public static func twoPropZTest(
        successes1 x1: Double, n1: Double, successes2 x2: Double, n2: Double,
        alternative: Alternative
    ) throws -> ProportionTestResult {
        guard n1 >= 1, n2 >= 1, x1 >= 0, x1 <= n1, x2 >= 0, x2 <= n2 else { throw TIError.domain }
        let p1 = x1 / n1
        let p2 = x2 / n2
        // The null hypothesis is that both proportions are equal, so the standard error uses the
        // combined estimate rather than the two separate ones.
        let pooled = (x1 + x2) / (n1 + n2)
        let standardError = (pooled * (1 - pooled) * (1 / n1 + 1 / n2)).squareRoot()
        guard standardError > 0 else { throw TIError.domain }
        let z = (p1 - p2) / standardError
        return ProportionTestResult(
            statistic: z, pValue: try normalP(z, alternative),
            proportion: pooled, proportion1: p1, proportion2: p2, n1: n1, n2: n2
        )
    }

    // MARK: - Chi-square

    /// `χ²GOF-Test`: observed against expected counts, with the degrees of freedom supplied.
    public static func goodnessOfFit(
        observed: [Double], expected: [Double], degreesOfFreedom df: Double
    ) throws -> ChiSquareTestResult {
        guard observed.count == expected.count else { throw TIError.dimensionMismatch }
        guard df > 0 else { throw TIError.domain }
        var statistic = 0.0
        for (o, e) in zip(observed, expected) {
            guard e > 0 else { throw TIError.domain }
            statistic += (o - e) * (o - e) / e
        }
        return ChiSquareTestResult(
            statistic: statistic,
            pValue: 1 - (try Distributions.chiSquareCDF(statistic, degreesOfFreedom: df)),
            degreesOfFreedom: df,
            expected: [expected]
        )
    }

    /// `χ²-Test`: independence in a two-way table. The expected counts are derived from the row
    /// and column totals, so the caller supplies only what was observed.
    public static func chiSquareTest(observed: [[Double]]) throws -> ChiSquareTestResult {
        guard let width = observed.first?.count, width >= 2, observed.count >= 2,
              observed.allSatisfy({ $0.count == width }) else {
            throw TIError.invalidDimension
        }
        let rowTotals = observed.map { $0.reduce(0, +) }
        let columnTotals = (0..<width).map { column in observed.reduce(0) { $0 + $1[column] } }
        let total = rowTotals.reduce(0, +)
        guard total > 0 else { throw TIError.domain }

        var expected: [[Double]] = []
        var statistic = 0.0
        for (row, rowTotal) in rowTotals.enumerated() {
            var expectedRow: [Double] = []
            for (column, columnTotal) in columnTotals.enumerated() {
                let e = rowTotal * columnTotal / total
                guard e > 0 else { throw TIError.domain }
                expectedRow.append(e)
                let o = observed[row][column]
                statistic += (o - e) * (o - e) / e
            }
            expected.append(expectedRow)
        }

        let df = Double((observed.count - 1) * (width - 1))
        return ChiSquareTestResult(
            statistic: statistic,
            pValue: 1 - (try Distributions.chiSquareCDF(statistic, degreesOfFreedom: df)),
            degreesOfFreedom: df,
            expected: expected
        )
    }

    // MARK: - Variances

    public static func twoSampleFTest(
        deviation1 s1: Double, n1: Double, deviation2 s2: Double, n2: Double,
        alternative: Alternative
    ) throws -> VarianceTestResult {
        guard s1 > 0, s2 > 0, n1 >= 2, n2 >= 2 else { throw TIError.domain }
        let f = (s1 * s1) / (s2 * s2)
        let d1 = n1 - 1
        let d2 = n2 - 1
        let left = try Distributions.fCDF(f, d1, d2)
        let p: Double
        switch alternative {
        case .less: p = left
        case .greater: p = 1 - left
        // F is not symmetric, so the two-sided p-value doubles the smaller tail rather than
        // reflecting the statistic.
        case .twoSided: p = 2 * Swift.min(left, 1 - left)
        }
        return VarianceTestResult(
            statistic: f, pValue: p, deviation1: s1, deviation2: s2, n1: n1, n2: n2
        )
    }

    // MARK: - Regression slope

    public static func linRegTTest(
        _ xs: [Double], _ ys: [Double], alternative: Alternative
    ) throws -> LinRegTestResult {
        guard xs.count == ys.count, xs.count >= 3 else { throw TIError.invalidDimension }
        let fit = try Statistics.regression(.linearABX, xs, ys)
        let intercept = fit.coefficients[0]
        let slope = fit.coefficients[1]
        let n = Double(xs.count)
        let df = n - 2

        let predicted = xs.map { intercept + slope * $0 }
        let residualSum = zip(ys, predicted).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        let s = (residualSum / df).squareRoot()

        let meanX = xs.reduce(0, +) / n
        let spreadX = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard spreadX > 0 else { throw TIError.domain }
        let standardError = s / spreadX.squareRoot()
        guard standardError > 0 else { throw TIError.domain }

        let t = slope / standardError
        return LinRegTestResult(
            statistic: t, pValue: try studentP(t, df, alternative), degreesOfFreedom: df,
            intercept: intercept, slope: slope, residualDeviation: s,
            correlation: fit.correlation ?? .nan
        )
    }

    // MARK: - Confidence intervals

    /// The confidence level every interval takes, as a proportion: `0.95`, not `95`.
    static func criticalArea(_ level: Double) throws -> Double {
        guard level > 0, level < 1 else { throw TIError.domain }
        return 1 - (1 - level) / 2
    }

    public static func zInterval(
        populationDeviation sigma: Double, mean: Double, n: Double, level: Double
    ) throws -> ConfidenceInterval {
        guard sigma > 0, n >= 1 else { throw TIError.domain }
        let critical = try Distributions.inverseNormal(area: try criticalArea(level))
        let margin = critical * sigma / n.squareRoot()
        return ConfidenceInterval(
            lower: mean - margin, upper: mean + margin, pointEstimate: mean,
            degreesOfFreedom: nil, n: n, n2: nil
        )
    }

    public static func tInterval(
        mean: Double, sampleDeviation sx: Double, n: Double, level: Double
    ) throws -> ConfidenceInterval {
        guard sx > 0, n >= 2 else { throw TIError.domain }
        let df = n - 1
        let critical = try Distributions.inverseT(area: try criticalArea(level), degreesOfFreedom: df)
        let margin = critical * sx / n.squareRoot()
        return ConfidenceInterval(
            lower: mean - margin, upper: mean + margin, pointEstimate: mean,
            degreesOfFreedom: df, n: n, n2: nil
        )
    }

    public static func twoSampleZInterval(
        deviation1 sigma1: Double, deviation2 sigma2: Double,
        mean1: Double, n1: Double, mean2: Double, n2: Double, level: Double
    ) throws -> ConfidenceInterval {
        guard sigma1 > 0, sigma2 > 0, n1 >= 1, n2 >= 1 else { throw TIError.domain }
        let critical = try Distributions.inverseNormal(area: try criticalArea(level))
        let margin = critical * (sigma1 * sigma1 / n1 + sigma2 * sigma2 / n2).squareRoot()
        let difference = mean1 - mean2
        return ConfidenceInterval(
            lower: difference - margin, upper: difference + margin, pointEstimate: difference,
            degreesOfFreedom: nil, n: n1, n2: n2
        )
    }

    public static func twoSampleTInterval(
        mean1: Double, deviation1 s1: Double, n1: Double,
        mean2: Double, deviation2 s2: Double, n2: Double,
        level: Double, pooled: Bool
    ) throws -> ConfidenceInterval {
        guard s1 > 0, s2 > 0, n1 >= 2, n2 >= 2 else { throw TIError.domain }
        let df: Double
        let standardError: Double
        if pooled {
            df = n1 + n2 - 2
            let variance = ((n1 - 1) * s1 * s1 + (n2 - 1) * s2 * s2) / df
            standardError = (variance * (1 / n1 + 1 / n2)).squareRoot()
        } else {
            df = try welchDegreesOfFreedom(s1, n1, s2, n2)
            standardError = (s1 * s1 / n1 + s2 * s2 / n2).squareRoot()
        }
        let critical = try Distributions.inverseT(area: try criticalArea(level), degreesOfFreedom: df)
        let difference = mean1 - mean2
        let margin = critical * standardError
        return ConfidenceInterval(
            lower: difference - margin, upper: difference + margin, pointEstimate: difference,
            degreesOfFreedom: df, n: n1, n2: n2
        )
    }

    public static func onePropZInterval(
        successes x: Double, n: Double, level: Double
    ) throws -> ConfidenceInterval {
        guard n >= 1, x >= 0, x <= n else { throw TIError.domain }
        let phat = x / n
        let critical = try Distributions.inverseNormal(area: try criticalArea(level))
        let margin = critical * (phat * (1 - phat) / n).squareRoot()
        return ConfidenceInterval(
            lower: phat - margin, upper: phat + margin, pointEstimate: phat,
            degreesOfFreedom: nil, n: n, n2: nil
        )
    }

    public static func twoPropZInterval(
        successes1 x1: Double, n1: Double, successes2 x2: Double, n2: Double, level: Double
    ) throws -> ConfidenceInterval {
        guard n1 >= 1, n2 >= 1, x1 >= 0, x1 <= n1, x2 >= 0, x2 <= n2 else { throw TIError.domain }
        let p1 = x1 / n1
        let p2 = x2 / n2
        let critical = try Distributions.inverseNormal(area: try criticalArea(level))
        // The interval estimates each proportion separately; only the *test* pools them.
        let margin = critical * (p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2).squareRoot()
        let difference = p1 - p2
        return ConfidenceInterval(
            lower: difference - margin, upper: difference + margin, pointEstimate: difference,
            degreesOfFreedom: nil, n: n1, n2: n2
        )
    }
}
