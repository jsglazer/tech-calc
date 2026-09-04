import SwiftUI
import TechCalcCore

/// The shared calculator surface: history above, entry line below, keypad at the bottom.
///
/// Platform differences are confined to `#if os(...)`. macOS is the v1 ship target; the iOS
/// layout only has to compile and launch.
public struct CalculatorScreen: View {
    @State private var model: CalculatorModel

    public init(model: CalculatorModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HistoryPane(model: model)
            Divider()
            EntryLine(model: model)
            Divider()
            KeypadGrid(model: model)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }
}

/// The readable, selectable result history.
struct HistoryPane: View {
    let model: CalculatorModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 10) {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.input)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .onTapGesture { model.insert(entry: entry, useResult: false) }
                            Text(entry.display)
                                .font(.system(.title3, design: .monospaced))
                                .foregroundStyle(entry.isError ? Color.red : Color.primary)
                                .onTapGesture { model.insert(entry: entry, useResult: true) }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .textSelection(.enabled)
                        .id(entry.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: model.entries.count) {
                if let last = model.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

/// The editable entry line. Typed text and keypad presses land in the same buffer.
struct EntryLine: View {
    let model: CalculatorModel

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: Binding(
                get: { model.entryText },
                set: { model.setEntryText($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(.title3, design: .monospaced))
            .onSubmit { model.submit() }
            #if os(iOS)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif

            if model.modifier != .none {
                Text(model.modifier.rawValue.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
            }

            Button("ENTER") { model.submit() }
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(12)
    }
}

/// The TI-style keypad. Every label and inserted token comes from `KeypadLayout`, which reads
/// `FunctionCatalog` — no function name is spelled in this view.
struct KeypadGrid: View {
    let model: CalculatorModel

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 6)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(KeypadLayout.keys) { key in
                    Button {
                        model.press(key)
                    } label: {
                        Text(label(for: key))
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                }
                Button("DEL") { model.backspace() }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .buttonStyle(.bordered)
                Button("CLEAR") { model.clear() }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .frame(maxHeight: 260)
    }

    private func label(for key: KeypadKey) -> String {
        switch key.role {
        case .secondModifier: "2nd"
        case .alphaModifier: "ALPHA"
        case .token: key.token(on: model.modifier.layer) ?? key.id
        }
    }
}
