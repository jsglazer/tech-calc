import Testing
@testable import TechCalcCore

/// `STAT TESTS`: the hypothesis tests and confidence intervals.
///
/// Numeric parity against R is in the benchmark fixtures. Here: the tail conventions, the two
/// degrees-of-freedom rules, and the property the pre-build decisions care most about — that the
/// typed command form and the pure function are one implementation with two callers.
@Suite("Inference")
struct InferenceTests {

    private static let sampleA = [22.1, 19.8, 24.5, 21.0, 23.3, 20.2, 25.1, 22.8]
    private static let sampleB = [18.4, 20.1, 17.9, 19.5, 21.2, 18.8]

    // MARK: - Degrees of freedom

    @Test("Welch-Satterthwaite is computed from its definition")
    func welchDegreesOfFreedom() throws {
        // s1 = 2, n1 = 10, s2 = 3, n2 = 20: a = 0.4, b = 0.45.
        // df = (a+b)² / (a²/9 + b²/45) = 0.7225 / (0.16/9 + 0.2025/45).
        let df = try Inference.welchDegreesOfFreedom(2, 10, 3, 20)
        let a = 4.0 / 10, b = 9.0 / 20
        expectClose(df, (a + b) * (a + b) / (a * a / 9 + b * b / 19), tolerance: 1e-12)
        #expect(throws: TIError.domain) { try Inference.welchDegreesOfFreedom(2, 1, 3, 20) }
    }

    @Test("The pooled procedure uses n1 + n2 - 2 and reports its pooled deviation")
    func pooledDegreesOfFreedom() throws {
        let result = try Inference.twoSampleTTest(
            mean1: 22, deviation1: 2, n1: 8, mean2: 19, deviation2: 1.5, n2: 6,
            alternative: .twoSided, pooled: true
        )
        #expect(result.degreesOfFreedom == 12)
        // sp² = (7·4 + 5·2.25) / 12.
        expectClose(result.pooledDeviation ?? .nan, ((7 * 4.0 + 5 * 2.25) / 12).squareRoot(), tolerance: 1e-14)

        let welch = try Inference.twoSampleTTest(
            mean1: 22, deviation1: 2, n1: 8, mean2: 19, deviation2: 1.5, n2: 6,
            alternative: .twoSided, pooled: false
        )
        #expect(welch.pooledDeviation == nil)
        #expect((welch.degreesOfFreedom ?? 0) != 12)
    }

    // MARK: - Tail conventions

    @Test("The one-sided p-values are complementary and the two-sided one is twice the smaller")
    func alternativeConventions() throws {
        let less = try Inference.tTest(hypothesisedMean: 10, mean: 12, sampleDeviation: 3, n: 9, alternative: .less)
        let greater = try Inference.tTest(hypothesisedMean: 10, mean: 12, sampleDeviation: 3, n: 9, alternative: .greater)
        let both = try Inference.tTest(hypothesisedMean: 10, mean: 12, sampleDeviation: 3, n: 9, alternative: .twoSided)
        expectClose(less.pValue + greater.pValue, 1, tolerance: 1e-12)
        expectClose(both.pValue, 2 * Swift.min(less.pValue, greater.pValue), tolerance: 1e-12)
        // The statistic itself does not depend on the alternative.
        expectClose(less.statistic, greater.statistic, tolerance: 1e-15)
    }

    @Test("The alternative is the TI's code: 0, -1 and 1, and nothing else")
    func alternativeCodes() throws {
        #expect(try Alternative(code: 0) == .twoSided)
        #expect(try Alternative(code: -1) == .less)
        #expect(try Alternative(code: 1) == .greater)
        #expect(throws: TIError.domain) { try Alternative(code: 2) }
        expectTIError("1-PropZTest(.5,45,100,2)", .domain)
    }

    @Test("The F test doubles the smaller tail rather than reflecting an asymmetric statistic")
    func varianceTestTails() throws {
        let result = try Inference.twoSampleFTest(
            deviation1: 3, n1: 10, deviation2: 2, n2: 12, alternative: .twoSided
        )
        let less = try Inference.twoSampleFTest(
            deviation1: 3, n1: 10, deviation2: 2, n2: 12, alternative: .less
        )
        expectClose(result.statistic, 9.0 / 4, tolerance: 1e-14)
        expectClose(result.pValue, 2 * Swift.min(less.pValue, 1 - less.pValue), tolerance: 1e-12)
    }

