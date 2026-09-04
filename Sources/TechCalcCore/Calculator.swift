import Foundation

/// The whole calculator as one pure value type: parse, evaluate, format, record.
///
/// This is what the app shells drive. It reads no clock, touches no filesystem and holds no
/// global state, so a sequence of `enter(_:)` calls is fully reproducible.
public struct Calculator: Sendable {
    public var context: EvaluationContext
    public private(set) var history: HistoryLog
    /// `L1`-`L6` and named lists. Persisted here from M1 so a document written now still opens
    /// once the list editor lands.
    public var lists: [String: TIList]
    /// `[A]`-`[J]`.
    public var matrices: [String: TIMatrix]

    private let random: RandomSource

    public init(
        context: EvaluationContext = EvaluationContext(),
        history: HistoryLog = HistoryLog(),
        lists: [String: TIList] = [:],
        matrices: [String: TIMatrix] = [:],
        random: RandomSource
    ) {
        self.context = context
        self.history = history
        self.lists = lists
        self.matrices = matrices
        self.random = random
    }

    public var mode: CalculatorMode {
        get { context.mode }
        set { context.mode = newValue }
    }

    public var formatter: DisplayFormatter { DisplayFormatter(mode: context.mode) }

    // MARK: - Entry

    /// Evaluates one input line and records it in the history, exactly as pressing ENTER does.
    /// Errors are recorded as rows rather than thrown, because the TI shows them on screen.
    @discardableResult
    public mutating func enter(_ input: String) -> HistoryEntry {
        do {
            let value = try evaluate(input)
            let display = displayString(for: value.result, conversion: value.conversion)
            context.ans = TIValueSnapshot(value.result)
            return history.append(input: input, result: context.ans, display: display)
        } catch let error as TIError {
            return history.append(input: input, result: nil, display: error.tiName, errorName: error.tiName)
        } catch {
            return history.append(input: input, result: nil, display: TIError.syntax.tiName, errorName: TIError.syntax.tiName)
        }
    }

    /// Evaluates without recording, for callers that only want the value (`MODE` previews, tests).
    public mutating func evaluate(_ input: String) throws -> (result: TIValue, conversion: FunctionID?) {
        let parsed = try Parser.parse(input)
        var evaluator = Evaluator(context: context, random: random)
        let result = try evaluator.evaluate(parsed.expression)
        context = evaluator.context

        // REAL mode rejects a complex answer; it never changes what was computed.
        if case .complex = result, context.mode.complex == .real {
            throw TIError.nonrealAnswer
        }
        return (result, Self.displayConversion(of: parsed.expression))
    }

    public mutating func clearHistory() {
        history.clear()
    }

    // MARK: - Presentation

    /// The postfix presentation mark at the root of the entry, if any.
    static func displayConversion(of expression: Expression) -> FunctionID? {
        switch expression {
        case .displayConversion(let id, _): id
        case .store(let inner, _): displayConversion(of: inner)
        default: nil
        }
    }

    func displayString(for value: TIValue, conversion: FunctionID?) -> String {
        var effectiveMode = context.mode
        switch conversion {
        case .toRectangular: effectiveMode.complex = .rectangular
        case .toPolar: effectiveMode.complex = .polar
        default: break
        }
        let formatter = DisplayFormatter(mode: effectiveMode)

        let wantsFraction = conversion == .toFraction
            || (conversion != .toDecimal && context.mode.answer == .fraction)
        return wantsFraction ? formatter.fractionString(for: value) : formatter.string(for: value)
    }

    // MARK: - Persistence

    /// A snapshot of everything `state.json` carries.
    public func document() -> CalculatorDocument {
        var variables: [String: Complex] = [:]
        for (name, value) in context.variables {
            variables[String(name)] = value
        }
        return CalculatorDocument(
            mode: context.mode,
            variables: variables,
            ans: context.ans,
            lists: lists,
            matrices: matrices,
            history: history
        )
    }

    /// Restores a calculator from a stored document.
    public static func restored(from document: CalculatorDocument, random: RandomSource) -> Calculator {
        var variables: [Character: Complex] = [:]
        for (name, value) in document.variables {
            guard let character = name.first, name.count == 1,
                  EvaluationContext.isVariableName(character) else { continue }
            variables[character] = value
        }
        let context = EvaluationContext(mode: document.mode, variables: variables, ans: document.ans)
        return Calculator(
            context: context,
            history: document.history,
            lists: document.lists,
            matrices: document.matrices,
            random: random
        )
    }

    public func save(to store: DocumentStore) throws {
        try store.save(document())
    }

    public static func loaded(from store: DocumentStore, random: RandomSource) throws -> Calculator {
        restored(from: try store.load(), random: random)
    }
}
