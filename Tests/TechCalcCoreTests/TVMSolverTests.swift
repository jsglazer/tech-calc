import Foundation
import Testing
@testable import TechCalcCore

/// The TVM solver *screen* is a renderer of `TVMField` and a caller of `Finance.solve`. Both are
/// pure, so the screen's whole behaviour except its pixels is asserted here — which is what keeps
/// "which field is blank" from turning into a second solver inside a view.
@Suite("TVM solver form")
struct TVMSolverTests {

    /// A 30-year mortgage: the payment that clears 250,000 at 6.5% nominal, monthly.
    private var mortgage: FinanceVariables {
        FinanceVariables(n: 360, interestPercent: 6.5, presentValue: 250_000,
                         payment: 0, futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12)
    }

    @Test("The screen's fields are declared once, with the TI's own names")
    func fieldsAreDeclaredOnce() {
        #expect(TVMField.allCases.count == 7)
        #expect(TVMField.solvable.count == 5)
        #expect(TVMField.paymentsPerYear.isSolvable == false)
        #expect(TVMField.compoundsPerYear.isSolvable == false)
        let labels = TVMField.allCases.map(\.label)
        #expect(Set(labels).count == labels.count, "two fields share a name")
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    @Test("A field reads and writes exactly its own slot")
    func fieldAccess() {
        var variables = mortgage
        for field in TVMField.allCases {
            variables = field.setting(field.value(in: variables) + 1, in: variables)
        }
        #expect(variables.n == mortgage.n + 1)
        #expect(variables.interestPercent == mortgage.interestPercent + 1)
        #expect(variables.presentValue == mortgage.presentValue + 1)
        #expect(variables.payment == mortgage.payment + 1)
        #expect(variables.futureValue == mortgage.futureValue + 1)
        #expect(variables.paymentsPerYear == mortgage.paymentsPerYear + 1)
        #expect(variables.compoundsPerYear == mortgage.compoundsPerYear + 1)
    }

    @Test("Solving for a field writes that field and leaves the rest alone")
    func solvingFillsOneField() throws {
        let solved = try Finance.solve(for: .payment, mortgage)
        #expect(solved.payment == (try Finance.payment(mortgage)))
        #expect(solved.n == mortgage.n)
        #expect(solved.presentValue == mortgage.presentValue)
        #expect(solved.timing == mortgage.timing)
    }

    @Test("Each of the five unknowns solves back to the scenario the others describe")
    func everyUnknownRoundTrips() throws {
        // Start from a scenario that already balances, then blank one field at a time.
        let complete = try Finance.solve(for: .payment, mortgage)
        for field in TVMField.solvable {
            let blanked = field.setting(0, in: complete)
            let solved = try Finance.solve(for: field, blanked)
            let expected = field.value(in: complete)
            let recovered = field.value(in: solved)
            #expect(abs(recovered - expected) < 1e-6 * Swift.max(1, abs(expected)),
                    "\(field.label) solved to \(recovered), expected \(expected)")
        }
    }

    @Test("A solved scenario has a residual of zero, whichever field was solved for")
    func solvedScenariosBalance() throws {
        for field in TVMField.solvable {
            let solved = try Finance.solve(for: field, try Finance.solve(for: .payment, mortgage))
            #expect(abs(try Finance.residual(solved)) < 1e-4)
        }
    }

    @Test("A settings field is not an unknown: asking to solve for it is a domain error")
    func settingsCannotBeSolved() {
        #expect(throws: TIError.self) { try Finance.solve(for: .paymentsPerYear, mortgage) }
        #expect(throws: TIError.self) { try Finance.solve(for: .compoundsPerYear, mortgage) }
    }

    @Test("The screen's solve and the entry-line command are the same implementation")
    func screenAndCommandAgree() throws {
        var calculator = Fixture.calculator()
        calculator.context.finance = mortgage
        let entryLine = try calculator.evaluate("tvm_Pmt()").result.asReal
        let screen = try Finance.solve(for: .payment, mortgage).payment
        #expect(entryLine == screen)
    }

    @Test("BEGIN timing changes the answer, and reaches the solver from the screen's own field")
    func timingReachesTheSolver() throws {
        var begin = mortgage
        begin.timing = .begin
        let atEnd = try Finance.solve(for: .payment, mortgage).payment
        let atStart = try Finance.solve(for: .payment, begin).payment
        #expect(atEnd != atStart)
        #expect(abs(atStart) < abs(atEnd))
    }

    @Test("An unsolvable scenario throws rather than spinning")
    func unsolvableScenarioThrows() {
        // No sign change in the cash flows, so no rate can balance the equation.
        let impossible = FinanceVariables(n: 12, interestPercent: 0, presentValue: 100,
                                          payment: 100, futureValue: 100,
                                          paymentsPerYear: 12, compoundsPerYear: 12)
        #expect(throws: TIError.self) { try Finance.solve(for: .ratePercent, impossible) }
    }
}
