import SwiftUI
import TechCalcCore

/// The `FINANCE ▸ TVM Solver` screen.
///
/// It is a form over `TVMField` and a button that calls `Finance.solve`. It does not know the TVM
/// equation, does not decide what a blank field means, and does not hold a second copy of the
/// scenario — the fields it edits are the same `EvaluationContext.finance` the `tvm_…(` commands
/// read, which is what makes the screen and the entry line two callers of one implementation.
public struct TVMSolverScreen: View {
    @Bindable private var model: CalculatorModel
    @State private var unknown: TVMField = .payment

    public init(model: CalculatorModel) {
        _model = Bindable(wrappedValue: model)
    }

    public var body: some View {
        Form {
            Section("Solve for") {
                Picker("Unknown", selection: $unknown) {
                    ForEach(TVMField.solvable, id: \.self) { field in
                        Text(field.label).tag(field)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Values") {
                ForEach(TVMField.allCases, id: \.self) { field in
                    LabeledContent(field.label) {
                        TextField(field.label, value: binding(for: field), format: .number)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                            .disabled(field == unknown)
                    }
                }
                Picker("Timing", selection: Binding(
                    get: { model.finance.timing },
                    set: { model.finance.timing = $0 }
                )) {
                    ForEach(PaymentTiming.allCases, id: \.self) { timing in
                        Text(timing.rawValue.uppercased()).tag(timing)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Solve") { model.solveTVM(for: unknown) }
                if let error = model.financeErrorName {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.system(.body, design: .monospaced))
                } else {
                    LabeledContent(unknown.label) {
                        Text(unknown.value(in: model.finance), format: .number)
                            .font(.system(.body, design: .monospaced).bold())
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("TVM Solver")
    }

    private func binding(for field: TVMField) -> Binding<Double> {
        Binding(
            get: { field.value(in: model.finance) },
            set: { model.finance = field.setting($0, in: model.finance) }
        )
    }
}
