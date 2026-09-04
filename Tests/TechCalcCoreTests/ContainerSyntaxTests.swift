import Testing
@testable import TechCalcCore

/// Container syntax: literals, stored names, 1-based element access, and every `STO▸` target.
///
/// The indexing assertions here are the syntax-layer half of the 1-based rule; `IndexingTests`
/// covers the accessors themselves.
@Suite("Container syntax")
struct ContainerSyntaxTests {

    // MARK: - Literals

    @Test("A list literal evaluates to a list, and an empty one is legal")
    func listLiteral() throws {
        #expect(try Fixture.list("{1,2,3}") == [Complex(1), Complex(2), Complex(3)])
        #expect(try Fixture.list("{2+3,4*5}") == [Complex(5), Complex(20)])
        #expect(try Fixture.list("{}") == [])
    }

    @Test("A matrix literal reads row by row, with or without commas between rows")
    func matrixLiteral() throws {
        #expect(try Fixture.matrixRows("[[1,2][3,4]]") == [[1, 2], [3, 4]])
        #expect(try Fixture.matrixRows("[[1,2],[3,4]]") == [[1, 2], [3, 4]])
        #expect(try Fixture.matrixRows("[[1,2,3]]") == [[1, 2, 3]])
    }

    @Test("A ragged matrix literal is ERR:INVALID DIM")
    func raggedMatrixLiteral() {
        expectTIError("[[1,2][3]]", .invalidDimension)
    }

    @Test("An unclosed literal auto-closes, as pressing ENTER does with parentheses")
    func autoClosingLiterals() throws {
        let list = try Parser.parse("{1,2,3")
        #expect(list.autoClosedParentheses)
        #expect(try Fixture.list("{1,2,3") == [Complex(1), Complex(2), Complex(3)])

        let matrix = try Parser.parse("[[1,2][3,4]")
        #expect(matrix.autoClosedParentheses)
        #expect(try Fixture.matrixRows("[[1,2][3,4]") == [[1, 2], [3, 4]])
    }

    // MARK: - Names

    @Test("L1-L6 and ∟NAME tokenize as list names, not as the variable L times a digit")
    func listNamesTokenize() throws {
        #expect(try Tokenizer().tokenize("L1") == [.listName(Fixture.listName(1))])
        #expect(try Tokenizer().tokenize("L₆") == [.listName(Fixture.listName(6))])
        #expect(try Tokenizer().tokenize("∟HEIGH") == [.listName(Fixture.namedList("HEIGH"))])
        // L7 is not one of the six numbered lists, so it falls back to `L * 7`.
        #expect(try Tokenizer().tokenize("L7") == [.variable("L"), .number(7)])
    }

    @Test("[A]-[J] tokenize as matrix names; [[ starts a literal")
    func matrixNamesTokenize() throws {
        #expect(try Tokenizer().tokenize("[A]") == [.matrixName(Fixture.matrixName("A"))])
        #expect(try Tokenizer().tokenize("[J]") == [.matrixName(Fixture.matrixName("J"))])
        #expect(try Tokenizer().tokenize("[[1]]").first == .leftBracket)
        // [K] is past the ten TI matrices, so it lexes as ordinary brackets.
        #expect(try Tokenizer().tokenize("[K]") == [.leftBracket, .variable("K"), .rightBracket])
    }

    @Test("An unset list reads as empty; an unset matrix is ERR:UNDEFINED")
    func unsetContainers() throws {
        #expect(try Fixture.list("L3") == [])
        expectTIError("det([B])", .undefined)
    }

    // MARK: - Element access

    @Test("Elements are addressed from 1, and a parenthesis after a container indexes it")
    func elementAccessIsOneBased() throws {
        #expect(try Fixture.real("{10,20,30}(1)") == 10)
        #expect(try Fixture.real("{10,20,30}(3)") == 30)
        #expect(try Fixture.real("[[1,2][3,4]](2,1)") == 3)

        expectTIError("{10,20,30}(0)", .invalidDimension)
        expectTIError("{10,20,30}(4)", .invalidDimension)
        expectTIError("[[1,2][3,4]](3,1)", .invalidDimension)
        // One subscript on a matrix, or two on a list, is a dimension error.
        expectTIError("[[1,2][3,4]](1)", .invalidDimension)
        expectTIError("{1,2,3}(1,1)", .invalidDimension)
    }

    @Test("Indexing parses as element access, never as implicit multiplication")
    func indexingBeatsJuxtaposition() throws {
        let parsed = try Parser.parse("L1(2)")
        #expect(parsed.expression == .element(.listVariable(Fixture.listName(1)), [.number(2)]))
        // A number followed by a parenthesis is still a product.
        #expect(try Fixture.real("2(3)") == 6)
    }

    // MARK: - Stores

    @Test("A whole list or matrix stores into a name and reads back")
    func storeWholeContainer() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3}→L1")
        calculator.enter("[[1,2][3,4]]→[A]")
        #expect(calculator.lists[Fixture.listName(1)] == TIList(reals: [1, 2, 3]))
        #expect(try calculator.evaluate("L1(2)").result == .real(2))
        #expect(try calculator.evaluate("det([A])").result == .real(-2))
    }

    @Test("Storing into one element writes through, and one past the end appends")
    func storeElement() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3}→L1")
        calculator.enter("99→L1(2)")
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [1, 99, 3])))

        calculator.enter("7→L1(4)")
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [1, 99, 3, 7])))
        // Two past the end is still out of range.
        #expect(throws: TIError.invalidDimension) { try calculator.evaluate("8→L1(6)") }

        calculator.enter("[[1,2][3,4]]→[A]")
        calculator.enter("42→[A](1,2)")
        #expect(try calculator.evaluate("[A](1,2)").result == .real(42))
        #expect(throws: TIError.invalidDimension) { try calculator.evaluate("1→[A](3,1)") }
    }

    @Test("dim( reads a size, and storing into dim( resizes or reshapes")
    func dimensionStores() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3}→L1")
        #expect(try calculator.evaluate("dim(L1)").result == .real(3))
        #expect(try calculator.evaluate("dim([[1,2,3][4,5,6]])").result == .list(TIList(reals: [2, 3])))

        calculator.enter("5→dim(L1)")
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [1, 2, 3, 0, 0])))
        calculator.enter("2→dim(L1)")
        #expect(try calculator.evaluate("L1").result == .list(TIList(reals: [1, 2])))

        calculator.enter("[[1,2][3,4]]→[A]")
        calculator.enter("{2,3}→dim([A])")
        #expect(try calculator.evaluate("[A]").result
                == .matrix(try TIMatrix(rows: 2, columns: 3, values: [1, 2, 0, 3, 4, 0].map { Complex(Double($0)) })))
    }

    @Test("A named list stores and reads back under its own name")
    func namedListStore() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{70.5,68}→∟HEIGH")
        #expect(calculator.lists[Fixture.namedList("HEIGH")] == TIList(reals: [70.5, 68]))
        #expect(try calculator.evaluate("∟HEIGH(1)").result == .real(70.5))
    }

    @Test("Storing the wrong shape into a container is ERR:DATA TYPE")
    func storeTypeMismatch() {
        expectTIError("5→L1", .dataType)
        expectTIError("{1,2}→[A]", .dataType)
    }
}
