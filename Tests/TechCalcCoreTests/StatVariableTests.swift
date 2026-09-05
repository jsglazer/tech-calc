import Testing
@testable import TechCalcCore

/// The `VARS ▸ Statistics` variables: how they tokenize, and what reading one means before any
/// command has written it.
@Suite("Statistics variables")
struct StatVariableTests {

    @Test("Every variable has a distinct spelling, and every spelling resolves back")
    func spellingsAreUnique() {
        var seen: Set<String> = []
        for variable in StatVariable.allCases {
            #expect(!variable.name.isEmpty, "\(variable) has no name")
            #expect(seen.insert(variable.name).inserted, "duplicate spelling \(variable.name)")
            #expect(StatVariable.variable(named: variable.name) == variable)
        }
        #expect(StatVariable.spellingIndex.count == StatVariable.allCases.count)
    }

    @Test("The spelling index is ordered longest first, so the longest match wins")
    func indexIsLongestFirst() {
        let lengths = StatVariable.spellingIndex.map(\.spelling.count)
        #expect(lengths == lengths.sorted(by: >))
    }

    @Test("Longest match resolves a variable against a function of overlapping spelling")
    func longestMatchAcrossBothTables() throws {
        // `minX` is the statistics variable, not `min(` followed by X.
        #expect(try Tokenizer().tokenize("minX") == [.statVariable(.minimumX)])
        #expect(try Tokenizer().tokenize("min(1,2)").first == .function(.minimum))
        // `t` is the statistic, but `tan(` is still the function.
        #expect(try Tokenizer().tokenize("t") == [.statVariable(.tStatistic)])
        #expect(try Tokenizer().tokenize("tan(2)").first == .function(.tan))
        // Longer statistics names win over their own prefixes.
        #expect(try Tokenizer().tokenize("Sx1") == [.statVariable(.sampleDeviation1)])
        #expect(try Tokenizer().tokenize("Sx") == [.statVariable(.sampleDeviationX)])
        #expect(try Tokenizer().tokenize("Σx²") == [.statVariable(.sumSquaredX)])
        #expect(try Tokenizer().tokenize("Σx") == [.statVariable(.sumX)])
        // And the catalog still owns the spellings it declares.
        #expect(try Tokenizer().tokenize("e") == [.constant(.eulersNumber)])
    }

    @Test("A command name beginning with a digit is a name, not a number")
    func digitLeadingCommandNames() throws {
        #expect(try Tokenizer().tokenize("2-SampTTest(").first == .function(.twoSampleTTest))
        #expect(try Tokenizer().tokenize("1-Var Stats(").first == .function(.oneVarStats))
        // Ordinary arithmetic beginning with the same digits is unaffected.
        #expect(try Tokenizer().tokenize("2-3") == [.number(2), .binaryOperator(.subtract), .number(3)])
        expectClose(try Fixture.real("2-3"), -1)
        expectClose(try Fixture.real("2-1"), 1)
    }

    @Test("Reading a variable no command has written is ERR:UNDEFINED")
    func unwrittenVariablesAreUndefined() {
        expectTIError("x̄", .undefined)
        expectTIError("r", .undefined)
        #expect(StatisticsVariables().isEmpty)
    }

    @Test("A statistics variable is an ordinary operand once it has a value")
    func variablesTakePartInArithmetic() throws {
        var calculator = Fixture.calculator()
        calculator.enter("{2,4,6,8}→L1")
        calculator.enter("1-Var Stats(L1)")
        // `2x̄` is implicit multiplication, exactly as `2X` would be.
        expectClose(try calculator.evaluate("2x̄").result.asReal, 10)
        expectClose(try calculator.evaluate("Σx+n").result.asReal, 24)
    }

    @Test("A statistics variable is distinct from the user variable of the same letter")
    func userVariablesAreUntouched() throws {
        var calculator = Fixture.calculator()
        calculator.enter("7→S")
        calculator.enter("{2,4,6,8}→L1")
        calculator.enter("1-Var Stats(L1)")
        // `S` is still the user's variable; `Sx` is the sample deviation.
        expectClose(try calculator.evaluate("S").result.asReal, 7)
        #expect(try calculator.evaluate("Sx").result.asReal > 0)
    }
}
