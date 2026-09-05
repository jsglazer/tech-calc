import Foundation

/// When a payment falls inside its period.
public enum PaymentTiming: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    /// The TI's `END`: the ordinary annuity-immediate, payments at the close of each period.
    case end
    /// The TI's `BEGIN`: an annuity-due, payments at the start of each period.
    case begin

    /// The TVM equation's `k`: one extra period of interest is earned on a payment made early.
    var annuityDueFactor: Double { self == .begin ? 1 : 0 }
}

/// The TI's `FINANCE ▸ TVM Solver` fields.
///
/// The solver screen and the entry-line `tvm_…(` commands are two callers of the same
/// `Finance` functions, and this struct is what they pass: the screen fills every field and
/// leaves one blank, while a command overrides only the fields written in its argument list.
public struct FinanceVariables: Equatable, Sendable, Codable {
    /// Number of payment periods.
    public var n: Double
    /// The nominal annual rate as a percent, exactly as the TI's `I%` field takes it.
    public var interestPercent: Double
    public var presentValue: Double
    public var payment: Double
    public var futureValue: Double
    /// Payments per year.
    public var paymentsPerYear: Double
    /// Compounding periods per year.
    public var compoundsPerYear: Double
    public var timing: PaymentTiming

    public init(
        n: Double = 0,
        interestPercent: Double = 0,
        presentValue: Double = 0,
        payment: Double = 0,
        futureValue: Double = 0,
        paymentsPerYear: Double = 12,
        compoundsPerYear: Double = 12,
        timing: PaymentTiming = .end
    ) {
        self.n = n
        self.interestPercent = interestPercent
        self.presentValue = presentValue
        self.payment = payment
        self.futureValue = futureValue
        self.paymentsPerYear = paymentsPerYear
        self.compoundsPerYear = compoundsPerYear
        self.timing = timing
    }

    /// The effective rate for one *payment* period, which is what the TVM equation is written in.
    ///
    /// When `P/Y` and `C/Y` differ, the nominal rate is compounded `C/Y` times a year and then
    /// re-expressed over a payment period — the TI's documented conversion.
    public var periodicRate: Double {
        get throws {
            guard paymentsPerYear > 0, compoundsPerYear > 0 else { throw TIError.domain }
            guard interestPercent.isFinite else { throw TIError.domain }
            let perCompound = interestPercent / 100 / compoundsPerYear
            guard perCompound > -1 else { throw TIError.domain }
            if interestPercent == 0 { return 0 }
            return Foundation.pow(1 + perCompound, compoundsPerYear / paymentsPerYear) - 1
        }
    }
}

/// The `FINANCE` menu, as pure functions.
///
/// Nothing here reads a clock, a file or global state: `dbd(` counts days from the two dates it
/// is handed, and every solver takes its inputs as a `FinanceVariables` value. Every iterative
/// routine below is bounded by a named constant and throws rather than spinning.
public enum Finance {

    // MARK: - Iteration limits

    /// Hard cap on the `I%` and `irr(` root-finds. Exceeding it is `ERR:ITERATIONS`.
    public static let maximumSolverIterations = 200
    /// Convergence bar for those root-finds, in absolute units of the function being zeroed.
    public static let solverTolerance = 1e-10
    /// How far out the `I%` and `irr(` bracket search will go, as a periodic rate.
    public static let maximumPeriodicRate = 1e6
    /// Upper bound on amortization payment numbers and expanded cash-flow counts, so a mistyped
    /// range cannot make the evaluator walk for minutes.
    public static let maximumPeriods = 1_000_000

    // MARK: - The TVM equation

    /// The annuity factor `(1 + i·k)·(1 − (1+i)^−N) / i`, with the `i = 0` limit `N·(1 + i·k)`
    /// written out rather than reached by dividing by zero.
    static func annuityFactor(rate i: Double, n: Double, timing: PaymentTiming) -> Double {
        let due = 1 + i * timing.annuityDueFactor
        if i == 0 { return n * due }
        return due * (1 - Foundation.pow(1 + i, -n)) / i
    }

    /// The TI's TVM equation, arranged so a solution is a zero of this function:
    /// `PV + PMT·annuity + FV·(1+i)^−N = 0`.
    ///
    /// Every one of the five solvers below either inverts this expression in closed form or
    /// root-finds on it, so there is one equation in the module rather than five.
    public static func residual(_ variables: FinanceVariables) throws -> Double {
        let i = try variables.periodicRate
        let discount = i == 0 ? 1 : Foundation.pow(1 + i, -variables.n)
        return variables.presentValue
            + variables.payment * annuityFactor(rate: i, n: variables.n, timing: variables.timing)
            + variables.futureValue * discount
    }

