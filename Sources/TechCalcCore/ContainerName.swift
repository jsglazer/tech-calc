import Foundation

/// The names a list can be stored under: `L1`-`L6`, and the user-named lists the TI writes with
/// a `∟` prefix.
///
/// A name is a value, not a string scattered through the module: the tokenizer, the evaluator and
/// the persisted document all round-trip through `key` and `init?(key:)`, so the storage
/// spelling exists in exactly one place.
public enum ListName: Equatable, Hashable, Sendable, Codable {
    /// `L1` through `L6`.
    case numbered(Int)
    /// A user-named list, without its `∟` prefix.
    case named(String)

    /// The TI ships six numbered lists.
    public static let numberedRange = 1...6

    /// The TI caps a list name at five characters.
    public static let maximumNamedLength = 5

    public init?(number: Int) {
        guard Self.numberedRange.contains(number) else { return nil }
        self = .numbered(number)
    }

    public init?(name: String) {
        guard !name.isEmpty, name.count <= Self.maximumNamedLength,
              let first = name.first, first.isLetter,
              name.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        self = .named(name)
    }

    /// The canonical spelling — the key in the persisted document and the text the display shows.
    public var key: String {
        switch self {
        case .numbered(let number): "\(ContainerSyntax.numberedListPrefix)\(number)"
        case .named(let name): "\(ContainerSyntax.namedListPrefix)\(name)"
        }
    }

    public init?(key: String) {
        var characters = Array(key)
        guard let first = characters.first else { return nil }
        characters.removeFirst()
        let rest = String(characters)
        if first == ContainerSyntax.namedListPrefix {
            self.init(name: rest)
        } else if first == ContainerSyntax.numberedListPrefix, let number = Int(rest) {
            self.init(number: number)
        } else {
            return nil
        }
    }

    /// `L1`-`L6`, in order — the set the list editor shows by default.
    public static let numberedNames: [ListName] = numberedRange.compactMap { ListName(number: $0) }
}

/// The names a matrix can be stored under: `[A]` through `[J]`.
public struct MatrixName: Equatable, Hashable, Sendable, Codable {
    public let letter: Character

    /// The TI ships ten matrices, `[A]` to `[J]`.
    public static let letters: [Character] = Array("ABCDEFGHIJ")

    public init?(letter: Character) {
        guard Self.letters.contains(letter) else { return nil }
        self.letter = letter
    }

    /// The canonical spelling, brackets included: `[A]`.
    public var key: String {
        "\(ContainerSyntax.matrixOpen)\(letter)\(ContainerSyntax.matrixClose)"
    }

    public init?(key: String) {
        let characters = Array(key)
        guard characters.count == 3,
              characters[0] == ContainerSyntax.matrixOpen,
              characters[2] == ContainerSyntax.matrixClose else { return nil }
        self.init(letter: characters[1])
    }

    public static let all: [MatrixName] = letters.compactMap { MatrixName(letter: $0) }

    public init(from decoder: Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        guard let name = MatrixName(key: key) else { throw TIError.dataType }
        self = name
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// The punctuation that introduces a container. Declared once, read by the tokenizer and by the
/// name types above; no container delimiter is spelled anywhere else in the module.
public enum ContainerSyntax {
    /// `L1`-`L6` are typed with an ASCII `L`; the TI prints them with a subscript digit.
    public static let numberedListPrefix: Character = "L"
    /// The TI's user-list mark, as in `∟SCORE`.
    public static let namedListPrefix: Character = "∟"
    /// Subscript digits, so a list pasted from TI-style text (`L₁`) tokenizes too.
    public static let subscriptDigits: [Character: Int] = [
        "₁": 1, "₂": 2, "₃": 3, "₄": 4, "₅": 5, "₆": 6
    ]
    public static let listOpen: Character = "{"
    public static let listClose: Character = "}"
    public static let matrixOpen: Character = "["
    public static let matrixClose: Character = "]"
}
