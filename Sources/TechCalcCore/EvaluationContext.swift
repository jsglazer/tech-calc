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
    /// `L1`-`L6` and the named lists. A name absent here is an empty list, as on the TI.
    public var lists: [ListName: TIList]
    /// `[A]`-`[J]`. A matrix that has never been dimensioned is `ERR:UNDEFINED`.
    public var matrices: [MatrixName: TIMatrix]
    /// What the last `STAT CALC` or `STAT TESTS` command produced. Reading a variable no command
    /// has written is `ERR:UNDEFINED`.
    public var statistics: StatisticsVariables

    public init(
        mode: CalculatorMode = .default,
        variables: [Character: Complex] = [:],
        ans: TIValueSnapshot = .real(0),
        lists: [ListName: TIList] = [:],
        matrices: [MatrixName: TIMatrix] = [:],
        statistics: StatisticsVariables = StatisticsVariables()
    ) {
        self.mode = mode
        self.variables = variables
        self.ans = ans
        self.lists = lists
        self.matrices = matrices
        self.statistics = statistics
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

    // MARK: - Containers

    /// An unset list reads as empty, matching the TI's freshly reset `L1`.
    public func list(_ name: ListName) -> TIList {
        lists[name] ?? TIList()
    }

    /// An unset matrix has no dimensions at all, so reading one is `ERR:UNDEFINED`.
    public func matrix(_ name: MatrixName) throws -> TIMatrix {
        guard let matrix = matrices[name] else { throw TIError.undefined }
        return matrix
    }
}
