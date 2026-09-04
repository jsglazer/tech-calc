import Testing
@testable import TechCalcCore

/// Parser precedence and syntax.
///
/// The first four tests are the mandatory fixtures named in the pre-build decisions: implicit
/// multiplication at `*` precedence, negation looser than `^`, right-associative `^`, and
/// adjacent calls as a product.
@Suite("Parser precedence")
struct ParserPrecedenceTests {

    @Test("Implicit multiplication binds as * does, left to right: 1/2X is (1/2)*X")
    func implicitMultiplicationBindsAsMultiply() throws {
        let parsed = try Parser.parse("1/2X")
        #expect(parsed.expression == .binary(
            .multiply,
            .binary(.divide, .number(1), .number(2)),
            .variable("X")
        ))

        var calculator = Fixture.calculator()
        calculator.enter("4→X")
        expectClose(try calculator.evaluate("1/2X").result.asReal, 2)
    }

    @Test("Negation binds looser than exponentiation: -3^2 is -9, (-3)^2 is 9")
    func negationBindsLooserThanPower() throws {
        #expect(try Parser.parse("-3^2").expression == .negation(
            .binary(.power, .number(3), .number(2))
        ))
        expectClose(try Fixture.real("-3^2"), -9)
        expectClose(try Fixture.real("(-3)^2"), 9)
        expectClose(try Fixture.real("⁻3^2"), -9)
    }

    @Test("Exponentiation is right-associative: 2^3^2 is 512")
    func powerIsRightAssociative() throws {
        #expect(try Parser.parse("2^3^2").expression == .binary(
            .power,
            .number(2),
            .binary(.power, .number(3), .number(2))
        ))
        expectClose(try Fixture.real("2^3^2"), 512)
    }

    @Test("Adjacent function calls are a product: sin(2)cos(2)")
    func adjacentCallsAreAProduct() throws {
        #expect(try Parser.parse("sin(2)cos(2)").expression == .binary(
            .multiply,
            .call(.sin, [.number(2)]),
            .call(.cos, [.number(2)])
        ))
        expectClose(try Fixture.real("sin(2)cos(2)"), -0.3784012476539641)
    }

    @Test("Negation and subtraction are distinct entries that agree in prefix position")
    func negationVersusSubtraction() throws {
        // The (-) key emits ⁻; the typed hyphen lexes as subtraction and reads as negation in
        // prefix position.
        #expect(try Tokenizer().tokenize("⁻5") == [.negation, .number(5)])
        #expect(try Tokenizer().tokenize("-5") == [.binaryOperator(.subtract), .number(5)])
        expectClose(try Fixture.real("⁻5"), -5)
        expectClose(try Fixture.real("8-5"), 3)
        expectClose(try Fixture.real("8-⁻5"), 13)
        // Negation in infix position is a syntax error, as on the TI.
        expectTIError("8⁻5", .syntax)
    }

    @Test("Multiplication and division group left to right")
    func multiplicativeIsLeftAssociative() throws {
        #expect(try Parser.parse("8/2/2").expression == .binary(
            .divide,
            .binary(.divide, .number(8), .number(2)),
            .number(2)
        ))
        expectClose(try Fixture.real("8/2/2"), 2)
    }

    @Test("Precedence runs postfix > ^ > negation > nPr > * / > + - > relational > and > or")
    func fullPrecedenceLadder() throws {
        expectClose(try Fixture.real("2+3*4"), 14)
        expectClose(try Fixture.real("2*3^2"), 18)
        expectClose(try Fixture.real("3!+1"), 7)          // postfix beats +
        expectClose(try Fixture.real("2^2!"), 4)          // postfix beats ^
        expectClose(try Fixture.real("5 nPr 2+1"), 21)    // nPr beats +
        expectClose(try Fixture.real("2*3 nPr 2"), 12)    // nPr beats *
        expectClose(try Fixture.real("1+1=2"), 1)         // + beats relational
        expectClose(try Fixture.real("1=1 and 2=2"), 1)   // relational beats and
        expectClose(try Fixture.real("0 and 0 or 1"), 1)  // and beats or
    }

    @Test("Unclosed parentheses are auto-closed at the end of the line")
    func parenthesesAutoClose() throws {
        let parsed = try Parser.parse("sin(2")
        #expect(parsed.autoClosedParentheses)
        #expect(parsed.expression == .call(.sin, [.number(2)]))

        let nested = try Parser.parse("((1+2")
        #expect(nested.autoClosedParentheses)
        #expect(nested.expression == .binary(.add, .number(1), .number(2)))

        // A line that closes its own parentheses is not marked as auto-closed.
        #expect(try Parser.parse("sin(2)").autoClosedParentheses == false)
    }

    @Test("Implicit multiplication spans numbers, variables, constants and groups")
    func implicitMultiplicationForms() throws {
        expectClose(try Fixture.real("2(3)"), 6)
        expectClose(try Fixture.real("(2)(3)"), 6)
        expectClose(try Fixture.real("2π"), 6.283185307179586)
        var calculator = Fixture.calculator()
        calculator.enter("3→A")
        calculator.enter("4→B")
        expectClose(try calculator.evaluate("AB").result.asReal, 12)
        expectClose(try calculator.evaluate("2A").result.asReal, 6)
    }

    @Test("STO▸ writes a variable and returns the stored value")
    func storeParsesAndAssigns() throws {
        #expect(try Parser.parse("5→A").expression == .store(.number(5), .variable("A")))
        var calculator = Fixture.calculator()
        expectClose(try calculator.evaluate("5→A").result.asReal, 5)
        expectClose(try calculator.evaluate("A²").result.asReal, 25)
    }

    @Test("Ans carries the previous result")
    func ansCarriesPreviousResult() throws {
        var calculator = Fixture.calculator()
        calculator.enter("2+3")
        expectClose(try calculator.evaluate("Ans*4").result.asReal, 20)
    }

    @Test("Malformed input is ERR:SYNTAX")
    func malformedInputIsSyntaxError() {
        expectTIError("2+", .syntax)
        expectTIError("*2", .syntax)
        expectTIError("sin(1,2)", .syntax)   // arity comes from the catalog
        expectTIError("2))", .syntax)
        expectTIError("5→2", .syntax)
    }

    @Test("Scientific-notation literals lex as one number, and 2e is 2*e")
    func scientificNotationLiterals() throws {
        #expect(try Tokenizer().tokenize("1E99") == [.number(1e99)])
        #expect(try Tokenizer().tokenize("1E-4") == [.number(1e-4)])
        #expect(try Tokenizer().tokenize("2e") == [.number(2), .constant(.eulersNumber)])
        expectClose(try Fixture.real("2e"), 5.43656365691809)
    }
}
