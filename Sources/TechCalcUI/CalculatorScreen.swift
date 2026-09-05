import SwiftUI
import TechCalcCore

/// The app's screens, behind one sidebar.
///
/// macOS is the v1 ship target; platform differences stay inside `#if os(...)`. The iOS layout
/// only has to compile and launch.
public enum Screen: String, CaseIterable, Identifiable, Hashable {
    case calculator = "Calculator"
    case lists = "Lists"
    case matrices = "Matrices"
    case statTests = "Stat Tests"
    case finance = "Finance"
    case mode = "Mode"

    public var id: String { rawValue }

    var symbol: String {
        switch self {
        case .calculator: "function"
        case .lists: "list.number"
        case .matrices: "tablecells"
        case .statTests: "chart.bar"
        case .finance: "dollarsign.circle"
        case .mode: "gearshape"
        }
    }
}

public struct CalculatorScreen: View {
    @State private var model: CalculatorModel
    @State private var screen: Screen = .calculator

    public init(model: CalculatorModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            #if os(macOS)
            List(Screen.allCases, selection: $screen) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            #else
            // iOS has no sidebar selection binding on a plain List, so the rows are buttons. The
            // detail switch below is unchanged: only the way a row is chosen differs.
            List {
                ForEach(Screen.allCases) { item in
                    Button { screen = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                    }
                }
            }
            #endif
        } detail: {
            switch screen {
            case .calculator: CalculatorPane(model: model)
            case .lists: ListEditorScreen(model: model)
            case .matrices: MatrixEditorScreen(model: model)
            case .statTests: StatTestsScreen(model: model)
            case .finance: TVMSolverScreen(model: model)
            case .mode: ModeScreen(model: model)
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
    }
}

/// The calculator surface: history above, entry line below, keypad at the bottom.
struct CalculatorPane: View {
    let model: CalculatorModel

    var body: some View {
        VStack(spacing: 0) {
            HistoryPane(model: model)
            Divider()
            EntryLine(model: model)
            Divider()
            KeypadGrid(model: model)
        }
        .navigationTitle("TechCalc")
        .toolbar {
            ToolbarItem {
                Button("Copy as Markdown") { model.copyToPasteboard(model.markdownExport) }
            }
        }
    }
}

/// The result history, typeset.
///
/// Each row draws the shape TechCalcCore laid out from the evaluator's own AST. A row that could
/// not be parsed back — or that errored — falls back to the plain text the calculator showed, so
/// nothing is ever blank.
struct HistoryPane: View {
    let model: CalculatorModel

    private let entryFontSize: CGFloat = 13
    private let resultFontSize: CGFloat = 17

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 10) {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .trailing, spacing: 2) {
                            typeset(model.inputNode(for: entry), fallback: entry.input, size: entryFontSize)
                                .foregroundStyle(.secondary)
                                .onTapGesture { model.insert(entry: entry, useResult: false) }

                            typeset(model.resultNode(for: entry), fallback: entry.display, size: resultFontSize)
                                .foregroundStyle(entry.isError ? Color.red : Color.primary)
                                .onTapGesture { model.insert(entry: entry, useResult: true) }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contextMenu {
                            Button("Copy as LaTeX") { model.copyToPasteboard(model.latex(for: entry)) }
                        }
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

    @ViewBuilder
    private func typeset(_ node: TypesetNode?, fallback: String, size: CGFloat) -> some View {
        if let node {
            TypesetMathView(node: node, fontSize: size)
        } else {
            Text(fallback)
                .font(.system(size: size, design: .monospaced))
                .textSelection(.enabled)
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
