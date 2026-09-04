import Foundation

/// A TI list (`L1`-`L6` and named lists).
///
/// TI list syntax is 1-based. `subscript(tiIndex:)` is the *only* place that conversion to
/// Swift's 0-based indices happens for a list, so the index boundary is auditable in one spot.
public struct TIList: Equatable, Hashable, Sendable, Codable {
    public private(set) var values: [Complex]

    public init(_ values: [Complex] = []) { self.values = values }
    public init(reals: [Double]) { self.values = reals.map { Complex($0) } }
    public init(repeating value: Complex, count: Int) {
        self.values = Array(repeating: value, count: Swift.max(0, count))
    }

    public var count: Int { values.count }

    /// 1-based element access, as written in TI syntax (`L1(1)` is the first element).
    public subscript(tiIndex index: Int) -> Complex {
        get throws {
            guard index >= 1, index <= values.count else { throw TIError.invalidDimension }
            return values[index - 1]
        }
    }

    public mutating func set(tiIndex index: Int, to value: Complex) throws {
        guard index >= 1, index <= values.count else { throw TIError.invalidDimension }
        values[index - 1] = value
    }

    /// Resizes as `dim(` does: growing pads with zeros, shrinking truncates.
    public mutating func resize(to newCount: Int) throws {
        guard newCount >= 0, newCount <= TILimits.maxListLength else { throw TIError.invalidDimension }
        if newCount < values.count {
            values.removeSubrange(newCount...)
        } else {
            values.append(contentsOf: Array(repeating: Complex.zero, count: newCount - values.count))
        }
    }
}

/// A TI matrix (`[A]`-`[J]`), stored row-major.
///
/// As with `TIList`, `subscript(tiRow:tiColumn:)` is the single 1-based/0-based boundary.
public struct TIMatrix: Equatable, Hashable, Sendable, Codable {
    public private(set) var rows: Int
    public private(set) var columns: Int
    public private(set) var values: [Complex]

    public init(rows: Int, columns: Int) throws {
        guard rows >= 1, columns >= 1,
              rows <= TILimits.maxMatrixDimension, columns <= TILimits.maxMatrixDimension else {
            throw TIError.invalidDimension
        }
        self.rows = rows
        self.columns = columns
        self.values = Array(repeating: Complex.zero, count: rows * columns)
    }

    public init(rows: Int, columns: Int, values: [Complex]) throws {
        guard rows >= 1, columns >= 1,
              rows <= TILimits.maxMatrixDimension, columns <= TILimits.maxMatrixDimension,
              values.count == rows * columns else {
            throw TIError.invalidDimension
        }
        self.rows = rows
        self.columns = columns
        self.values = values
    }

    /// 1-based element access, as written in TI syntax (`[A](1,1)` is the top-left element).
    public subscript(tiRow row: Int, tiColumn column: Int) -> Complex {
        get throws {
            guard row >= 1, row <= rows, column >= 1, column <= columns else {
                throw TIError.invalidDimension
            }
            return values[(row - 1) * columns + (column - 1)]
        }
    }

    public mutating func set(tiRow row: Int, tiColumn column: Int, to value: Complex) throws {
        guard row >= 1, row <= rows, column >= 1, column <= columns else {
            throw TIError.invalidDimension
        }
        values[(row - 1) * columns + (column - 1)] = value
    }
}

/// Fixed TI-84 capacity limits, in one place.
public enum TILimits {
    public static let maxListLength = 999
    public static let maxMatrixDimension = 99
    public static let maxHistoryEntries = 500
    /// `randM(` draws integers in `-9...9`, matching the TI.
    public static let randomMatrixMagnitude = 9
}

/// The one value type that crosses the evaluator.
///
/// `.real` and `.complex` are two spellings of the same number, not two evaluator paths:
/// arithmetic runs through `Complex` unconditionally and `TIValue.number(_:)` normalizes the
/// result back to `.real` whenever the imaginary part is exactly zero.
public enum TIValue: Equatable, Hashable, Sendable {
    case real(Double)
    case complex(Complex)
    case list(TIList)
    case matrix(TIMatrix)
    case string(String)

    /// The single normalization point from complex arithmetic back into the value enum.
    public static func number(_ z: Complex) -> TIValue {
        z.isReal ? .real(z.re) : .complex(z)
    }

    /// Every numeric value viewed as a complex number, so callers never branch on realness.
    public var asComplex: Complex {
        get throws {
            switch self {
            case .real(let x): Complex(x)
            case .complex(let z): z
            case .list, .matrix, .string: throw TIError.dataType
            }
        }
    }

    /// A real scalar, or `ERR:DATA TYPE` / `ERR:NONREAL ANS` where one is required.
    public var asReal: Double {
        get throws {
            switch self {
            case .real(let x): x
            case .complex: throw TIError.nonrealAnswer
            case .list, .matrix, .string: throw TIError.dataType
            }
        }
    }

    /// A real value that must be a whole number (list dimensions, `randInt` bounds, and so on).
    public var asInteger: Int {
        get throws {
            let x = try asReal
            guard x.isFinite, x == x.rounded(), Swift.abs(x) < 1e15 else { throw TIError.domain }
            return Int(x)
        }
    }

    /// What the TI shows for a command that acted rather than computed — `SortA(`, `Fill(`.
    public static let done = TIValue.string("Done")

    public var isNumber: Bool {
        switch self {
        case .real, .complex: true
        case .list, .matrix, .string: false
        }
    }
}