    // MARK: - The five closed-form solves

    public static func payment(_ variables: FinanceVariables) throws -> Double {
        let i = try variables.periodicRate
        let factor = annuityFactor(rate: i, n: variables.n, timing: variables.timing)
        guard factor != 0 else { throw TIError.divideByZero }
        let discount = i == 0 ? 1 : Foundation.pow(1 + i, -variables.n)
        return -(variables.presentValue + variables.futureValue * discount) / factor
    }

    public static func presentValue(_ variables: FinanceVariables) throws -> Double {
        let i = try variables.periodicRate
        let factor = annuityFactor(rate: i, n: variables.n, timing: variables.timing)
        let discount = i == 0 ? 1 : Foundation.pow(1 + i, -variables.n)
        return -(variables.payment * factor + variables.futureValue * discount)
    }

    public static func futureValue(_ variables: FinanceVariables) throws -> Double {
        let i = try variables.periodicRate
        let factor = annuityFactor(rate: i, n: variables.n, timing: variables.timing)
        let compound = i == 0 ? 1 : Foundation.pow(1 + i, variables.n)
        return -(variables.presentValue + variables.payment * factor) * compound
    }

    /// `N` from the other four. Solving `PV + A·(1 − (1+i)^−N) + FV·(1+i)^−N = 0` for `N` gives
    /// `N = ln((A − FV) / (A + PV)) / ln(1 + i)`, where `A = PMT·(1 + i·k)/i`.
    public static func periods(_ variables: FinanceVariables) throws -> Double {
        let i = try variables.periodicRate
        if i == 0 {
            guard variables.payment != 0 else { throw TIError.divideByZero }
            return -(variables.presentValue + variables.futureValue) / variables.payment
        }
        let a = variables.payment * (1 + i * variables.timing.annuityDueFactor) / i
        let numerator = a - variables.futureValue
        let denominator = a + variables.presentValue
        guard denominator != 0, numerator / denominator > 0 else { throw TIError.noSignChange }
        return Foundation.log(numerator / denominator) / Foundation.log(1 + i)
    }

    // MARK: - The one iterative solve

    /// `I%` from the other four, by bracketed bisection with a secant refinement.
    ///
    /// There is no closed form for the rate, so this is the only TVM unknown that iterates. The
    /// bracket is found by expanding outward from zero and the loop is capped at
    /// `maximumSolverIterations`; a sign change that never appears is `ERR:NO SIGN CHNG`, and a
    /// bracket that never closes is `ERR:ITERATIONS`. Neither can hang the caller.
    public static func interestPercent(_ variables: FinanceVariables) throws -> Double {
        guard variables.n > 0, variables.paymentsPerYear > 0, variables.compoundsPerYear > 0 else {
            throw TIError.domain
        }

        // The equation in terms of the *periodic* rate, so the bracket search is over one number.
        let f: (Double) throws -> Double = { i in
            var trial = variables
            trial.interestPercent = try percent(fromPeriodicRate: i, variables)
            return try residual(trial)
        }

        let rate = try findRoot(f)
        return try percent(fromPeriodicRate: rate, variables)
    }

    /// Inverts `FinanceVariables.periodicRate`: a periodic rate back to the nominal annual percent.
    static func percent(fromPeriodicRate i: Double, _ variables: FinanceVariables) throws -> Double {
        guard variables.paymentsPerYear > 0, variables.compoundsPerYear > 0 else { throw TIError.domain }
        if i == 0 { return 0 }
        guard 1 + i > 0 else { throw TIError.domain }
        let perCompound = Foundation.pow(1 + i, variables.paymentsPerYear / variables.compoundsPerYear) - 1
        return perCompound * variables.compoundsPerYear * 100
    }

