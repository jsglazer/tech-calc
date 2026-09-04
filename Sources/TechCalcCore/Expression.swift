import Foundation

/// What a `STO▸` writes into. `rand` is a legal target: storing to it reseeds the generator.
public enum StoreTarget: Equatable, Sendable {
    case variable(Character)
    case randomSeed
}

/// The parsed expression tree.
///
/// Every entry form — prefix call, named infix operator, named postfix operator — normalizes to
/// `.call`, so the evaluator has one dispatch point and a future plotting layer walking this tree
/// sees a single node shape per function.
public indirect enum Expression: Equatable, Sendable {
    case number(Double)
    case variable(Character)
    case ans
    case constant(FunctionID)
    case call(FunctionID, [Expression])
    case binary(BinaryOperator, Expression, Expression)
    case negation(Expression)
    /// A presentation-only mark (`▸Frac`, `▸Polar`) wrapping the value it applies to.
    case displayConversion(FunctionID, Expression)
    /// `value STO▸ target`.
    case store(Expression, StoreTarget)
}
