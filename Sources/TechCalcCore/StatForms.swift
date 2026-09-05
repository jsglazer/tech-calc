import Foundation

/// The `STAT TESTS` form screens, declared as data.
///
/// A form is a list of fields and a call into `Inference`. Both live here, in the core, so the
/// SwiftUI screen is a renderer of this table and nothing else: it computes no statistic, decides
/// no default and spells no field name. The entry-line command form and the screen are therefore
/// two callers of the same pure functions, which is the shape Decision 12 asks for and Decision 27
/// restates for the screens.
public enum StatFormField: String, Equatable, Hashable, Sendable, CaseIterable {
    case hypothesisedMean
    case hypothesisedProportion
    case populationDeviation
    case populationDeviation2
    case mean
    case mean2
    case sampleDeviation
    case sampleDeviation2
    case sampleSize
    case sampleSize2
    case successes
    case successes2
    case degreesOfFreedom
    case confidenceLevel
    case alternative
    case pooled
    case listX
    case listY
    case observedMatrix

    /// What kind of control the screen puts on the field. The view switches on this and on
    /// nothing else.
    public enum Kind: String, Equatable, Sendable {
        case number
        /// A proportion strictly between 0 and 1.
        case level
        /// The TI's `≠ / < / >` choice.
        case alternative
        /// The pooled toggle.
        case flag
        case list
        case matrix
    }

    public var kind: Kind {
        switch self {
        case .alternative: .alternative
        case .pooled: .flag
        case .confidenceLevel: .level
        case .listX, .listY: .list
        case .observedMatrix: .matrix
        default: .number
        }
    }

    /// The field's name on screen. Where the TI's form field is a statistics variable the app
    /// already knows how to spell, the spelling is read from `StatVariable` rather than written
    /// a second time.
    public var label: String {
        switch self {
        case .hypothesisedMean: "\u{03BC}0"
        case .hypothesisedProportion: "p0"
        case .populationDeviation: "\u{03C3}"
        case .populationDeviation2: "\u{03C3}2"
        case .mean: StatVariable.meanX.name
        case .mean2: StatVariable.meanX2.name
        case .sampleDeviation: StatVariable.sampleDeviationX.name
        case .sampleDeviation2: StatVariable.sampleDeviation2.name
        case .sampleSize: StatVariable.n.name
        case .sampleSize2: StatVariable.n2.name
        case .successes: "x"
        case .successes2: "x2"
        case .degreesOfFreedom: StatVariable.degreesOfFreedom.name
        case .confidenceLevel: "C-Level"
        case .alternative: "alternative"
        case .pooled: "Pooled"
        case .listX: "Xlist"
        case .listY: "Ylist"
        case .observedMatrix: "Observed"
        }
    }

    /// What the field holds when the screen first opens, matching the TI's own blank form.
    public var defaultValue: Double {
        switch self {
        case .confidenceLevel: 0.95
        case .sampleSize, .sampleSize2: 1
        case .sampleDeviation, .sampleDeviation2, .populationDeviation, .populationDeviation2: 1
        case .hypothesisedProportion: 0.5
        case .degreesOfFreedom: 1
        default: 0
        }
    }
}

/// One form: which procedure it runs, and the fields it collects for it.
public struct StatFormDefinition: Equatable, Sendable {
    public let id: FunctionID
    public let fields: [StatFormField]

    /// The form's title is the procedure's catalog name — the same spelling the entry line takes.
    public var title: String { FunctionCatalog.definition(for: id)?.name ?? id.rawValue }
    public var menuPath: String { FunctionCatalog.definition(for: id)?.menuPath ?? "" }

    public init(id: FunctionID, fields: [StatFormField]) {
        self.id = id
        self.fields = fields
    }
}

/// What a screen has collected. Absent entries fall back to the field's declared default, so a
/// half-filled form still runs the same way the TI's does.
public struct StatFormValues: Equatable, Sendable {
    public var numbers: [StatFormField: Double]
    public var lists: [StatFormField: ListName]
    public var matrix: MatrixName

    public init(
        numbers: [StatFormField: Double] = [:],
        lists: [StatFormField: ListName] = [:],
        matrix: MatrixName = MatrixName(letter: "A") ?? MatrixName.all[0]
    ) {
        self.numbers = numbers
        self.lists = lists
        self.matrix = matrix
    }

    public subscript(field: StatFormField) -> Double {
        get { numbers[field] ?? field.defaultValue }
        set { numbers[field] = newValue }
    }

