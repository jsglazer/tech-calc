import Testing
@testable import TechCalcCore

/// The `MATRX MATH` menu and matrix arithmetic.
///
/// Expected values are closed-form: 2x2 determinants and inverses by the adjugate formula,
/// products by hand, and `rref` by its uniqueness. `ref` is deliberately *not* asserted
/// element by element — row echelon form is not unique, so this suite asserts its defining
/// properties instead of one pivoting order's output.
@Suite("Matrix operations")
struct MatrixOperationTests {

    private static let two = "[[1,2][3,4]]"

    // MARK: - Arithmetic

    @Test("Matrix addition and subtraction are element-wise and shape-checked")
    func additionAndSubtraction() throws {
        #expect(try Fixture.matrixRows("[[1,2][3,4]]+[[5,6][7,8]]") == [[6, 8], [10, 12]])
        #expect(try Fixture.matrixRows("[[5,6][7,8]]-[[1,2][3,4]]") == [[4, 4], [4, 4]])
        expectTIError("[[1,2][3,4]]+[[1,2,3][4,5,6]]", .dimensionMismatch)
        // A matrix plus a scalar is a data-type error on the TI, not a broadcast.
        expectTIError("[[1,2][3,4]]+5", .dataType)
        expectTIError("[[1,2][3,4]]+{1,2}", .dataType)
    }

    @Test("Matrix multiplication follows the inner-dimension rule; a scalar scales")
    func multiplication() throws {
        // [1 2; 3 4] * [5 6; 7 8] = [19 22; 43 50]
        #expect(try Fixture.matrixRows("[[1,2][3,4]]*[[5,6][7,8]]") == [[19, 22], [43, 50]])
        // 2x3 times 3x1 is 2x1.
        #expect(try Fixture.matrixRows("[[1,2,3][4,5,6]]*[[1][1][1]]") == [[6], [15]])
        #expect(try Fixture.matrixRows("3*[[1,2][3,4]]") == [[3, 6], [9, 12]])
        #expect(try Fixture.matrixRows("[[1,2][3,4]]*3") == [[3, 6], [9, 12]])
        #expect(try Fixture.matrixRows("[[2,4][6,8]]/2") == [[1, 2], [3, 4]])
        expectTIError("[[1,2][3,4]]*[[1,2,3]]", .dimensionMismatch)
    }

    @Test("A matrix raised to an integer power multiplies it out; ⁻¹ inverts")
    func powers() throws {
        #expect(try Fixture.matrixRows("[[1,2][3,4]]²") == [[7, 10], [15, 22]])
        #expect(try Fixture.matrixRows("[[1,2][3,4]]^2") == [[7, 10], [15, 22]])
        // Any square matrix to the zero power is the identity.
        #expect(try Fixture.matrixRows("[[1,2][3,4]]^0") == [[1, 0], [0, 1]])
        // The adjugate formula: 1/det * [d -b; -c a]. Partial pivoting reorders the
        // elimination, so the result is asserted to the numeric-parity tolerance, not bit-exactly.
        expectMatrix(try Fixture.matrixRows("[[1,2][3,4]]⁻¹"), [[-2, 1], [1.5, -0.5]])
        expectMatrix(try Fixture.matrixRows("[[1,2][3,4]]^-1"), [[-2, 1], [1.5, -0.5]])
        expectTIError("[[1,2,3][4,5,6]]²", .invalidDimension)
    }

