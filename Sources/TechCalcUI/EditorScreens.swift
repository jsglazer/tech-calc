import SwiftUI
import TechCalcCore

/// The `STAT ▸ EDIT` list editor.
///
/// The lists it edits are the calculator's own `L1`-`L6`; every write goes through the model,
/// which hands it to `TIList`. Nothing here indexes storage: the 1-based/0-based boundary stays
/// in the one accessor TechCalcCore declares it in.
public struct ListEditorScreen: View {
    @Bindable private var model: CalculatorModel
    @State private var name: ListName = ListName.numberedNames[0]
    @State private var text = ""

    public init(model: CalculatorModel) {
        _model = Bindable(wrappedValue: model)
    }

    public var body: some View {
        Form {
            Section("List") {
                Picker("List", selection: $name) {
                    ForEach(ListName.numberedNames, id: \.self) { list in
                        Text(list.key).tag(list)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: name) { text = entryText(for: name) }
            }

            Section("Elements") {
                // The list is edited as an entry line, so the same tokenizer and evaluator that
                // read `{1,2,3}` on the keypad read it here too.
                TextField("{1,2,3}", text: $text, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3...8)
                Button("Store") { model.setEntryText(text + storeSuffix); model.submit() }
            }

            Section("Contents") {
                let values = model.list(name).values
                if values.isEmpty {
                    Text("empty").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        LabeledContent("\(index + 1)") {
                            Text(model.calculator.formatter.string(forComplex: value))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("List Editor")
        .onAppear { text = entryText(for: name) }
    }

    private func entryText(for name: ListName) -> String {
        model.calculator.formatter.string(for: .list(model.list(name)))
    }

    /// The store arrow and the target name; both spellings come from TechCalcCore.
    private var storeSuffix: String {
        "\u{2192}" + name.key
    }
}

/// The `MATRX ▸ EDIT` matrix editor: dimensions, then a grid of cells.
public struct MatrixEditorScreen: View {
    @Bindable private var model: CalculatorModel
    @State private var name: MatrixName = MatrixName.all[0]
    @State private var rows = 2
    @State private var columns = 2

    public init(model: CalculatorModel) {
        _model = Bindable(wrappedValue: model)
    }

    public var body: some View {
        Form {
            Section("Matrix") {
                Picker("Matrix", selection: $name) {
                    ForEach(MatrixName.all, id: \.self) { matrix in
                        Text(matrix.key).tag(matrix)
                    }
                }
                .onChange(of: name) { syncDimensions() }
            }

            Section("Dimensions") {
                Stepper("Rows: \(rows)", value: $rows, in: 1...TILimits.maxMatrixDimension)
                Stepper("Columns: \(columns)", value: $columns, in: 1...TILimits.maxMatrixDimension)
                Button("Resize") { model.resizeMatrix(name, rows: rows, columns: columns) }
            }

            if let matrix = model.matrix(name) {
                Section("Elements") {
                    ForEach(1...matrix.rows, id: \.self) { row in
                        HStack {
                            ForEach(1...matrix.columns, id: \.self) { column in
                                TextField("", value: cell(row: row, column: column), format: .number)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minWidth: 60)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Matrix Editor")
        .onAppear { syncDimensions() }
    }

    private func syncDimensions() {
        guard let matrix = model.matrix(name) else { return }
        rows = matrix.rows
        columns = matrix.columns
    }

    private func cell(row: Int, column: Int) -> Binding<Double> {
        Binding(
            get: { (try? model.matrix(name)?[tiRow: row, tiColumn: column])??.re ?? 0 },
            set: { model.setMatrixElement(name, row: row, column: column, to: $0) }
        )
    }
}

/// The `MODE` screen. Every option is a case of a TechCalcCore mode enum, so the screen cannot
/// offer a setting the evaluator does not have.
public struct ModeScreen: View {
    @Bindable private var model: CalculatorModel

    public init(model: CalculatorModel) {
        _model = Bindable(wrappedValue: model)
    }

    public var body: some View {
        Form {
            Section("Angle") {
                Picker("Angle", selection: binding(\.angle)) {
                    ForEach(AngleMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Notation") {
                Picker("Notation", selection: binding(\.notation)) {
                    ForEach(NotationMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Decimals") {
                Toggle("Float", isOn: Binding(
                    get: { model.mode.decimals == .float },
                    set: { model.mode.decimals = $0 ? .float : .fixedClamped(2) }
                ))
                if case .fixed(let places) = model.mode.decimals {
                    Stepper("Places: \(places)", value: Binding(
                        get: { places },
                        set: { model.mode.decimals = .fixedClamped($0) }
                    ), in: 0...9)
                }
            }
            Section("Complex") {
                Picker("Complex", selection: binding(\.complex)) {
                    ForEach(ComplexMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Answers") {
                Picker("Answers", selection: binding(\.answer)) {
                    ForEach(AnswerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Mode")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CalculatorMode, Value>) -> Binding<Value> {
        Binding(
            get: { model.mode[keyPath: keyPath] },
            set: { model.mode[keyPath: keyPath] = $0 }
        )
    }
}
