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

/// A caret move the arrow pad asks for. `up`/`down` walk the entry history the way the TI's
/// home screen does; `left`/`right` walk the entry line.
public enum KeypadCursor: String, Equatable, Sendable {
    case left, right, up, down
}

/// A screen a menu key opens. The core names the destination; which view that is stays in the UI.
public enum KeypadDestination: String, Equatable, Sendable {
    case calculator, lists, matrices, statTests, finance, mode
}

/// What a key does on one layer.
///
/// The TI prints three faces on most keys, and not every printed face has a feature behind it in
/// this app — `unavailable` is the face that is drawn in its true position but does nothing, so
/// the layout can match the hardware without inventing behaviour.
public enum KeypadEffect: Equatable, Sendable {
    case insert(String)
    /// `DEL`: remove the character under the caret.
    case delete
    case clear
    case enter
    /// `2ND ENTRY`: step back through previous inputs.
    case recallEntry
    /// `2ND INS`: flip the edit buffer between inserting and overwriting.
    case toggleInsertMode
    case move(KeypadCursor)
    case open(KeypadDestination)
    case unavailable

    /// The text this face inserts, or `nil` when it does something else.
    public var insertedText: String? {
        if case .insert(let text) = self { return text }
        return nil
    }
}

/// One printed face of a key: what the hardware prints there, and what pressing it does.
public struct KeyFace: Equatable, Sendable {
    public let label: String
    public let effect: KeypadEffect

    public init(_ label: String, _ effect: KeypadEffect) {
        self.label = label
        self.effect = effect
    }

    /// The common case: the printed label is also the inserted text.
    public static func insert(_ text: String) -> KeyFace {
        KeyFace(text, .insert(text))
    }

    /// A face printed on the hardware that this app has no feature for.
    public static func inert(_ label: String) -> KeyFace {
        KeyFace(label, .unavailable)
    }
}

/// How a key is coloured. The TI groups its keys by colour, and the skin reads this rather than
/// re-deriving a group from the key's id.
public enum KeypadStyle: Equatable, Sendable {
    case function      // the grey scientific keys
    case digit         // the white number pad
    case arithmetic    // the darker right-hand column
    case second        // the 2nd key itself
    case alpha         // the ALPHA key itself
    case navigation    // menu keys: mode, stat, math, apps…
    case arrow
}

/// One physical key: where it sits on the hardware, and what it does on each layer.
public struct KeypadKey: Equatable, Sendable, Identifiable {
    public enum Role: Equatable, Sendable {
        case token
        case secondModifier
        case alphaModifier
    }

    public let id: String
    public let role: Role
    /// 1-based position on the 5-column hardware grid, read top-left to bottom-right.
    public let row: Int
    public let column: Int
    public let rowSpan: Int
    public let columnSpan: Int
    public let style: KeypadStyle
    public let primaryFace: KeyFace?
    public let secondFace: KeyFace?
    public let alphaFace: KeyFace?

    public init(
        id: String,
        role: Role = .token,
        row: Int = 0,
        column: Int = 0,
        rowSpan: Int = 1,
        columnSpan: Int = 1,
        style: KeypadStyle = .function,
        primaryFace: KeyFace? = nil,
        secondFace: KeyFace? = nil,
        alphaFace: KeyFace? = nil
    ) {
        self.id = id
        self.role = role
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.style = style
        self.primaryFace = primaryFace
        self.secondFace = secondFace
        self.alphaFace = alphaFace
    }

    /// The text-only spelling: every layer inserts the string given for it.
    public init(id: String, role: Role = .token, primary: String? = nil, second: String? = nil, alpha: String? = nil) {
        self.init(
            id: id,
            role: role,
            primaryFace: primary.map(KeyFace.insert),
            secondFace: second.map(KeyFace.insert),
            alphaFace: alpha.map(KeyFace.insert)
        )
    }

    public var primary: String? { primaryFace?.effect.insertedText }
    public var second: String? { secondFace?.effect.insertedText }
    public var alpha: String? { alphaFace?.effect.insertedText }

    /// The face a layer shows. A layer the hardware leaves blank falls through to the primary.
    public func face(on layer: KeypadLayer) -> KeyFace? {
        switch layer {
        case .primary: primaryFace
        case .second: secondFace ?? primaryFace
        case .alpha: alphaFace ?? primaryFace
        }
    }

    public func token(on layer: KeypadLayer) -> String? {
        face(on: layer)?.effect.insertedText
    }
}

/// What a key press produced.
public struct KeypadPressResult: Equatable, Sendable {
    /// The text to insert into the edit buffer, or `nil` for a modifier press.
    public let token: String?
    public let modifier: KeypadModifier

    public init(token: String?, modifier: KeypadModifier) {
        self.token = token
        self.modifier = modifier
    }
}

