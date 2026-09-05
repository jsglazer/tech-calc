import Foundation
import Testing
@testable import TechCalcCore

/// The `STAT TESTS` screens are generated from `StatForms`, so everything a screen can get wrong
/// except its pixels is checkable here: which fields it collects, what it does with them, and
/// whether it agrees with the entry-line command that runs the same procedure.
@Suite("Stat test forms")
struct StatFormTests {

    private func context(x: [Double] = [1, 2, 3, 4, 5], y: [Double] = [2, 4, 5, 4, 5]) -> EvaluationContext {
        var context = EvaluationContext()
        context.lists[Fixture.listName(1)] = TIList(reals: x)
        context.lists[Fixture.listName(2)] = TIList(reals: y)
        return context
    }

    @Test("Every declared form names a real procedure and collects at least one field")
    func formsAreWellFormed() {
        #expect(!StatForms.all.isEmpty)
        for form in StatForms.all {
            #expect(FunctionCatalog.definition(for: form.id) != nil, "\(form.id) is not in the catalog")
            #expect(!form.fields.isEmpty, "\(form.title) collects nothing")
            #expect(form.fields.count == Set(form.fields).count, "\(form.title) repeats a field")
            #expect(!form.title.isEmpty)
        }
    }

    @Test("Every STAT TESTS entry in the catalog has a form, and every form runs")
    func everyProcedureHasAForm() throws {
        let menu = FunctionCatalog.entries(inMenu: "STAT TESTS").map(\.id)
        for id in menu {
            #expect(StatForms.definition(for: id) != nil, "\(id) has no form screen")
        }
        // Each form produces rows from representative values: no procedure is declared but dead.
        var values = StatFormValues()
        values[.mean] = 12
        values[.mean2] = 10
        values[.sampleDeviation] = 2
        values[.sampleDeviation2] = 3
        values[.sampleSize] = 30
        values[.sampleSize2] = 25
        values[.populationDeviation] = 2
        values[.populationDeviation2] = 3
        values[.successes] = 12
        values[.successes2] = 9
        values[.hypothesisedMean] = 10
        values[.hypothesisedProportion] = 0.4
        values[.degreesOfFreedom] = 4
        var context = context()
        context.matrices[Fixture.matrixName("A")] =
            try TIMatrix(rows: 2, columns: 2, values: [Complex(20), Complex(30), Complex(30), Complex(20)])
        for form in StatForms.all {
            let report = try StatForms.run(form.id, values: values, context: context)
            #expect(!report.rows.isEmpty, "\(form.title) produced no rows")
            #expect(report.rows.allSatisfy { $0.value.isFinite }, "\(form.title) produced a non-finite row")
        }
    }

    @Test("A field's control kind and default are declared once, on the field")
    func fieldDeclarations() {
        #expect(StatFormField.confidenceLevel.kind == .level)
        #expect(StatFormField.confidenceLevel.defaultValue == 0.95)
        #expect(StatFormField.alternative.kind == .alternative)
        #expect(StatFormField.pooled.kind == .flag)
        #expect(StatFormField.listX.kind == .list)
        #expect(StatFormField.observedMatrix.kind == .matrix)
        // A field the screen has not touched reads as its declared default.
        let values = StatFormValues()
        #expect(values[.confidenceLevel] == 0.95)
        #expect(values[.alternative] == 0)
        // The two regression lists default to L1 and L2, as on the hardware.
        #expect(values.list(.listX) == Fixture.listName(1))
        #expect(values.list(.listY) == Fixture.listName(2))
    }

    @Test("A form's field labels come from the statistics variable table, not a second spelling")
    func labelsAreNotRespelled() {
        #expect(StatFormField.mean.label == StatVariable.meanX.name)
        #expect(StatFormField.sampleSize.label == StatVariable.n.name)
        #expect(StatFormField.sampleDeviation2.label == StatVariable.sampleDeviation2.name)
    }

    @Test("The T-Test form and the T-Test command are the same implementation")
    func tTestAgreesWithTheCommand() throws {
        var values = StatFormValues()
        values[.hypothesisedMean] = 10
        values[.mean] = 12
        values[.sampleDeviation] = 2
        values[.sampleSize] = 30
        values[.alternative] = 1
        let report = try StatForms.run(.tTest, values: values, context: EvaluationContext())

        var calculator = Fixture.calculator()
        calculator.enter("T-Test(10,12,2,30,1)")
        #expect(report.published == calculator.context.statistics.asDictionary)
    }

    @Test("The 2-SampTTest form reports Welch's df, exactly as the command does")
    func twoSampleTTestAgreesWithTheCommand() throws {
        var values = StatFormValues()
        values[.mean] = 12
        values[.sampleDeviation] = 2
        values[.sampleSize] = 30
        values[.mean2] = 10
        values[.sampleDeviation2] = 3
        values[.sampleSize2] = 25
        values[.alternative] = 0
        values[.pooled] = 0
        let report = try StatForms.run(.twoSampleTTest, values: values, context: EvaluationContext())

        var calculator = Fixture.calculator()
        calculator.enter("2-SampTTest(12,2,30,10,3,25,0,0)")
        #expect(report.published == calculator.context.statistics.asDictionary)
        let welch = try Inference.welchDegreesOfFreedom(2, 30, 3, 25)
        let reported = report.rows.first { $0.variable == .degreesOfFreedom }
        #expect(reported != nil)
        #expect(abs((reported?.value ?? 0) - welch) < 1e-12)
    }

