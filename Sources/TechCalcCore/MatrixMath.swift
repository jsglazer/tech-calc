import Foundation

/// Pure-Swift dense linear algebra for the TI matrix menu.
///
/// Accelerate, vDSP, BLAS and LAPACK are deliberately absent: TI matrices are at most 10x10,
/// LAPACK's pivoting choices diverge from the TI's `ref`/`rref` output, and vendor kernels vary
/// across architectures. Gaussian elimination with partial pivoting, written out here, is
/// deterministic and architecture-independent, which is what the benchmark fixtures need.
public enum MatrixMath {
    /// A pivot whose magnitude is at or below this is treated as zero.
    ///
    /// This is the single tolerance the whole module compares against, so "when is this matrix
    /// singular?" has exactly one answer.
    public static let singularityTolerance = 1e-12

    // MARK: - Shape

    /// Row-major storage viewed as rows of complex numbers.
    static func rows(of matrix: TIMatrix) -> [[Complex]] {
        (0..<matrix.rows).map { row in
            Array(matrix.values[(row * matrix.columns)..<((row + 1) * matrix.columns)])
        }
    }

    static func matrix(from rows: [[Complex]]) throws -> TIMatrix {
        guard let width = rows.first?.count, rows.allSatisfy({ $0.count == width }) else {
            throw TIError.invalidDimension
        }
        return try TIMatrix(rows: rows.count, columns: width, values: rows.flatMap { $0 })
    }

    static func isNegligible(_ z: Complex) -> Bool {
        z.magnitude <= singularityTolerance
    }

    // MARK: - Elementwise and product

    public static func add(_ a: TIMatrix, _ b: TIMatrix) throws -> TIMatrix {
        try combine(a, b, +)
    }

    public static func subtract(_ a: TIMatrix, _ b: TIMatrix) throws -> TIMatrix {
        try combine(a, b, -)
    }

    private static func combine(
        _ a: TIMatrix,
        _ b: TIMatrix,
        _ operation: (Complex, Complex) -> Complex
    ) throws -> TIMatrix {
        guard a.rows == b.rows, a.columns == b.columns else { throw TIError.dimensionMismatch }
        let values = zip(a.values, b.values).map(operation)
        return try TIMatrix(rows: a.rows, columns: a.columns, values: values)
    }

    public static func scale(_ matrix: TIMatrix, by factor: Complex) throws -> TIMatrix {
        try TIMatrix(rows: matrix.rows, columns: matrix.columns, values: matrix.values.map { $0 * factor })
    }

    public static func multiply(_ a: TIMatrix, _ b: TIMatrix) throws -> TIMatrix {
        guard a.columns == b.rows else { throw TIError.dimensionMismatch }
        var product = [Complex](repeating: .zero, count: a.rows * b.columns)
        for row in 0..<a.rows {
            for inner in 0..<a.columns {
                let left = a.values[row * a.columns + inner]
                if left == .zero { continue }
                for column in 0..<b.columns {
                    product[row * b.columns + column] =
                        product[row * b.columns + column] + left * b.values[inner * b.columns + column]
                }
            }
        }
        return try TIMatrix(rows: a.rows, columns: b.columns, values: product)
    }

    /// `[A]^n`. A negative exponent is the inverse raised to `|n|`, as the TI's `[A]⁻¹` is.
    public static func power(_ matrix: TIMatrix, _ exponent: Int) throws -> TIMatrix {
        guard matrix.rows == matrix.columns else { throw TIError.invalidDimension }
        if exponent < 0 {
            return try power(try inverse(matrix), -exponent)
        }
        var result = try identity(size: matrix.rows)
        // Exponents are small (TI matrices are at most 10x10), so repeated multiplication is
        // both clear and bounded by the exponent itself.
        for _ in 0..<exponent {
            result = try multiply(result, matrix)
        }
        return result
    }

