import Testing
@testable import TechCalcCore

/// The `FINANCE` menu.
///
/// Every expected value below was produced by R 4.5.3 — either by `stats::uniroot` on the TVM
/// equation as the guidebook documents it, or by walking the amortization recursion in R — and
/// none by running tech-calc. The generator for the entry-line half of these is
/// `~/.claude/scripts/techcalc-fixtures.R`; the values inlined here are the ones the entry line
/// cannot reach, because the TVM fields have no entry-line spelling (see the build log).
@Suite("Finance")
struct FinanceTests {

    /// A 24-payment loan of 10,000 at 6% nominal, compounded and paid monthly. Every solve in
    /// this suite is a different unknown of this one scenario, so an inconsistency between two
    /// of them shows up as a failure rather than as two separately plausible numbers.
    static let loan = FinanceVariables(
        n: 24, interestPercent: 6, presentValue: 10_000, payment: -443.206102527578,
        futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12
    )

    // MARK: - The TVM equation

    @Test("Each unknown solves to the value the other four imply")
    func theFiveSolvesAgree() throws {
        // R: -10000 * i / (1 - (1+i)^-24), i = 0.06/12
        expectClose(try Finance.payment(Self.loan), -443.206102527578)
        expectClose(try Finance.periods(Self.loan), 24)
        expectClose(try Finance.interestPercent(Self.loan), 6, tolerance: 1e-7)
        expectClose(try Finance.presentValue(Self.loan), 10_000)
        // The scenario is written to close exactly, so the leftover future value is rounding.
        expectClose(try Finance.futureValue(Self.loan), 0, tolerance: 1e-6)
    }

    @Test("A solved value satisfies the equation it was solved from")
    func solvesAreZeroesOfTheResidual() throws {
        var variables = Self.loan
        variables.payment = try Finance.payment(variables)
        expectClose(try Finance.residual(variables), 0, tolerance: 1e-9)

        variables = Self.loan
        variables.interestPercent = try Finance.interestPercent(variables)
        expectClose(try Finance.residual(variables), 0, tolerance: 1e-6)
    }

    @Test("BEGIN timing earns one extra period of interest on every payment")
    func annuityDuePaysLess() throws {
        var due = Self.loan
        due.timing = .begin
        let endPayment = try Finance.payment(Self.loan)
        let beginPayment = try Finance.payment(due)
        // Paying at the start of each period retires principal sooner, so the payment is smaller
        // in magnitude by exactly one period's interest factor.
        expectClose(beginPayment, endPayment / (1 + 0.06 / 12))
        #expect(abs(beginPayment) < abs(endPayment))
    }

    @Test("A zero rate takes the equation's other branch rather than dividing by zero")
    func zeroRateIsALimitNotAnError() throws {
        var free = FinanceVariables(n: 10, interestPercent: 0, presentValue: 1000, futureValue: 0)
        free.payment = try Finance.payment(free)
        expectClose(free.payment, -100)
        expectClose(try Finance.periods(free), 10)
        expectClose(try Finance.residual(free), 0)
    }

    @Test("P/Y and C/Y differing re-expresses the rate over a payment period")
    func mismatchedPeriodsConvertTheRate() throws {
        var mixed = Self.loan
        mixed.compoundsPerYear = 4
        // R: (1 + 0.06/4)^(4/12) - 1
        expectClose(try mixed.periodicRate, 0.004975206341906)
        // Quarterly compounding on a monthly payment is a shade cheaper than monthly compounding.
        #expect(try abs(Finance.payment(mixed)) < abs(Finance.payment(Self.loan)))
    }

    @Test("A rate with no sign change is ERR:NO SIGN CHNG, not a spun-out loop")
    func unsolvableRateThrows() {
        // Every term the same sign: no rate makes the equation balance.
        let impossible = FinanceVariables(n: 24, presentValue: 1000, payment: 100, futureValue: 500)
        #expect(throws: TIError.noSignChange) { _ = try Finance.interestPercent(impossible) }
    }

    @Test("The solver's iteration cap and tolerance are explicit named constants")
    func solverLimitsAreExplicit() {
        #expect(Finance.maximumSolverIterations > 0)
        #expect(Finance.solverTolerance > 0)
        #expect(Finance.maximumPeriodicRate > 0)
        #expect(Finance.maximumPeriods > 0)
    }

    // MARK: - Amortization

