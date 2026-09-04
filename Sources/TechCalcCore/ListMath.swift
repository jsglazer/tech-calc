import Foundation

/// The pure list reductions and transforms behind the TI `LIST MATH` and `LIST OPS` menus.
///
/// Every entry here is a pure function of its arguments: no stored state, no randomness, no
/// clock. The statistics phase calls these rather than reimplementing them, so `1-Var Stats` and
/// `mean(` can never disagree.
public enum ListMath {

    // MARK: - Sub-ranges

    /// The 1-based `start`/`end` window the TI's `sum(` and `prod(` accept as optional arguments.
    ///
    /// This is the only place a TI element position becomes a Swift slice bound for a list.
    public static func window(_ list: TIList, start: Int?, end: Int?) throws -> [Complex] {
        let first = start ?? 1
        let last = end ?? list.count
        guard first >= 1, last <= list.count, first <= last else { throw TIError.invalidDimension }
        return Array(list.values[(first - 1)...(last - 1)])
    }

    // MARK: - Reductions

    public static func sum(_ values: [Complex]) -> Complex {
        values.reduce(.zero, +)
    }

    public static func product(_ values: [Complex]) -> Complex {
        values.reduce(.one, *)
    }

    public static func mean(_ values: [Complex]) throws -> Complex {
        guard !values.isEmpty else { throw TIError.invalidDimension }
        return try sum(values) / Complex(Double(values.count))
    }

    /// The sample variance, divisor `n - 1`, matching the TI's `variance(`.
    public static func variance(_ values: [Complex]) throws -> Double {
        let reals = try realValues(values)
        guard reals.count >= 2 else { throw TIError.invalidDimension }
        let average = reals.reduce(0, +) / Double(reals.count)
        let squaredError = reals.reduce(0) { $0 + ($1 - average) * ($1 - average) }
        return squaredError / Double(reals.count - 1)
    }

    public static func standardDeviation(_ values: [Complex]) throws -> Double {
        try variance(values).squareRoot()
    }

    public static func median(_ values: [Complex]) throws -> Double {
        let sorted = try realValues(values).sorted()
        guard !sorted.isEmpty else { throw TIError.invalidDimension }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    public static func minimum(_ values: [Complex]) throws -> Double {
        guard let smallest = try realValues(values).min() else { throw TIError.invalidDimension }
        return smallest
    }

    public static func maximum(_ values: [Complex]) throws -> Double {
        guard let largest = try realValues(values).max() else { throw TIError.invalidDimension }
        return largest
    }

    // MARK: - Transforms

    /// `cumSum(` — running totals, same length as the input.
    public static func cumulativeSum(_ list: TIList) -> TIList {
        var running = Complex.zero
        return TIList(list.values.map { value in
            running = running + value
            return running
        })
    }

    /// `ΔList(` — successive differences; one element shorter than the input.
    public static func differences(_ list: TIList) throws -> TIList {
        guard list.count >= 2 else { throw TIError.invalidDimension }
        return TIList((1..<list.count).map { list.values[$0] - list.values[$0 - 1] })
    }

    public static func sorted(_ list: TIList, ascending: Bool) throws -> TIList {
        let reals = try realValues(list.values).sorted()
        return TIList(reals: ascending ? reals : reals.reversed())
    }

    /// `augment(` — one list appended to another.
    public static func augment(_ a: TIList, _ b: TIList) throws -> TIList {
        let joined = a.values + b.values
        guard joined.count <= TILimits.maxListLength else { throw TIError.invalidDimension }
        return TIList(joined)
    }

    // MARK: - Conversions

    /// `List▸matr(` — each list becomes one *column* of the resulting matrix, as on the TI.
    /// Shorter lists are padded with zeros so ragged input still produces a rectangle.
    public static func matrix(fromColumns lists: [TIList]) throws -> TIMatrix {
        guard !lists.isEmpty else { throw TIError.invalidDimension }
        let height = lists.map(\.count).max() ?? 0
        guard height >= 1 else { throw TIError.invalidDimension }
        var values = [Complex](repeating: .zero, count: height * lists.count)
        for (column, list) in lists.enumerated() {
            for (row, value) in list.values.enumerated() {
                values[row * lists.count + column] = value
            }
        }
        return try TIMatrix(rows: height, columns: lists.count, values: values)
    }

    /// `Matr▸list(` — the matrix's columns, each as its own list.
    public static func columns(of matrix: TIMatrix) -> [TIList] {
        (0..<matrix.columns).map { column in
            TIList((0..<matrix.rows).map { row in matrix.values[row * matrix.columns + column] })
        }
    }

    // MARK: - Helpers

    /// Ordering, sorting and the spread statistics are real-only on the TI.
    static func realValues(_ values: [Complex]) throws -> [Double] {
        try values.map { value in
            guard value.isReal else { throw TIError.dataType }
            return value.re
        }
    }
}
