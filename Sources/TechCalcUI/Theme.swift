import SwiftUI

/// The app's skins.
///
/// `system` follows the OS appearance; the other two pin the app to one look regardless of it.
/// `cyanDark` is the black-and-cyan skin — a dark case with a cyan display, the way a calculator
/// looks with the lights off.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system, light, cyanDark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .cyanDark: "Cyan Dark"
        }
    }

    /// The scheme to force, or `nil` to take the OS's.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .cyanDark: .dark
        }
    }

    /// Whether this theme paints the cyan skin, given what the OS is currently doing.
    func isDark(systemScheme: ColorScheme) -> Bool {
        switch self {
        case .system: systemScheme == .dark
        case .light: false
        case .cyanDark: true
        }
    }
}

/// Every colour the calculator surface uses, resolved once per theme.
///
/// The views read a palette rather than naming colours, so the two skins differ in exactly one
/// place and neither can drift from the other.
public struct CalculatorPalette: Sendable {
    public let background: Color
    public let display: Color
    public let displayText: Color
    public let displaySecondaryText: Color
    public let errorText: Color

    /// The case the keys are set into.
    public let caseFill: Color
    /// The small printed labels above each key.
    public let secondLabel: Color
    public let alphaLabel: Color
    public let inertLabel: Color

    public let functionKey: Color
    public let functionKeyText: Color
    public let digitKey: Color
    public let digitKeyText: Color
    public let arithmeticKey: Color
    public let arithmeticKeyText: Color
    public let navigationKey: Color
    public let secondKey: Color
    public let secondKeyText: Color
    public let alphaKey: Color
    public let alphaKeyText: Color
    public let arrowKey: Color
    public let keyBorder: Color
    /// Ring drawn around the layer a latched modifier has selected.
    public let latchHighlight: Color

    /// The silver-case skin, matching the hardware in daylight.
    public static let light = CalculatorPalette(
        background: Color(white: 0.90),
        display: Color(red: 0.87, green: 0.90, blue: 0.83),
        displayText: Color(white: 0.08),
        displaySecondaryText: Color(white: 0.38),
        errorText: Color(red: 0.72, green: 0.12, blue: 0.12),
        caseFill: Color(white: 0.82),
        secondLabel: Color(red: 0.10, green: 0.30, blue: 0.62),
        alphaLabel: Color(red: 0.62, green: 0.48, blue: 0.10),
        inertLabel: Color(white: 0.55),
        functionKey: Color(white: 0.46),
        functionKeyText: .white,
        digitKey: Color(white: 0.97),
        digitKeyText: Color(red: 0.10, green: 0.16, blue: 0.34),
        arithmeticKey: Color(white: 0.38),
        arithmeticKeyText: .white,
        navigationKey: Color(white: 0.52),
        secondKey: Color(red: 0.13, green: 0.20, blue: 0.36),
        secondKeyText: .white,
        alphaKey: Color(red: 0.93, green: 0.83, blue: 0.42),
        alphaKeyText: Color(white: 0.12),
        arrowKey: Color(white: 0.55),
        keyBorder: Color(white: 0.35).opacity(0.35),
        latchHighlight: Color(red: 0.15, green: 0.45, blue: 0.85)
    )

    /// Black case, cyan everything.
    public static let cyanDark = CalculatorPalette(
        background: Color(red: 0.02, green: 0.03, blue: 0.04),
        display: Color(red: 0.03, green: 0.07, blue: 0.08),
        displayText: Color(red: 0.25, green: 0.94, blue: 1.0),
        displaySecondaryText: Color(red: 0.20, green: 0.60, blue: 0.66),
        errorText: Color(red: 1.0, green: 0.40, blue: 0.46),
        caseFill: Color(red: 0.05, green: 0.07, blue: 0.08),
        secondLabel: Color(red: 0.30, green: 0.85, blue: 0.95),
        alphaLabel: Color(red: 0.35, green: 0.72, blue: 0.62),
        inertLabel: Color(red: 0.28, green: 0.40, blue: 0.43),
        functionKey: Color(red: 0.10, green: 0.14, blue: 0.16),
        functionKeyText: Color(red: 0.55, green: 0.93, blue: 1.0),
        digitKey: Color(red: 0.14, green: 0.20, blue: 0.22),
        digitKeyText: Color(red: 0.45, green: 0.98, blue: 1.0),
        arithmeticKey: Color(red: 0.07, green: 0.11, blue: 0.13),
        arithmeticKeyText: Color(red: 0.55, green: 0.93, blue: 1.0),
        navigationKey: Color(red: 0.09, green: 0.13, blue: 0.15),
        secondKey: Color(red: 0.06, green: 0.30, blue: 0.36),
        secondKeyText: Color(red: 0.65, green: 0.98, blue: 1.0),
        alphaKey: Color(red: 0.08, green: 0.26, blue: 0.24),
        alphaKeyText: Color(red: 0.55, green: 0.98, blue: 0.88),
        arrowKey: Color(red: 0.10, green: 0.15, blue: 0.17),
        keyBorder: Color(red: 0.20, green: 0.65, blue: 0.72).opacity(0.35),
        latchHighlight: Color(red: 0.25, green: 0.94, blue: 1.0)
    )

    public static func resolve(theme: AppTheme, systemScheme: ColorScheme) -> CalculatorPalette {
        theme.isDark(systemScheme: systemScheme) ? .cyanDark : .light
    }
}

private struct CalculatorPaletteKey: EnvironmentKey {
    static let defaultValue = CalculatorPalette.light
}

extension EnvironmentValues {
    var palette: CalculatorPalette {
        get { self[CalculatorPaletteKey.self] }
        set { self[CalculatorPaletteKey.self] = newValue }
    }
}
