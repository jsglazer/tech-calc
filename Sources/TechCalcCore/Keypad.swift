import Foundation

/// The three layers a TI key can produce.
public enum KeypadLayer: String, Equatable, Sendable {
    case primary, second, alpha
}

/// The modifier latch. `2nd` and `ALPHA` are single-shot; `2nd` then `ALPHA` engages A-LOCK,
/// which stays engaged until it is pressed off.
public enum KeypadModifier: String, Equatable, Sendable {
    case none, second, alpha, alphaLock

    public var layer: KeypadLayer {
        switch self {
        case .none: .primary
        case .second: .second
        case .alpha, .alphaLock: .alpha
        }
    }
}

/// One physical key: what it inserts on each layer. Modifier keys carry no tokens.
public struct KeypadKey: Equatable, Sendable, Identifiable {
    public enum Role: Equatable, Sendable {
        case token
        case secondModifier
        case alphaModifier
    }

    public let id: String
    public let role: Role
    public let primary: String?
    public let second: String?
    public let alpha: String?

    public init(id: String, role: Role = .token, primary: String? = nil, second: String? = nil, alpha: String? = nil) {
        self.id = id
        self.role = role
        self.primary = primary
        self.second = second
        self.alpha = alpha
    }

    public func token(on layer: KeypadLayer) -> String? {
        switch layer {
        case .primary: primary
        case .second: second ?? primary
        case .alpha: alpha ?? primary
        }
    }
}

/// What a key press produced.
public struct KeypadPressResult: Equatable, Sendable {
    /// The text to insert into the edit buffer, or `nil` for a modifier press.
    public let token: String?
    public let modifier: KeypadModifier
}

/// The `2nd` / `ALPHA` state machine.
///
/// It is a pure value type with no view attached, so the whole modifier behaviour — single-shot
/// latches, A-LOCK, and toggling a latch back off — is exercised headlessly.
public struct KeypadState: Equatable, Sendable {
    public private(set) var modifier: KeypadModifier

    public init(modifier: KeypadModifier = .none) {
        self.modifier = modifier
    }

    @discardableResult
    public mutating func press(_ key: KeypadKey) -> KeypadPressResult {
        switch key.role {
        case .secondModifier:
            // Pressing 2nd again cancels it; from any other state it latches.
            modifier = (modifier == .second) ? .none : .second

        case .alphaModifier:
            switch modifier {
            case .second: modifier = .alphaLock   // 2nd then ALPHA is A-LOCK
            case .alpha, .alphaLock: modifier = .none
            case .none: modifier = .alpha
            }

        case .token:
            let emitted = key.token(on: modifier.layer)
            // Single-shot: the latch clears after one key, except under A-LOCK.
            if modifier != .alphaLock { modifier = .none }
            return KeypadPressResult(token: emitted, modifier: modifier)
        }
        return KeypadPressResult(token: nil, modifier: modifier)
    }

    public mutating func clear() {
        modifier = .none
    }
}

/// The default key layout.
///
/// Every function key takes its inserted text from `FunctionCatalog`, so a function's spelling
/// exists in exactly one place in the module and the keypad cannot drift from the tokenizer.
public enum KeypadLayout {
    static func token(_ id: FunctionID) -> String? {
        FunctionCatalog.definition(for: id)?.keypadToken
    }

    public static let second = KeypadKey(id: "2nd", role: .secondModifier)
    public static let alpha = KeypadKey(id: "alpha", role: .alphaModifier)

    /// The scientific rows. Digits and punctuation are generated; named functions come from
    /// the catalog.
    public static let keys: [KeypadKey] = {
        var keys: [KeypadKey] = [second, alpha]

        // Digits 0-9, with their ALPHA-layer letters where the TI assigns one.
        let digitAlphaLetters: [Character: String] = [
            "1": "Y", "2": "Z", "4": "T", "5": "U", "6": "V", "7": "Q", "8": "R", "9": "S"
        ]
        for digit in "0123456789" {
            keys.append(KeypadKey(
                id: "digit-\(digit)",
                primary: String(digit),
                second: String(digit),
                alpha: digitAlphaLetters[digit] ?? String(digit)
            ))
        }
        keys.append(KeypadKey(id: "decimal", primary: ".", alpha: ":"))
        keys.append(KeypadKey(id: "negate", primary: String(Tokenizer.negationCharacter), alpha: "?"))

        // Arithmetic, with the ALPHA letters the TI prints on those keys.
        keys.append(KeypadKey(id: "add", primary: "+", alpha: "\""))
        keys.append(KeypadKey(id: "subtract", primary: "-", alpha: "W"))
        keys.append(KeypadKey(id: "multiply", primary: "*", alpha: "X"))
        keys.append(KeypadKey(id: "divide", primary: "/", alpha: "O"))
        keys.append(KeypadKey(id: "power", primary: "^"))
        keys.append(KeypadKey(id: "leftParenthesis", primary: "(", alpha: "A"))
        keys.append(KeypadKey(id: "rightParenthesis", primary: ")", alpha: "B"))
        keys.append(KeypadKey(id: "comma", primary: ",", alpha: "D"))
        keys.append(KeypadKey(id: "store", primary: "→"))

        // Function keys: primary and 2nd layers both come from the catalog.
        keys.append(KeypadKey(id: FunctionID.sin.rawValue, primary: token(.sin), second: token(.asin), alpha: "E"))
        keys.append(KeypadKey(id: FunctionID.cos.rawValue, primary: token(.cos), second: token(.acos), alpha: "F"))
        keys.append(KeypadKey(id: FunctionID.tan.rawValue, primary: token(.tan), second: token(.atan), alpha: "G"))
        keys.append(KeypadKey(id: FunctionID.log.rawValue, primary: token(.log), second: token(.powerOfTen), alpha: "H"))
        keys.append(KeypadKey(id: FunctionID.ln.rawValue, primary: token(.ln), second: token(.powerOfE), alpha: "I"))
        keys.append(KeypadKey(id: FunctionID.square.rawValue, primary: token(.square), second: token(.squareRoot), alpha: "J"))
        keys.append(KeypadKey(id: FunctionID.reciprocal.rawValue, primary: token(.reciprocal), second: token(.pi), alpha: "K"))

        return keys
    }()

    public static func key(id: String) -> KeypadKey? {
        keys.first { $0.id == id }
    }
}
