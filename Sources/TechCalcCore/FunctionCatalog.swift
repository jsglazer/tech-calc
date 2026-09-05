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
    // DISTR — continuous
    case normalPDF, normalCDF, inverseNormal
    case studentPDF, studentCDF, inverseStudent
    case chiSquarePDF, chiSquareCDF, inverseChiSquare
    case fPDF, fCDF, inverseF
    // DISTR — discrete
    case binomialPDF, binomialCDF, poissonPDF, poissonCDF, geometricPDF, geometricCDF
    // PROB — the seeded draws that follow a distribution
    case randomNormal, randomBinomial, randomIntegerNoRepeat
    // STAT CALC
    case oneVarStats, twoVarStats
    case linRegAXB, linRegABX, quadReg, cubicReg, quartReg, lnReg, expReg, pwrReg
    // STAT TESTS — hypothesis tests
    case zTest, tTest, twoSampleZTest, twoSampleTTest
    case onePropZTest, twoPropZTest, chiSquareTest, chiSquareGOFTest, twoSampleFTest, linRegTTest
    // STAT TESTS — confidence intervals
    case zInterval, tInterval, twoSampleZInterval, twoSampleTInterval
    case onePropZInterval, twoPropZInterval, linRegTInterval
    // FINANCE — the TVM solver, one entry per unknown
    case tvmN, tvmInterest, tvmPresentValue, tvmPayment, tvmFutureValue
    // FINANCE — cash flows, amortization, rate conversion and dates
    case netPresentValue, internalRateOfReturn
    case amortizationBalance, amortizationPrincipal, amortizationInterest
    case toNominalRate, toEffectiveRate, daysBetweenDates
    // BASE — display conversions and the bitwise operators
    case toBinary, toHexadecimal, toOctal
    case bitwiseAnd, bitwiseOr, bitwiseXor, bitwiseNot
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
    /// How the TI's own menu spells it, when that differs from the callable `name`. The TI writes
    /// its two linear regressions as `LinReg(ax+b)` and `LinReg(a+bx)`, which are menu labels
    /// rather than call syntax; the menus show this and the entry line takes `name`.
    public let menuLabel: String
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
        menuLabel: String? = nil,
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
        self.menuLabel = menuLabel ?? name
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
        FunctionDefinition(id: .toPolar, name: "▸Polar", menuPath: "MATH CMPLX", form: .displayConversion, arity: 1...1, argumentLabels: ["value"]),

        // MARK: 2ND DISTR — continuous. A `cdf` integrates lower to upper, left to right, and
        // treats a magnitude of 1E99 as infinity; `lower > upper` is ERR:DOMAIN.
        FunctionDefinition(id: .normalPDF, name: "normalpdf", menuPath: "2ND DISTR", arity: 1...3,
                           argumentLabels: ["x", "\u{03BC}", "\u{03C3}"]),
        FunctionDefinition(id: .normalCDF, name: "normalcdf", menuPath: "2ND DISTR", arity: 2...4,
                           argumentLabels: ["lower", "upper", "\u{03BC}", "\u{03C3}"]),
        FunctionDefinition(id: .inverseNormal, name: "invNorm", menuPath: "2ND DISTR", arity: 1...3,
                           argumentLabels: ["area", "\u{03BC}", "\u{03C3}"]),
        FunctionDefinition(id: .studentPDF, name: "tpdf", menuPath: "2ND DISTR", arity: 2...2,
                           argumentLabels: ["x", "df"]),
        FunctionDefinition(id: .studentCDF, name: "tcdf", menuPath: "2ND DISTR", arity: 3...3,
                           argumentLabels: ["lower", "upper", "df"]),
        FunctionDefinition(id: .inverseStudent, name: "invT", menuPath: "2ND DISTR", arity: 2...2,
                           argumentLabels: ["area", "df"]),
        FunctionDefinition(id: .chiSquarePDF, name: "\u{03C7}\u{00B2}pdf", aliases: ["chi2pdf"], menuPath: "2ND DISTR",
                           arity: 2...2, argumentLabels: ["x", "df"]),
        FunctionDefinition(id: .chiSquareCDF, name: "\u{03C7}\u{00B2}cdf", aliases: ["chi2cdf"], menuPath: "2ND DISTR",
                           arity: 3...3, argumentLabels: ["lower", "upper", "df"]),
        FunctionDefinition(id: .inverseChiSquare, name: "inv\u{03C7}\u{00B2}", aliases: ["invChi2"], menuPath: "2ND DISTR",
                           arity: 2...2, argumentLabels: ["area", "df"]),
        FunctionDefinition(id: .fPDF, name: "Fpdf", menuPath: "2ND DISTR", arity: 3...3,
                           argumentLabels: ["x", "df1", "df2"]),
        FunctionDefinition(id: .fCDF, name: "Fcdf", menuPath: "2ND DISTR", arity: 4...4,
                           argumentLabels: ["lower", "upper", "df1", "df2"]),
        FunctionDefinition(id: .inverseF, name: "invF", menuPath: "2ND DISTR", arity: 3...3,
                           argumentLabels: ["area", "df1", "df2"]),

        // MARK: 2ND DISTR — discrete. Omitting the count from `binompdf(`/`binomcdf(` returns the
        // whole list over 0...n, as on the TI.
        FunctionDefinition(id: .binomialPDF, name: "binompdf", menuPath: "2ND DISTR", arity: 2...3,
                           argumentLabels: ["trials", "p", "x"]),
        FunctionDefinition(id: .binomialCDF, name: "binomcdf", menuPath: "2ND DISTR", arity: 2...3,
                           argumentLabels: ["trials", "p", "x"]),
        FunctionDefinition(id: .poissonPDF, name: "poissonpdf", menuPath: "2ND DISTR", arity: 2...2,
                           argumentLabels: ["\u{03BC}", "x"]),
        FunctionDefinition(id: .poissonCDF, name: "poissoncdf", menuPath: "2ND DISTR", arity: 2...2,
                           argumentLabels: ["\u{03BC}", "x"]),
        FunctionDefinition(id: .geometricPDF, name: "geometpdf", menuPath: "2ND DISTR", arity: 2...2,
                           argumentLabels: ["p", "trial"]),
        FunctionDefinition(id: .geometricCDF, name: "geometcdf", menuPath: "2ND DISTR", arity: 2...2,
                           argumentLabels: ["p", "trial"]),

        // MARK: MATH PROB — the remaining seeded draws. Every one flows through RandomSource.
        FunctionDefinition(id: .randomNormal, name: "randNorm", menuPath: "MATH PROB", arity: 2...3,
                           argumentLabels: ["\u{03BC}", "\u{03C3}", "count"], mapsOverLists: false),
        FunctionDefinition(id: .randomBinomial, name: "randBin", menuPath: "MATH PROB", arity: 2...3,
                           argumentLabels: ["trials", "p", "count"], mapsOverLists: false),
        FunctionDefinition(id: .randomIntegerNoRepeat, name: "randIntNoRep", menuPath: "MATH PROB", arity: 2...2,
                           argumentLabels: ["lower", "upper"], mapsOverLists: false),

        // MARK: STAT CALC — every entry consumes whole lists, so none of them broadcasts.
        FunctionDefinition(id: .oneVarStats, name: "1-Var Stats", aliases: ["1-VarStats"], menuPath: "STAT CALC",
                           arity: 1...2, argumentLabels: ["list", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .twoVarStats, name: "2-Var Stats", aliases: ["2-VarStats"], menuPath: "STAT CALC",
                           arity: 2...3, argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .linRegAXB, name: "LinRegAXB", menuPath: "STAT CALC", menuLabel: "LinReg(ax+b)",
                           arity: 2...3, argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .linRegABX, name: "LinRegABX", menuPath: "STAT CALC", menuLabel: "LinReg(a+bx)",
                           arity: 2...3, argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .quadReg, name: "QuadReg", menuPath: "STAT CALC", arity: 2...3,
                           argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .cubicReg, name: "CubicReg", menuPath: "STAT CALC", arity: 2...3,
                           argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .quartReg, name: "QuartReg", menuPath: "STAT CALC", arity: 2...3,
                           argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .lnReg, name: "LnReg", menuPath: "STAT CALC", arity: 2...3,
                           argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .expReg, name: "ExpReg", menuPath: "STAT CALC", arity: 2...3,
                           argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),
        FunctionDefinition(id: .pwrReg, name: "PwrReg", menuPath: "STAT CALC", arity: 2...3,
                           argumentLabels: ["listX", "listY", "freq"], mapsOverLists: false),

        // MARK: STAT TESTS — hypothesis tests. Each accepts the TI's Data form (a list) and its
        // Stats form (summary numbers); which one was written is decided by the argument's type.
        // `alternative` is the TI's code: 0 for two-sided, -1 for <, 1 for >.
        FunctionDefinition(id: .zTest, name: "Z-Test", menuPath: "STAT TESTS", arity: 4...5,
                           argumentLabels: ["\u{03BC}0", "\u{03C3}", "list or x\u{0304}", "n", "alternative"],
                           mapsOverLists: false),
        FunctionDefinition(id: .tTest, name: "T-Test", menuPath: "STAT TESTS", arity: 3...5,
                           argumentLabels: ["\u{03BC}0", "list or x\u{0304}", "Sx", "n", "alternative"],
                           mapsOverLists: false),
        FunctionDefinition(id: .twoSampleZTest, name: "2-SampZTest", menuPath: "STAT TESTS", arity: 5...7,
                           argumentLabels: ["\u{03C3}1", "\u{03C3}2", "list1 or x\u{0304}1", "list2 or n1",
                                            "x\u{0304}2", "n2", "alternative"],
                           mapsOverLists: false),
        FunctionDefinition(id: .twoSampleTTest, name: "2-SampTTest", menuPath: "STAT TESTS", arity: 4...8,
                           argumentLabels: ["list1 or x\u{0304}1", "list2 or Sx1", "n1", "x\u{0304}2", "Sx2", "n2",
                                            "alternative", "pooled"],
                           mapsOverLists: false),
        FunctionDefinition(id: .onePropZTest, name: "1-PropZTest", menuPath: "STAT TESTS", arity: 4...4,
                           argumentLabels: ["p0", "x", "n", "alternative"], mapsOverLists: false),
        FunctionDefinition(id: .twoPropZTest, name: "2-PropZTest", menuPath: "STAT TESTS", arity: 5...5,
                           argumentLabels: ["x1", "n1", "x2", "n2", "alternative"], mapsOverLists: false),
        FunctionDefinition(id: .chiSquareTest, name: "\u{03C7}\u{00B2}-Test", aliases: ["chi2-Test"],
                           menuPath: "STAT TESTS", arity: 1...1, argumentLabels: ["observed"], mapsOverLists: false),
        FunctionDefinition(id: .chiSquareGOFTest, name: "\u{03C7}\u{00B2}GOF-Test", aliases: ["chi2GOF-Test"],
                           menuPath: "STAT TESTS", arity: 3...3, argumentLabels: ["observed", "expected", "df"],
                           mapsOverLists: false),
        FunctionDefinition(id: .twoSampleFTest, name: "2-SampFTest", menuPath: "STAT TESTS", arity: 3...5,
                           argumentLabels: ["list1 or Sx1", "list2 or n1", "Sx2", "n2", "alternative"],
                           mapsOverLists: false),
        FunctionDefinition(id: .linRegTTest, name: "LinRegTTest", menuPath: "STAT TESTS", arity: 3...3,
                           argumentLabels: ["listX", "listY", "alternative"], mapsOverLists: false),

        // MARK: STAT TESTS — confidence intervals. The level is a proportion (0.95), as on the TI.
        FunctionDefinition(id: .zInterval, name: "ZInterval", menuPath: "STAT TESTS", arity: 3...4,
                           argumentLabels: ["\u{03C3}", "list or x\u{0304}", "n", "level"], mapsOverLists: false),
        FunctionDefinition(id: .tInterval, name: "TInterval", menuPath: "STAT TESTS", arity: 2...4,
                           argumentLabels: ["list or x\u{0304}", "Sx", "n", "level"], mapsOverLists: false),
        FunctionDefinition(id: .twoSampleZInterval, name: "2-SampZInt", menuPath: "STAT TESTS", arity: 5...7,
                           argumentLabels: ["\u{03C3}1", "\u{03C3}2", "list1 or x\u{0304}1", "list2 or n1",
                                            "x\u{0304}2", "n2", "level"],
                           mapsOverLists: false),
        FunctionDefinition(id: .twoSampleTInterval, name: "2-SampTInt", menuPath: "STAT TESTS", arity: 4...8,
                           argumentLabels: ["list1 or x\u{0304}1", "list2 or Sx1", "n1", "x\u{0304}2", "Sx2", "n2",
                                            "level", "pooled"],
                           mapsOverLists: false),
        FunctionDefinition(id: .onePropZInterval, name: "1-PropZInt", menuPath: "STAT TESTS", arity: 3...3,
                           argumentLabels: ["x", "n", "level"], mapsOverLists: false),
        FunctionDefinition(id: .twoPropZInterval, name: "2-PropZInt", menuPath: "STAT TESTS", arity: 5...5,
                           argumentLabels: ["x1", "n1", "x2", "n2", "level"], mapsOverLists: false),
        // The interval on a regression slope. It shares `Inference`'s interval machinery with the
        // entries above and is the M4 carry-over the post-M4 decisions (D23) put at the head of M5.
        FunctionDefinition(id: .linRegTInterval, name: "LinRegTInt", menuPath: "STAT TESTS", arity: 3...3,
                           argumentLabels: ["listX", "listY", "level"], mapsOverLists: false),

        // MARK: FINANCE CALC — the TVM solver. The five entries solve one equation for five
        // different unknowns; an argument the caller omits is read from the stored TVM variables,
        // so `tvm_Pmt()` after filling the solver screen means what it does on the hardware.
        FunctionDefinition(id: .tvmN, name: "tvm_N", menuPath: "FINANCE CALC", arity: 0...6,
                           argumentLabels: ["I%", "PV", "PMT", "FV", "P/Y", "C/Y"], mapsOverLists: false),
        FunctionDefinition(id: .tvmInterest, name: "tvm_I%", menuPath: "FINANCE CALC", arity: 0...6,
                           argumentLabels: ["N", "PV", "PMT", "FV", "P/Y", "C/Y"], mapsOverLists: false),
        FunctionDefinition(id: .tvmPresentValue, name: "tvm_PV", menuPath: "FINANCE CALC", arity: 0...6,
                           argumentLabels: ["N", "I%", "PMT", "FV", "P/Y", "C/Y"], mapsOverLists: false),
        FunctionDefinition(id: .tvmPayment, name: "tvm_Pmt", menuPath: "FINANCE CALC", arity: 0...6,
                           argumentLabels: ["N", "I%", "PV", "FV", "P/Y", "C/Y"], mapsOverLists: false),
        FunctionDefinition(id: .tvmFutureValue, name: "tvm_FV", menuPath: "FINANCE CALC", arity: 0...6,
                           argumentLabels: ["N", "I%", "PV", "PMT", "P/Y", "C/Y"], mapsOverLists: false),

        // MARK: FINANCE CALC — cash flows and amortization. The amortization trio reads the same
        // stored TVM variables the solver writes, as it does on the hardware.
        FunctionDefinition(id: .netPresentValue, name: "npv", menuPath: "FINANCE CALC", arity: 3...4,
                           argumentLabels: ["rate", "CF0", "CFList", "CFFreq"], mapsOverLists: false),
        FunctionDefinition(id: .internalRateOfReturn, name: "irr", menuPath: "FINANCE CALC", arity: 2...3,
                           argumentLabels: ["CF0", "CFList", "CFFreq"], mapsOverLists: false),
        FunctionDefinition(id: .amortizationBalance, name: "bal", menuPath: "FINANCE CALC", arity: 1...2,
                           argumentLabels: ["payment", "decimals"], mapsOverLists: false),
        FunctionDefinition(id: .amortizationPrincipal, name: "\u{03A3}Prn", menuPath: "FINANCE CALC", arity: 2...3,
                           argumentLabels: ["first", "last", "decimals"], mapsOverLists: false),
        FunctionDefinition(id: .amortizationInterest, name: "\u{03A3}Int", menuPath: "FINANCE CALC", arity: 2...3,
                           argumentLabels: ["first", "last", "decimals"], mapsOverLists: false),
        FunctionDefinition(id: .toNominalRate, name: "\u{25B8}Nom", menuPath: "FINANCE CALC", arity: 2...2,
                           argumentLabels: ["effective", "periods"], mapsOverLists: false),
        FunctionDefinition(id: .toEffectiveRate, name: "\u{25B8}Eff", menuPath: "FINANCE CALC", arity: 2...2,
                           argumentLabels: ["nominal", "periods"], mapsOverLists: false),
        FunctionDefinition(id: .daysBetweenDates, name: "dbd", menuPath: "FINANCE CALC", arity: 2...2,
                           argumentLabels: ["date1", "date2"], mapsOverLists: false),

        // MARK: MATH BASE. The TI-84 Plus CE has no BASE menu, so this is beyond TI parity and
        // the post-M4 decisions (D22) fix its shape: the bitwise operators are *named functions*,
        // distinct from the boolean `and`/`or`/`xor`/`not` the TEST LOGIC menu already declares,
        // so no expression that was already valid changes meaning. `\u{25B8}Dec` is not redeclared here —
        // the MATH MATH entry above already means "show this answer in base ten".
        FunctionDefinition(id: .toBinary, name: "\u{25B8}Bin", menuPath: "MATH BASE", form: .displayConversion,
                           arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .toHexadecimal, name: "\u{25B8}Hex", menuPath: "MATH BASE", form: .displayConversion,
                           arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .toOctal, name: "\u{25B8}Oct", menuPath: "MATH BASE", form: .displayConversion,
                           arity: 1...1, argumentLabels: ["value"]),
        FunctionDefinition(id: .bitwiseAnd, name: "bitAnd", menuPath: "MATH BASE", arity: 2...2,
                           argumentLabels: ["valueA", "valueB"]),
        FunctionDefinition(id: .bitwiseOr, name: "bitOr", menuPath: "MATH BASE", arity: 2...2,
                           argumentLabels: ["valueA", "valueB"]),
        FunctionDefinition(id: .bitwiseXor, name: "bitXor", menuPath: "MATH BASE", arity: 2...2,
                           argumentLabels: ["valueA", "valueB"]),
        FunctionDefinition(id: .bitwiseNot, name: "bitNot", menuPath: "MATH BASE", arity: 1...1,
                           argumentLabels: ["value"])
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

extension FunctionCatalog {
    /// The LaTeX command an entry is typeset with, when it has a real one.
    ///
    /// This lives here for the same reason every other spelling does: the catalog is the single
    /// declaration site for what a function is called, in any notation. `nil` means "no dedicated
    /// command" — the serializer falls back to `\operatorname{…}` over the canonical `name`, so a
    /// new catalog entry is typeset sensibly without being listed twice.
    public static func latexCommand(for id: FunctionID) -> String? {
        switch id {
        case .sin: "\\sin"
        case .cos: "\\cos"
        case .tan: "\\tan"
        case .asin: "\\sin^{-1}"
        case .acos: "\\cos^{-1}"
        case .atan: "\\tan^{-1}"
        case .sinh: "\\sinh"
        case .cosh: "\\cosh"
        case .tanh: "\\tanh"
        case .asinh: "\\sinh^{-1}"
        case .acosh: "\\cosh^{-1}"
        case .atanh: "\\tanh^{-1}"
        case .log: "\\log"
        case .ln: "\\ln"
        case .minimum: "\\min"
        case .maximum: "\\max"
        case .gcd: "\\gcd"
        case .pi: "\\pi"
        case .eulersNumber: "e"
        case .imaginaryUnit: "i"
        default: nil
        }
    }
}
