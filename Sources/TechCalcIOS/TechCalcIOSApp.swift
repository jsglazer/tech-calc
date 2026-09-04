import SwiftUI
import TechCalcCore
import TechCalcUI

/// The iOS shell. It must compile and launch; it is not a v1 ship target.
@main
struct TechCalcIOSApp: App {
    var body: some Scene {
        WindowGroup {
            CalculatorScreen(model: CalculatorModel.makeDefault())
        }
    }
}
