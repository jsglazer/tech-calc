import Foundation

/// The statistics half of the evaluator: the `DISTR` menu, the seeded draws, `STAT CALC` and
/// `STAT TESTS`.
///
/// It is split from `Evaluator` for readability only — dispatch is still on `FunctionID`, and no
/// function name is spelled here. The split that *is* meaningful is the one inside this file:
///
///   * `applyStatisticsFunction` is non-mutating. The distributions and the seeded draws compute
///     a value and change no state, so they can be broadcast element-wise over a list.
///   * `applyStatisticsCommand` is mutating. The `STAT CALC` and `STAT TESTS` commands publish
///     their results into `context.statistics` and return `Done`, as the TI does.
///
/// Every command here is a thin argument reader in front of a pure function in `Statistics`,
/// `Inference` or `Distributions`. No statistical arithmetic is performed in this file, which is
/// what keeps the form-style UI screens and the typed command form two callers of one
/// implementation rather than two implementations.
extension Evaluator {

    // MARK: - Argument readers

    private func number(_ values: [TIValue], _ index: Int) throws -> Double {
        guard values.indices.contains(index) else { throw TIError.syntax }
        return try values[index].asReal
    }

    private func count(_ values: [TIValue], _ index: Int) throws -> Int {
        guard values.indices.contains(index) else { throw TIError.syntax }
        return try values[index].asInteger
    }

    /// A list argument, as plain reals. Statistics is real-only on the TI.
    private func sample(_ values: [TIValue], _ index: Int) throws -> [Double] {
        guard values.indices.contains(index), case .list(let list) = values[index] else {
            throw TIError.dataType
        }
        return try ListMath.realValues(list.values)
    }

    /// An optional trailing frequency list.
    private func frequencies(_ values: [TIValue], _ index: Int) throws -> [Double]? {
        guard values.indices.contains(index) else { return nil }
        return try sample(values, index)
    }

    private func isList(_ values: [TIValue], _ index: Int) -> Bool {
        guard values.indices.contains(index), case .list = values[index] else { return false }
        return true
    }

    private func alternative(_ values: [TIValue], _ index: Int) throws -> Alternative {
        try Alternative(code: try count(values, index))
    }

    /// The TI writes a flag as 0 or 1.
    private func flag(_ values: [TIValue], _ index: Int) throws -> Bool {
        guard values.indices.contains(index) else { return false }
        return try number(values, index) != 0
    }

    /// The optional `μ`/`σ` pair the normal-family entries accept after their required arguments.
    private func normalParameters(_ values: [TIValue], from index: Int) throws -> (mean: Double, deviation: Double) {
        let mean = values.indices.contains(index) ? try number(values, index) : 0
        let deviation = values.indices.contains(index + 1) ? try number(values, index + 1) : 1
        return (mean, deviation)
    }

    /// Publishes a result into the `VARS ▸ Statistics` bag and answers `Done`, as the TI's
    /// results screen does. Every command ends here, so "what a command returns" is one rule.
    private mutating func publish(_ result: some StatisticsPublishing) -> TIValue {
        context.statistics.publish(result.published)
        return .done
    }

    // MARK: - DISTR and the seeded draws (pure; broadcastable over lists)