    /// The single root-finder the rate solves share: expand a bracket outward from zero, then
    /// close it by bisection with a secant step taken only when it stays inside.
    ///
    /// Both `I%` and `irr(` come through here, so there is one convergence policy to audit.
    static func findRoot(_ f: (Double) throws -> Double) throws -> Double {
        // A rate of exactly zero is the answer often enough to be worth checking first.
        let atZero = try f(0)
        if Swift.abs(atZero) < solverTolerance { return 0 }

        var low = 0.0
        var high = 0.0
        var lowValue = atZero
        var highValue = atZero
        var found = false

        // Expand a bracket in both directions. The step doubles, so the whole legal rate range is
        // covered in a bounded number of probes rather than a scan.
        var step = 1e-6
        var probes = 0
        while step <= maximumPeriodicRate, probes < maximumSolverIterations {
            probes += 1
            for candidate in [step, -step] where candidate > -1 {
                let value = try f(candidate)
                guard value.isFinite else { continue }
                if Swift.abs(value) < solverTolerance { return candidate }
                if (value < 0) != (atZero < 0) {
                    low = Swift.min(0, candidate)
                    high = Swift.max(0, candidate)
                    lowValue = try f(low)
                    highValue = try f(high)
                    found = true
                    break
                }
            }
            if found { break }
            step *= 2
        }
        guard found else { throw TIError.noSignChange }

        var x = (low + high) / 2
        for _ in 0..<maximumSolverIterations {
            let value = try f(x)
            if Swift.abs(value) < solverTolerance { return x }
            if (value < 0) == (lowValue < 0) {
                low = x
                lowValue = value
            } else {
                high = x
                highValue = value
            }
            if high - low < solverTolerance { return x }

            // Secant, but only when it lands strictly inside the bracket the bisection guarantees.
            let secant = highValue == lowValue
                ? Double.nan
                : low - lowValue * (high - low) / (highValue - lowValue)
            x = (secant.isFinite && secant > low && secant < high) ? secant : (low + high) / 2
        }
        throw TIError.iterations
    }

    // MARK: - Cash flows

    /// Expands a grouped cash-flow list into one flow per period, as the TI's `CFFreq` does.
    static func expand(_ flows: [Double], frequencies: [Double]?) throws -> [Double] {
        guard let frequencies else { return flows }
        guard frequencies.count == flows.count else { throw TIError.dimensionMismatch }
        var expanded: [Double] = []
        for (flow, frequency) in zip(flows, frequencies) {
            guard frequency >= 0, frequency == frequency.rounded(), frequency.isFinite else {
                throw TIError.domain
            }
            let repeats = Int(frequency)
            guard expanded.count + repeats <= maximumPeriods else { throw TIError.invalidDimension }
            expanded.append(contentsOf: Array(repeating: flow, count: repeats))
        }
        return expanded
    }

    /// `npv(rate, CF0, CFList[, CFFreq])`: the flows discounted back to period zero at a
    /// per-period rate written as a percent.
    public static func netPresentValue(
        rate: Double, initialFlow: Double, flows: [Double], frequencies: [Double]? = nil
    ) throws -> Double {
        let i = rate / 100
        guard i > -1 else { throw TIError.domain }
        return netPresentValue(periodicRate: i, initialFlow: initialFlow,
                               flows: try expand(flows, frequencies: frequencies))
    }

    /// The same sum in terms of a plain periodic rate, which is what `irr(` root-finds on.
    static func netPresentValue(periodicRate i: Double, initialFlow: Double, flows: [Double]) -> Double {
        var total = initialFlow
        var discount = 1.0
        for flow in flows {
            discount /= (1 + i)
            total += flow * discount
        }
        return total
    }

    /// `irr(CF0, CFList[, CFFreq])`: the periodic rate, as a percent, at which the flows are worth
    /// nothing at period zero.
    public static func internalRateOfReturn(
        initialFlow: Double, flows: [Double], frequencies: [Double]? = nil
    ) throws -> Double {
        let expanded = try expand(flows, frequencies: frequencies)
        guard !expanded.isEmpty else { throw TIError.invalidDimension }
        let rate = try findRoot { i in
            netPresentValue(periodicRate: i, initialFlow: initialFlow, flows: expanded)
        }
        return rate * 100
    }

    // MARK: - Amortization

    /// One payment's split into interest and principal, plus the balance it leaves behind.
    public struct AmortizationEntry: Equatable, Sendable {
        public let interest: Double
        public let principal: Double
        public let balance: Double
    }

