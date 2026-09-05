import Foundation

/// How a result struct reaches the `VARS ▸ Statistics` bag.
///
/// Every mapping from a computed result to the variables it fills lives here, in one file, so
/// "which command sets `df`" is answerable by reading a single place rather than by tracing the
/// evaluator. The result structs stay pure values; the evaluator only calls `published`.
protocol StatisticsPublishing {
    var published: [StatVariable: Double] { get }
}

/// Drops the entries whose value is absent or not a number, so an undefined variable stays
/// undefined rather than being published as a NaN a later expression could carry silently.
private func defined(_ entries: [StatVariable: Double?]) -> [StatVariable: Double] {
    entries.compactMapValues { value in
        guard let value, !value.isNaN else { return nil }
        return value
    }
}

extension OneVarStats: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            .n: n, .meanX: mean, .sumX: sumX, .sumSquaredX: sumSquaredX,
            .sampleDeviationX: sampleStandardDeviation,
            .populationDeviationX: populationStandardDeviation,
            .minimumX: minimum, .firstQuartile: firstQuartile, .median: median,
            .thirdQuartile: thirdQuartile, .maximumX: maximum
        ])
    }
}

extension TwoVarStats: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            .n: n,
            .meanX: meanX, .sumX: sumX, .sumSquaredX: sumSquaredX,
            .sampleDeviationX: sampleStandardDeviationX,
            .populationDeviationX: populationStandardDeviationX,
            .minimumX: minimumX, .maximumX: maximumX,
            .meanY: meanY, .sumY: sumY, .sumSquaredY: sumSquaredY,
            .sampleDeviationY: sampleStandardDeviationY,
            .populationDeviationY: populationStandardDeviationY,
            .minimumY: minimumY, .maximumY: maximumY,
            .sumXY: sumXY
        ])
    }
}

extension RegressionResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        // The coefficient order is the model's own, so `a` means what the TI says it means for
        // this family; the slots beyond the model's coefficient count stay undefined.
        let slots: [StatVariable] = [.coefficientA, .coefficientB, .coefficientC, .coefficientD]
        var values: [StatVariable: Double?] = [:]
        for (slot, coefficient) in zip(slots, coefficients) {
            values[slot] = coefficient
        }
        values[.correlation] = correlation
        values[.determination] = coefficientOfDetermination
        return defined(values)
    }
}

extension MeanTestResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            // A z procedure reports `z`, a t procedure `t`: the degrees of freedom decide which,
            // exactly as the presence of `df` does on the TI's results screen.
            degreesOfFreedom == nil ? .zStatistic : .tStatistic: statistic,
            .probability: pValue,
            .degreesOfFreedom: degreesOfFreedom,
            .meanX: mean,
            .sampleDeviationX: sampleDeviation,
            .n: n
        ])
    }
}

extension TwoMeanTestResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            degreesOfFreedom == nil ? .zStatistic : .tStatistic: statistic,
            .probability: pValue,
            .degreesOfFreedom: degreesOfFreedom,
            .meanX1: mean1, .meanX2: mean2,
            .sampleDeviation1: deviation1, .sampleDeviation2: deviation2,
            .n1: n1, .n2: n2,
            .pooledDeviation: pooledDeviation
        ])
    }
}

extension ProportionTestResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            .zStatistic: statistic,
            .probability: pValue,
            .proportion: proportion,
            .proportion1: proportion1, .proportion2: proportion2,
            .n1: n1, .n2: n2
        ])
    }
}

extension ChiSquareTestResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            .chiSquareStatistic: statistic,
            .probability: pValue,
            .degreesOfFreedom: degreesOfFreedom
        ])
    }
}

extension VarianceTestResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            // The F statistic has no entry-line variable of its own: `F` is already a user
            // variable. It reaches the caller through this struct instead.
            .probability: pValue,
            .sampleDeviation1: deviation1, .sampleDeviation2: deviation2,
            .n1: n1, .n2: n2
        ])
    }
}

extension LinRegTestResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            .tStatistic: statistic,
            .probability: pValue,
            .degreesOfFreedom: degreesOfFreedom,
            .coefficientA: intercept,
            .coefficientB: slope,
            .residualDeviation: residualDeviation,
            .correlation: correlation,
            .determination: correlation * correlation
        ])
    }
}

extension LinRegIntervalResult: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            .lowerBound: lower, .upperBound: upper,
            // The slope is the estimate the interval is about, so it goes to `b`, not to the
            // point-estimate slot the mean intervals use.
            .coefficientA: intercept,
            .coefficientB: slope,
            .degreesOfFreedom: degreesOfFreedom,
            .residualDeviation: residualDeviation,
            .correlation: correlation,
            .determination: correlation * correlation,
            .n: n
        ])
    }
}

extension ConfidenceInterval: StatisticsPublishing {
    var published: [StatVariable: Double] {
        defined([
            .lowerBound: lower, .upperBound: upper,
            .meanX: pointEstimate,
            .degreesOfFreedom: degreesOfFreedom,
            .n: n, .n2: n2
        ])
    }
}