    // MARK: - Chi-square

    @Test("The expected table preserves the observed row and column totals")
    func chiSquareExpectedTable() throws {
        let observed = [[20.0, 30, 25], [25.0, 15, 35]]
        let result = try Inference.chiSquareTest(observed: observed)
        #expect(result.degreesOfFreedom == 2)
        for (row, expectedRow) in result.expected.enumerated() {
            expectClose(expectedRow.reduce(0, +), observed[row].reduce(0, +), tolerance: 1e-12)
        }
        for column in 0..<3 {
            expectClose(
                result.expected.reduce(0) { $0 + $1[column] },
                observed.reduce(0) { $0 + $1[column] },
                tolerance: 1e-12
            )
        }
    }

    @Test("A table smaller than two by two has no independence test")
    func chiSquareRequiresATable() {
        #expect(throws: TIError.invalidDimension) { try Inference.chiSquareTest(observed: [[1.0, 2, 3]]) }
        expectTIError("χ²GOF-Test({10,20},{10},1)", .dimensionMismatch)
    }

    // MARK: - Confidence intervals

    @Test("An interval is centred on its point estimate and widens with the level")
    func intervalGeometry() throws {
        let narrow = try Inference.tInterval(mean: 20, sampleDeviation: 3, n: 16, level: 0.90)
        let wide = try Inference.tInterval(mean: 20, sampleDeviation: 3, n: 16, level: 0.99)
        expectClose((narrow.lower + narrow.upper) / 2, 20, tolerance: 1e-12)
        #expect(wide.marginOfError > narrow.marginOfError)
        #expect(narrow.degreesOfFreedom == 15)
        #expect(throws: TIError.domain) {
            try Inference.tInterval(mean: 20, sampleDeviation: 3, n: 16, level: 1)
        }
    }

    @Test("The two-proportion interval estimates each proportion separately; only the test pools")
    func proportionIntervalIsUnpooled() throws {
        let interval = try Inference.twoPropZInterval(successes1: 45, n1: 100, successes2: 30, n2: 90, level: 0.95)
        expectClose(interval.pointEstimate, 45.0 / 100 - 30.0 / 90, tolerance: 1e-14)
        let test = try Inference.twoPropZTest(successes1: 45, n1: 100, successes2: 30, n2: 90, alternative: .twoSided)
        expectClose(test.proportion, 75.0 / 190, tolerance: 1e-14)
    }

    // MARK: - Two callers, one implementation

    @Test("The typed command and the pure function return the same numbers")
    func commandFormMatchesTheFunction() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{22.1,19.8,24.5,21,23.3,20.2,25.1,22.8}→L1")
        calculator.enter("{18.4,20.1,17.9,19.5,21.2,18.8}→L2")
        #expect(calculator.enter("2-SampTTest(L1,L2,0,0)").display == "Done")

        let first = try Statistics.oneVar(Self.sampleA)
        let second = try Statistics.oneVar(Self.sampleB)
        let expected = try Inference.twoSampleTTest(
            mean1: first.mean, deviation1: first.sampleStandardDeviation, n1: first.n,
            mean2: second.mean, deviation2: second.sampleStandardDeviation, n2: second.n,
            alternative: .twoSided, pooled: false
        )
        expectClose(try calculator.context.statistics.value(of: .tStatistic), expected.statistic, tolerance: 1e-14)
        expectClose(try calculator.context.statistics.value(of: .degreesOfFreedom),
                    expected.degreesOfFreedom ?? .nan, tolerance: 1e-14)
        expectClose(try calculator.context.statistics.value(of: .probability), expected.pValue, tolerance: 1e-14)
    }

    @Test("The Data form and the Stats form of a test agree")
    func dataFormMatchesStatsForm() throws {
        var data = Fixture.calculator()
        data.enter("{22.1,19.8,24.5,21,23.3,20.2,25.1,22.8}→L1")
        data.enter("T-Test(21,L1,0)")

        let summary = try Statistics.oneVar(Self.sampleA)
        var stats = Fixture.calculator()
        stats.enter("T-Test(21,\(summary.mean),\(summary.sampleStandardDeviation),8,0)")

        expectClose(
            try stats.context.statistics.value(of: .tStatistic),
            try data.context.statistics.value(of: .tStatistic),
            tolerance: 1e-12
        )
    }

    @Test("A z procedure publishes z and a t procedure publishes t")
    func statisticNamesMatchTheProcedure() throws {
        var calculator = Fixture.calculator()
        calculator.enter("1-PropZTest(.5,45,100,0)")
        #expect((try? calculator.context.statistics.value(of: .zStatistic)) != nil)
        #expect(throws: TIError.undefined) { try calculator.context.statistics.value(of: .tStatistic) }

        calculator.enter("{1,2,3,4,5,6}→L1")
        calculator.enter("T-Test(2,L1,0)")
        #expect((try? calculator.context.statistics.value(of: .tStatistic)) != nil)
        #expect(throws: TIError.undefined) { try calculator.context.statistics.value(of: .zStatistic) }
    }

    // MARK: - The regression-slope interval (D23 carry-over)

    @Test("LinRegTInt brackets the slope its own t test computes")
    func regressionIntervalAgreesWithTheTest() throws {
        // R: reg_x 1..8, reg_y the paired values the fixture suite uses.
        let xs: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
        let ys: [Double] = [2.1, 3.9, 6.2, 7.8, 10.1, 12.2, 13.8, 16.1]

        let interval = try Inference.linRegTInt(xs, ys, level: 0.95)
        let test = try Inference.linRegTTest(xs, ys, alternative: .twoSided)

        // The interval and the test are the same fit, so every shared field must agree exactly.
        #expect(interval.slope == test.slope)
        #expect(interval.intercept == test.intercept)
        #expect(interval.degreesOfFreedom == test.degreesOfFreedom)
        #expect(interval.residualDeviation == test.residualDeviation)
        // R: confint(lm(reg_y ~ reg_x))["reg_x", ]
        expectClose(interval.lower, 1.929593811075, tolerance: 1e-9)
        expectClose(interval.upper, 2.065644284163, tolerance: 1e-9)
        // The slope sits at the centre of its own interval.
        expectClose((interval.lower + interval.upper) / 2, interval.slope)
    }

    @Test("A wider confidence level gives a wider interval")
    func regressionIntervalWidensWithTheLevel() throws {
        let xs: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
        let ys: [Double] = [2.1, 3.9, 6.2, 7.8, 10.1, 12.2, 13.8, 16.1]
        let ninetyFive = try Inference.linRegTInt(xs, ys, level: 0.95)
        let ninetyNine = try Inference.linRegTInt(xs, ys, level: 0.99)
        #expect(ninetyNine.marginOfError > ninetyFive.marginOfError)
    }

    @Test("LinRegTInt publishes the endpoints and the fit, and not x\u{0304}")
    func regressionIntervalPublishesTheFit() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3,4,5,6,7,8}→L1")
        calculator.enter("{2.1,3.9,6.2,7.8,10.1,12.2,13.8,16.1}→L2")
        calculator.enter("LinRegTInt(L1,L2,.95)")

        let statistics = calculator.context.statistics
        expectClose(try statistics.value(of: .lowerBound), 1.929593811075, tolerance: 1e-9)
        expectClose(try statistics.value(of: .upperBound), 2.065644284163, tolerance: 1e-9)
        expectClose(try statistics.value(of: .degreesOfFreedom), 6)
        expectClose(try statistics.value(of: .n), 8)
        // The slope is `b`; the point-estimate slot the mean intervals use stays undefined,
        // because a slope is not a sample mean.
        expectClose(try statistics.value(of: .coefficientB), 1.997619047619, tolerance: 1e-9)
        #expect(statistics[.meanX] == nil)
    }

    @Test("A level outside (0,1) and a sample too short are TI errors")
    func regressionIntervalValidatesItsInputs() {
        let xs: [Double] = [1, 2, 3, 4]
        let ys: [Double] = [2, 4, 6, 8.1]
        #expect(throws: TIError.domain) { _ = try Inference.linRegTInt(xs, ys, level: 1) }
        #expect(throws: TIError.invalidDimension) {
            _ = try Inference.linRegTInt([1, 2], [2, 4], level: 0.95)
        }
    }
}
