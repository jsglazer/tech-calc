import Foundation
import Testing
@testable import TechCalcCore

/// The `DISTR` menu: the fixed tail conventions, the inverse solver, and the guards that keep
/// every iterative loop bounded.
///
/// Numeric parity against R lives in the benchmark fixtures; this suite asserts the *behaviour*
/// the fixtures cannot — conventions, round-trips, and the explicit limits the reviewer criteria
/// ask to see.
@Suite("Distributions")
struct DistributionTests {

    // MARK: - The infinity sentinel and the interval rule

    @Test("A magnitude of 1E99 or more is the infinity sentinel")
    func infinitySentinel() throws {
        expectClose(try Fixture.real("normalcdf(-1E99,1E99)"), 1)
        // Anything past the sentinel is infinity too, not a very large finite bound.
        expectClose(try Fixture.real("normalcdf(-1E100,1E100)"), 1)
        #expect(Distributions.resolveBound(1e99) == .infinity)
        #expect(Distributions.resolveBound(-1e99) == -.infinity)
        #expect(Distributions.resolveBound(1e98).isFinite)
    }

    @Test("A cdf integrates left to right, and inverted bounds are ERR:DOMAIN")
    func intervalConvention() throws {
        // Left to right: the same bounds the other way round is an error, never a negative
        // probability. The convention is shared by every continuous cdf.
        expectTIError("normalcdf(2,1)", .domain)
        expectTIError("tcdf(2,1,10)", .domain)
        expectTIError("χ²cdf(9,1,4)", .domain)
        expectTIError("Fcdf(4,1,3,10)", .domain)
        #expect(try Fixture.real("normalcdf(-1,1)") > 0)
    }

    @Test("Degrees of freedom and deviations must be positive")
    func domainGuards() {
        expectTIError("tpdf(1,0)", .domain)
        expectTIError("χ²pdf(1,-2)", .domain)
        expectTIError("Fpdf(1,0,10)", .domain)
        expectTIError("normalpdf(1,0,0)", .domain)
        expectTIError("invNorm(0)", .domain)
        expectTIError("invNorm(1)", .domain)
        expectTIError("invT(1.5,10)", .domain)
    }

    // MARK: - Inverses

    @Test("Each inverse undoes its own cdf")
    func inversesRoundTrip() throws {
        for z in [-2.5, -1.0, 0.0, 0.75, 2.33] {
            let area = try Distributions.standardNormalCDF(z)
            expectClose(try Distributions.inverseNormal(area: area), z, tolerance: 1e-9)
        }
        for t in [-3.0, -0.5, 1.2, 4.0] {
            let area = try Distributions.tCDF(t, degreesOfFreedom: 7)
            expectClose(try Distributions.inverseT(area: area, degreesOfFreedom: 7), t, tolerance: 1e-8)
        }
        for x in [0.5, 3.0, 12.0] {
            let area = try Distributions.chiSquareCDF(x, degreesOfFreedom: 5)
            expectClose(try Distributions.inverseChiSquare(area: area, degreesOfFreedom: 5), x, tolerance: 1e-8)
        }
        for x in [0.3, 1.0, 4.5] {
            let area = try Distributions.fCDF(x, 4, 9)
            expectClose(try Distributions.inverseF(area: area, 4, 9), x, tolerance: 1e-8)
        }
    }

    @Test("The inverse solver has an explicit tolerance and iteration cap")
    func inverseLimitsAreExplicit() {
        // The reviewer criterion is that the iterative loops carry stated limits; these are the
        // numbers the pre-build decisions fixed, asserted so a later edit cannot quietly relax them.
        #expect(Distributions.inverseTolerance == 1e-12)
        #expect(Distributions.maximumInverseIterations == 200)
        #expect(SpecialFunctions.convergenceTolerance == 1e-15)
        #expect(SpecialFunctions.maximumIterations == 300)
    }

    @Test("A target outside the distribution's range fails rather than running away")
    func unbracketedTargetThrows() {
        #expect(throws: TIError.domain) {
            try Distributions.solve(
                target: 2, lowerBracket: 0, upperBracket: 1,
                cdf: { $0 }, pdf: { _ in 1 }
            )
        }
    }

    // MARK: - Continuity between the pdf and the cdf

    @Test("The continuous cdfs are monotone and bounded")
    func cdfsAreMonotone() throws {
        var previous = 0.0
        for step in stride(from: -4.0, through: 4.0, by: 0.5) {
            let value = try Distributions.standardNormalCDF(step)
            #expect(value >= previous)
            #expect(value >= 0 && value <= 1)
            previous = value
        }
        #expect(try Distributions.chiSquareCDF(0, degreesOfFreedom: 3) == 0)
        #expect(try Distributions.fCDF(0, 3, 4) == 0)
    }

    @Test("The normal cdf is symmetric about its mean")
    func normalSymmetry() throws {
        for z in [0.25, 1.0, 3.5] {
            expectClose(
                (try Distributions.standardNormalCDF(z)) + (try Distributions.standardNormalCDF(-z)),
                1, tolerance: 1e-14
            )
        }
    }

    // MARK: - Discrete

    @Test("binompdf( over the whole range is a distribution, and binomcdf( is its running total")
    func binomialConsistency() throws {
        let probabilities = try Fixture.list("binompdf(8,.35)")
        #expect(probabilities.count == 9)
        expectClose(ListMath.sum(probabilities).re, 1, tolerance: 1e-12)

        var running = 0.0
        for successes in 0...8 {
            running += try Distributions.binomialPDF(trials: 8, probability: 0.35, successes: successes)
            expectClose(
                try Distributions.binomialCDF(trials: 8, probability: 0.35, successes: successes),
                running, tolerance: 1e-12
            )
        }
    }

    @Test("The geometric distribution counts trials from 1, as the TI does")
    func geometricSupport() throws {
        #expect(try Distributions.geometricPDF(probability: 0.3, trial: 0) == 0)
        expectClose(try Distributions.geometricPDF(probability: 0.3, trial: 1), 0.3)
        // The closed form of the cdf, independent of the loop the pdf would need.
        for trial in 1...6 {
            expectClose(
                try Distributions.geometricCDF(probability: 0.3, trial: trial),
                1 - Foundation.pow(0.7, Double(trial)), tolerance: 1e-12
            )
        }
    }

    @Test("poissoncdf( agrees with the sum of its own pdf")
    func poissonConsistency() throws {
        var running = 0.0
        for successes in 0...12 {
            running += try Distributions.poissonPDF(mean: 4.2, successes: successes)
            expectClose(
                try Distributions.poissonCDF(mean: 4.2, successes: successes),
                running, tolerance: 1e-12
            )
        }
    }

    // MARK: - Broadcasting

    @Test("A distribution maps over a list, element by element")
    func distributionsBroadcast() throws {
        let densities = try Fixture.list("normalpdf({-1,0,1})")
        #expect(densities.count == 3)
        expectClose(densities[1].re, try Distributions.normalPDF(0))
        expectClose(densities[0].re, densities[2].re, tolerance: 1e-15)
    }
}