    public static func transpose(_ matrix: TIMatrix) throws -> TIMatrix {
        var values = [Complex](repeating: .zero, count: matrix.values.count)
        for row in 0..<matrix.rows {
            for column in 0..<matrix.columns {
                values[column * matrix.rows + row] = matrix.values[row * matrix.columns + column]
            }
        }
        return try TIMatrix(rows: matrix.columns, columns: matrix.rows, values: values)
    }

    public static func identity(size: Int) throws -> TIMatrix {
        guard size >= 1, size <= TILimits.maxMatrixDimension else { throw TIError.invalidDimension }
        var values = [Complex](repeating: .zero, count: size * size)
        for index in 0..<size {
            values[index * size + index] = .one
        }
        return try TIMatrix(rows: size, columns: size, values: values)
    }

    /// `augment(`: two matrices joined side by side.
    public static func augment(_ a: TIMatrix, _ b: TIMatrix) throws -> TIMatrix {
        guard a.rows == b.rows else { throw TIError.dimensionMismatch }
        var joined: [[Complex]] = []
        let left = rows(of: a), right = rows(of: b)
        for index in 0..<a.rows {
            joined.append(left[index] + right[index])
        }
        return try matrix(from: joined)
    }

    // MARK: - Elimination

    /// One Gaussian elimination with partial pivoting, shared by `det`, `ref`, `rref` and
    /// `inverse` so all four agree on what counts as a pivot.
    private struct Elimination {
        var rows: [[Complex]]
        /// The product of the pivots, with the sign of the row interchanges folded in.
        var determinant: Complex
        var rank: Int
        /// Column index of each pivot, in row order.
        var pivotColumns: [Int]
    }

    /// `pivotColumnLimit` bounds the columns a pivot may be *searched* in, while elimination
    /// still runs across the full width. `inverse` needs it: on `[A | I]` the identity half
    /// always offers pivots, so counting them would report a singular `A` as full rank.
    private static func eliminate(
        _ input: [[Complex]],
        normalizePivots: Bool,
        pivotColumnLimit: Int? = nil
    ) -> Elimination {
        var rows = input
        let height = rows.count
        let width = rows.first?.count ?? 0
        let searchWidth = Swift.min(pivotColumnLimit ?? width, width)
        var determinant = Complex.one
        var pivotColumns: [Int] = []
        var pivotRow = 0

        for column in 0..<searchWidth where pivotRow < height {
            // Partial pivoting: the largest magnitude in the column, for numerical stability.
            var best = pivotRow
            for row in (pivotRow + 1)..<height where rows[row][column].magnitude > rows[best][column].magnitude {
                best = row
            }
            guard !isNegligible(rows[best][column]) else {
                determinant = .zero
                continue
            }
            if best != pivotRow {
                rows.swapAt(best, pivotRow)
                determinant = -determinant
            }

            let pivot = rows[pivotRow][column]
            determinant = determinant * pivot

            if normalizePivots {
                for index in 0..<width {
                    rows[pivotRow][index] = (try? rows[pivotRow][index] / pivot) ?? .zero
                }
            }

            // Clear below; and above too when a reduced form was asked for.
            let eliminationRange = normalizePivots ? (0..<height) : ((pivotRow + 1)..<height)
            for row in eliminationRange where row != pivotRow {
                let factor = normalizePivots
                    ? rows[row][column]
                    : ((try? rows[row][column] / pivot) ?? .zero)
                if factor == .zero { continue }
                for index in 0..<width {
                    rows[row][index] = rows[row][index] - factor * rows[pivotRow][index]
                }
            }

            pivotColumns.append(column)
            pivotRow += 1
        }

        return Elimination(rows: rows, determinant: determinant, rank: pivotRow, pivotColumns: pivotColumns)
    }

    /// `det(`. Square only; a singular matrix gives zero rather than an error, as on the TI.
    public static func determinant(_ matrix: TIMatrix) throws -> Complex {
        guard matrix.rows == matrix.columns else { throw TIError.invalidDimension }
        return eliminate(rows(of: matrix), normalizePivots: false).determinant
    }

