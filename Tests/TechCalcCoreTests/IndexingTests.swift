import Testing
@testable import TechCalcCore

/// List and matrix index semantics are strictly 1-based at the TI layer, and the conversion to
/// Swift's 0-based indices lives in exactly one accessor per container type.
@Suite("1-based indexing")
struct IndexingTests {

    @Test("List elements are addressed from 1")
    func listIsOneBased() throws {
        var list = TIList(reals: [10, 20, 30])
        #expect(try list[tiIndex: 1] == Complex(10))
        #expect(try list[tiIndex: 3] == Complex(30))
        #expect(throws: TIError.invalidDimension) { try list[tiIndex: 0] }
        #expect(throws: TIError.invalidDimension) { try list[tiIndex: 4] }
        #expect(throws: TIError.invalidDimension) { try list[tiIndex: -1] }

        try list.set(tiIndex: 2, to: Complex(99))
        #expect(try list[tiIndex: 2] == Complex(99))
        #expect(throws: TIError.invalidDimension) { try list.set(tiIndex: 0, to: .zero) }
    }

    @Test("Resizing a list pads with zeros and truncates")
    func listResize() throws {
        var list = TIList(reals: [1, 2, 3])
        try list.resize(to: 5)
        #expect(list.values == [Complex(1), Complex(2), Complex(3), .zero, .zero])
        try list.resize(to: 2)
        #expect(list.values == [Complex(1), Complex(2)])
        #expect(throws: TIError.invalidDimension) { try list.resize(to: TILimits.maxListLength + 1) }
    }

    @Test("Matrix elements are addressed from 1 in both dimensions")
    func matrixIsOneBased() throws {
        var matrix = try TIMatrix(rows: 2, columns: 3, values: (1...6).map { Complex(Double($0)) })
        #expect(try matrix[tiRow: 1, tiColumn: 1] == Complex(1))
        #expect(try matrix[tiRow: 1, tiColumn: 3] == Complex(3))
        #expect(try matrix[tiRow: 2, tiColumn: 1] == Complex(4))
        #expect(try matrix[tiRow: 2, tiColumn: 3] == Complex(6))
        #expect(throws: TIError.invalidDimension) { try matrix[tiRow: 0, tiColumn: 1] }
        #expect(throws: TIError.invalidDimension) { try matrix[tiRow: 1, tiColumn: 0] }
        #expect(throws: TIError.invalidDimension) { try matrix[tiRow: 3, tiColumn: 1] }

        try matrix.set(tiRow: 2, tiColumn: 2, to: Complex(42))
        #expect(try matrix[tiRow: 2, tiColumn: 2] == Complex(42))
    }

    @Test("Degenerate dimensions are rejected")
    func dimensionValidation() {
        #expect(throws: TIError.invalidDimension) { try TIMatrix(rows: 0, columns: 2) }
        #expect(throws: TIError.invalidDimension) { try TIMatrix(rows: 2, columns: 2, values: [.zero]) }
        #expect(throws: TIError.invalidDimension) {
            try TIMatrix(rows: TILimits.maxMatrixDimension + 1, columns: 1)
        }
    }
}