/// The full result of a press: the face that fired, its effect, and the latch afterwards.
public struct KeypadOutcome: Equatable, Sendable {
    /// The face the layer selected at the moment of the press — the latch has already cleared by
    /// the time a caller sees `modifier`, so the face is reported rather than re-derived.
    public let face: KeyFace?
    public let modifier: KeypadModifier

    public var effect: KeypadEffect? { face?.effect }

    public init(face: KeyFace?, modifier: KeypadModifier) {
        self.face = face
        self.modifier = modifier
    }
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

    /// Presses a key and reports the face's effect. This is the whole press path; `press`
    /// narrows it to the inserted text.
    @discardableResult
    public mutating func activate(_ key: KeypadKey) -> KeypadOutcome {
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
            let face = key.face(on: modifier.layer)
            // Single-shot: the latch clears after one key, except under A-LOCK.
            if modifier != .alphaLock { modifier = .none }
            return KeypadOutcome(face: face, modifier: modifier)
        }
        return KeypadOutcome(face: nil, modifier: modifier)
    }

    @discardableResult
    public mutating func press(_ key: KeypadKey) -> KeypadPressResult {
        let outcome = activate(key)
        return KeypadPressResult(token: outcome.effect?.insertedText, modifier: outcome.modifier)
    }

    public mutating func clear() {
        modifier = .none
    }
}

/// The TI-84 Plus keypad, key for key.
///
/// The grid is the hardware's: five columns and ten rows, with the arrow pad spanning the right
/// half of rows 2 and 3. Every function key takes its inserted text from `FunctionCatalog`, so a
/// function's spelling exists in exactly one place in the module and the keypad cannot drift from
/// the tokenizer. Faces the hardware prints but this app has no feature for are `.unavailable` —
/// present, in position, inert.
public enum KeypadLayout {
    /// The number of columns the hardware grid is laid out on.
    public static let columnCount = 5
    /// The number of key rows, `y=` down to `enter`.
    public static let rowCount = 10

    static func token(_ id: FunctionID) -> String? {
        FunctionCatalog.definition(for: id)?.keypadToken
    }

    /// A catalog-backed face: the label is what the hardware prints, the token is the catalog's.
    static func catalogFace(_ id: FunctionID, label: String? = nil) -> KeyFace? {
        guard let definition = FunctionCatalog.definition(for: id) else { return nil }
        return KeyFace(label ?? definition.name, .insert(definition.keypadToken))
    }

    /// The ALPHA letters, in the order the hardware prints them.
    ///
    /// The TI assigns them in keypad reading order — `A` on MATH straight through to `θ` on the
    /// `3` key — so the sequence is `EvaluationContext.variableNames` itself, taken in turn. The
    /// keypad therefore cannot offer a variable name the evaluator would reject, and no letter is
    /// spelled twice in the module. `KeypadLayoutTests` pins the order.
    private final class AlphaSequence {
        private var index = 0

        func next() -> KeyFace? {
            guard EvaluationContext.variableNames.indices.contains(index) else { return nil }
            defer { index += 1 }
            let name = String(EvaluationContext.variableNames[index])
            return KeyFace(name, .insert(name))
        }
    }

    public static let second = KeypadKey(
        id: "2nd", role: .secondModifier, row: 2, column: 1, style: .second,
        // The case prints nothing above 2nd; A-LOCK is printed above ALPHA, in 2nd's colour.
        primaryFace: KeyFace("2nd", .unavailable)
    )

    public static let alpha = KeypadKey(
        id: "alpha", role: .alphaModifier, row: 3, column: 1, style: .alpha,
        primaryFace: KeyFace("alpha", .unavailable),
        secondFace: KeyFace("A-lock", .unavailable),
        alphaFace: nil
    )

    /// The arrow pad: one control spanning rows 2-3 of the right two columns. The four arrows
    /// inside it are separate keys so each carries its own effect, and they share a position
    /// because the pad is drawn as a unit rather than as grid cells.
    public static let arrowKeys: [KeypadKey] = [
        ("arrow-up", "▲", KeypadCursor.up),
        ("arrow-left", "◀", .left),
        ("arrow-right", "▶", .right),
        ("arrow-down", "▼", .down),
    ].map { id, label, cursor in
        KeypadKey(
            id: id, row: 2, column: 4, rowSpan: 2, columnSpan: 2, style: .arrow,
            primaryFace: KeyFace(label, .move(cursor))
        )
    }

    public static func arrow(_ cursor: KeypadCursor) -> KeypadKey {
        arrowKeys.first { $0.primaryFace?.effect == .move(cursor) } ?? arrowKeys[0]
    }

