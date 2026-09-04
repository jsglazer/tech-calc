import Foundation

/// Stable identity of a catalog entry. The evaluator dispatches on this, never on a name string,
/// so no function name is spelled anywhere outside `FunctionCatalog.all`.
public enum FunctionID: String, Equatable, Hashable, Sendable, CaseIterable, Codable {
    // Trigonometry
    case sin, cos, tan, asin, acos, atan
    case sinh, cosh, tanh, asinh, acosh, atanh
    // Logarithms and exponentials
    case log, ln, powerOfTen, powerOfE, logBase
    // Roots and powers
    case squareRoot, cubeRoot, nthRoot, square, cube, reciprocal
    // NUM
    case absoluteValue, round, integerPart, fractionalPart, floorInt
    case minimum, maximum, lcm, gcd, remainder
    // PROB
    case permutations, combinations, factorial, random, randomInteger
    // CMPLX
    case conjugate, realPart, imaginaryPart, argument
    // ANGLE
    case degreeUnit, radianUnit, toPolarRadius, toPolarAngle, toRectangularX, toRectangularY
    // MATH — iterative numerics
    case numericIntegral, numericDerivative, summation
    // TEST / LOGIC
    case logicalAnd, logicalOr, logicalXor, logicalNot
    // Constants
    case pi, eulersNumber, imaginaryUnit
    // LIST OPS
    case sortAscending, sortDescending, dimension, fill, sequence
    case cumulativeSum, listDifference, augment, listToMatrix, matrixToList
    // LIST MATH
    case listSum, listProduct, listMean, listMedian, listStandardDeviation, listVariance
    // MATRX MATH
    case determinant, transpose, identityMatrix, randomMatrix
    case rowEchelon, reducedRowEchelon, rowSwap, rowAdd, rowScale, rowScaleAdd
    // Display conversions
    case toFraction, toDecimal, toRectangular, toPolar
}

/// How an entry is written in an expression.
public enum FunctionForm: String, Equatable, Sendable {
    /// `name(arg, ...)` — the ordinary prefix call.
    case function
    /// `a name b` — TI writes `nPr`, `nCr`, `and`, `or`, `xor` between their operands.
    case infix
    /// `a name` — `!`, `squared`, `inverse`, the angle unit marks.
    case postfix
    /// A bare symbol standing for a value.
    case constant
    /// A postfix mark that changes how the answer is *shown*, not what it is.
    case displayConversion
    /// A keypad/menu entry that inserts ordinary syntax rather than a call of its own: the TI's
    /// `10^(` key is the digits `10`, the `^` operator and an open parenthesis, so it needs a
    /// catalog entry for the keypad and the menus but is not a function the tokenizer knows.
    case macro
}

/// One supported function, declared exactly once.
public struct FunctionDefinition: Equatable, Sendable {
    public let id: FunctionID
    /// The canonical spelling, as the TI writes it.
    public let name: String
    /// Additional accepted spellings for typed entry (ASCII stand-ins for TI glyphs).
    public let aliases: [String]
    /// Where the TI keypad menus put it, e.g. `MATH NUM`.
    public let menuPath: String
    public let form: FunctionForm
    /// Accepted argument counts. A range wider than one point means optional arguments.
    public let arity: ClosedRange<Int>
    /// Labels for the form-style UI and for menu help.
    public let argumentLabels: [String]
    /// Exactly what a keypad press inserts into the edit buffer.
    public let keypadToken: String
    /// True when the evaluator must receive the *unevaluated* arguments — `fnInt(`, `nDeriv(`
    /// and `summation(` bind a variable over a sub-expression, and the list/matrix commands that
    /// write into a named container need the container's *name*, not its current value.
    public let takesUnevaluatedArguments: Bool
    /// True when a list argument is mapped element by element (`sin(L1)` is a list of sines).
    /// The list and matrix commands set this false: they consume a whole container.
    public let mapsOverLists: Bool

    public init(
        id: FunctionID,
        name: String,
        aliases: [String] = [],
        menuPath: String,
        form: FunctionForm = .function,
        arity: ClosedRange<Int>,
        argumentLabels: [String] = [],
        keypadToken: String? = nil,
        takesUnevaluatedArguments: Bool = false,
        mapsOverLists: Bool = true
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.menuPath = menuPath
        self.form = form
        self.arity = arity
        self.argumentLabels = argumentLabels
        self.keypadToken = keypadToken ?? (form == .function ? name + "(" : name)
        self.takesUnevaluatedArguments = takesUnevaluatedArguments
        self.mapsOverLists = mapsOverLists
    }

