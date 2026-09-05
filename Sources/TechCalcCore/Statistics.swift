import Foundation

/// One-variable summary statistics, in the order the TI's `1-Var Stats` screen lists them.
public struct OneVarStats: Equatable, Sendable {
    public let n: Double
    public let mean: Double
    public let sumX: Double
    public let sumSquaredX: Double
    /// The sample standard deviation, divisor `n - 1` — the TI's `Sx`.
    public let sampleStandardDeviation: Double
    /// The population standard deviation, divisor `n` — the TI's `σx`.
    public let populationStandardDeviation: Double
    public let minimum: Double
    public let firstQuartile: Double
    public let median: Double
    public let thirdQuartile: Double
    public let maximum: Double
}

/// Two-variable summary statistics, as `2-Var Stats` reports them.
public struct TwoVarStats: Equatable, Sendable {
    public let n: Double
    public let meanX: Double
    public let sumX: Double
    public let sumSquaredX: Double
    public let sampleStandardDeviationX: Double
    public let populationStandardDeviationX: Double
    public let minimumX: Double
    public let maximumX: Double
    public let meanY: Double
    public let sumY: Double
    public let sumSquaredY: Double
    public let sampleStandardDeviationY: Double
    public let populationStandardDeviationY: Double
    public let minimumY: Double
    public let maximumY: Double
    public let sumXY: Double
}

/// A fitted regression. `coefficients` is ordered as the TI's `a`, `b`, `c`, `d`, `e` variables
/// are, so the model determines what `a` means and no caller has to reorder anything.
public struct RegressionResult: Equatable, Sendable {
    public let model: RegressionModel
    public let coefficients: [Double]
    /// The correlation coefficient. Defined for the two-parameter models only.
    public let correlation: Double?
    /// The coefficient of determination.
    public let coefficientOfDetermination: Double
}

/// The regression families this build fits, each with the TI's own coefficient convention.
public enum RegressionModel: String, Equatable, Sendable, CaseIterable {
    /// `y = ax + b` — `a` is the slope.
    case linearAXB
    /// `y = a + bx` — `b` is the slope.
    case linearABX
    /// `y = ax² + bx + c`
    case quadratic
    /// `y = ax³ + bx² + cx + d`
    case cubic
    /// `y = ax⁴ + bx³ + cx² + dx + e`
    case quartic
    /// `y = a + b·ln x`
    case logarithmic
    /// `y = a·bˣ`, fitted as a linear regression of `ln y` on `x`, as the TI does.
    case exponential
    /// `y = a·xᵇ`, fitted as a linear regression of `ln y` on `ln x`.
    case power

    /// The number of fitted coefficients, which is also how many of `a`-`e` the model fills.
    var coefficientCount: Int {
        switch self {
        case .linearAXB, .linearABX, .logarithmic, .exponential, .power: 2
        case .quadratic: 3
        case .cubic: 4
        case .quartic: 5
        }
    }
}

/// Descriptive statistics and curve fitting, as pure functions over plain arrays.
///
/// Everything here is a pure function of its arguments: the `STAT CALC` commands on the entry
/// line and the form-style UI screens are two *callers* of these, never two implementations.
/// The reductions delegate to `ListMath`, so `mean(L1)` and `1-Var Stats L1` cannot disagree.
public enum Statistics {

    // MARK: - Frequency expansion

    /// Repeats each value by its frequency, which is how the TI's optional frequency list works.
    /// Frequencies must be non-negative whole numbers, as on the TI.
    public static func expanded(_ values: [Double], frequencies: [Double]?) throws -> [Double] {
        guard let frequencies else { return values }
        guard frequencies.count == values.count else { throw TIError.dimensionMismatch }
        var expanded: [Double] = []
        for (value, frequency) in zip(values, frequencies) {
            guard frequency >= 0, frequency == frequency.rounded(), frequency < 1e6 else {
                throw TIError.domain
            }
            expanded.append(contentsOf: Array(repeating: value, count: Int(frequency)))
        }
        guard !expanded.isEmpty else { throw TIError.invalidDimension }
        return expanded
    }

    // MARK: - Quartiles

