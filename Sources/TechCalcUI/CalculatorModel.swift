import Foundation
import Observation
import TechCalcCore

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

    private func persist() {
        guard let store else { return }
        try? calculator.save(to: store)
    }
}
