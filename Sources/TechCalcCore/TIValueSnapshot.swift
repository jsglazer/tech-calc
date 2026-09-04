import Foundation

/// The `Codable` mirror of `TIValue`, used for persistence and for `Ans`.
///
/// `TIValue` itself stays free of `Codable` conformance so the evaluator's value type is not
/// shaped by the storage format; this snapshot is the one place the two meet.
public enum TIValueSnapshot: Equatable, Sendable, Codable {
    case real(Double)
    case complex(Complex)
    case list(TIList)
    case matrix(TIMatrix)
    case string(String)

    public init(_ value: TIValue) {
        switch value {
        case .real(let x): self = .real(x)
        case .complex(let z): self = .complex(z)
        case .list(let list): self = .list(list)
        case .matrix(let matrix): self = .matrix(matrix)
        case .string(let text): self = .string(text)
        }
    }

    public var value: TIValue {
        switch self {
        case .real(let x): .real(x)
        case .complex(let z): .complex(z)
        case .list(let list): .list(list)
        case .matrix(let matrix): .matrix(matrix)
        case .string(let text): .string(text)
        }
    }
}
