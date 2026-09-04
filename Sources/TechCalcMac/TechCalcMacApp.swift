import SwiftUI
import TechCalcCore
import TechCalcUI

/// The macOS shell. It wires the model and hosts the shared screen; it contains no logic.
@main
struct TechCalcMacApp: App {
    var body: some Scene {
        WindowGroup {
            CalculatorScreen(model: CalculatorModel.makeDefault())
        }
        .windowResizability(.contentSize)
    }
}
