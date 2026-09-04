import Testing
@testable import TechCalcCore

/// The catalog is the single declaration site for a function's name, arity and keypad token.
/// This suite walks the whole table: every entry must tokenize, parse to its declared arity, and
/// evaluate on representative arguments.
@Suite("Function catalog")
struct FunctionCatalogTests {

    /// Representative arguments, keyed by `FunctionID` rather than by name, so this test does not
    /// become a second place where function names are written down.
    private static let representativeArguments: [FunctionID: [String]] = [
        .logBase: ["8", "2"],
        .nthRoot: ["3", "8"],
        .randomInteger: ["1", "6"],
        .gcd: ["24", "36"],
        .lcm: ["4", "6"],
        .remainder: ["17", "5"],
        .permutations: ["5", "2"],
        .combinations: ["5", "2"],
        .acosh: ["2"],
        .numericIntegral: ["X", "X", "0", "1"],
        .numericDerivative: ["X", "X", "2"],
        .summation: ["X", "X", "1", "3"],

        // The list and matrix menus, exercised on literals so the entries need no stored state.
        .minimum: [list],
        .maximum: [list],
        .sortAscending: ["L1"],
        .sortDescending: ["L1"],
        .dimension: [list],
        .fill: ["0", "L1"],
        .sequence: ["X", "X", "1", "3"],
        .cumulativeSum: [list],
        .listDifference: [list],
        .augment: [list, list],
        .listToMatrix: [list, "[A]"],
        .matrixToList: [matrix, "L1"],
        .listSum: [list],
        .listProduct: [list],
        .listMean: [list],
        .listMedian: [list],
        .listStandardDeviation: [list],
        .listVariance: [list],
        .determinant: [matrix],
        .transpose: [matrix],
        .identityMatrix: ["3"],
        .randomMatrix: ["2", "2"],
        .rowEchelon: [matrix],
        .reducedRowEchelon: [matrix],
        .rowSwap: [matrix, "1", "2"],
        .rowAdd: [matrix, "1", "2"],
        .rowScale: ["2", matrix, "1"],
        .rowScaleAdd: ["2", matrix, "1", "2"]
    ]

    private static let list = "{1,2,3}"
    private static let matrix = "[[1,2][3,4]]"


    private static func arguments(for definition: FunctionDefinition) -> [String] {
        if let explicit = representativeArguments[definition.id] { return explicit }
        return Array(repeating: "2", count: definition.arity.lowerBound)
    }

    /// The source text that exercises one catalog entry in its declared form.
    private static func source(for definition: FunctionDefinition) -> String {
        let args = arguments(for: definition)
        switch definition.form {
        case .function:
            return definition.name + "(" + args.joined(separator: ",") + ")"
        case .infix:
            return "\(args[0]) \(definition.name) \(args[1])"
        case .postfix, .displayConversion:
            return "\(args[0])\(definition.name)"
        case .constant:
            return definition.name
        case .macro:
            // A macro inserts ordinary syntax, so it is exercised through its keypad token.
            return definition.keypadToken + args.joined(separator: ",") + ")"
        }
    }

    @Test("Every catalog entry tokenizes, parses to its declared arity, and evaluates")
    func everyEntryRoundTrips() throws {
        // a+bi so that entries with complex results (asin(2), ln of a negative) are values, not errors.
        let mode = CalculatorMode(complex: .rectangular)

        for definition in FunctionCatalog.all {
            let source = Self.source(for: definition)
            let parsed = try Parser.parse(source)

            switch definition.form {
            case .function, .infix, .postfix:
                guard case .call(let id, let arguments) = parsed.expression else {
                    Issue.record("\(definition.name) did not parse to a call: \(parsed.expression)")
                    continue
                }
                #expect(id == definition.id, "\(definition.name) parsed to \(id)")
                #expect(definition.arity.contains(arguments.count), "\(definition.name) arity")
            case .constant:
                #expect(parsed.expression == .constant(definition.id), "\(definition.name)")
            case .displayConversion:
                guard case .displayConversion(let id, _) = parsed.expression else {
                    Issue.record("\(definition.name) did not parse to a display conversion")
                    continue
                }
                #expect(id == definition.id)
            case .macro:
                // Expands to ordinary syntax; correctness is asserted by the evaluation below.
                break
            }

            var calculator = Fixture.calculator(mode: mode)
            let entry = calculator.enter(source)
            #expect(entry.errorName == nil, "\(source) evaluated to \(entry.display)")
        }
    }

    @Test("Every alias of every entry tokenizes to the same definition")
    func aliasesResolveToTheSameEntry() throws {
        for definition in FunctionCatalog.all {
            for spelling in definition.spellings {
                #expect(FunctionCatalog.definition(named: spelling)?.id == definition.id, "\(spelling)")
            }
        }
    }

    @Test("Names and keypad tokens are unique, and every FunctionID has exactly one entry")
    func catalogIsWellFormed() {
        var seenSpellings: Set<String> = []
        for definition in FunctionCatalog.all {
            for spelling in definition.spellings {
                #expect(seenSpellings.insert(spelling).inserted, "duplicate spelling \(spelling)")
            }
            #expect(!definition.keypadToken.isEmpty, "\(definition.name) has no keypad token")
            #expect(definition.arity.lowerBound >= 0)
        }
        // One entry per id, and one id per entry: nothing declared twice, nothing undeclared.
        #expect(Set(FunctionCatalog.all.map(\.id)).count == FunctionCatalog.all.count)
        for id in FunctionID.allCases {
            #expect(FunctionCatalog.definition(for: id) != nil, "\(id.rawValue) is not in the catalog")
        }
    }

    @Test("The longest-match index resolves overlapping names correctly")
    func longestMatchOrdering() throws {
        // sinh before sin, iPart before int, ⁻¹ before the bare negation key.
        #expect(try Tokenizer().tokenize("sinh(2)").first == .function(.sinh))
        #expect(try Tokenizer().tokenize("iPart(2)").first == .function(.integerPart))
        #expect(try Tokenizer().tokenize("2⁻¹") == [.number(2), .postfixFunction(.reciprocal)])
        #expect(try Tokenizer().tokenize("sin⁻¹(.5)").first == .function(.asin))
    }

    @Test("The keypad takes every function label from the catalog")
    func keypadTokensComeFromTheCatalog() {
        let catalogTokens = Set(FunctionCatalog.all.map(\.keypadToken))
        let namedKeys = KeypadLayout.keys.filter { key in
            guard let primary = key.primary else { return false }
            return primary.count > 1 && primary.hasSuffix("(")
        }
        #expect(!namedKeys.isEmpty)
        for key in namedKeys {
            #expect(catalogTokens.contains(key.primary ?? ""), "\(key.id) is not a catalog token")
        }
    }
}