    /// The amortization schedule from payment 1 through `payment`, under the stored TVM variables.
    ///
    /// Signs follow the TVM equation: a loan is `PV > 0` with `PMT < 0`, so the interest and
    /// principal portions both come back negative, and `ΣPrn + ΣInt` equals the total paid. The
    /// TI rounds each period's interest to the display's decimals before applying it, so
    /// `decimals` is honoured inside the recursion rather than only on the answer.
    public static func schedule(
        through payment: Int, _ variables: FinanceVariables, decimals: Int? = nil
    ) throws -> [AmortizationEntry] {
        guard payment >= 0, payment <= maximumPeriods else { throw TIError.invalidDimension }
        let i = try variables.periodicRate

        // In BEGIN mode the first payment lands before any interest accrues, so it is pure
        // principal and the recursion starts from the balance it leaves.
        var balance = variables.presentValue
        var entries: [AmortizationEntry] = []
        if payment == 0 { return entries }

        for index in 1...payment {
            let interest: Double
            if variables.timing == .begin && index == 1 {
                interest = 0
            } else {
                interest = round(-balance * i, decimals: decimals)
            }
            let principal = variables.payment - interest
            balance += principal
            entries.append(AmortizationEntry(interest: interest, principal: principal, balance: balance))
        }
        return entries
    }

    /// `bal(npmt)`: the balance remaining after `payment` payments.
    public static func balance(after payment: Int, _ variables: FinanceVariables, decimals: Int? = nil) throws -> Double {
        guard payment > 0 else { return variables.presentValue }
        guard let last = try schedule(through: payment, variables, decimals: decimals).last else {
            return variables.presentValue
        }
        return last.balance
    }

    /// `ΣPrn(first, last)` and `ΣInt(first, last)` share this range walk, so the two commands
    /// cannot disagree about which payments a range covers.
    static func range(
        _ first: Int, _ last: Int, _ variables: FinanceVariables, decimals: Int?
    ) throws -> ArraySlice<AmortizationEntry> {
        guard first >= 1, last >= first else { throw TIError.domain }
        let entries = try schedule(through: last, variables, decimals: decimals)
        return entries[(first - 1)..<last]
    }

    public static func sumPrincipal(
        from first: Int, to last: Int, _ variables: FinanceVariables, decimals: Int? = nil
    ) throws -> Double {
        try range(first, last, variables, decimals: decimals).reduce(0) { $0 + $1.principal }
    }

    public static func sumInterest(
        from first: Int, to last: Int, _ variables: FinanceVariables, decimals: Int? = nil
    ) throws -> Double {
        try range(first, last, variables, decimals: decimals).reduce(0) { $0 + $1.interest }
    }

    static func round(_ value: Double, decimals: Int?) -> Double {
        guard let decimals, decimals >= 0, decimals <= 9 else { return value }
        let scale = Foundation.pow(10.0, Double(decimals))
        return (value * scale).rounded() / scale
    }

    // MARK: - Rate conversion

    /// `▸Eff(nominal, periods)`: the effective annual rate a nominal rate compounds to.
    public static func effectiveRate(nominal: Double, periodsPerYear: Double) throws -> Double {
        guard periodsPerYear >= 1, periodsPerYear == periodsPerYear.rounded() else { throw TIError.domain }
        let perPeriod = nominal / 100 / periodsPerYear
        guard perPeriod > -1 else { throw TIError.domain }
        return (Foundation.pow(1 + perPeriod, periodsPerYear) - 1) * 100
    }

    /// `▸Nom(effective, periods)`: the inverse of `effectiveRate`.
    public static func nominalRate(effective: Double, periodsPerYear: Double) throws -> Double {
        guard periodsPerYear >= 1, periodsPerYear == periodsPerYear.rounded() else { throw TIError.domain }
        let annual = effective / 100
        guard 1 + annual > 0 else { throw TIError.domain }
        return (Foundation.pow(1 + annual, 1 / periodsPerYear) - 1) * periodsPerYear * 100
    }

    // MARK: - Dates

    /// A date as the TI writes it on the entry line: `MM.DDYY`, e.g. `12.3190` is 31 December 1990.
    ///
    /// Parsing is arithmetic on the entered number, not a calendar lookup — nothing here reads
    /// the clock or a locale, so `dbd(` is as deterministic as every other function in the module.
    struct EnteredDate: Equatable {
        let year: Int
        let month: Int
        let day: Int

