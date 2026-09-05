import Foundation

/// The TI's `VARS ▸ Statistics` results, as values.
///
/// This enum is the single declaration site for a statistics variable's spelling, exactly as
/// `FunctionCatalog` is for a function's: the tokenizer, the evaluator and the results screens
/// all reach a variable through a case, and no statistics-variable name is written down anywhere
/// else in the module.
public enum StatVariable: String, Equatable, Hashable, Sendable, CaseIterable, Codable {
    // XY — the 1-Var and 2-Var summaries
    case n, meanX, sampleDeviationX, populationDeviationX
    case minimumX, firstQuartile, median, thirdQuartile, maximumX
    case meanY, sampleDeviationY, populationDeviationY, minimumY, maximumY
    // Σ — the running sums
    case sumX, sumSquaredX, sumY, sumSquaredY, sumXY
    // EQ — fitted coefficients
    case coefficientA, coefficientB, coefficientC, coefficientD
    case correlation, determination, residualDeviation
    // TEST — statistics and their tail probabilities
    case probability, zStatistic, tStatistic, chiSquareStatistic, degreesOfFreedom
    // TEST — the per-sample values a two-sample procedure reports back
    case meanX1, meanX2, sampleDeviation1, sampleDeviation2, n1, n2
    case proportion, proportion1, proportion2, pooledDeviation
    // INTERVAL — the endpoints of a confidence interval
    case lowerBound, upperBound

    /// How the variable is written on the entry line, in the TI's own glyphs.
    public var name: String {
        switch self {
        case .n: "n"
        case .meanX: "x\u{0304}"
        case .sampleDeviationX: "Sx"
        case .populationDeviationX: "\u{03C3}x"
        case .minimumX: "minX"
        case .firstQuartile: "Q1"
        case .median: "Med"
        case .thirdQuartile: "Q3"
        case .maximumX: "maxX"
        case .meanY: "y\u{0304}"
        case .sampleDeviationY: "Sy"
        case .populationDeviationY: "\u{03C3}y"
        case .minimumY: "minY"
        case .maximumY: "maxY"
        case .sumX: "\u{03A3}x"
        case .sumSquaredX: "\u{03A3}x\u{00B2}"
        case .sumY: "\u{03A3}y"
        case .sumSquaredY: "\u{03A3}y\u{00B2}"
        case .sumXY: "\u{03A3}xy"
        case .coefficientA: "a"
        case .coefficientB: "b"
        case .coefficientC: "c"
        case .coefficientD: "d"
        case .correlation: "r"
        case .determination: "r\u{00B2}"
        case .residualDeviation: "s"
        case .probability: "p"
        case .zStatistic: "z"
        case .tStatistic: "t"
        case .chiSquareStatistic: "\u{03C7}\u{00B2}"
        case .degreesOfFreedom: "df"
        case .meanX1: "x\u{0304}1"
        case .meanX2: "x\u{0304}2"
        case .sampleDeviation1: "Sx1"
        case .sampleDeviation2: "Sx2"
        case .n1: "n1"
        case .n2: "n2"
        case .proportion: "p\u{0302}"
        case .proportion1: "p\u{0302}1"
        case .proportion2: "p\u{0302}2"
        case .pooledDeviation: "sp"
        case .lowerBound: "lower"
        case .upperBound: "upper"
        }
    }

    /// How the variable is typeset. Overridden only where LaTeX has a real construct for the
    /// TI's glyph; everything else is set upright from `name`, so a new case needs nothing here.
    public var latexName: String {
        switch self {
        case .meanX: "\\bar{x}"
        case .meanY: "\\bar{y}"
        case .meanX1: "\\bar{x}_{1}"
        case .meanX2: "\\bar{x}_{2}"
        case .proportion: "\\hat{p}"
        case .proportion1: "\\hat{p}_{1}"
        case .proportion2: "\\hat{p}_{2}"
        case .chiSquareStatistic: "\\chi^{2}"
        case .determination: "r^{2}"
        case .sumX: "\\Sigma x"
        case .sumY: "\\Sigma y"
        case .sumSquaredX: "\\Sigma x^{2}"
        case .sumSquaredY: "\\Sigma y^{2}"
        case .sumXY: "\\Sigma xy"
        case .populationDeviationX: "\\sigma x"
        case .populationDeviationY: "\\sigma y"
        default: "\\mathrm\u{7B}" + name + "\u{7D}"
        }
    }

    /// Every spelling mapped to its case, longest first, so the tokenizer's longest-match scan
    /// resolves `Sx1` before `Sx` and `minX` before the `min(` function.
    public static let spellingIndex: [(spelling: String, variable: StatVariable)] = {
        allCases
            .map { (spelling: $0.name, variable: $0) }
            .sorted { $0.spelling.count > $1.spelling.count }
    }()

    public static func variable(named name: String) -> StatVariable? {
        allCases.first { $0.name == name }
    }
}

/// The values the last `STAT CALC` or `STAT TESTS` command produced.
///
/// A variable that no command has written is `ERR:UNDEFINED` rather than silently zero, so a
/// misread result is a visible error instead of a plausible wrong number.
public struct StatisticsVariables: Equatable, Sendable {
    private var values: [StatVariable: Double]

    public init(_ values: [StatVariable: Double] = [:]) {
        self.values = values
    }

    public subscript(variable: StatVariable) -> Double? {
        get { values[variable] }
        set { values[variable] = newValue }
    }

    public func value(of variable: StatVariable) throws -> Double {
        guard let value = values[variable] else { throw TIError.undefined }
        return value
    }

    /// Replaces the whole bag, as running a new command does: results from two different
    /// commands are never visible at the same time.
    public mutating func publish(_ published: [StatVariable: Double]) {
        values = published
    }

    public var isEmpty: Bool { values.isEmpty }

    /// The whole bag, for a results pane and for the tests that compare what a form screen shows
    /// with what the entry-line command published.
    public var asDictionary: [StatVariable: Double] { values }
}
