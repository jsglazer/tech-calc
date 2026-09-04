import Foundation

/// The whole calculator as one pure value type: parse, evaluate, format, record.
///
/// This is what the app shells drive. It reads no clock, touches no filesystem and holds no
/// global state, so a sequence of `enter(_:)` calls is fully reproducible.
public struct Calculator: Sendable {
    public var context: EvaluationContext
    public private(set) var history: HistoryLog

    private let random: RandomSource

    public init(
        context: EvaluationContext = EvaluationContext(),
        history: HistoryLog = HistoryLog(),
        random: RandomSource
    ) {
        self.context = context
        self.history = history
        self.random = random
    }

    /// `L1`-`L6` and the named lists. They live in the evaluation context — the evaluator reads
    /// and writes them during a `STO▸` — and are surfaced here for the list editor.
    public var lists: [ListName: TIList] {
        get { context.lists }
        set { context.lists = newValue }
    }

    /// `[A]`-`[J]`, likewise owned by the evaluation context.
    public var matrices: [MatrixName: TIMatrix] {
        get { context.matrices }
        set { context.matrices = newValue }
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
        // Container names round-trip through their canonical `key`, so the stored spelling of a
        // list or matrix is decided in exactly one place.
        var lists: [String: TIList] = [:]
        for (name, list) in context.lists {
            lists[name.key] = list
        }
        var matrices: [String: TIMatrix] = [:]
        for (name, matrix) in context.matrices {
            matrices[name.key] = matrix
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
        // A key the current build does not recognise is dropped rather than failing the load:
        // an older or newer document still opens.
        var lists: [ListName: TIList] = [:]
        for (key, list) in document.lists {
            guard let name = ListName(key: key) else { continue }
            lists[name] = list
        }
        var matrices: [MatrixName: TIMatrix] = [:]
        for (key, matrix) in document.matrices {
            guard let name = MatrixName(key: key) else { continue }
            matrices[name] = matrix
        }
        let context = EvaluationContext(
            mode: document.mode,
            variables: variables,
            ans: document.ans,
            lists: lists,
            matrices: matrices
        )
        return Calculator(context: context, history: document.history, random: random)
    }

    public func save(to store: DocumentStore) throws {
        try store.save(document())
    }

    public static func loaded(from store: DocumentStore, random: RandomSource) throws -> Calculator {
        restored(from: try store.load(), random: random)
    }
}
