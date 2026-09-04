import Foundation

/// Errors thrown by the tokenizer, parser and evaluator.
///
/// The cases mirror the TI-84 Plus CE error names exactly, because error parity is part of
/// TI parity: benchmark fixtures assert the specific name for error cases.
public enum TIError: Error, Equatable, Sendable {
    case syntax
    case domain
    case divideByZero
    case nonrealAnswer
    case dimensionMismatch
    case invalidDimension
    case singularMatrix
    case dataType
    case noSignChange
    case iterations
    case undefined
    case unsupportedSchemaVersion(Int)

    /// The name the TI-84 displays, used verbatim by fixtures and by the history rows.
    public var tiName: String {
        switch self {
        case .syntax: "ERR:SYNTAX"
        case .domain: "ERR:DOMAIN"
        case .divideByZero: "ERR:DIVIDE BY 0"
        case .nonrealAnswer: "ERR:NONREAL ANS"
        case .dimensionMismatch: "ERR:DIM MISMATCH"
        case .invalidDimension: "ERR:INVALID DIM"
        case .singularMatrix: "ERR:SINGULAR MAT"
        case .dataType: "ERR:DATA TYPE"
        case .noSignChange: "ERR:NO SIGN CHNG"
        case .iterations: "ERR:ITERATIONS"
        case .undefined: "ERR:UNDEFINED"
        case .unsupportedSchemaVersion: "ERR:VERSION"
        }
    }
}
