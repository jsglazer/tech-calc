import Foundation

/// The finance and number-base half of the evaluator.
///
/// As with the statistics half, this file is a thin argument reader in front of pure functions —
/// every number below comes out of `Finance` or `NumberBases`, and no financial or bitwise
/// arithmetic is performed here. That is what lets the TVM solver screen and the entry-line
/// `tvm_…(` commands be two callers of one implementation.
///
/// The split mirrors the statistics one:
///
///   * `applyFinanceFunction` is non-mutating — every finance and bitwise entry computes a value
///     and changes nothing, so `bal(` and `bitAnd(` are as pure as `sin(`.
///   * the TVM commands read `context.finance` for the fields the caller left out, which is the
///     hardware's behaviour: the solver screen fills the fields, the command names the unknown.
extension Evaluator {

    // MARK: - Argument readers

    private func financeNumber(_ values: [TIValue], _ index: Int) throws -> Double {
        guard values.indices.contains(index) else { throw TIError.syntax }
        return try values[index].asReal
    }

    /// An argument the caller may omit, in which case the stored TVM field stands in.
    private func financeNumber(_ values: [TIValue], _ index: Int, or stored: Double) throws -> Double {
        values.indices.contains(index) ? try values[index].asReal : stored
    }

    private func financeCount(_ values: [TIValue], _ index: Int) throws -> Int {
        guard values.indices.contains(index) else { throw TIError.syntax }
        return try values[index].asInteger
    }

    /// The optional trailing rounding argument the amortization commands take.
    private func financeDecimals(_ values: [TIValue], _ index: Int) throws -> Int? {
        guard values.indices.contains(index) else { return nil }
        return try values[index].asInteger
    }

    private func cashFlows(_ values: [TIValue], _ index: Int) throws -> [Double] {
        guard values.indices.contains(index), case .list(let list) = values[index] else {
            throw TIError.dataType
        }
        return try ListMath.realValues(list.values)
    }

    private func optionalCashFlows(_ values: [TIValue], _ index: Int) throws -> [Double]? {
        guard values.indices.contains(index) else { return nil }
        return try cashFlows(values, index)
    }

    /// The stored TVM fields with the arguments a `tvm_…(` call supplied written over them.
    ///
    /// All five commands take the same six trailing fields in the same order, minus the one they
    /// solve for, so the override table is written once and the caller says which slot to skip.
    private func tvmVariables(solvingFor unknown: FunctionID, _ values: [TIValue]) throws -> FinanceVariables {
        var variables = context.finance
        // The argument order of every `tvm_…(` entry: N, I%, PV, PMT, FV, P/Y, C/Y with the
        // unknown removed. Walking it in order keeps the positions in step with the catalog's
        // `argumentLabels`, which is the only other place this ordering is written down.
        var position = 0
        func next(_ stored: Double) throws -> Double {
            defer { position += 1 }
            return try financeNumber(values, position, or: stored)
        }
        if unknown != .tvmN { variables.n = try next(variables.n) }
        if unknown != .tvmInterest { variables.interestPercent = try next(variables.interestPercent) }
        if unknown != .tvmPresentValue { variables.presentValue = try next(variables.presentValue) }
        if unknown != .tvmPayment { variables.payment = try next(variables.payment) }
        if unknown != .tvmFutureValue { variables.futureValue = try next(variables.futureValue) }
        variables.paymentsPerYear = try next(variables.paymentsPerYear)
        variables.compoundsPerYear = try next(variables.compoundsPerYear)
        return variables
    }

    // MARK: - FINANCE and MATH BASE

    func applyFinanceFunction(_ id: FunctionID, _ values: [TIValue]) throws -> TIValue? {
        switch id {
        // MARK: The TVM solver
        case .tvmN:
            return .real(try Finance.periods(try tvmVariables(solvingFor: id, values)))
        case .tvmInterest:
            return .real(try Finance.interestPercent(try tvmVariables(solvingFor: id, values)))
        case .tvmPresentValue:
            return .real(try Finance.presentValue(try tvmVariables(solvingFor: id, values)))
        case .tvmPayment:
            return .real(try Finance.payment(try tvmVariables(solvingFor: id, values)))
        case .tvmFutureValue:
            return .real(try Finance.futureValue(try tvmVariables(solvingFor: id, values)))

        // MARK: Cash flows
        case .netPresentValue:
            return .real(try Finance.netPresentValue(
                rate: try financeNumber(values, 0), initialFlow: try financeNumber(values, 1),
                flows: try cashFlows(values, 2), frequencies: try optionalCashFlows(values, 3)))
        case .internalRateOfReturn:
            return .real(try Finance.internalRateOfReturn(
                initialFlow: try financeNumber(values, 0), flows: try cashFlows(values, 1),
                frequencies: try optionalCashFlows(values, 2)))

        // MARK: Amortization, against the stored TVM fields
        case .amortizationBalance:
            return .real(try Finance.balance(
                after: try financeCount(values, 0), context.finance,
                decimals: try financeDecimals(values, 1)))
        case .amortizationPrincipal:
            return .real(try Finance.sumPrincipal(
                from: try financeCount(values, 0), to: try financeCount(values, 1),
                context.finance, decimals: try financeDecimals(values, 2)))
        case .amortizationInterest:
            return .real(try Finance.sumInterest(
                from: try financeCount(values, 0), to: try financeCount(values, 1),
                context.finance, decimals: try financeDecimals(values, 2)))

        // MARK: Rate conversion and dates
        case .toNominalRate:
            return .real(try Finance.nominalRate(
                effective: try financeNumber(values, 0), periodsPerYear: try financeNumber(values, 1)))
        case .toEffectiveRate:
            return .real(try Finance.effectiveRate(
                nominal: try financeNumber(values, 0), periodsPerYear: try financeNumber(values, 1)))
        case .daysBetweenDates:
            return .real(try Finance.daysBetween(
                try financeNumber(values, 0), try financeNumber(values, 1)))

        // MARK: The bitwise operators, which are distinct from the boolean ones (D22)
        case .bitwiseAnd:
            return .real(try NumberBases.and(try financeNumber(values, 0), try financeNumber(values, 1)))
        case .bitwiseOr:
            return .real(try NumberBases.or(try financeNumber(values, 0), try financeNumber(values, 1)))
        case .bitwiseXor:
            return .real(try NumberBases.xor(try financeNumber(values, 0), try financeNumber(values, 1)))
        case .bitwiseNot:
            return .real(try NumberBases.not(try financeNumber(values, 0)))

        default:
            return nil
        }
    }

    /// A base conversion is presentation only, but it is presentation that can fail: a value that
    /// is not a 32-bit integer has no binary, octal or hexadecimal spelling.
    ///
    /// Rejecting it here, at evaluation, is what keeps the formatter total — the display layer
    /// never has to invent an answer for a number it cannot write.
    func validateBaseConversion(_ id: FunctionID, _ value: TIValue) throws {
        guard NumberBases.isBaseConversion(id) else { return }
        _ = try NumberBases.integer(try value.asReal)
    }
}