    @Test("A matrix times its inverse is the identity")
    func inverseRoundTrip() throws {
        expectMatrix(try Fixture.matrixRows("[[2,1,1][1,3,2][1,0,0]]*[[2,1,1][1,3,2][1,0,0]]⁻¹"),
                     [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
    }

    // MARK: - det, ref, rref

    @Test("det( is the signed volume, and zero for a singular matrix")
    func determinant() throws {
        #expect(try Fixture.real("det([[1,2][3,4]])") == -2)
        // Expanding [2 1 1; 1 3 2; 1 0 0] along its last row gives 1*(1*2 - 1*3) = -1.
        expectClose(try Fixture.real("det([[2,1,1][1,3,2][1,0,0]])"), -1)
        // Row 3 = row 1 + row 2, so the matrix is singular.
        expectClose(try Fixture.real("det([[1,2,3][4,5,6][5,7,9]])"), 0, tolerance: 1e-9)
        expectTIError("det([[1,2,3][4,5,6]])", .invalidDimension)
    }

    @Test("Inverting a singular matrix is ERR:SINGULAR MAT")
    func singularInverse() {
        expectTIError("[[1,2][2,4]]⁻¹", .singularMatrix)
        expectTIError("[[1,2,3][4,5,6][5,7,9]]⁻¹", .singularMatrix)
    }

    @Test("rref( is unique, so it can be asserted element by element")
    func reducedRowEchelonForm() throws {
        // The classic [1 2 3; 4 5 6; 7 8 9] has rank 2 and rref [1 0 -1; 0 1 2; 0 0 0].
        expectMatrix(try Fixture.matrixRows("rref([[1,2,3][4,5,6][7,8,9]])"),
                     [[1, 0, -1], [0, 1, 2], [0, 0, 0]])
        // A non-singular square matrix reduces to the identity.
        #expect(try Fixture.matrixRows("rref([[1,2][3,4]])") == [[1, 0], [0, 1]])
    }

    @Test("ref( leaves leading ones in echelon position and is row-equivalent to the input")
    func rowEchelonForm() throws {
        let echelon = try Fixture.matrixRows("ref([[1,2,3][4,5,6][7,8,9]])")
        var previousPivot = -1
        for row in echelon {
            guard let pivot = row.firstIndex(where: { abs($0) > MatrixMath.singularityTolerance }) else {
                continue
            }
            // Each pivot is a 1, and sits strictly right of the pivot above it.
            expectClose(row[pivot], 1, tolerance: 1e-12)
            #expect(pivot > previousPivot)
            previousPivot = pivot
        }
        // Row equivalence: reducing the echelon form again reproduces the input's rref.
        expectMatrix(try Fixture.matrixRows("rref(ref([[1,2,3][4,5,6][7,8,9]]))"),
                     try Fixture.matrixRows("rref([[1,2,3][4,5,6][7,8,9]])"))
    }

    // MARK: - Shape and construction

    @Test("Transpose swaps the dimensions and reflects the elements")
    func transpose() throws {
        #expect(try Fixture.matrixRows("[[1,2,3][4,5,6]]ᵀ") == [[1, 4], [2, 5], [3, 6]])
        #expect(try Fixture.matrixRows("[[1,2][3,4]]ᵀᵀ") == [[1, 2], [3, 4]])
    }

    @Test("identity( and augment( build matrices")
    func construction() throws {
        #expect(try Fixture.matrixRows("identity(3)") == [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
        #expect(try Fixture.matrixRows("augment([[1,2][3,4]],[[5][6]])") == [[1, 2, 5], [3, 4, 6]])
        expectTIError("identity(0)", .invalidDimension)
        expectTIError("augment([[1,2][3,4]],[[5,6]])", .dimensionMismatch)
    }

    @Test("The row operations are 1-based and leave the other rows alone")
    func rowOperations() throws {
        #expect(try Fixture.matrixRows("rowSwap([[1,2][3,4]],1,2)") == [[3, 4], [1, 2]])
        // row+ adds row 1 into row 2.
        #expect(try Fixture.matrixRows("row+([[1,2][3,4]],1,2)") == [[1, 2], [4, 6]])
        // *row multiplies row 2 by 10.
        #expect(try Fixture.matrixRows("*row(10,[[1,2][3,4]],2)") == [[1, 2], [30, 40]])
        // *row+ adds -3 times row 1 into row 2, clearing the first column.
        #expect(try Fixture.matrixRows("*row+(-3,[[1,2][3,4]],1,2)") == [[1, 2], [0, -2]])
        expectTIError("rowSwap([[1,2][3,4]],1,3)", .invalidDimension)
        expectTIError("*row(2,[[1,2][3,4]],0)", .invalidDimension)
    }

    @Test("randM( draws from the injected generator, so the same seed gives the same matrix")
    func randomMatrixIsSeeded() throws {
        let first = try Fixture.matrixRows("randM(2,3)", seed: 42)
        let second = try Fixture.matrixRows("randM(2,3)", seed: 42)
        #expect(first == second)
        #expect(try Fixture.matrixRows("randM(2,3)", seed: 7) != first)

        #expect(first.count == 2 && first[0].count == 3)
        for value in first.flatMap({ $0 }) {
            #expect(value == value.rounded())
            #expect(abs(value) <= Double(TILimits.randomMatrixMagnitude))
        }
    }

    @Test("The singularity tolerance is one named constant, not a scattered literal")
    func singularityToleranceIsShared() throws {
        #expect(MatrixMath.singularityTolerance > 0)
        // A pivot at the tolerance counts as zero, so this matrix inverts as singular.
        let nearlySingular = try TIMatrix(rows: 2, columns: 2, values: [
            Complex(MatrixMath.singularityTolerance / 2), .zero, .zero, .one
        ])
        #expect(throws: TIError.singularMatrix) { try MatrixMath.inverse(nearlySingular) }
    }
}