    /// The TI's quartile rule: `Q1` is the median of the values strictly below the median and
    /// `Q3` the median of those strictly above, so an odd-length sample excludes its own median
    /// from both halves. This differs from every `quantile()` default, which is why it is spelled
    /// out here rather than borrowed.
    public static func quartiles(of sorted: [Double]) throws -> (q1: Double, median: Double, q3: Double) {
        guard !sorted.isEmpty else { throw TIError.invalidDimension }
        let count = sorted.count
        let half = count / 2
        let lower = Array(sorted[0..<half])
        // An odd count leaves the middle value out of both halves.
        let upper = Array(sorted[(count.isMultiple(of: 2) ? half : half + 1)...])
        return (
            q1: try medianOfSorted(lower.isEmpty ? sorted : lower),
            median: try medianOfSorted(sorted),
            q3: try medianOfSorted(upper.isEmpty ? sorted : upper)
        )
    }

    /// The median of an already-sorted array.
    static func medianOfSorted(_ sorted: [Double]) throws -> Double {
        guard !sorted.isEmpty else { throw TIError.invalidDimension }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    // MARK: - One and two variable summaries

    public static func oneVar(_ values: [Double], frequencies: [Double]? = nil) throws -> OneVarStats {
        let sample = try expanded(values, frequencies: frequencies)
        guard !sample.isEmpty else { throw TIError.invalidDimension }
        let n = Double(sample.count)
        let sumX = sample.reduce(0, +)
        let sumSquaredX = sample.reduce(0) { $0 + $1 * $1 }
        let mean = sumX / n
        let squaredError = sample.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let sorted = sample.sorted()
        let quartiles = try quartiles(of: sorted)

        return OneVarStats(
            n: n,
            mean: mean,
            sumX: sumX,
            sumSquaredX: sumSquaredX,
            // A single observation has no sample spread; the TI shows an error there rather
            // than dividing by zero.
            sampleStandardDeviation: sample.count >= 2 ? (squaredError / (n - 1)).squareRoot() : .nan,
            populationStandardDeviation: (squaredError / n).squareRoot(),
            minimum: sorted[0],
            firstQuartile: quartiles.q1,
            median: quartiles.median,
            thirdQuartile: quartiles.q3,
            maximum: sorted[sorted.count - 1]
        )
    }

    public static func twoVar(
        _ xs: [Double], _ ys: [Double], frequencies: [Double]? = nil
    ) throws -> TwoVarStats {
        guard xs.count == ys.count else { throw TIError.dimensionMismatch }
        let x = try expanded(xs, frequencies: frequencies)
        let y = try expanded(ys, frequencies: frequencies)
        guard !x.isEmpty else { throw TIError.invalidDimension }
        let statsX = try oneVar(x)
        let statsY = try oneVar(y)
        let sumXY = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }

        return TwoVarStats(
            n: statsX.n,
            meanX: statsX.mean, sumX: statsX.sumX, sumSquaredX: statsX.sumSquaredX,
            sampleStandardDeviationX: statsX.sampleStandardDeviation,
            populationStandardDeviationX: statsX.populationStandardDeviation,
            minimumX: statsX.minimum, maximumX: statsX.maximum,
            meanY: statsY.mean, sumY: statsY.sumX, sumSquaredY: statsY.sumSquaredX,
            sampleStandardDeviationY: statsY.sampleStandardDeviation,
            populationStandardDeviationY: statsY.populationStandardDeviation,
            minimumY: statsY.minimum, maximumY: statsY.maximum,
            sumXY: sumXY
        )
    }

    // MARK: - Regression

