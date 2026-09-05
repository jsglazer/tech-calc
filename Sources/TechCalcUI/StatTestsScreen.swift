import SwiftUI
import TechCalcCore

/// The `STAT TESTS` screens.
///
/// There is one view for seventeen procedures because a form is data: `StatForms` declares which
/// fields a procedure collects and `StatForms.run` performs it. This file switches on a field's
/// declared control kind and on nothing else — no procedure is named here, no default is chosen
/// here, and no statistic is computed here.
public struct StatTestsScreen: View {
    @Bindable private var model: CalculatorModel

    public init(model: CalculatorModel) {
        _model = Bindable(wrappedValue: model)
    }

    private var definition: StatFormDefinition? {
        StatForms.definition(for: model.selectedFormID)
    }

    public var body: some View {
        Form {
            Section("Procedure") {
                Picker("Procedure", selection: Binding(
                    get: { model.selectedFormID },
                    set: { model.selectForm($0) }
                )) {
                    ForEach(StatForms.all, id: \.id) { form in
                        Text(form.title).tag(form.id)
                    }
                }
            }

            if let definition {
                Section("Inputs") {
                    ForEach(definition.fields, id: \.self) { field in
                        StatFieldRow(model: model, field: field)
                    }
                }

                Section {
                    Button("Calculate") { model.runForm(definition.id) }
                    if let error = model.formErrorName {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if let report = model.formReport {
                    Section("Results") {
                        ForEach(report.rows, id: \.variable) { row in
                            LabeledContent(row.label) {
                                Text(row.value, format: .number)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Stat Tests")
    }
}

/// One input row. The control is chosen by the field's declared kind.
struct StatFieldRow: View {
    @Bindable var model: CalculatorModel
    let field: StatFormField

    var body: some View {
        switch field.kind {
        case .number, .level:
            LabeledContent(field.label) {
                TextField(field.label, value: number, format: .number)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            }

        case .alternative:
            Picker(field.label, selection: alternative) {
                ForEach(Alternative.allCases, id: \.self) { choice in
                    Text(Self.symbol(for: choice)).tag(choice)
                }
            }
            .pickerStyle(.segmented)

        case .flag:
            Toggle(field.label, isOn: Binding(
                get: { model.formValues[field] != 0 },
                set: { model.formValues[field] = $0 ? 1 : 0 }
            ))

        case .list:
            Picker(field.label, selection: Binding(
                get: { model.formValues.list(field) },
                set: { model.formValues.lists[field] = $0 }
            )) {
                ForEach(ListName.numberedNames, id: \.self) { name in
                    Text(name.key).tag(name)
                }
            }

        case .matrix:
            Picker(field.label, selection: $model.formValues.matrix) {
                ForEach(MatrixName.all, id: \.self) { name in
                    Text(name.key).tag(name)
                }
            }
        }
    }

    private var number: Binding<Double> {
        Binding(
            get: { model.formValues[field] },
            set: { model.formValues[field] = $0 }
        )
    }

    private var alternative: Binding<Alternative> {
        Binding(
            get: { (try? Alternative(code: Int(model.formValues[field]))) ?? .twoSided },
            set: { model.formValues[field] = Double($0.rawValue) }
        )
    }

    /// The TI's own three alternatives, as the tail symbols the form shows.
    static func symbol(for alternative: Alternative) -> String {
        switch alternative {
        case .twoSided: "\u{2260}"
        case .less: "<"
        case .greater: ">"
        }
    }
}
