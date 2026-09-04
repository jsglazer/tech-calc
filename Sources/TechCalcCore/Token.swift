import Foundation

/// A binary operator written as punctuation rather than as a catalog name.
public enum BinaryOperator: String, Equatable, Hashable, Sendable {
    case add, subtract, multiply, divide, power
    case equal, notEqual, less, lessEqual, greater, greaterEqual

    /// Left binding power. The ordering is the TI-84's documented precedence table:
    /// postfix > `^` > negation > `nPr`/`nCr` > `*` `/` > `+` `-` > relational > and > or/xor.
    var bindingPower: Int {
        switch self {
        case .power: 80
        case .multiply, .divide: 50
        case .add, .subtract: 40
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual: 30
        }
    }

    /// `^` is right-associative (2^3^2 is 2^(3^2)); everything else groups left to right.
    var isRightAssociative: Bool { self == .power }
}

/// Binding powers for the constructs that are not simple binary operators.
enum BindingPower {
    /// `▸Frac` and friends convert the *answer*, so they bind looser than every operator and
    /// wrap the whole entry rather than the operand they happen to follow.
    static let displayConversion = 5
    static let logicalOr = 10
    static let logicalAnd = 20
    static let permutation = 60
    /// Unary negation binds looser than exponentiation, so `-3^2` is `-9`.
    static let negation = 70
    static let postfix = 90
    /// Implicit multiplication binds exactly as tightly as explicit `*`.
    static let implicitMultiplication = BinaryOperator.multiply.bindingPower
}

/// One lexical unit. Both keypad presses and typed characters reach the parser as these — there
/// is one input path, not two.
public enum Token: Equatable, Sendable {
    case number(Double)
    case variable(Character)
    case ans
    /// A prefix call, e.g. `sin(`.
    case function(FunctionID)
    /// A bare value such as `π` or `rand`.
    case constant(FunctionID)
    /// A named infix operator, e.g. `nPr`, `and`.
    case infixFunction(FunctionID)
    /// A named postfix operator, e.g. `²`, `!`.
    case postfixFunction(FunctionID)
    /// A postfix mark that changes presentation only, e.g. `▸Frac`.
    case displayConversion(FunctionID)
    case binaryOperator(BinaryOperator)
    /// The `(-)` key: negation, distinct from the subtraction key.
    case negation
    case leftParenthesis
    case rightParenthesis
    case comma
    /// `STO▸`.
    case store
    /// A stored list: `L1`-`L6` or `∟NAME`.
    case listName(ListName)
    /// A stored matrix: `[A]`-`[J]`.
    case matrixName(MatrixName)
    /// `{` and `}` — the list literal delimiters.
    case leftBrace
    case rightBrace
    /// `[` and `]` — the matrix literal delimiters.
    case leftBracket
    case rightBracket
}