    func applyStatisticsFunction(_ id: FunctionID, _ values: [TIValue]) throws -> TIValue? {
        switch id {
        // MARK: Normal
        case .normalPDF:
            let parameters = try normalParameters(values, from: 1)
            return .real(try Distributions.normalPDF(
                try number(values, 0), mean: parameters.mean, standardDeviation: parameters.deviation))
        case .normalCDF:
            let parameters = try normalParameters(values, from: 2)
            return .real(try Distributions.normalCDF(
                lower: try number(values, 0), upper: try number(values, 1),
                mean: parameters.mean, standardDeviation: parameters.deviation))
        case .inverseNormal:
            let parameters = try normalParameters(values, from: 1)
            return .real(try Distributions.inverseNormal(
                area: try number(values, 0), mean: parameters.mean, standardDeviation: parameters.deviation))

        // MARK: Student t
        case .studentPDF:
            return .real(try Distributions.tPDF(try number(values, 0), degreesOfFreedom: try number(values, 1)))
        case .studentCDF:
            return .real(try Distributions.tCDF(
                lower: try number(values, 0), upper: try number(values, 1),
                degreesOfFreedom: try number(values, 2)))
        case .inverseStudent:
            return .real(try Distributions.inverseT(
                area: try number(values, 0), degreesOfFreedom: try number(values, 1)))

        // MARK: Chi-square
        case .chiSquarePDF:
            return .real(try Distributions.chiSquarePDF(
                try number(values, 0), degreesOfFreedom: try number(values, 1)))
        case .chiSquareCDF:
            return .real(try Distributions.chiSquareCDF(
                lower: try number(values, 0), upper: try number(values, 1),
                degreesOfFreedom: try number(values, 2)))
        case .inverseChiSquare:
            return .real(try Distributions.inverseChiSquare(
                area: try number(values, 0), degreesOfFreedom: try number(values, 1)))

        // MARK: F
        case .fPDF:
            return .real(try Distributions.fPDF(
                try number(values, 0), try number(values, 1), try number(values, 2)))
        case .fCDF:
            return .real(try Distributions.fCDF(
                lower: try number(values, 0), upper: try number(values, 1),
                try number(values, 2), try number(values, 3)))
        case .inverseF:
            return .real(try Distributions.inverseF(
                area: try number(values, 0), try number(values, 1), try number(values, 2)))

        // MARK: Discrete. Omitting the count returns the whole distribution as a list, as on the TI.
        case .binomialPDF, .binomialCDF:
            let trials = try count(values, 0)
            let probability = try number(values, 1)
            let single: (Int) throws -> Double = { successes in
                id == .binomialPDF
                    ? try Distributions.binomialPDF(trials: trials, probability: probability, successes: successes)
                    : try Distributions.binomialCDF(trials: trials, probability: probability, successes: successes)
            }
            if values.count == 3 { return .real(try single(try count(values, 2))) }
            guard trials >= 0, trials <= TILimits.maxListLength else { throw TIError.invalidDimension }
            return .list(TIList(reals: try (0...trials).map(single)))

        case .poissonPDF:
            return .real(try Distributions.poissonPDF(
                mean: try number(values, 0), successes: try count(values, 1)))
        case .poissonCDF:
            return .real(try Distributions.poissonCDF(
                mean: try number(values, 0), successes: try count(values, 1)))
        case .geometricPDF:
            return .real(try Distributions.geometricPDF(
                probability: try number(values, 0), trial: try count(values, 1)))
        case .geometricCDF:
            return .real(try Distributions.geometricCDF(
                probability: try number(values, 0), trial: try count(values, 1)))

        // MARK: The seeded draws. All three go through the injected RandomSource.
        case .randomNormal:
            let mean = try number(values, 0)
            let deviation = try number(values, 1)
            guard deviation > 0 else { throw TIError.domain }
            let draw = { mean + deviation * self.random.nextNormal() }
            guard values.count == 3 else { return .real(draw()) }
            return .list(TIList(reals: try repeated(try count(values, 2), draw)))

        case .randomBinomial:
            let trials = try count(values, 0)
            let probability = try number(values, 1)
            let draw = { Double(try self.random.nextBinomial(trials: trials, probability: probability)) }
            guard values.count == 3 else { return .real(try draw()) }
            return .list(TIList(reals: try repeated(try count(values, 2), draw)))

        case .randomIntegerNoRepeat:
            let drawn = try random.nextPermutation(lower: try count(values, 0), upper: try count(values, 1))
            return .list(TIList(reals: drawn.map(Double.init)))

        default:
            return nil
        }
    }

    /// `count` draws from `draw`, with the list-length cap applied before any drawing happens.
    private func repeated(_ count: Int, _ draw: () throws -> Double) throws -> [Double] {
        guard count >= 1, count <= TILimits.maxListLength else { throw TIError.invalidDimension }
        return try (0..<count).map { _ in try draw() }
    }

    // MARK: - STAT CALC and STAT TESTS (publish their results, then answer Done)