        init(_ entered: Double) throws {
            guard entered.isFinite, entered > 0 else { throw TIError.domain }
            // MM.DDYY: the integer part is the month, the four fractional digits are DDYY.
            let month = Int(entered.rounded(.down))
            let fraction = ((entered - Double(month)) * 10_000).rounded()
            guard month >= 1, month <= 12, fraction >= 0, fraction <= 9999 else { throw TIError.domain }
            let day = Int(fraction) / 100
            let twoDigitYear = Int(fraction) % 100
            // The TI's window is 1950-2049, so a two-digit year has one reading.
            let year = twoDigitYear >= 50 ? 1900 + twoDigitYear : 2000 + twoDigitYear
            guard day >= 1, day <= Self.daysInMonth(month: month, year: year) else { throw TIError.domain }
            self.year = year
            self.month = month
            self.day = day
        }

        static func isLeapYear(_ year: Int) -> Bool {
            (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        }

        static func daysInMonth(month: Int, year: Int) -> Int {
            switch month {
            case 1, 3, 5, 7, 8, 10, 12: 31
            case 4, 6, 9, 11: 30
            default: isLeapYear(year) ? 29 : 28
            }
        }

        /// The proleptic Gregorian day number, so a difference of two dates is a subtraction.
        var dayNumber: Int {
            // Shift the year so that leap days land at the end of it, which removes the month
            // special-casing from the count.
            let shiftedYear = month <= 2 ? year - 1 : year
            let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
            let yearOfEra = shiftedYear - era * 400
            let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
            let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
            return era * 146_097 + dayOfEra
        }
    }

    /// `dbd(date1, date2)`: the number of days from the first date to the second.
    public static func daysBetween(_ first: Double, _ second: Double) throws -> Double {
        Double(try EnteredDate(second).dayNumber - (try EnteredDate(first).dayNumber))
    }
}

/// One field on the `TVM Solver` screen.
///
/// The screen is generated from this list rather than hand-wired, so the solver's fields, their
/// names and which of them can be solved for are declared exactly once — the same rule the
/// function catalog follows. A view reads labels from here and never spells one.
public enum TVMField: String, Equatable, Hashable, Sendable, CaseIterable {
    case periods
    case ratePercent
    case presentValue
    case payment
    case futureValue
    case paymentsPerYear
    case compoundsPerYear

    /// The TI's own field name.
    public var label: String {
        switch self {
        case .periods: "N"
        case .ratePercent: "I%"
        case .presentValue: "PV"
        case .payment: "PMT"
        case .futureValue: "FV"
        case .paymentsPerYear: "P/Y"
        case .compoundsPerYear: "C/Y"
        }
    }

    /// The five the TVM equation can be solved for; `P/Y` and `C/Y` are settings, not unknowns.
    public static let solvable: [TVMField] = [.periods, .ratePercent, .presentValue, .payment, .futureValue]

    public var isSolvable: Bool { Self.solvable.contains(self) }

    public func value(in variables: FinanceVariables) -> Double {
        switch self {
        case .periods: variables.n
        case .ratePercent: variables.interestPercent
        case .presentValue: variables.presentValue
        case .payment: variables.payment
        case .futureValue: variables.futureValue
        case .paymentsPerYear: variables.paymentsPerYear
        case .compoundsPerYear: variables.compoundsPerYear
        }
    }

    public func setting(_ value: Double, in variables: FinanceVariables) -> FinanceVariables {
        var updated = variables
        switch self {
        case .periods: updated.n = value
        case .ratePercent: updated.interestPercent = value
        case .presentValue: updated.presentValue = value
        case .payment: updated.payment = value
        case .futureValue: updated.futureValue = value
        case .paymentsPerYear: updated.paymentsPerYear = value
        case .compoundsPerYear: updated.compoundsPerYear = value
        }
        return updated
    }
}

extension Finance {
    /// Solves the TVM equation for one field and returns the scenario with that field filled in.
    ///
    /// This is the *only* place that decides which solve a chosen unknown maps to. The solver
    /// screen and the entry-line `tvm_…(` commands both come here, so there is one implementation
    /// and two callers rather than a second solver living in a view.
    public static func solve(for field: TVMField, _ variables: FinanceVariables) throws -> FinanceVariables {
        let solved: Double
        switch field {
        case .periods: solved = try periods(variables)
        case .ratePercent: solved = try interestPercent(variables)
        case .presentValue: solved = try presentValue(variables)
        case .payment: solved = try payment(variables)
        case .futureValue: solved = try futureValue(variables)
        case .paymentsPerYear, .compoundsPerYear: throw TIError.domain
        }
        return field.setting(solved, in: variables)
    }
}