    /// The list a regression form reads, defaulting to `L1` for x and `L2` for y as the TI does.
    public func list(_ field: StatFormField) -> ListName {
        lists[field] ?? ListName(number: field == .listY ? 2 : 1) ?? ListName.numberedNames[0]
    }
}

/// One line of a result screen.
public struct StatFormRow: Equatable, Sendable {
    public let variable: StatVariable
    public let value: Double

    public var label: String { variable.name }
}

/// What a form produced: the rows to show, and the same `VARS ▸ Statistics` bag the entry-line
/// command publishes — so a result read on screen and a result read back with `p` or `df` on the
/// entry line can never disagree.
public struct StatFormReport: Equatable, Sendable {
    public let rows: [StatFormRow]
    public let published: [StatVariable: Double]

    init(_ published: [StatVariable: Double]) {
        self.published = published
        // Declaration order in `StatVariable` is the display order, so the rows come out in the
        // same sequence for every procedure without a second ordering table.
        self.rows = StatVariable.allCases.compactMap { variable in
            published[variable].map { StatFormRow(variable: variable, value: $0) }
        }
    }
}

public enum StatForms {
    /// Every form the app shows, in menu order.
    public static let all: [StatFormDefinition] = [
        StatFormDefinition(id: .zTest, fields: [.hypothesisedMean, .populationDeviation, .mean, .sampleSize, .alternative]),
        StatFormDefinition(id: .tTest, fields: [.hypothesisedMean, .mean, .sampleDeviation, .sampleSize, .alternative]),
        StatFormDefinition(id: .twoSampleZTest, fields: [
            .populationDeviation, .populationDeviation2, .mean, .sampleSize, .mean2, .sampleSize2, .alternative
        ]),
        StatFormDefinition(id: .twoSampleTTest, fields: [
            .mean, .sampleDeviation, .sampleSize, .mean2, .sampleDeviation2, .sampleSize2, .alternative, .pooled
        ]),
        StatFormDefinition(id: .onePropZTest, fields: [.hypothesisedProportion, .successes, .sampleSize, .alternative]),
        StatFormDefinition(id: .twoPropZTest, fields: [.successes, .sampleSize, .successes2, .sampleSize2, .alternative]),
        StatFormDefinition(id: .twoSampleFTest, fields: [
            .sampleDeviation, .sampleSize, .sampleDeviation2, .sampleSize2, .alternative
        ]),
        StatFormDefinition(id: .chiSquareTest, fields: [.observedMatrix]),
        StatFormDefinition(id: .chiSquareGOFTest, fields: [.listX, .listY, .degreesOfFreedom]),
        StatFormDefinition(id: .linRegTTest, fields: [.listX, .listY, .alternative]),
        StatFormDefinition(id: .zInterval, fields: [.populationDeviation, .mean, .sampleSize, .confidenceLevel]),
        StatFormDefinition(id: .tInterval, fields: [.mean, .sampleDeviation, .sampleSize, .confidenceLevel]),
        StatFormDefinition(id: .twoSampleZInterval, fields: [
            .populationDeviation, .populationDeviation2, .mean, .sampleSize, .mean2, .sampleSize2, .confidenceLevel
        ]),
        StatFormDefinition(id: .twoSampleTInterval, fields: [
            .mean, .sampleDeviation, .sampleSize, .mean2, .sampleDeviation2, .sampleSize2, .confidenceLevel, .pooled
        ]),
        StatFormDefinition(id: .onePropZInterval, fields: [.successes, .sampleSize, .confidenceLevel]),
        StatFormDefinition(id: .twoPropZInterval, fields: [.successes, .sampleSize, .successes2, .sampleSize2, .confidenceLevel]),
        StatFormDefinition(id: .linRegTInterval, fields: [.listX, .listY, .confidenceLevel])
    ]

    public static func definition(for id: FunctionID) -> StatFormDefinition? {
        all.first { $0.id == id }
    }