    mutating func applyStatisticsCommand(_ id: FunctionID, _ values: [TIValue]) throws -> TIValue? {
        switch id {
        // MARK: STAT CALC
        case .oneVarStats:
            return publish(try Statistics.oneVar(
                try sample(values, 0), frequencies: try frequencies(values, 1)))

        case .twoVarStats:
            return publish(try Statistics.twoVar(
                try sample(values, 0), try sample(values, 1), frequencies: try frequencies(values, 2)))

        case .linRegAXB, .linRegABX, .quadReg, .cubicReg, .quartReg, .lnReg, .expReg, .pwrReg:
            guard let model = Self.regressionModel(for: id) else { throw TIError.undefined }
            return publish(try Statistics.regression(
                model, try sample(values, 0), try sample(values, 1),
                frequencies: try frequencies(values, 2)))

        // MARK: STAT TESTS — means
        case .zTest:
            // Data form: (μ0, σ, list, alternative). Stats form: (μ0, σ, x̄, n, alternative).
            let mu0 = try number(values, 0)
            let sigma = try number(values, 1)
            if isList(values, 2) {
                let data = try Statistics.oneVar(try sample(values, 2))
                return publish(try Inference.zTest(
                    hypothesisedMean: mu0, populationDeviation: sigma,
                    mean: data.mean, n: data.n, alternative: try alternative(values, 3)))
            }
            return publish(try Inference.zTest(
                hypothesisedMean: mu0, populationDeviation: sigma,
                mean: try number(values, 2), n: try number(values, 3),
                alternative: try alternative(values, 4)))

        case .tTest:
            // Data form: (μ0, list, alternative). Stats form: (μ0, x̄, Sx, n, alternative).
            let mu0 = try number(values, 0)
            if isList(values, 1) {
                let data = try Statistics.oneVar(try sample(values, 1))
                return publish(try Inference.tTest(
                    hypothesisedMean: mu0, mean: data.mean,
                    sampleDeviation: data.sampleStandardDeviation, n: data.n,
                    alternative: try alternative(values, 2)))
            }
            return publish(try Inference.tTest(
                hypothesisedMean: mu0, mean: try number(values, 1),
                sampleDeviation: try number(values, 2), n: try number(values, 3),
                alternative: try alternative(values, 4)))

        case .twoSampleZTest:
            let sigma1 = try number(values, 0)
            let sigma2 = try number(values, 1)
            if isList(values, 2) {
                let first = try Statistics.oneVar(try sample(values, 2))
                let second = try Statistics.oneVar(try sample(values, 3))
                return publish(try Inference.twoSampleZTest(
                    deviation1: sigma1, deviation2: sigma2,
                    mean1: first.mean, n1: first.n, mean2: second.mean, n2: second.n,
                    alternative: try alternative(values, 4)))
            }
            return publish(try Inference.twoSampleZTest(
                deviation1: sigma1, deviation2: sigma2,
                mean1: try number(values, 2), n1: try number(values, 3),
                mean2: try number(values, 4), n2: try number(values, 5),
                alternative: try alternative(values, 6)))

        case .twoSampleTTest:
            // Data form: (list1, list2, alternative, pooled).
            // Stats form: (x̄1, Sx1, n1, x̄2, Sx2, n2, alternative, pooled).
            if isList(values, 0) {
                let first = try Statistics.oneVar(try sample(values, 0))
                let second = try Statistics.oneVar(try sample(values, 1))
                return publish(try Inference.twoSampleTTest(
                    mean1: first.mean, deviation1: first.sampleStandardDeviation, n1: first.n,
                    mean2: second.mean, deviation2: second.sampleStandardDeviation, n2: second.n,
                    alternative: try alternative(values, 2), pooled: try flag(values, 3)))
            }
            return publish(try Inference.twoSampleTTest(
                mean1: try number(values, 0), deviation1: try number(values, 1), n1: try number(values, 2),
                mean2: try number(values, 3), deviation2: try number(values, 4), n2: try number(values, 5),
                alternative: try alternative(values, 6), pooled: try flag(values, 7)))

        // MARK: STAT TESTS — proportions
        case .onePropZTest:
            return publish(try Inference.onePropZTest(
                hypothesisedProportion: try number(values, 0), successes: try number(values, 1),
                n: try number(values, 2), alternative: try alternative(values, 3)))

        case .twoPropZTest:
            return publish(try Inference.twoPropZTest(
                successes1: try number(values, 0), n1: try number(values, 1),
                successes2: try number(values, 2), n2: try number(values, 3),
                alternative: try alternative(values, 4)))

        // MARK: STAT TESTS — counts and variances
        case .chiSquareTest:
            guard case .matrix(let observed) = values[0] else { throw TIError.dataType }
            return publish(try Inference.chiSquareTest(observed: try MatrixMath.rows(of: observed).map {
                try ListMath.realValues($0)
            }))

        case .chiSquareGOFTest:
            return publish(try Inference.goodnessOfFit(
                observed: try sample(values, 0), expected: try sample(values, 1),
                degreesOfFreedom: try number(values, 2)))

        case .twoSampleFTest:
            // Data form: (list1, list2, alternative). Stats form: (Sx1, n1, Sx2, n2, alternative).
            if isList(values, 0) {
                let first = try Statistics.oneVar(try sample(values, 0))
                let second = try Statistics.oneVar(try sample(values, 1))
                return publish(try Inference.twoSampleFTest(
                    deviation1: first.sampleStandardDeviation, n1: first.n,
                    deviation2: second.sampleStandardDeviation, n2: second.n,
                    alternative: try alternative(values, 2)))
            }
            return publish(try Inference.twoSampleFTest(
                deviation1: try number(values, 0), n1: try number(values, 1),
                deviation2: try number(values, 2), n2: try number(values, 3),
                alternative: try alternative(values, 4)))

        case .linRegTTest:
            return publish(try Inference.linRegTTest(
                try sample(values, 0), try sample(values, 1), alternative: try alternative(values, 2)))

        // MARK: STAT TESTS — confidence intervals
        case .zInterval:
            let sigma = try number(values, 0)
            if isList(values, 1) {
                let data = try Statistics.oneVar(try sample(values, 1))
                return publish(try Inference.zInterval(
                    populationDeviation: sigma, mean: data.mean, n: data.n,
                    level: try number(values, 2)))
            }
            return publish(try Inference.zInterval(
                populationDeviation: sigma, mean: try number(values, 1),
                n: try number(values, 2), level: try number(values, 3)))

        case .tInterval:
            if isList(values, 0) {
                let data = try Statistics.oneVar(try sample(values, 0))
                return publish(try Inference.tInterval(
                    mean: data.mean, sampleDeviation: data.sampleStandardDeviation, n: data.n,
                    level: try number(values, 1)))
            }
            return publish(try Inference.tInterval(
                mean: try number(values, 0), sampleDeviation: try number(values, 1),
                n: try number(values, 2), level: try number(values, 3)))

        case .twoSampleZInterval:
            let sigma1 = try number(values, 0)
            let sigma2 = try number(values, 1)
            if isList(values, 2) {
                let first = try Statistics.oneVar(try sample(values, 2))
                let second = try Statistics.oneVar(try sample(values, 3))
                return publish(try Inference.twoSampleZInterval(
                    deviation1: sigma1, deviation2: sigma2,
                    mean1: first.mean, n1: first.n, mean2: second.mean, n2: second.n,
                    level: try number(values, 4)))
            }
            return publish(try Inference.twoSampleZInterval(
                deviation1: sigma1, deviation2: sigma2,
                mean1: try number(values, 2), n1: try number(values, 3),
                mean2: try number(values, 4), n2: try number(values, 5),
                level: try number(values, 6)))

        case .twoSampleTInterval:
            if isList(values, 0) {
                let first = try Statistics.oneVar(try sample(values, 0))
                let second = try Statistics.oneVar(try sample(values, 1))
                return publish(try Inference.twoSampleTInterval(
                    mean1: first.mean, deviation1: first.sampleStandardDeviation, n1: first.n,
                    mean2: second.mean, deviation2: second.sampleStandardDeviation, n2: second.n,
                    level: try number(values, 2), pooled: try flag(values, 3)))
            }
            return publish(try Inference.twoSampleTInterval(
                mean1: try number(values, 0), deviation1: try number(values, 1), n1: try number(values, 2),
                mean2: try number(values, 3), deviation2: try number(values, 4), n2: try number(values, 5),
                level: try number(values, 6), pooled: try flag(values, 7)))

        case .onePropZInterval:
            return publish(try Inference.onePropZInterval(
                successes: try number(values, 0), n: try number(values, 1), level: try number(values, 2)))

        case .twoPropZInterval:
            return publish(try Inference.twoPropZInterval(
                successes1: try number(values, 0), n1: try number(values, 1),
                successes2: try number(values, 2), n2: try number(values, 3),
                level: try number(values, 4)))

        case .linRegTInterval:
            return publish(try Inference.linRegTInt(
                try sample(values, 0), try sample(values, 1), level: try number(values, 2)))

        default:
            return nil
        }
    }

    /// The one place a catalog entry is tied to a regression family, so the eight `STAT CALC`
    /// regressions share a single command implementation.
    static func regressionModel(for id: FunctionID) -> RegressionModel? {
        switch id {
        case .linRegAXB: .linearAXB
        case .linRegABX: .linearABX
        case .quadReg: .quadratic
        case .cubicReg: .cubic
        case .quartReg: .quartic
        case .lnReg: .logarithmic
        case .expReg: .exponential
        case .pwrReg: .power
        default: nil
        }
    }
}
