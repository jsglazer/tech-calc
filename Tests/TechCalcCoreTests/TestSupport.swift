import Testing
@testable import TechCalcCore

/// Shared fixtures. Every helper builds a *fresh* value, so suites can run in parallel with no
/// shared mutable state and no dependence on execution order.
enum Fixture {
    /// A calculator with a fixed seed, so any random-producing test is exactly reproducible.
    static func calculator(mode: CalculatorMode = .default, seed: UInt64 = 1) -> Calculator {
        Calculator(context: EvaluationContext(mode: mode), random: SeededRandomSource(seed: seed))
    }

    static func evaluator(mode: CalculatorMode = .default, seed: UInt64 = 1) -> Evaluator {
        Evaluator(context: EvaluationContext(mode: mode), random: SeededRandomSource(seed: seed))
    }

    /// Evaluates one line and returns the raw value.
    static func value(_ source: String, mode: CalculatorMode = .default, seed: UInt64 = 1) throws -> TIValue {
        var calculator = calculator(mode: mode, seed: seed)
        return try calculator.evaluate(source).result
    }

    /// Evaluates one line and returns the real result.
    static func real(_ source: String, mode: CalculatorMode = .default, seed: UInt64 = 1) throws -> Double {
        try value(source, mode: mode, seed: seed).asReal
    }

    /// Evaluates one line and returns the string the calculator would display.
    static func display(_ source: String, mode: CalculatorMode = .default, seed: UInt64 = 1) -> String {
        var calculator = calculator(mode: mode, seed: seed)
        return calculator.enter(source).display
    }

    /// Container names, unwrapped once here so the suites read as TI syntax does.
    static func listName(_ number: Int) -> ListName {
        guard let name = ListName(number: number) else { preconditionFailure("L\(number) is not a list") }
        return name
    }

    static func namedList(_ text: String) -> ListName {
        guard let name = ListName(name: text) else { preconditionFailure("\(text) is not a list name") }
        return name
    }

    static func matrixName(_ letter: Character) -> MatrixName {
        guard let name = MatrixName(letter: letter) else { preconditionFailure("[\(letter)] is not a matrix") }
        return name
    }

    /// Evaluates one line and returns the resulting list.
    static func list(_ source: String, mode: CalculatorMode = .default, seed: UInt64 = 1) throws -> [Complex] {
        guard case .list(let list) = try value(source, mode: mode, seed: seed) else { throw TIError.dataType }
        return list.values
    }

    /// Evaluates one line and returns the resulting matrix as rows of reals.
    static func matrixRows(_ source: String, mode: CalculatorMode = .default, seed: UInt64 = 1) throws -> [[Double]] {
        guard case .matrix(let matrix) = try value(source, mode: mode, seed: seed) else { throw TIError.dataType }
        return (1...matrix.rows).map { row in
            (1...matrix.columns).compactMap { column in
                try? matrix[tiRow: row, tiColumn: column].re
            }
        }
    }

    /// Relative comparison at the 1e-9 numeric-parity bar the pre-build decisions set.
    static func isClose(_ a: Double, _ b: Double, relativeTolerance: Double = 1e-9) -> Bool {
        if a == b { return true }
        let scale = Swift.max(1, Swift.max(abs(a), abs(b)))
        return abs(a - b) <= relativeTolerance * scale
    }
}

/// Asserts numeric parity at a relative tolerance, the way the benchmark fixtures will.
func expectClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 1e-9,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        Fixture.isClose(actual, expected, relativeTolerance: tolerance),
        comment ?? "\(actual) is not within \(tolerance) of \(expected)",
        sourceLocation: sourceLocation
    )
}

/// Asserts a matrix element by element at the numeric-parity tolerance. Partial pivoting means
/// an inverse or a reduction lands within rounding of the exact value rather than on it.
func expectMatrix(
    _ actual: [[Double]],
    _ expected: [[Double]],
    tolerance: Double = 1e-12,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(actual.count == expected.count, "row count", sourceLocation: sourceLocation)
    for (actualRow, expectedRow) in zip(actual, expected) {
        #expect(actualRow.count == expectedRow.count, "column count", sourceLocation: sourceLocation)
        for (actualValue, expectedValue) in zip(actualRow, expectedRow) {
            expectClose(actualValue, expectedValue, tolerance: tolerance, sourceLocation: sourceLocation)
        }
    }
}

/// Asserts that evaluating `source` fails with a specific TI error name — error parity is part
/// of TI parity, so the name is asserted, not merely the fact of failure.
func expectTIError(
    _ source: String,
    _ expected: TIError,
    mode: CalculatorMode = .default,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    var calculator = Fixture.calculator(mode: mode)
    do {
        let result = try calculator.evaluate(source)
        Issue.record(
            "expected \(expected.tiName) from \"\(source)\" but got \(result.result)",
            sourceLocation: sourceLocation
        )
    } catch let error as TIError {
        #expect(error.tiName == expected.tiName, sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected \(expected.tiName), got \(error)", sourceLocation: sourceLocation)
    }
}
