import Foundation
import Observation
import TechCalcCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// The view model: it owns the edit buffer, the keypad latch and the `Calculator`, and forwards
/// every question of arithmetic, formatting or statistics to TechCalcCore. No computation of any
/// kind happens in this file or in the views that observe it.
@Observable
@MainActor
public final class CalculatorModel {
    public private(set) var calculator: Calculator
    public private(set) var buffer = EditBuffer()
    public private(set) var keypad = KeypadState()
    /// Cursor into `2ND ENTRY` recall; -1 means "not recalling".
    private var recallIndex = -1

    /// The `STAT TESTS` screen's state: which form is open, what has been typed into it, and what
    /// the last run produced. The values and the result are TechCalcCore types — the screen keeps
    /// no parallel copy of a statistic.
    public var selectedFormID: FunctionID = StatForms.all[0].id
    public var formValues = StatFormValues()
    public private(set) var formReport: StatFormReport?
    public private(set) var formErrorName: String?
    /// The TVM solver screen's last error, shown in place of a result.
    public private(set) var financeErrorName: String?

    private let store: DocumentStore?

    public init(calculator: Calculator, store: DocumentStore? = nil) {
        self.calculator = calculator
        self.store = store
    }

    /// The app's standard wiring: a seeded generator and a file-backed document.
    public static func makeDefault() -> CalculatorModel {
        let random = SeededRandomSource(seed: 0x5445_4348_4341_4C43)
        guard let provider = try? FileStorageProvider.applicationSupport() else {
            return CalculatorModel(calculator: Calculator(random: random))
        }
        let store = DocumentStore(provider: provider)
        let calculator = (try? Calculator.loaded(from: store, random: random)) ?? Calculator(random: random)
        return CalculatorModel(calculator: calculator, store: store)
    }

    public var entries: [HistoryEntry] { calculator.history.entries }
    public var entryText: String { buffer.text }
    public var modifier: KeypadModifier { keypad.modifier }
    public var mode: CalculatorMode {
        get { calculator.mode }
        set { calculator.mode = newValue; persist() }
    }

    // MARK: - Input

    public func type(_ text: String) {
        buffer.insert(text)
    }

    public func setEntryText(_ text: String) {
        buffer.replace(with: text)
    }

    public func press(_ key: KeypadKey) {
        let result = keypad.press(key)
        if let token = result.token {
            buffer.insert(token)
        }
    }

    public func backspace() {
        buffer.backspace()
    }

    public func clear() {
        buffer.clear()
        keypad.clear()
        recallIndex = -1
    }

    /// ENTER.
    public func submit() {
        let input = buffer.text
        guard !input.isEmpty else { return }
        calculator.enter(input)
        buffer.clear()
        keypad.clear()
        recallIndex = -1
        persist()
    }

    /// `2ND ENTRY`: step back through previous inputs.
    public func recallPreviousEntry() {
        let inputs = calculator.history.recallableInputs
        guard !inputs.isEmpty else { return }
        recallIndex = min(recallIndex + 1, inputs.count - 1)
        buffer.replace(with: inputs[recallIndex])
    }

    /// Tapping a history row puts it back on the entry line.
    public func insert(entry: HistoryEntry, useResult: Bool) {
        buffer.replace(with: useResult ? entry.display : entry.input)
    }

    public func clearHistory() {
        calculator.clearHistory()
        persist()
    }

    // MARK: - Typesetting

    /// The typeset shape of an entry line, and of the result beside it. Both are built by
    /// TechCalcCore from the evaluator's own AST; the view draws what comes back and computes
    /// nothing of its own.
    public func inputNode(for entry: HistoryEntry) -> TypesetNode? {
        TypesetBuilder(formatter: calculator.formatter).node(forInput: entry.input)
    }

    public func resultNode(for entry: HistoryEntry) -> TypesetNode? {
        entry.result.map { TypesetBuilder(formatter: calculator.formatter).node(for: $0.value) }
    }

    // MARK: - Export

    /// Copy as LaTeX, for one row or for the whole pane.
    public func latex(for entry: HistoryEntry) -> String {
        HistoryExport.latex(for: entry, formatter: calculator.formatter)
    }

    public var markdownExport: String {
        HistoryExport.markdown(for: entries, formatter: calculator.formatter)
    }

    /// The one place this module touches a pasteboard. It carries a string the core produced.
    public func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    // MARK: - Lists and matrices

    public var lists: [ListName: TIList] { calculator.lists }
    public var matrices: [MatrixName: TIMatrix] { calculator.matrices }

    public func list(_ name: ListName) -> TIList {
        calculator.context.list(name)
    }

    public func setList(_ name: ListName, values: [Double]) {
        calculator.lists[name] = TIList(reals: values)
        persist()
    }

    public func matrix(_ name: MatrixName) -> TIMatrix? {
        calculator.matrices[name]
    }

    /// Resizing and editing both go through `TIMatrix`, whose 1-based accessor is the single
    /// index boundary; the editor never indexes storage itself.
    public func resizeMatrix(_ name: MatrixName, rows: Int, columns: Int) {
        guard let resized = try? TIMatrix(rows: rows, columns: columns) else { return }
        var updated = resized
        if let existing = calculator.matrices[name] {
            for row in 1...rows where row <= existing.rows {
                for column in 1...columns where column <= existing.columns {
                    guard let value = try? existing[tiRow: row, tiColumn: column] else { continue }
                    try? updated.set(tiRow: row, tiColumn: column, to: value)
                }
            }
        }
        calculator.matrices[name] = updated
        persist()
    }

    public func setMatrixElement(_ name: MatrixName, row: Int, column: Int, to value: Double) {
        guard var matrix = calculator.matrices[name] else { return }
        try? matrix.set(tiRow: row, tiColumn: column, to: Complex(value))
        calculator.matrices[name] = matrix
        persist()
    }

    // MARK: - The TVM solver screen

    public var finance: FinanceVariables {
        get { calculator.context.finance }
        set { calculator.context.finance = newValue; persist() }
    }

    /// Solves for one field. The screen chooses the unknown; `Finance` does every bit of the
    /// arithmetic and owns the only mapping from an unknown to a solve.
    public func solveTVM(for field: TVMField) {
        do {
            calculator.context.finance = try Finance.solve(for: field, calculator.context.finance)
            financeErrorName = nil
            persist()
        } catch let error as TIError {
            financeErrorName = error.tiName
        } catch {
            financeErrorName = TIError.syntax.tiName
        }
    }

    // MARK: - The STAT TESTS screens

    /// Runs a form. The result rows are the procedure's own published variables, so the screen and
    /// the entry line report the same numbers.
    public func runForm(_ id: FunctionID) {
        do {
            let report = try StatForms.run(id, values: formValues, context: calculator.context)
            formReport = report
            formErrorName = nil
            // A form result publishes to VARS ▸ Statistics exactly as the command form does.
            calculator.context.statistics.publish(report.published)
        } catch let error as TIError {
            formReport = nil
            formErrorName = error.tiName
        } catch {
            formReport = nil
            formErrorName = TIError.syntax.tiName
        }
    }

    public func selectForm(_ id: FunctionID) {
        selectedFormID = id
        formReport = nil
        formErrorName = nil
    }

    private func persist() {
        guard let store else { return }
        try? calculator.save(to: store)
    }
}
