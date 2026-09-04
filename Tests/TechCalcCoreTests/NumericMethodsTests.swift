import Foundation
import Testing
@testable import TechCalcCore

/// Every iterative routine carries an explicit step limit and a defined tolerance, and throws
/// rather than spinning.
@Suite("Iterative numerics")
struct NumericMethodsTests {

    @Test("Romberg integration converges within its level budget")
    func integrationConverges() throws {
        expectClose(try NumericMethods.integrate(lower: 0, upper: 1) { $0 * $0 }, 1.0 / 3.0, tolerance: 1e-9)
        expectClose(try NumericMethods.integrate(lower: 0, upper: Double.pi) { Foundation.sin($0) }, 2, tolerance: 1e-9)
        expectClose(try NumericMethods.integrate(lower: 1, upper: 2) { 1 / $0 }, Foundation.log(2), tolerance: 1e-9)
    }

    @Test("Reversed limits negate, and equal limits are zero")
    func integrationLimits() throws {
        expectClose(try NumericMethods.integrate(lower: 1, upper: 0) { $0 * $0 }, -1.0 / 3.0, tolerance: 1e-9)
        #expect(try NumericMethods.integrate(lower: 2, upper: 2) { $0 } == 0)
        #expect(throws: TIError.domain) { try NumericMethods.integrate(lower: 0, upper: .infinity) { $0 } }
    }

    @Test("A non-converging integrand hits the level cap and throws ERR:ITERATIONS")
    func integrationStepLimit() {
        #expect(NumericMethods.maximumIntegrationLevels == 20)
        // 1/x on [0, 1] diverges: the refinement can never settle, so the guard must fire.
        #expect(throws: TIError.iterations) {
            try NumericMethods.integrate(lower: 0, upper: 1) { $0 == 0 ? .infinity : 1 / $0 }
        }
    }

    @Test("The derivative uses a fixed symmetric stencil")
    func derivative() throws {
        expectClose(try NumericMethods.derivative(at: 3) { $0 * $0 }, 6, tolerance: 1e-6)
        expectClose(try NumericMethods.derivative(at: 0) { Foundation.sin($0) }, 1, tolerance: 1e-6)
        #expect(NumericMethods.derivativeStep == 1e-3)
        #expect(throws: TIError.domain) { try NumericMethods.derivative(at: 1, step: 0) { $0 } }
    }

    @Test("Summation is bounded by an explicit term budget")
    func summationBudget() throws {
        #expect(try NumericMethods.summation(from: 1, through: 10) { Complex(Double($0)) } == Complex(55))
        #expect(throws: TIError.domain) { try NumericMethods.summation(from: 5, through: 1) { Complex(Double($0)) } }
        #expect(NumericMethods.maximumSummationTerms == 1_000_000)
        #expect(throws: TIError.iterations) {
            try NumericMethods.summation(from: 1, through: NumericMethods.maximumSummationTerms + 2) { Complex(Double($0)) }
        }
    }
}
