import Foundation

/// What a `STO▸` writes into. `rand` is a legal target: storing to it reseeds the generator.
///
/// The element and dimension cases carry the *unevaluated* index expressions, so `2+1→L1(A)`
/// resolves the subscript against the context in force when the store runs.
public indirect enum StoreTarget: Equatable, Sendable {
    case variable(Character)
    case randomSeed
    /// `{1,2,3}→L1`
    case list(ListName)
    /// `[[1,2][3,4]]→[A]`
    case matrix(MatrixName)
    /// `5→L1(2)`
    case listElement(ListName, Expression)
    /// `5→[A](1,2)`
    case matrixElement(MatrixName, Expression, Expression)
    /// `5→dim(L1)` resizes a list.
    case listDimension(ListName)
    /// `{2,3}→dim([A])` reshapes a matrix.
    case matrixDimension(MatrixName)
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
    /// `{1,2,3}` — a list written out.
    case listLiteral([Expression])
    /// `[[1,2][3,4]]` — a matrix written out, row by row.
    case matrixLiteral([[Expression]])
    /// A `VARS ▸ Statistics` result produced by the last STAT command, e.g. `x̄` or `r`.
    case statVariable(StatVariable)
    /// A reference to a stored list, e.g. `L1`.
    case listVariable(ListName)
    /// A reference to a stored matrix, e.g. `[A]`.
    case matrixVariable(MatrixName)
    /// 1-based element access: `L1(3)` or `[A](2,3)`. The subscripts stay TI-numbered here; the
    /// conversion to Swift indices happens in `TIList`/`TIMatrix`, not in the tree.
    case element(Expression, [Expression])
}