    /// Runs one form.
    ///
    /// Every branch is a single call into `Inference` — there is no arithmetic in this function,
    /// and none in the screen that calls it. The lists and the matrix come from the calculator's
    /// own context, so a form reads the same `L1` the entry line does.
    public static func run(
        _ id: FunctionID, values: StatFormValues, context: EvaluationContext
    ) throws -> StatFormReport {
        let alternative = try Alternative(code: Int(values[.alternative].rounded()))
        let pooled = values[.pooled] != 0
        let level = values[.confidenceLevel]

        switch id {
        case .zTest:
            return report(try Inference.zTest(
                hypothesisedMean: values[.hypothesisedMean], populationDeviation: values[.populationDeviation],
                mean: values[.mean], n: values[.sampleSize], alternative: alternative))

        case .tTest:
            return report(try Inference.tTest(
                hypothesisedMean: values[.hypothesisedMean], mean: values[.mean],
                sampleDeviation: values[.sampleDeviation], n: values[.sampleSize], alternative: alternative))

        case .twoSampleZTest:
            return report(try Inference.twoSampleZTest(
                deviation1: values[.populationDeviation], deviation2: values[.populationDeviation2],
                mean1: values[.mean], n1: values[.sampleSize],
                mean2: values[.mean2], n2: values[.sampleSize2], alternative: alternative))

        case .twoSampleTTest:
            return report(try Inference.twoSampleTTest(
                mean1: values[.mean], deviation1: values[.sampleDeviation], n1: values[.sampleSize],
                mean2: values[.mean2], deviation2: values[.sampleDeviation2], n2: values[.sampleSize2],
                alternative: alternative, pooled: pooled))

        case .onePropZTest:
            return report(try Inference.onePropZTest(
                hypothesisedProportion: values[.hypothesisedProportion], successes: values[.successes],
                n: values[.sampleSize], alternative: alternative))

        case .twoPropZTest:
            return report(try Inference.twoPropZTest(
                successes1: values[.successes], n1: values[.sampleSize],
                successes2: values[.successes2], n2: values[.sampleSize2], alternative: alternative))

        case .twoSampleFTest:
            return report(try Inference.twoSampleFTest(
                deviation1: values[.sampleDeviation], n1: values[.sampleSize],
                deviation2: values[.sampleDeviation2], n2: values[.sampleSize2], alternative: alternative))

        case .chiSquareTest:
            let observed = try context.matrix(values.matrix)
            return report(try Inference.chiSquareTest(
                observed: try MatrixMath.rows(of: observed).map { try ListMath.realValues($0) }))

        case .chiSquareGOFTest:
            return report(try Inference.goodnessOfFit(
                observed: try sample(values.list(.listX), in: context),
                expected: try sample(values.list(.listY), in: context),
                degreesOfFreedom: values[.degreesOfFreedom]))

        case .linRegTTest:
            return report(try Inference.linRegTTest(
                try sample(values.list(.listX), in: context),
                try sample(values.list(.listY), in: context),
                alternative: alternative))

        case .zInterval:
            return report(try Inference.zInterval(
                populationDeviation: values[.populationDeviation], mean: values[.mean],
                n: values[.sampleSize], level: level))

        case .tInterval:
            return report(try Inference.tInterval(
                mean: values[.mean], sampleDeviation: values[.sampleDeviation],
                n: values[.sampleSize], level: level))

        case .twoSampleZInterval:
            return report(try Inference.twoSampleZInterval(
                deviation1: values[.populationDeviation], deviation2: values[.populationDeviation2],
                mean1: values[.mean], n1: values[.sampleSize],
                mean2: values[.mean2], n2: values[.sampleSize2], level: level))

        case .twoSampleTInterval:
            return report(try Inference.twoSampleTInterval(
                mean1: values[.mean], deviation1: values[.sampleDeviation], n1: values[.sampleSize],
                mean2: values[.mean2], deviation2: values[.sampleDeviation2], n2: values[.sampleSize2],
                level: level, pooled: pooled))

        case .onePropZInterval:
            return report(try Inference.onePropZInterval(
                successes: values[.successes], n: values[.sampleSize], level: level))

        case .twoPropZInterval:
            return report(try Inference.twoPropZInterval(
                successes1: values[.successes], n1: values[.sampleSize],
                successes2: values[.successes2], n2: values[.sampleSize2], level: level))

        case .linRegTInterval:
            return report(try Inference.linRegTInt(
                try sample(values.list(.listX), in: context),
                try sample(values.list(.listY), in: context),
                level: level))

        default:
            throw TIError.syntax
        }
    }

    /// The result rows are the procedure's own publishing map — the one the entry-line command
    /// writes into `VARS ▸ Statistics` — so the screen cannot show a different set of numbers.
    private static func report(_ result: some StatisticsPublishing) -> StatFormReport {
        StatFormReport(result.published)
    }

    private static func sample(_ name: ListName, in context: EvaluationContext) throws -> [Double] {
        try ListMath.realValues(context.list(name).values)
    }
}