    @Test("The pooled toggle reaches the pure function rather than a second formula")
    func pooledTogglesTheProcedure() throws {
        var values = StatFormValues()
        values[.mean] = 12
        values[.sampleDeviation] = 2
        values[.sampleSize] = 30
        values[.mean2] = 10
        values[.sampleDeviation2] = 3
        values[.sampleSize2] = 25
        let unpooled = try StatForms.run(.twoSampleTTest, values: values, context: EvaluationContext())
        values[.pooled] = 1
        let pooled = try StatForms.run(.twoSampleTTest, values: values, context: EvaluationContext())
        #expect(unpooled.published[.degreesOfFreedom] != pooled.published[.degreesOfFreedom])
        #expect(pooled.published[.degreesOfFreedom] == 53)
        #expect(pooled.published[.pooledDeviation] != nil)
    }

    @Test("A regression form reads the lists it was pointed at")
    func regressionFormsReadTheirLists() throws {
        var values = StatFormValues()
        values[.alternative] = 0
        let report = try StatForms.run(.linRegTTest, values: values, context: context())
        let direct = try Inference.linRegTTest([1, 2, 3, 4, 5], [2, 4, 5, 4, 5], alternative: .twoSided)
        #expect(report.published[.coefficientB] == direct.slope)
        #expect(report.published[.tStatistic] == direct.statistic)

        // Pointing the form at a different list changes the fit; nothing is hard-wired to L1.
        var swapped = values
        swapped.lists[.listX] = Fixture.listName(2)
        swapped.lists[.listY] = Fixture.listName(1)
        let reversed = try StatForms.run(.linRegTTest, values: swapped, context: context())
        #expect(reversed.published[.coefficientB] != report.published[.coefficientB])
    }

    @Test("The interval forms report their endpoints and honour the confidence level")
    func intervalForms() throws {
        var values = StatFormValues()
        values[.mean] = 12
        values[.sampleDeviation] = 2
        values[.sampleSize] = 30
        let ninetyFive = try StatForms.run(.tInterval, values: values, context: EvaluationContext())
        values[.confidenceLevel] = 0.99
        let ninetyNine = try StatForms.run(.tInterval, values: values, context: EvaluationContext())

        let lower = ninetyFive.published[.lowerBound]
        let wider = ninetyNine.published[.lowerBound]
        #expect(lower != nil && wider != nil)
        #expect((wider ?? 0) < (lower ?? 0))
        let direct = try Inference.tInterval(mean: 12, sampleDeviation: 2, n: 30, level: 0.95)
        #expect(lower == direct.lower)
    }

    @Test("The χ² form reads the matrix it was pointed at")
    func chiSquareFormReadsItsMatrix() throws {
        var context = EvaluationContext()
        let observed = try TIMatrix(rows: 2, columns: 2,
                                    values: [Complex(20), Complex(30), Complex(30), Complex(20)])
        context.matrices[Fixture.matrixName("B")] = observed
        var values = StatFormValues()
        values.matrix = Fixture.matrixName("B")
        let report = try StatForms.run(.chiSquareTest, values: values, context: context)
        let direct = try Inference.chiSquareTest(observed: [[20, 30], [30, 20]])
        #expect(report.published[.chiSquareStatistic] == direct.statistic)
        #expect(report.published[.degreesOfFreedom] == 1)
    }

    @Test("An out-of-range field is a TI error, not a silent number")
    func invalidInputIsAnError() {
        var values = StatFormValues()
        values[.alternative] = 7
        #expect(throws: TIError.self) {
            try StatForms.run(.tTest, values: values, context: EvaluationContext())
        }
        var level = StatFormValues()
        level[.mean] = 12
        level[.sampleDeviation] = 2
        level[.sampleSize] = 30
        level[.confidenceLevel] = 1.5
        #expect(throws: TIError.self) {
            try StatForms.run(.tInterval, values: level, context: EvaluationContext())
        }
    }

    @Test("A procedure with no form is refused rather than half-run")
    func unknownProcedure() {
        #expect(throws: TIError.self) {
            try StatForms.run(.oneVarStats, values: StatFormValues(), context: EvaluationContext())
        }
    }

    @Test("Result rows come out in the statistics variables' own order, with no gaps")
    func rowOrdering() throws {
        var values = StatFormValues()
        values[.hypothesisedMean] = 10
        values[.mean] = 12
        values[.sampleDeviation] = 2
        values[.sampleSize] = 30
        let report = try StatForms.run(.tTest, values: values, context: EvaluationContext())
        let order = StatVariable.allCases
        let indices = report.rows.compactMap { order.firstIndex(of: $0.variable) }
        #expect(indices == indices.sorted())
        #expect(Set(report.rows.map(\.variable)) == Set(report.published.keys))
    }
}
