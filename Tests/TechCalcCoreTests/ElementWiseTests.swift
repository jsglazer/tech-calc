import Testing
@testable import TechCalcCore

/// Scalar functions and operators applied across a list.
///
/// Which functions map and which consume a whole container is declared once, in the catalog's
/// `mapsOverLists` flag; this suite checks both sides of that flag behave as declared.
@Suite("Element-wise lists")
struct ElementWiseTests {

    @Test("Arithmetic between two lists pairs them element by element")
    func listWithList() throws {
        #expect(try Fixture.list("{1,2,3}+{10,20,30}") == [11, 22, 33].map { Complex(Double($0)) })
        #expect(try Fixture.list("{10,20}-{1,2}") == [Complex(9), Complex(18)])
        #expect(try Fixture.list("{2,3}*{4,5}") == [Complex(8), Complex(15)])
        #expect(try Fixture.list("{8,9}/{2,3}") == [Complex(4), Complex(3)])
        #expect(try Fixture.list("{2,3}^{3,2}") == [Complex(8), Complex(9)])
        expectTIError("{1,2}+{1,2,3}", .dimensionMismatch)
    }

    @Test("A scalar is repeated across the list, on either side")
    func listWithScalar() throws {
        #expect(try Fixture.list("{1,2,3}+1") == [Complex(2), Complex(3), Complex(4)])
        #expect(try Fixture.list("1+{1,2,3}") == [Complex(2), Complex(3), Complex(4)])
        #expect(try Fixture.list("2*{1,2}") == [Complex(2), Complex(4)])
        #expect(try Fixture.list("10-{1,2}") == [Complex(9), Complex(8)])
        #expect(try Fixture.list("-{1,2}") == [Complex(-1), Complex(-2)])
    }

    @Test("Dividing a list by zero is still ERR:DIVIDE BY 0")
    func listDivideByZero() {
        expectTIError("{1,2}/0", .divideByZero)
        expectTIError("{1,2}/{1,0}", .divideByZero)
    }

    @Test("Relational operators compare a list element by element")
    func listComparison() throws {
        #expect(try Fixture.list("{1,5,3}>2") == [Complex(0), Complex(1), Complex(1)])
        #expect(try Fixture.list("{1,2}≤{2,1}") == [Complex(1), Complex(0)])
    }

    @Test("A one-argument function maps over a list")
    func unaryFunctionsMap() throws {
        #expect(try Fixture.list("√({1,4,9})") == [Complex(1), Complex(2), Complex(3)])
        #expect(try Fixture.list("{1,2,3}²") == [Complex(1), Complex(4), Complex(9)])
        #expect(try Fixture.list("abs({-1,2,-3})") == [Complex(1), Complex(2), Complex(3)])
        #expect(try Fixture.list("int({1.7,-1.2})") == [Complex(1), Complex(-2)])
        #expect(try Fixture.list("{1,2,4}⁻¹") == [Complex(1), Complex(0.5), Complex(0.25)])

        // sin over a list, in degrees, so the values are exact.
        let sines = try Fixture.list("sin({0,90,180})", mode: CalculatorMode(angle: .degrees))
        expectClose(sines[0].re, 0)
        expectClose(sines[1].re, 1)
        expectClose(sines[2].re, 0, tolerance: 1e-12)
    }

    @Test("A two-argument function pairs two lists and repeats a scalar")
    func binaryFunctionsMap() throws {
        #expect(try Fixture.list("gcd({4,8},{6,12})") == [Complex(2), Complex(4)])
        #expect(try Fixture.list("round({1.234,5.678},1)") == [Complex(1.2), Complex(5.7)])
        #expect(try Fixture.list("logBASE({8,27},{2,3})") == [Complex(3), Complex(3)])
        expectTIError("gcd({4,8},{6,12,18})", .dimensionMismatch)
    }

    @Test("The catalog decides what maps: the container functions consume a whole list")
    func catalogGovernsMapping() throws {
        // `sum(` is declared not to map, so it reduces rather than producing a list of sums.
        #expect(FunctionCatalog.definition(for: .listSum)?.mapsOverLists == false)
        #expect(try Fixture.real("sum({1,2,3})") == 6)
        // `√` is declared to map.
        #expect(FunctionCatalog.definition(for: .squareRoot)?.mapsOverLists == true)
        // Every list and matrix menu entry is declared non-mapping, so none of them can be
        // silently broadcast over its own argument.
        let containerMenus = ["2ND LIST OPS", "2ND LIST MATH", "MATRX MATH"]
        let containerEntries = FunctionCatalog.all.filter { containerMenus.contains($0.menuPath) }
        #expect(!containerEntries.isEmpty)
        for definition in containerEntries {
            #expect(!definition.mapsOverLists, "\(definition.name) would broadcast")
        }
    }

    @Test("A matrix does not broadcast a scalar function, as on the TI")
    func matricesDoNotBroadcast() {
        expectTIError("sin([[1,2][3,4]])", .dataType)
        expectTIError("ln([[1,2][3,4]])", .dataType)
    }

    @Test("A list stored, then used in arithmetic, keeps its values")
    func storedListArithmetic() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3}→L1")
        calculator.enter("{10,20,30}→L2")
        #expect(try calculator.evaluate("L1+L2").result == .list(TIList(reals: [11, 22, 33])))
        #expect(try calculator.evaluate("sum(L1*L2)").result == .real(10 + 40 + 90))
        // The stored lists are unchanged by the arithmetic.
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [1, 2, 3])))
    }
}