    @Test("The schedule reproduces R's own amortization recursion")
    func amortizationMatchesR() throws {
        // R: b <- pv; for (m in 1:12) b <- b*(1+i) + pmt
        expectClose(try Finance.balance(after: 12, Self.loan), 5149.581596866175)
        expectClose(try Finance.sumInterest(from: 1, to: 12, Self.loan), -468.054827197119)
        expectClose(try Finance.sumPrincipal(from: 1, to: 12, Self.loan), -4850.418403133817)
        expectClose(try Finance.sumInterest(from: 13, to: 24, Self.loan), -168.891633464525)
        // The loan closes: the balance after the last payment is zero to rounding.
        expectClose(try Finance.balance(after: 24, Self.loan), 0, tolerance: 1e-6)
    }

    @Test("ΣPrn and ΣInt split the payments they cover, and nothing else")
    func principalAndInterestSumToThePaymentsMade() throws {
        let principal = try Finance.sumPrincipal(from: 1, to: 12, Self.loan)
        let interest = try Finance.sumInterest(from: 1, to: 12, Self.loan)
        // The TI's documented identity: every payment is principal plus interest.
        expectClose(principal + interest, 12 * Self.loan.payment)
    }

    @Test("In BEGIN timing the first payment is pure principal")
    func annuityDueFirstPaymentCarriesNoInterest() throws {
        var due = Self.loan
        due.timing = .begin
        let entries = try Finance.schedule(through: 12, due)
        #expect(entries[0].interest == 0)
        // R: bb <- pv; for (m in 1:12) { it <- if (m==1) 0 else -bb*i; bb <- bb + pmt - it }
        expectClose(try Finance.balance(after: 12, due), 5096.761805231134)
        expectClose(try Finance.sumInterest(from: 1, to: 12, due), -415.235035562069)
    }

    @Test("An inverted or zero-based payment range is ERR:DOMAIN")
    func amortizationRangesAreValidated() {
        #expect(throws: TIError.domain) { _ = try Finance.sumInterest(from: 5, to: 2, Self.loan) }
        #expect(throws: TIError.domain) { _ = try Finance.sumPrincipal(from: 0, to: 2, Self.loan) }
    }

    @Test("The rounding argument is applied inside the recursion, not only to the answer")
    func roundingCompoundsThroughTheSchedule() throws {
        let exact = try Finance.balance(after: 12, Self.loan)
        let rounded = try Finance.balance(after: 12, Self.loan, decimals: 2)
        // Rounding each period's interest to cents changes the balance it leaves behind, so the
        // two answers differ — which is the point of honouring the argument in the recursion.
        #expect(exact != rounded)
        expectClose(rounded, exact, tolerance: 1e-4)
    }

    // MARK: - Cash flows

    @Test("npv discounts each flow by its own period")
    func netPresentValueMatchesTheDiscountedSum() throws {
        // R: -1000 + sum(c(300,400,500,600) / 1.1^(1:4))
        expectClose(
            try Finance.netPresentValue(rate: 10, initialFlow: -1000, flows: [300, 400, 500, 600]),
            388.771258793798
        )
        // A zero rate is a plain sum.
        expectClose(
            try Finance.netPresentValue(rate: 0, initialFlow: -1000, flows: [300, 400, 500, 600]),
            800
        )
    }

    @Test("A frequency list is exactly a repeated flow")
    func frequenciesExpandTheList() throws {
        let grouped = try Finance.netPresentValue(
            rate: 10, initialFlow: -1000, flows: [300, 500], frequencies: [2, 2])
        let expanded = try Finance.netPresentValue(
            rate: 10, initialFlow: -1000, flows: [300, 300, 500, 500])
        expectClose(grouped, expanded)
    }