    /// `[A]⁻¹`. Gauss-Jordan on `[A | I]`; a pivot at or below the singularity tolerance is
    /// `ERR:SINGULAR MAT`.
    public static func inverse(_ matrix: TIMatrix) throws -> TIMatrix {
        guard matrix.rows == matrix.columns else { throw TIError.invalidDimension }
        let size = matrix.rows
        let augmented = try augment(matrix, try identity(size: size))
        let result = eliminate(rows(of: augmented), normalizePivots: true, pivotColumnLimit: size)
        guard result.rank == size else { throw TIError.singularMatrix }
        let inverseRows = result.rows.map { Array($0[size..<(2 * size)]) }
        return try self.matrix(from: inverseRows)
    }

    /// `ref(` — row echelon form with leading ones, pivots not cleared above.
    public static func rowEchelonForm(_ matrix: TIMatrix) throws -> TIMatrix {
        let eliminated = eliminate(rows(of: matrix), normalizePivots: false)
        var rows = eliminated.rows
        // `eliminate` leaves the pivots unnormalized when it is not reducing; `ref` wants
        // leading ones, so scale each pivot row here.
        for (index, column) in eliminated.pivotColumns.enumerated() {
            let pivot = rows[index][column]
            guard !isNegligible(pivot) else { continue }
            for position in 0..<rows[index].count {
                rows[index][position] = (try? rows[index][position] / pivot) ?? .zero
            }
        }
        return try self.matrix(from: rows)
    }

    /// `rref(` — reduced row echelon form.
    public static func reducedRowEchelonForm(_ matrix: TIMatrix) throws -> TIMatrix {
        try self.matrix(from: eliminate(rows(of: matrix), normalizePivots: true).rows)
    }

    // MARK: - Row operations (MATRX MATH)

    /// `rowSwap(matrix, rowA, rowB)` — 1-based rows, as everywhere in TI syntax.
    public static func swappingRows(_ matrix: TIMatrix, _ rowA: Int, _ rowB: Int) throws -> TIMatrix {
        var grid = rows(of: matrix)
        guard let a = swiftRow(rowA, in: matrix), let b = swiftRow(rowB, in: matrix) else {
            throw TIError.invalidDimension
        }
        grid.swapAt(a, b)
        return try self.matrix(from: grid)
    }

    /// `row+(matrix, source, target)` — adds row `source` into row `target`.
    public static func addingRow(_ matrix: TIMatrix, from source: Int, to target: Int) throws -> TIMatrix {
        try transformingRow(matrix, from: source, to: target, factor: .one)
    }

    /// `*row(factor, matrix, row)` — multiplies one row by a scalar.
    public static func scalingRow(_ matrix: TIMatrix, _ row: Int, by factor: Complex) throws -> TIMatrix {
        var grid = rows(of: matrix)
        guard let index = swiftRow(row, in: matrix) else { throw TIError.invalidDimension }
        grid[index] = grid[index].map { $0 * factor }
        return try self.matrix(from: grid)
    }

    /// `*row+(factor, matrix, source, target)` — adds `factor` times `source` into `target`.
    public static func transformingRow(
        _ matrix: TIMatrix,
        from source: Int,
        to target: Int,
        factor: Complex
    ) throws -> TIMatrix {
        var grid = rows(of: matrix)
        guard let from = swiftRow(source, in: matrix), let into = swiftRow(target, in: matrix) else {
            throw TIError.invalidDimension
        }
        for column in 0..<matrix.columns {
            grid[into][column] = grid[into][column] + factor * grid[from][column]
        }
        return try self.matrix(from: grid)
    }

    /// The one place a TI row number becomes a Swift row index for these operations.
    private static func swiftRow(_ tiRow: Int, in matrix: TIMatrix) -> Int? {
        guard tiRow >= 1, tiRow <= matrix.rows else { return nil }
        return tiRow - 1
    }
}