    /// Every key, in reading order.
    public static let keys: [KeypadKey] = {
        let lists = ListName.numberedNames
        func listFace(_ index: Int) -> KeyFace {
            let name = lists[index]
            return KeyFace(name.key, .insert(name.key))
        }

        var keys: [KeypadKey] = []
        let letters = AlphaSequence()

        // MARK: Row 1 — the graphing row. None of it is backed in this build.
        let graphing: [(String, String, String, String)] = [
            ("graph-y", "y=", "stat plot", "f1"),
            ("graph-window", "window", "tblset", "f2"),
            ("graph-zoom", "zoom", "format", "f3"),
            ("graph-trace", "trace", "calc", "f4"),
            ("graph-graph", "graph", "table", "f5"),
        ]
        for (column, entry) in graphing.enumerated() {
            keys.append(KeypadKey(
                id: entry.0, row: 1, column: column + 1, style: .navigation,
                primaryFace: .inert(entry.1), secondFace: .inert(entry.2), alphaFace: .inert(entry.3)
            ))
        }

        // MARK: Row 2 — 2nd, mode, del, and the top half of the arrow pad.
        keys.append(second)
        keys.append(KeypadKey(
            id: "mode", row: 2, column: 2, style: .navigation,
            primaryFace: KeyFace("mode", .open(.mode)),
            secondFace: KeyFace("quit", .open(.calculator))
        ))
        keys.append(KeypadKey(
            id: "del", row: 2, column: 3, style: .navigation,
            primaryFace: KeyFace("del", .delete),
            secondFace: KeyFace("ins", .toggleInsertMode)
        ))
        keys.append(contentsOf: arrowKeys)

        // MARK: Row 3 — alpha, the variable key, stat.
        keys.append(alpha)
        keys.append(KeypadKey(
            id: "variable", row: 3, column: 2, style: .function,
            primaryFace: KeyFace("x,T,θ,n", .insert("X")),
            secondFace: .inert("link")
        ))
        keys.append(KeypadKey(
            id: "stat", row: 3, column: 3, style: .navigation,
            primaryFace: KeyFace("stat", .open(.lists)),
            secondFace: KeyFace("list", .open(.lists))
        ))

        // MARK: Row 4 — the menu row.
        keys.append(KeypadKey(
            id: "math", row: 4, column: 1, style: .navigation,
            primaryFace: .inert("math"), secondFace: .inert("test"), alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "apps", row: 4, column: 2, style: .navigation,
            primaryFace: KeyFace("apps", .open(.finance)),
            secondFace: .inert("angle"), alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "prgm", row: 4, column: 3, style: .navigation,
            primaryFace: .inert("prgm"), secondFace: .inert("draw"), alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "vars", row: 4, column: 4, style: .navigation,
            primaryFace: .inert("vars"),
            secondFace: KeyFace("distr", .open(.statTests))
        ))
        keys.append(KeypadKey(
            id: "clear", row: 4, column: 5, style: .navigation,
            primaryFace: KeyFace("clear", .clear)
        ))

        // MARK: Row 5 — reciprocal and the trig keys.
        keys.append(KeypadKey(
            id: FunctionID.reciprocal.rawValue, row: 5, column: 1, style: .function,
            primaryFace: catalogFace(.reciprocal, label: "x⁻¹"),
            secondFace: KeyFace("matrix", .open(.matrices)),
            alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: FunctionID.sin.rawValue, row: 5, column: 2, style: .function,
            primaryFace: catalogFace(.sin), secondFace: catalogFace(.asin), alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: FunctionID.cos.rawValue, row: 5, column: 3, style: .function,
            primaryFace: catalogFace(.cos), secondFace: catalogFace(.acos), alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: FunctionID.tan.rawValue, row: 5, column: 4, style: .function,
            primaryFace: catalogFace(.tan), secondFace: catalogFace(.atan), alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "power", row: 5, column: 5, style: .arithmetic,
            primaryFace: .insert("^"), secondFace: catalogFace(.pi), alphaFace: letters.next()
        ))

        // MARK: Row 6 — square, comma, the parentheses, divide.
        keys.append(KeypadKey(
            id: FunctionID.square.rawValue, row: 6, column: 1, style: .function,
            primaryFace: catalogFace(.square, label: "x²"),
            secondFace: catalogFace(.squareRoot),
            alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "comma", row: 6, column: 2, style: .function,
            primaryFace: .insert(","), secondFace: KeyFace("EE", .insert("E")), alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "leftParenthesis", row: 6, column: 3, style: .function,
            primaryFace: .insert("("),
            secondFace: .insert(String(ContainerSyntax.listOpen)),
            alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "rightParenthesis", row: 6, column: 4, style: .function,
            primaryFace: .insert(")"),
            secondFace: .insert(String(ContainerSyntax.listClose)),
            alphaFace: letters.next()
        ))
        keys.append(KeypadKey(
            id: "divide", row: 6, column: 5, style: .arithmetic,
            primaryFace: KeyFace("÷", .insert("/")),
            secondFace: catalogFace(.eulersNumber),
            alphaFace: letters.next()
        ))

        // MARK: Row 7 — log, 7 8 9, multiply.
        keys.append(KeypadKey(
            id: FunctionID.log.rawValue, row: 7, column: 1, style: .function,
            primaryFace: catalogFace(.log),
            secondFace: catalogFace(.powerOfTen, label: "10ˣ"),
            alphaFace: letters.next()
        ))
        for (offset, digit) in ["7", "8", "9"].enumerated() {
            // 2nd on 7/8/9 is the sequence variables u, v and w, which this build has no feature for.
            keys.append(KeypadKey(
                id: "digit-\(digit)", row: 7, column: offset + 2, style: .digit,
                primaryFace: .insert(digit),
                secondFace: .inert(["u", "v", "w"][offset]),
                alphaFace: letters.next()
            ))
        }
        keys.append(KeypadKey(
            id: "multiply", row: 7, column: 5, style: .arithmetic,
            primaryFace: KeyFace("×", .insert("*")),
            secondFace: .insert(String(ContainerSyntax.matrixOpen)),
            alphaFace: letters.next()
        ))

        // MARK: Row 8 — ln, 4 5 6, subtract.
        keys.append(KeypadKey(
            id: FunctionID.ln.rawValue, row: 8, column: 1, style: .function,
            primaryFace: catalogFace(.ln),
            secondFace: catalogFace(.powerOfE, label: "eˣ"),
            alphaFace: letters.next()
        ))
        for (offset, digit) in ["4", "5", "6"].enumerated() {
            keys.append(KeypadKey(
                id: "digit-\(digit)", row: 8, column: offset + 2, style: .digit,
                primaryFace: .insert(digit),
                secondFace: listFace(offset + 3),
                alphaFace: letters.next()
            ))
        }
        keys.append(KeypadKey(
            id: "subtract", row: 8, column: 5, style: .arithmetic,
            primaryFace: KeyFace("−", .insert("-")),
            secondFace: .insert(String(ContainerSyntax.matrixClose)),
            alphaFace: letters.next()
        ))

        // MARK: Row 9 — store, 1 2 3, add.
        keys.append(KeypadKey(
            id: "store", row: 9, column: 1, style: .function,
            primaryFace: KeyFace("sto→", .insert("→")),
            secondFace: .inert("rcl"),
            alphaFace: letters.next()
        ))
        for (offset, digit) in ["1", "2", "3"].enumerated() {
            keys.append(KeypadKey(
                id: "digit-\(digit)", row: 9, column: offset + 2, style: .digit,
                primaryFace: .insert(digit),
                secondFace: listFace(offset),
                alphaFace: letters.next()
            ))
        }
        keys.append(KeypadKey(
            id: "add", row: 9, column: 5, style: .arithmetic,
            primaryFace: .insert("+"), secondFace: .inert("mem"), alphaFace: .insert("\"")
        ))

        // MARK: Row 10 — on, 0, the decimal point, negate, enter.
        keys.append(KeypadKey(
            id: "on", row: 10, column: 1, style: .navigation,
            primaryFace: .inert("on"), secondFace: .inert("off")
        ))
        keys.append(KeypadKey(
            id: "digit-0", row: 10, column: 2, style: .digit,
            primaryFace: .insert("0"), secondFace: .inert("catalog"), alphaFace: KeyFace("_", .insert(" "))
        ))
        keys.append(KeypadKey(
            id: "decimal", row: 10, column: 3, style: .digit,
            primaryFace: .insert("."), secondFace: catalogFace(.imaginaryUnit), alphaFace: .insert(":")
        ))
        keys.append(KeypadKey(
            id: "negate", row: 10, column: 4, style: .digit,
            primaryFace: KeyFace("(-)", .insert(String(Tokenizer.negationCharacter))),
            secondFace: KeyFace("ans", .insert(Tokenizer.answerSpelling)),
            alphaFace: .insert("?")
        ))
        keys.append(KeypadKey(
            id: "enter", row: 10, column: 5, style: .arithmetic,
            primaryFace: KeyFace("enter", .enter),
            secondFace: KeyFace("entry", .recallEntry),
            alphaFace: .inert("solve")
        ))

        return keys
    }()

    public static func key(id: String) -> KeypadKey? {
        keys.first { $0.id == id }
    }

    /// The grid cells of one hardware row, left to right. The arrow pad is not a grid cell — it
    /// is drawn as a unit over the right of rows 2 and 3 — so it is not returned here.
    public static func row(_ index: Int) -> [KeypadKey] {
        keys.filter { $0.row == index && $0.style != .arrow }.sorted { $0.column < $1.column }
    }
}