    @Test("A frequency list of the wrong length is ERR:DIM MISMATCH")
    func frequenciesMustMatchTheFlows() {
        #expect(throws: TIError.dimensionMismatch) {
            _ = try Finance.netPresentValue(rate: 10, initialFlow: -1000, flows: [300, 500],
                                            frequencies: [2])
        }
    }

    @Test("irr is the rate at which npv is zero")
    func internalRateOfReturnZeroesTheNetPresentValue() throws {
        let rate = try Finance.internalRateOfReturn(initialFlow: -1000, flows: [300, 400, 500, 600])
        // R: uniroot(function(r) npv(r), c(0.0001, 500))
        expectClose(rate, 24.888335662, tolerance: 1e-7)
        expectClose(
            try Finance.netPresentValue(rate: rate, initialFlow: -1000, flows: [300, 400, 500, 600]),
            0, tolerance: 1e-8
        )
    }

    @Test("Flows that never change sign have no irr")
    func internalRateOfReturnNeedsASignChange() {
        #expect(throws: TIError.noSignChange) {
            _ = try Finance.internalRateOfReturn(initialFlow: 1000, flows: [300, 400])
        }
    }

    // MARK: - Rate conversion

    @Test("Nominal and effective invert each other")
    func rateConversionRoundTrips() throws {
        // R: ((1 + 0.06/12)^12 - 1) * 100
        let effective = try Finance.effectiveRate(nominal: 6, periodsPerYear: 12)
        expectClose(effective, 6.167781186449828)
        expectClose(try Finance.nominalRate(effective: effective, periodsPerYear: 12), 6)
    }

    @Test("A fractional or absent compounding count is ERR:DOMAIN")
    func rateConversionValidatesPeriods() {
        #expect(throws: TIError.domain) { _ = try Finance.effectiveRate(nominal: 6, periodsPerYear: 0) }
        #expect(throws: TIError.domain) { _ = try Finance.nominalRate(effective: 6, periodsPerYear: 2.5) }
    }

    // MARK: - Dates

    @Test("dbd counts calendar days, leap day included")
    func daysBetweenDatesMatchesTheCalendar() throws {
        // R: as.Date("2024-12-31") - as.Date("2024-03-01")
        expectClose(try Finance.daysBetween(3.0124, 12.3124), 305)
        // Across 29 February 2024.
        expectClose(try Finance.daysBetween(1.0124, 3.0124), 60)
        // Across the 2000 century boundary, which is a leap year by the 400-year rule.
        expectClose(try Finance.daysBetween(12.3199, 1.0100), 1)
        // Backwards is the negative of forwards.
        expectClose(try Finance.daysBetween(12.3124, 3.0124), -305)
    }

    @Test("The two-digit year window is 1950-2049, so a date has one reading")
    func twoDigitYearsResolveInOneWindow() throws {
        // R: as.Date("2049-01-01") - as.Date("1950-01-01"), which is 99 years and 25 leap days.
        let span = try Finance.daysBetween(1.0150, 1.0149)
        expectClose(span, 36_160)
    }

    @Test("A date that is not on the calendar is ERR:DOMAIN")
    func impossibleDatesAreRejected() {
        // 30 February.
        #expect(throws: TIError.domain) { _ = try Finance.daysBetween(2.3024, 3.0124) }
        // Month 13.
        #expect(throws: TIError.domain) { _ = try Finance.daysBetween(13.0124, 3.0124) }
        // 29 February in a non-leap year.
        #expect(throws: TIError.domain) { _ = try Finance.daysBetween(2.2923, 3.0123) }
    }

    // MARK: - The entry line

    /// A calculator whose TVM fields are already filled, as the solver screen would leave them.
    private static func calculator() -> Calculator {
        Calculator(
            context: EvaluationContext(finance: loan),
            random: SeededRandomSource(seed: 1)
        )
    }

    @Test("The amortization commands read the stored TVM fields, as on the hardware")
    func amortizationCommandsUseTheStoredScenario() throws {
        var calculator = Self.calculator()
        expectClose(try calculator.evaluate("bal(12)").result.asReal, 5149.581596866175)
        expectClose(try calculator.evaluate("ΣInt(1,12)").result.asReal, -468.054827197119)
        expectClose(try calculator.evaluate("ΣPrn(1,12)").result.asReal, -4850.418403133817)
    }

    @Test("An omitted tvm_ argument falls back to the stored field")
    func omittedArgumentsComeFromTheStoredScenario() throws {
        var calculator = Self.calculator()
        // Every field is already stored, so the bare call is the full call.
        let bare = try calculator.evaluate("tvm_Pmt()").result.asReal
        let spelled = try calculator.evaluate("tvm_Pmt(24,6,10000,0,12,12)").result.asReal
        expectClose(bare, spelled)
        expectClose(bare, -443.206102527578)
    }

    @Test("The command form and the pure function are the same implementation")
    func commandFormMatchesTheFunction() throws {
        var calculator = Self.calculator()
        expectClose(
            try calculator.evaluate("tvm_I%(24,10000,⁻443.206102527578,0,12,12)").result.asReal,
            try Finance.interestPercent(Self.loan),
            tolerance: 1e-9
        )
        expectClose(
            try calculator.evaluate("npv(10,⁻1000,{300,400,500,600})").result.asReal,
            try Finance.netPresentValue(rate: 10, initialFlow: -1000, flows: [300, 400, 500, 600])
        )
    }
}