    public static func regression(
        _ model: RegressionModel, _ xs: [Double], _ ys: [Double], frequencies: [Double]? = nil
    ) throws -> RegressionResult {
        guard xs.count == ys.count else { throw TIError.dimensionMismatch }
        let x = try expanded(xs, frequencies: frequencies)
        let y = try expanded(ys, frequencies: frequencies)
        guard x.count >= model.coefficientCount else { throw TIError.invalidDimension }

        switch model {
        case .linearAXB, .linearABX:
            let fit = try leastSquares(design: designMatrix(x, degree: 1), y)
            // The two forms differ only in which coefficient the TI calls `a`.
            let coefficients = model == .linearAXB ? [fit[1], fit[0]] : [fit[0], fit[1]]
            let r = try correlation(x, y)
            return RegressionResult(
                model: model, coefficients: coefficients,
                correlation: r, coefficientOfDetermination: r * r
            )

        case .quadratic, .cubic, .quartic:
            let degree = model.coefficientCount - 1
            let fit = try leastSquares(design: designMatrix(x, degree: degree), y)
            // The TI reports polynomial coefficients highest power first.
            let coefficients = Array(fit.reversed())
            let predicted = x.map { value in
                (0..<fit.count).reduce(0.0) { $0 + fit[$1] * Foundation.pow(value, Double($1)) }
            }
            return RegressionResult(
                model: model, coefficients: coefficients,
                correlation: nil,
                coefficientOfDetermination: try determination(y, predicted)
            )

        case .logarithmic:
            // y = a + b ln x, fitted on (ln x, y).
            let transformedX = try positiveLogarithms(x)
            let fit = try leastSquares(design: designMatrix(transformedX, degree: 1), y)
            let r = try correlation(transformedX, y)
            return RegressionResult(
                model: model, coefficients: [fit[0], fit[1]],
                correlation: r, coefficientOfDetermination: r * r
            )

        case .exponential:
            // y = a·bˣ, fitted on (x, ln y) and mapped back, which is what the TI does.
            let transformedY = try positiveLogarithms(y)
            let fit = try leastSquares(design: designMatrix(x, degree: 1), transformedY)
            let r = try correlation(x, transformedY)
            return RegressionResult(
                model: model,
                coefficients: [Foundation.exp(fit[0]), Foundation.exp(fit[1])],
                correlation: r, coefficientOfDetermination: r * r
            )

        case .power:
            // y = a·xᵇ, fitted on (ln x, ln y).
            let transformedX = try positiveLogarithms(x)
            let transformedY = try positiveLogarithms(y)
            let fit = try leastSquares(design: designMatrix(transformedX, degree: 1), transformedY)
            let r = try correlation(transformedX, transformedY)
            return RegressionResult(
                model: model,
                coefficients: [Foundation.exp(fit[0]), fit[1]],
                correlation: r, coefficientOfDetermination: r * r
            )
        }
    }

    /// Pearson's r.
    public static func correlation(_ x: [Double], _ y: [Double]) throws -> Double {
        guard x.count == y.count, x.count >= 2 else { throw TIError.invalidDimension }
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        var covariance = 0.0, varianceX = 0.0, varianceY = 0.0
        for (xi, yi) in zip(x, y) {
            let dx = xi - meanX, dy = yi - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        let denominator = (varianceX * varianceY).squareRoot()
        guard denominator > 0 else { throw TIError.domain }
        return covariance / denominator
    }

    /// R² from the residual and total sums of squares, for the models where r is undefined.
    static func determination(_ observed: [Double], _ predicted: [Double]) throws -> Double {
        let n = Double(observed.count)
        let mean = observed.reduce(0, +) / n
        let total = observed.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        let residual = zip(observed, predicted).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        guard total > 0 else { throw TIError.domain }
        return 1 - residual / total
    }

    /// A Vandermonde design matrix: column `j` is `x^j`, so column 0 is the intercept.
    static func designMatrix(_ x: [Double], degree: Int) -> [[Double]] {
        x.map { value in (0...degree).map { Foundation.pow(value, Double($0)) } }
    }

    /// The logarithms a transformed fit needs; a non-positive value is `ERR:DOMAIN`, as on the TI.
    static func positiveLogarithms(_ values: [Double]) throws -> [Double] {
        try values.map { value in
            guard value > 0 else { throw TIError.domain }
            return Foundation.log(value)
        }
    }

    /// Ordinary least squares by the normal equations, solved through `MatrixMath`.
    ///
    /// Routing the solve through `MatrixMath` rather than writing a second elimination keeps one
    /// Gaussian elimination and one singularity tolerance in the module. A rank-deficient design
    /// surfaces as `ERR:SINGULAR MAT` from that same elimination.
    static func leastSquares(design: [[Double]], _ y: [Double]) throws -> [Double] {
        guard let width = design.first?.count, design.count == y.count else {
            throw TIError.dimensionMismatch
        }
        let x = try MatrixMath.matrix(from: design.map { row in row.map { Complex($0) } })
        let target = try MatrixMath.matrix(from: y.map { [Complex($0)] })
        let xT = try MatrixMath.transpose(x)
        let normal = try MatrixMath.multiply(xT, x)
        let rhs = try MatrixMath.multiply(xT, target)
        let solution = try MatrixMath.multiply(try MatrixMath.inverse(normal), rhs)
        return try (0..<width).map { row in
            try TIValue.number(solution[tiRow: row + 1, tiColumn: 1]).asReal
        }
    }
}
