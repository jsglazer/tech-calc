import Foundation

/// Angle unit for trigonometric arguments and inverse-trig results.
public enum AngleMode: String, Equatable, Sendable, Codable, CaseIterable {
    case degrees = "DEGREE"
    case radians = "RADIAN"
}

/// Numeric notation, as on the TI `MODE` screen.
public enum NotationMode: String, Equatable, Sendable, Codable, CaseIterable {
    case normal = "NORMAL"
    case scientific = "SCI"
    case engineering = "ENG"
}

/// Decimal setting: floating, or a fixed number of decimal places 0-9.
public enum DecimalMode: Equatable, Hashable, Sendable, Codable {
    case float
    case fixed(Int)

    /// Clamps to the TI's 0-9 range so an out-of-range value can never reach the formatter.
    public static func fixedClamped(_ places: Int) -> DecimalMode {
        .fixed(Swift.max(0, Swift.min(9, places)))
    }
}

/// Complex presentation. This never changes what the evaluator computes — only how a result is
/// shown, and whether a complex result is rejected as `ERR:NONREAL ANS`.
public enum ComplexMode: String, Equatable, Sendable, Codable, CaseIterable {
    case real = "REAL"
    case rectangular = "a+bi"
    case polar = "re^0i"
}

/// How an exact-looking answer is presented.
public enum AnswerMode: String, Equatable, Sendable, Codable, CaseIterable {
    case auto = "AUTO"
    case decimal = "DEC"
    case fraction = "FRAC"
}

/// The full `MODE` screen state.
public struct CalculatorMode: Equatable, Sendable, Codable {
    public var angle: AngleMode
    public var notation: NotationMode
    public var decimals: DecimalMode
    public var complex: ComplexMode
    public var answer: AnswerMode

    public init(
        angle: AngleMode = .radians,
        notation: NotationMode = .normal,
        decimals: DecimalMode = .float,
        complex: ComplexMode = .real,
        answer: AnswerMode = .auto
    ) {
        self.angle = angle
        self.notation = notation
        self.decimals = decimals
        self.complex = complex
        self.answer = answer
    }

    public static let `default` = CalculatorMode()

    /// Radians per unit of the current angle mode.
    public var radiansPerUnit: Double {
        switch angle {
        case .radians: 1
        case .degrees: Double.pi / 180
        }
    }
}
