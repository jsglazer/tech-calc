import Foundation

/// The evaluator's mutable state: MODE, the TI variables, and `Ans`.
///
/// It is a value type with no reference to the outside world — no clock, no filesystem, no
/// defaults — so an evaluation is a pure function of this struct, the expression, and the
/// injected `RandomSource`.
public struct EvaluationContext: Equatable, Sendable {
    public var mode: CalculatorMode
    /// `A`-`Z` and `θ`.
    public var variables: [Character: Complex]
    public var ans: TIValueSnapshot

    public init(
        mode: CalculatorMode = .default,
        variables: [Character: Complex] = [:],
        ans: TIValueSnapshot = .real(0)
    ) {
        self.mode = mode
        self.variables = variables
        self.ans = ans
    }

    /// The TI's variable names: the 26 letters plus theta.
    public static let variableNames: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ") + ["θ"]

    public static func isVariableName(_ name: Character) -> Bool {
        variableNames.contains(name)
    }

    public func value(of name: Character) throws -> Complex {
        guard Self.isVariableName(name) else { throw TIError.undefined }
        return variables[name] ?? .zero
    }

    public mutating func setValue(_ value: Complex, for name: Character) throws {
        guard Self.isVariableName(name) else { throw TIError.undefined }
        variables[name] = value
    }
}