    /// Every spelling that tokenizes to this entry.
    public var spellings: [String] { [name] + aliases }
}

/// The single declaration site for every supported function: its name, its arity, and its keypad
/// token. The tokenizer, the parser, the menus and the keypad all read from this table — a
/// function name is never hard-coded anywhere else in the module.
public enum FunctionCatalog {
    public static let all: [FunctionDefinition] = [
        // MARK: Trigonometry (TRIG keys)
        FunctionDefinition(id: .sin, name: "sin", menuPath: "KEYPAD", arity: 1...1, argumentLabels: ["angle"]),
        FunctionDefinition(id: .cos, name: "cos", menuPath: "KEYPAD", arity: 1...1, argumentLabels: ["angle"]),
        FunctionDefinition(id: .tan, name: "tan", menuPath: "KEYPAD", arity: 1...1, argumentLabels: ["angle"]),
        FunctionDefinition(id: .asin, name: "sin⁻¹", aliases: ["asin", "arcsin"], menuPath: "2ND KEYPAD", arity: 1...1, argumentLabels: ["ratio"]),
        FunctionDefinition(id: .acos, name: "cos⁻¹", aliases: ["acos", "arccos"], menuPath: "2ND KEYPAD", arity: 1...1, argumentLabels: ["ratio"]),
        FunctionDefinition(id: .atan, name: "tan⁻¹", aliases: ["atan", "arctan"], menuPath: "2ND KEYPAD", arity: 1...1, argumentLabels: ["ratio"]),
        FunctionDefinition(id: .sinh, name: "sinh", menuPath: "MATH HYP", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .cosh, name: "cosh", menuPath: "MATH HYP", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .tanh, name: "tanh", menuPath: "MATH HYP", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .asinh, name: "sinh⁻¹", aliases: ["asinh"], menuPath: "MATH HYP", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .acosh, name: "cosh⁻¹", aliases: ["acosh"], menuPath: "MATH HYP", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .atanh, name: "tanh⁻¹", aliases: ["atanh"], menuPath: "MATH HYP", arity: 1...1, argumentLabels: ["value"]),

        // MARK: Logarithms and exponentials
        FunctionDefinition(id: .log, name: "log", menuPath: "KEYPAD", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .ln, name: "ln", menuPath: "KEYPAD", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .powerOfTen, name: "10^", menuPath: "2ND KEYPAD", form: .macro, arity: 1...1, argumentLabels: ["exponent"], keypadToken: "10^("),
        FunctionDefinition(id: .powerOfE, name: "e^", menuPath: "2ND KEYPAD", form: .macro, arity: 1...1, argumentLabels: ["exponent"], keypadToken: "e^("),
        FunctionDefinition(id: .logBase, name: "logBASE", menuPath: "MATH MATH", arity: 2...2, argumentLabels: ["value", "base"]),

        // MARK: Roots and powers
        FunctionDefinition(id: .squareRoot, name: "√", aliases: ["sqrt"], menuPath: "2ND KEYPAD", arity: 1...1, argumentLabels: ["value"], keypadToken: "√("),
        FunctionDefinition(id: .cubeRoot, name: "³√", aliases: ["cbrt"], menuPath: "MATH MATH", arity: 1...1, argumentLabels: ["value"], keypadToken: "³√("),
        FunctionDefinition(id: .nthRoot, name: "ˣ√", aliases: ["xroot"], menuPath: "MATH MATH", arity: 2...2, argumentLabels: ["index", "value"], keypadToken: "ˣ√("),
        FunctionDefinition(id: .square, name: "²", menuPath: "KEYPAD", form: .postfix, arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .cube, name: "³", menuPath: "MATH MATH", form: .postfix, arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .reciprocal, name: "⁻¹", menuPath: "KEYPAD", form: .postfix, arity: 1...1, argumentLabels: ["value"]),

        // MARK: MATH NUM
        FunctionDefinition(id: .absoluteValue, name: "abs", menuPath: "MATH NUM", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .round, name: "round", menuPath: "MATH NUM", arity: 1...2, argumentLabels: ["value", "decimals"]),
        FunctionDefinition(id: .integerPart, name: "iPart", menuPath: "MATH NUM", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .fractionalPart, name: "fPart", menuPath: "MATH NUM", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .floorInt, name: "int", menuPath: "MATH NUM", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .minimum, name: "min", menuPath: "MATH NUM", arity: 1...2, argumentLabels: ["valueA", "valueB"], mapsOverLists: false),
        FunctionDefinition(id: .maximum, name: "max", menuPath: "MATH NUM", arity: 1...2, argumentLabels: ["valueA", "valueB"], mapsOverLists: false),
        FunctionDefinition(id: .lcm, name: "lcm", menuPath: "MATH NUM", arity: 2...2, argumentLabels: ["valueA", "valueB"]),
        FunctionDefinition(id: .gcd, name: "gcd", menuPath: "MATH NUM", arity: 2...2, argumentLabels: ["valueA", "valueB"]),
        FunctionDefinition(id: .remainder, name: "remainder", menuPath: "MATH NUM", arity: 2...2, argumentLabels: ["dividend", "divisor"]),

        // MARK: MATH PROB
        FunctionDefinition(id: .permutations, name: "nPr", menuPath: "MATH PROB", form: .infix, arity: 2...2, argumentLabels: ["n", "r"]),
        FunctionDefinition(id: .combinations, name: "nCr", menuPath: "MATH PROB", form: .infix, arity: 2...2, argumentLabels: ["n", "r"]),
        FunctionDefinition(id: .factorial, name: "!", menuPath: "MATH PROB", form: .postfix, arity: 1...1, argumentLabels: ["n"]),
        FunctionDefinition(id: .random, name: "rand", menuPath: "MATH PROB", form: .constant, arity: 0...0, keypadToken: "rand"),
        FunctionDefinition(id: .randomInteger, name: "randInt", menuPath: "MATH PROB", arity: 2...2, argumentLabels: ["lower", "upper"]),

        // MARK: MATH CMPLX
        FunctionDefinition(id: .conjugate, name: "conj", menuPath: "MATH CMPLX", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .realPart, name: "real", menuPath: "MATH CMPLX", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .imaginaryPart, name: "imag", menuPath: "MATH CMPLX", arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .argument, name: "angle", menuPath: "MATH CMPLX", arity: 1...1, argumentLabels: ["value"]),

        // MARK: ANGLE
        FunctionDefinition(id: .degreeUnit, name: "°", menuPath: "2ND ANGLE", form: .postfix, arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .radianUnit, name: "ʳ", menuPath: "2ND ANGLE", form: .postfix, arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .toPolarRadius, name: "R▸Pr", menuPath: "2ND ANGLE", arity: 2...2, argumentLabels: ["x", "y"]),
        FunctionDefinition(id: .toPolarAngle, name: "R▸Pθ", menuPath: "2ND ANGLE", arity: 2...2, argumentLabels: ["x", "y"]),
        FunctionDefinition(id: .toRectangularX, name: "P▸Rx", menuPath: "2ND ANGLE", arity: 2...2, argumentLabels: ["r", "θ"]),
        FunctionDefinition(id: .toRectangularY, name: "P▸Ry", menuPath: "2ND ANGLE", arity: 2...2, argumentLabels: ["r", "θ"]),

        // MARK: MATH — iterative numerics (all step-limited; see NumericMethods)
        FunctionDefinition(id: .numericIntegral, name: "fnInt", menuPath: "MATH MATH", arity: 4...4,
                           argumentLabels: ["expression", "variable", "lower", "upper"], takesUnevaluatedArguments: true),
        FunctionDefinition(id: .numericDerivative, name: "nDeriv", menuPath: "MATH MATH", arity: 3...4,
                           argumentLabels: ["expression", "variable", "value", "step"], takesUnevaluatedArguments: true),
        FunctionDefinition(id: .summation, name: "Σ", aliases: ["summation"], menuPath: "MATH MATH", arity: 4...4,
                           argumentLabels: ["expression", "variable", "start", "end"], keypadToken: "Σ(", takesUnevaluatedArguments: true),

        // MARK: TEST LOGIC
        FunctionDefinition(id: .logicalAnd, name: "and", menuPath: "2ND TEST LOGIC", form: .infix, arity: 2...2, argumentLabels: ["a", "b"]),
        FunctionDefinition(id: .logicalOr, name: "or", menuPath: "2ND TEST LOGIC", form: .infix, arity: 2...2, argumentLabels: ["a", "b"]),
        FunctionDefinition(id: .logicalXor, name: "xor", menuPath: "2ND TEST LOGIC", form: .infix, arity: 2...2, argumentLabels: ["a", "b"]),
        FunctionDefinition(id: .logicalNot, name: "not", menuPath: "2ND TEST LOGIC", arity: 1...1, argumentLabels: ["a"]),

        // MARK: Constants
        FunctionDefinition(id: .pi, name: "π", aliases: ["pi"], menuPath: "2ND KEYPAD", form: .constant, arity: 0...0),
        FunctionDefinition(id: .eulersNumber, name: "e", menuPath: "2ND KEYPAD", form: .constant, arity: 0...0),
        FunctionDefinition(id: .imaginaryUnit, name: "i", menuPath: "2ND KEYPAD", form: .constant, arity: 0...0),

        // MARK: LIST OPS — the commands that write into a named container take their arguments
        // unevaluated, because they need the container's *name*, not a copy of its value.
        FunctionDefinition(id: .sortAscending, name: "SortA", menuPath: "2ND LIST OPS", arity: 1...1,
                           argumentLabels: ["list"], takesUnevaluatedArguments: true, mapsOverLists: false),
        FunctionDefinition(id: .sortDescending, name: "SortD", menuPath: "2ND LIST OPS", arity: 1...1,
                           argumentLabels: ["list"], takesUnevaluatedArguments: true, mapsOverLists: false),
        FunctionDefinition(id: .dimension, name: "dim", menuPath: "2ND LIST OPS", arity: 1...1,
                           argumentLabels: ["container"], mapsOverLists: false),
        FunctionDefinition(id: .fill, name: "Fill", menuPath: "2ND LIST OPS", arity: 2...2,
                           argumentLabels: ["value", "container"], takesUnevaluatedArguments: true, mapsOverLists: false),
        FunctionDefinition(id: .sequence, name: "seq", menuPath: "2ND LIST OPS", arity: 4...5,
                           argumentLabels: ["expression", "variable", "start", "end", "step"],
                           takesUnevaluatedArguments: true, mapsOverLists: false),
        FunctionDefinition(id: .cumulativeSum, name: "cumSum", menuPath: "2ND LIST OPS", arity: 1...1,
                           argumentLabels: ["list"], mapsOverLists: false),
        FunctionDefinition(id: .listDifference, name: "\u{0394}List", aliases: ["DeltaList"], menuPath: "2ND LIST OPS",
                           arity: 1...1, argumentLabels: ["list"], mapsOverLists: false),
        FunctionDefinition(id: .augment, name: "augment", menuPath: "2ND LIST OPS", arity: 2...2,
                           argumentLabels: ["first", "second"], mapsOverLists: false),
        FunctionDefinition(id: .listToMatrix, name: "List\u{25B8}matr", menuPath: "2ND LIST OPS", arity: 2...11,
                           argumentLabels: ["list", "matrix"], takesUnevaluatedArguments: true, mapsOverLists: false),
        FunctionDefinition(id: .matrixToList, name: "Matr\u{25B8}list", menuPath: "MATRX MATH", arity: 2...11,
                           argumentLabels: ["matrix", "list"], takesUnevaluatedArguments: true, mapsOverLists: false),

        // MARK: LIST MATH — pure reductions. The statistics phase calls these rather than
        // reimplementing them, so `1-Var Stats` and `mean(` cannot disagree.
        FunctionDefinition(id: .listSum, name: "sum", menuPath: "2ND LIST MATH", arity: 1...3,
                           argumentLabels: ["list", "start", "end"], mapsOverLists: false),
        FunctionDefinition(id: .listProduct, name: "prod", menuPath: "2ND LIST MATH", arity: 1...3,
                           argumentLabels: ["list", "start", "end"], mapsOverLists: false),
        FunctionDefinition(id: .listMean, name: "mean", menuPath: "2ND LIST MATH", arity: 1...1,
                           argumentLabels: ["list"], mapsOverLists: false),
        FunctionDefinition(id: .listMedian, name: "median", menuPath: "2ND LIST MATH", arity: 1...1,
                           argumentLabels: ["list"], mapsOverLists: false),
        FunctionDefinition(id: .listStandardDeviation, name: "stdDev", menuPath: "2ND LIST MATH", arity: 1...1,
                           argumentLabels: ["list"], mapsOverLists: false),
        FunctionDefinition(id: .listVariance, name: "variance", menuPath: "2ND LIST MATH", arity: 1...1,
                           argumentLabels: ["list"], mapsOverLists: false),

        // MARK: MATRX MATH — pure Swift throughout; see MatrixMath for the elimination.
        FunctionDefinition(id: .determinant, name: "det", menuPath: "MATRX MATH", arity: 1...1,
                           argumentLabels: ["matrix"], mapsOverLists: false),
        FunctionDefinition(id: .transpose, name: "\u{1D40}", menuPath: "MATRX MATH", form: .postfix, arity: 1...1,
                           argumentLabels: ["matrix"], mapsOverLists: false),
        FunctionDefinition(id: .identityMatrix, name: "identity", menuPath: "MATRX MATH", arity: 1...1,
                           argumentLabels: ["size"], mapsOverLists: false),
        FunctionDefinition(id: .randomMatrix, name: "randM", menuPath: "MATRX MATH", arity: 2...2,
                           argumentLabels: ["rows", "columns"], mapsOverLists: false),
        FunctionDefinition(id: .rowEchelon, name: "ref", menuPath: "MATRX MATH", arity: 1...1,
                           argumentLabels: ["matrix"], mapsOverLists: false),
        FunctionDefinition(id: .reducedRowEchelon, name: "rref", menuPath: "MATRX MATH", arity: 1...1,
                           argumentLabels: ["matrix"], mapsOverLists: false),
        FunctionDefinition(id: .rowSwap, name: "rowSwap", menuPath: "MATRX MATH", arity: 3...3,
                           argumentLabels: ["matrix", "rowA", "rowB"], mapsOverLists: false),
        FunctionDefinition(id: .rowAdd, name: "row+", menuPath: "MATRX MATH", arity: 3...3,
                           argumentLabels: ["matrix", "source", "target"], mapsOverLists: false),
        FunctionDefinition(id: .rowScale, name: "*row", menuPath: "MATRX MATH", arity: 3...3,
                           argumentLabels: ["factor", "matrix", "row"], mapsOverLists: false),
        FunctionDefinition(id: .rowScaleAdd, name: "*row+", menuPath: "MATRX MATH", arity: 4...4,
                           argumentLabels: ["factor", "matrix", "source", "target"], mapsOverLists: false),

        // MARK: Display conversions
        FunctionDefinition(id: .toFraction, name: "▸Frac", menuPath: "MATH MATH", form: .displayConversion, arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .toDecimal, name: "▸Dec", menuPath: "MATH MATH", form: .displayConversion, arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .toRectangular, name: "▸Rect", menuPath: "MATH CMPLX", form: .displayConversion, arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .toPolar, name: "▸Polar", menuPath: "MATH CMPLX", form: .displayConversion, arity: 1...1, argumentLabels: ["value"])
    ]

    /// Every tokenizable spelling mapped to its definition, longest names first so the
    /// tokenizer's longest-match scan resolves `sinh` before `sin`. Macros are excluded: they
    /// expand to ordinary syntax and have no token of their own.
    public static let spellingIndex: [(spelling: String, definition: FunctionDefinition)] = {
        var pairs: [(String, FunctionDefinition)] = []
        for definition in all where definition.form != .macro {
            for spelling in definition.spellings {
                pairs.append((spelling, definition))
            }
        }
        return pairs.sorted { $0.0.count > $1.0.count }.map { (spelling: $0.0, definition: $0.1) }
    }()

    public static func definition(for id: FunctionID) -> FunctionDefinition? {
        all.first { $0.id == id }
    }

    public static func definition(named name: String) -> FunctionDefinition? {
        all.first { $0.spellings.contains(name) }
    }

    /// Entries grouped by their TI menu path, for the menu UI.
    public static func entries(inMenu menuPath: String) -> [FunctionDefinition] {
        all.filter { $0.menuPath == menuPath }
    }
}
