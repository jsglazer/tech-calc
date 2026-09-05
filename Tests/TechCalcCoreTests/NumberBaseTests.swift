import Testing
@testable import TechCalcCore

/// Number-base entry, base display, and the bitwise operators.
///
/// The TI-84 Plus CE has no BASE menu, so the reference for this suite is the post-M4 developer
/// decision D22 rather than hardware. Its central claim is a negative one — that adding bases
/// changed nothing about expressions that were already valid — so most of what follows asserts
/// what did *not* move.
@Suite("Number bases")
struct NumberBaseTests {

    // MARK: - D22's worked examples, verbatim

    @Test("The decision's worked examples come out as written")
    func workedExamplesFromTheDecision() throws {
        #expect(try Fixture.real("2 and 3") == 1)
        #expect(try Fixture.real("bitAnd(2,3)") == 2)
        #expect(Fixture.display("0b1101▸Dec") == "13")
        #expect(Fixture.display("255▸Hex") == "0hFF")
        #expect(try Fixture.real("bitXor(12,10)") == 6)
    }

    // MARK: - Entry

    @Test("A based literal is a number, not a product")
    func basedLiteralsParseAsNumbers() throws {
        #expect(try Tokenizer().tokenize("0b1101") == [.number(13)])
        #expect(try Tokenizer().tokenize("0hFF") == [.number(255)])
        #expect(try Fixture.real("0hFF+1") == 256)
        #expect(try Fixture.real("0b1101+0b11") == 16)
        // Lower case hex digits are the same digits.
        #expect(try Fixture.real("0hff") == 255)
    }

    @Test("A prefix with no digits after it is still a product, so nothing already valid moved")
    func aBarePrefixIsNotALiteral() throws {
        // The tokenizer is the place this is decided, so assert the tokens rather than a value
        // that zero multiplication would produce either way.
        #expect(try Tokenizer().tokenize("0b") == [.number(0), .statVariable(.coefficientB)])
        #expect(try Tokenizer().tokenize("0h") == [.number(0), .variable("h")])

        // And it still evaluates as the product it always was. `b` is the intercept of a
        // `LinReg(ax+b)` fit, so this scenario gives it the value 1.
        var calculator = Fixture.calculator()
        calculator.enter("{1,2,3}→L1")
        calculator.enter("{3,5,7}→L2")
        calculator.enter("LinRegAXB(L1,L2)")
        expectClose(try calculator.evaluate("b").result.asReal, 1)
        expectClose(try calculator.evaluate("2b").result.asReal, 2)
        #expect(try calculator.evaluate("0b").result.asReal == 0)
    }

    @Test("A full-width hex pattern reads back as its signed value")
    func hexPatternsAreTwosComplement() throws {
        #expect(try Fixture.real("0hFFFFFFFF") == -1)
        #expect(try Fixture.real("0h7FFFFFFF") == 2_147_483_647)
        #expect(try Fixture.real("0h80000000") == -2_147_483_648)
    }

    // MARK: - Display

    @Test("A base conversion replaces the numeral, prefix included")
    func baseConversionsRenderWithTheirPrefix() {
        #expect(Fixture.display("13▸Bin") == "0b1101")
        #expect(Fixture.display("64▸Oct") == "0o100")
        #expect(Fixture.display("255▸Hex") == "0hFF")
        #expect(Fixture.display("0▸Hex") == "0h0")
        // A negative number shows the two's-complement pattern of the declared width.
        #expect(Fixture.display("⁻1▸Hex") == "0hFFFFFFFF")
        #expect(Fixture.display("⁻1▸Bin") == "0b" + String(repeating: "1", count: NumberBases.bitWidth))
    }

    @Test("A conversion applies to the whole entry, as ▸Frac does")
    func baseConversionsBindLoosest() {
        #expect(Fixture.display("200+55▸Hex") == "0hFF")
    }

    @Test("A value with no spelling in the base is ERR:DOMAIN, not a rounded guess")
    func unrepresentableValuesAreRejected() {
        expectTIError("2.5▸Hex", .domain)
        expectTIError("2147483648▸Hex", .domain)
        expectTIError("⁻2147483649▸Bin", .domain)
        expectTIError("{1,2}▸Hex", .dataType)
    }

    @Test("▸Dec is not redeclared: the MATH MATH entry already means base ten")
    func decimalConversionIsTheExistingEntry() throws {
        #expect(FunctionCatalog.definition(named: "▸Dec")?.id == .toDecimal)
        #expect(Fixture.display("0hFF▸Dec") == "255")
        // And it still does what M1 built it for: forcing a decimal answer in fraction mode.
        #expect(Fixture.display("1/2▸Dec", mode: CalculatorMode(answer: .fraction)) == ".5")
    }

    // MARK: - Bitwise operators

    @Test("The bitwise operators act bit by bit, not on truth values")
    func bitwiseOperatorsAreNotBoolean() throws {
        #expect(try Fixture.real("bitAnd(12,10)") == 8)
        #expect(try Fixture.real("bitOr(12,10)") == 14)
        #expect(try Fixture.real("bitXor(12,10)") == 6)
        // Two's-complement inversion is -x - 1.
        #expect(try Fixture.real("bitNot(12)") == -13)
        #expect(try Fixture.real("bitNot(0)") == -1)
        #expect(try Fixture.real("bitNot(bitNot(1234))") == 1234)
    }

    @Test("The boolean operators are exactly what M1 built, untouched")
    func booleanOperatorsAreUnchanged() throws {
        // The whole point of D22's naming: these four answers did not move.
        #expect(try Fixture.real("2 and 3") == 1)
        #expect(try Fixture.real("12 or 0") == 1)
        #expect(try Fixture.real("1 xor 1") == 0)
        #expect(try Fixture.real("not(0)") == 1)
        // And they are still the TEST LOGIC entries, not the new ones.
        #expect(FunctionCatalog.definition(named: "and")?.id == .logicalAnd)
        #expect(FunctionCatalog.definition(named: "bitAnd")?.id == .bitwiseAnd)
    }

    @Test("A bitwise argument outside the declared width is ERR:DOMAIN")
    func bitwiseArgumentsAreValidated() {
        expectTIError("bitAnd(2.5,3)", .domain)
        expectTIError("bitOr(4294967296,1)", .domain)
    }

    @Test("Entry, display and the operators agree on one round trip")
    func entryAndDisplayRoundTrip() throws {
        // 0b1100 AND 0b1010 is 0b1000, written three ways and read back as one number.
        #expect(Fixture.display("bitAnd(0b1100,0b1010)▸Bin") == "0b1000")
        #expect(try Fixture.real("0b1000") == 8)
    }

    @Test("The width and the prefixes are named constants, declared once")
    func baseConstantsAreExplicit() {
        #expect(NumberBases.bitWidth == 32)
        #expect(NumberBases.binaryPrefix == "0b")
        #expect(NumberBases.hexadecimalPrefix == "0h")
        #expect(NumberBases.octalPrefix == "0o")
    }
}
