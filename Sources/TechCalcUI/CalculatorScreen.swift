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

    /// The screen a keypad menu key asks for. The core names a destination; this is the one
    /// place that says which screen it is.
    init(_ destination: KeypadDestination) {
        switch destination {
        case .calculator: self = .calculator
        case .lists: self = .lists
        case .matrices: self = .matrices
        case .statTests: self = .statTests
        case .finance: self = .finance
        case .mode: self = .mode
        }
    }

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
    @Bindable private var model: CalculatorModel
    @Environment(\.colorScheme) private var systemScheme

    public init(model: CalculatorModel) {
        _model = Bindable(wrappedValue: model)
    }

    /// The screen selection lives on the model because the keypad's menu keys move it too.
    private var palette: CalculatorPalette {
        CalculatorPalette.resolve(theme: model.theme, systemScheme: systemScheme)
    }

    public var body: some View {
        NavigationSplitView {
            #if os(macOS)
            List(Screen.allCases, selection: Binding(
                get: { model.screen },
                set: { model.screen = $0 ?? model.screen }
            )) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            #else
            // iOS has no sidebar selection binding on a plain List, so the rows are buttons. The
            // detail switch below is unchanged: only the way a row is chosen differs.
            List {
                ForEach(Screen.allCases) { item in
                    Button { model.screen = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                    }
                }
            }
            #endif
        } detail: {
            switch model.screen {
            case .calculator: CalculatorPane(model: model)
            case .lists: ListEditorScreen(model: model)
            case .matrices: MatrixEditorScreen(model: model)
            case .statTests: StatTestsScreen(model: model)
            case .finance: TVMSolverScreen(model: model)
            case .mode: ModeScreen(model: model)
            }
        }
        .environment(\.palette, palette)
        .preferredColorScheme(model.theme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 780)
        #endif
    }
}

/// The calculator surface: history above, entry line below, keypad at the bottom.
struct CalculatorPane: View {
    let model: CalculatorModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HistoryPane(model: model)
            Divider()
            EntryLine(model: model)
            KeypadView(model: model)
        }
        .background(palette.background)
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
    @Environment(\.palette) private var palette

    private let entryFontSize: CGFloat = 13
    private let resultFontSize: CGFloat = 17

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 10) {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .trailing, spacing: 2) {
                            typeset(model.inputNode(for: entry), fallback: entry.input, size: entryFontSize)
                                .foregroundStyle(palette.displaySecondaryText)
                                .onTapGesture { model.insert(entry: entry, useResult: false) }

                            typeset(model.resultNode(for: entry), fallback: entry.display, size: resultFontSize)
                                .foregroundStyle(entry.isError ? palette.errorText : palette.displayText)
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
            .background(palette.display)
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
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: Binding(
                get: { model.entryText },
                set: { model.setEntryText($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(.title3, design: .monospaced))
            .foregroundStyle(palette.displayText)
            .onSubmit { model.submit() }
            #if os(iOS)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif

            // The status corner the hardware keeps in its top right: the armed latch, the INS
            // toggle, and the name of the last key pressed that this build does not implement.
            if let unavailable = model.unavailableKeyLabel {
                Text("\(unavailable) — not in this version")
                    .font(.caption)
                    .foregroundStyle(palette.displaySecondaryText)
            }
            if model.isOverwriting {
                statusChip("INS")
            }
            if model.modifier != .none {
                statusChip(model.modifier == .alphaLock ? "A-LOCK" : model.modifier.rawValue.uppercased())
            }
        }
        .padding(12)
        .background(palette.display)
    }

    private func statusChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(palette.display)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette.latchHighlight, in: Capsule())
    }
}

