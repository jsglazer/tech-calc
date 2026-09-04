import Testing
@testable import TechCalcCore

/// The `LIST OPS` and `LIST MATH` menus.
///
/// Every expected value here is a closed-form arithmetic result computed by hand from the inputs
/// on the same line — none was produced by running tech-calc.
@Suite("List operations")
struct ListOperationTests {

    // MARK: - LIST MATH

    @Test("sum( and prod( reduce a whole list, or a 1-based sub-range")
    func sumAndProduct() throws {
        #expect(try Fixture.real("sum({1,2,3,4})") == 10)
        #expect(try Fixture.real("prod({1,2,3,4})") == 24)
        // Elements 2 through 3 are 2 and 3.
        #expect(try Fixture.real("sum({1,2,3,4},2,3)") == 5)
        #expect(try Fixture.real("prod({1,2,3,4},2,3)") == 6)
        // A start on its own runs to the end of the list.
        #expect(try Fixture.real("sum({1,2,3,4},3)") == 7)
        expectTIError("sum({1,2,3},0,2)", .invalidDimension)
        expectTIError("sum({1,2,3},2,9)", .invalidDimension)
    }

    @Test("mean(, median(, stdDev( and variance( match their definitions")
    func centreAndSpread() throws {
        #expect(try Fixture.real("mean({1,2,3,4})") == 2.5)
        // Even count: the mean of the two middle values.
        #expect(try Fixture.real("median({1,2,3,4})") == 2.5)
        #expect(try Fixture.real("median({3,1,2})") == 2)
        // Sample variance of 1,2,3,4: sum of squared error 5, divided by n-1 = 3.
        expectClose(try Fixture.real("variance({1,2,3,4})"), 5.0 / 3.0)
        expectClose(try Fixture.real("stdDev({1,2,3,4})"), (5.0 / 3.0).squareRoot())
        // The spread statistics need at least two values.
        expectTIError("variance({1})", .invalidDimension)
    }

    @Test("min( and max( reduce one list and pair two")
    func extrema() throws {
        #expect(try Fixture.real("min({3,1,2})") == 1)
        #expect(try Fixture.real("max({3,1,2})") == 3)
        #expect(try Fixture.list("min({1,5},{4,2})") == [Complex(1), Complex(2)])
        #expect(try Fixture.list("max({1,5},{4,2})") == [Complex(4), Complex(5)])
        // A scalar is repeated against the list, as on the TI.
        #expect(try Fixture.list("min({1,5},3)") == [Complex(1), Complex(3)])
        // Two scalars keep the ordinary MATH NUM behaviour.
        #expect(try Fixture.real("min(4,7)") == 4)
        expectTIError("min({1,2},{1,2,3})", .dimensionMismatch)
    }

    // MARK: - LIST OPS

    @Test("cumSum( accumulates and ΔList( differences")
    func cumulativeSumAndDifferences() throws {
        #expect(try Fixture.list("cumSum({1,2,3})") == [Complex(1), Complex(3), Complex(6)])
        #expect(try Fixture.list("ΔList({1,4,9})") == [Complex(3), Complex(5)])
        // ΔList is one element shorter, so a single element has no differences.
        expectTIError("ΔList({1})", .invalidDimension)
    }

    @Test("seq( evaluates its expression over a bounded index")
    func sequence() throws {
        #expect(try Fixture.list("seq(X²,X,1,4)") == [1, 4, 9, 16].map { Complex(Double($0)) })
        #expect(try Fixture.list("seq(X,X,1,10,3)") == [1, 4, 7, 10].map { Complex(Double($0)) })
        #expect(try Fixture.list("seq(2X,X,1,1)") == [Complex(2)])
        // seq( leaves the caller's own X untouched.
        var calculator = Fixture.calculator()
        calculator.enter("5→X")
        calculator.enter("seq(X,X,1,3)")
        #expect(try calculator.evaluate("X").result == .real(5))
        // A zero step would never terminate; it is rejected rather than capped.
        expectTIError("seq(X,X,1,4,0)", .domain)
    }

    @Test("seq( refuses to build a list past the TI's length cap")
    func sequenceLengthCap() {
        expectTIError("seq(X,X,1,\(TILimits.maxListLength + 1))", .invalidDimension)
    }

    @Test("augment( joins two lists end to end")
    func augment() throws {
        #expect(try Fixture.list("augment({1,2},{3,4})") == [1, 2, 3, 4].map { Complex(Double($0)) })
        #expect(try Fixture.list("augment({1,2},{})") == [Complex(1), Complex(2)])
    }

    @Test("SortA( and SortD( write back into the named list")
    func sorting() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{3,1,2}→L1")
        #expect(calculator.enter("SortA(L1)").display == "Done")
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [1, 2, 3])))
        calculator.enter("SortD(L1)")
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [3, 2, 1])))
        // Sorting needs a named list, not a literal: there would be nowhere to write the result.
        expectTIError("SortA({3,1,2})", .dataType)
    }

    @Test("Fill( overwrites every element of a named container, keeping its size")
    func fill() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3}→L1")
        #expect(calculator.enter("Fill(7,L1)").display == "Done")
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [7, 7, 7])))

        calculator.enter("[[1,2][3,4]]→[A]")
        calculator.enter("Fill(0,[A])")
        #expect(try calculator.evaluate("[A]").result
                == .matrix(try TIMatrix(rows: 2, columns: 2)))
    }

    @Test("List▸matr fills the matrix's columns; Matr▸list reads them back")
    func listMatrixConversions() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2}→L1")
        calculator.enter("{3,4}→L2")
        #expect(calculator.enter("List▸matr(L1,L2,[A])").display == "Done")
        // Each list is a column, so L1 is the first column and L2 the second.
        #expect(try calculator.evaluate("[A]").result
                == .matrix(try TIMatrix(rows: 2, columns: 2, values: [1, 3, 2, 4].map { Complex(Double($0)) })))

        calculator.enter("Matr▸list([A],L3,L4)")
        #expect(try calculator.evaluate("L3").result == .list(TIList(reals: [1, 2])))
        #expect(try calculator.evaluate("L4").result == .list(TIList(reals: [3, 4])))
        // More target lists than the matrix has columns is a dimension mismatch.
        expectTIError("Matr▸list([[1][2]],L1,L2)", .dimensionMismatch)
    }

    @Test("Sorting and the spread statistics reject complex elements, as on the TI")
    func realOnlyOperations() {
        let mode = CalculatorMode(complex: .rectangular)
        expectTIError("median({1,i})", .dataType, mode: mode)
        expectTIError("stdDev({1,i,2})", .dataType, mode: mode)
        expectTIError("min({1,i})", .dataType, mode: mode)
    }
}
