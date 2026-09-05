import Foundation

/// Turns source text into tokens.
///
/// This is the single normalization point for input: a keypad press is rendered into the edit
/// buffer as its catalog `keypadToken` and then tokenized by exactly this code, so keypad entry
/// and typed entry cannot diverge. No function name is spelled here — every name comes from
/// `FunctionCatalog.spellingIndex`.
public struct Tokenizer: Sendable {
    /// How the last answer is written on the entry line. Declared once here, the way a function
    /// name is declared once in the catalog; the typeset builder and the LaTeX serializer read it
    /// rather than spelling it again.
    public static let answerSpelling = "Ans"

    public init() {}

    /// The subtraction key and the `(-)` negation key are distinct on the TI. Typed text has only
    /// one hyphen, so `-` lexes as subtraction and the parser reads it as negation in prefix
    /// position; the keypad's negation key inserts `⁻`, which lexes as negation everywhere.
    static let negationCharacter: Character = "⁻"

    private static let punctuation: [(text: String, token: Token)] = [
        ("≠", .binaryOperator(.notEqual)),
        ("≥", .binaryOperator(.greaterEqual)),
        ("≤", .binaryOperator(.lessEqual)),
        ("!=", .binaryOperator(.notEqual)),
        (">=", .binaryOperator(.greaterEqual)),
        ("<=", .binaryOperator(.lessEqual)),
        ("->", .store),
        ("→", .store),
        ("▸", .store),
        ("+", .binaryOperator(.add)),
        ("-", .binaryOperator(.subtract)),
        ("−", .binaryOperator(.subtract)),
        ("*", .binaryOperator(.multiply)),
        ("×", .binaryOperator(.multiply)),
        ("/", .binaryOperator(.divide)),
        ("÷", .binaryOperator(.divide)),
        ("^", .binaryOperator(.power)),
        ("=", .binaryOperator(.equal)),
        (">", .binaryOperator(.greater)),
        ("<", .binaryOperator(.less)),
        ("(", .leftParenthesis),
        (")", .rightParenthesis),
        (",", .comma),
        (String(ContainerSyntax.listOpen), .leftBrace),
        (String(ContainerSyntax.listClose), .rightBrace),
        (String(ContainerSyntax.matrixOpen), .leftBracket),
        (String(ContainerSyntax.matrixClose), .rightBracket)
    ]

    /// Longest-match punctuation, so `≥`'s ASCII spelling `>=` is not read as `>` then `=`.
    private static let sortedPunctuation = punctuation.sorted { $0.text.count > $1.text.count }

    /// ASCII digits only. Swift reports the superscripts `²` and `³` as numbers, and they are
    /// postfix operators here, not digits.
    static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    public func tokenize(_ source: String) throws -> [Token] {
        let characters = Array(source)
        var index = 0
        var tokens: [Token] = []

        while index < characters.count {
            let character = characters[index]

            if character == " " || character == "\t" {
                index += 1
                continue
            }

            // The name scan runs before the number scan because several TI command names begin
            // with a digit — `2-SampTTest`, `1-Var Stats` — and would otherwise lex as a number
            // followed by nonsense. No name is a bare digit string, so ordinary numbers are
            // unaffected.
            if let match = matchesName(characters, at: index) {
                tokens.append(match.token)
                index += match.length
                continue
            }

            // A based literal is scanned before the ordinary number, because `0b1101` starts
            // with a digit the number scanner would happily take on its own. A prefix with no
            // digits after it is not a literal, so `0b` alone still means zero times `B`.
            if let match = NumberBases.scanLiteral(characters, at: index) {
                tokens.append(.number(match.value))
                index += match.length
                continue
            }

            if Self.isDigit(character)
                || (character == "." && index + 1 < characters.count && Self.isDigit(characters[index + 1])) {
                let (value, length) = try scanNumber(characters, from: index)
                tokens.append(.number(value))
                index += length
                continue
            }

            if let match = scanContainerName(characters, at: index) {
                tokens.append(match.token)
                index += match.length
                continue
            }

            // Reached only when the catalog did not match `⁻¹`: a bare `⁻` is the negation key.
            if character == Self.negationCharacter {
                tokens.append(.negation)
                index += 1
                continue
            }

            if let match = matchesPunctuation(characters, at: index) {
                tokens.append(match.token)
                index += match.length
                continue
            }

            if let ansLength = matchesLiteral(characters, at: index, Self.answerSpelling) {
                tokens.append(.ans)
                index += ansLength
                continue
            }

            if character.isLetter || character == "θ" {
                tokens.append(.variable(character))
                index += 1
                continue
            }

            throw TIError.syntax
        }

        return tokens
    }

    // MARK: - Scanners

    /// A stored container name: `[A]`-`[J]`, `L1`-`L6` (or `L₁`-`L₆`), and `∟NAME`.
    ///
    /// `L` followed immediately by a digit is a list, never the variable `L` times that digit —
    /// the TI writes the numbered lists as single subscripted glyphs, and this is the typed
    /// stand-in for them.
    private func scanContainerName(_ characters: [Character], at index: Int) -> (token: Token, length: Int)? {
        let character = characters[index]

        if character == ContainerSyntax.matrixOpen,
           index + 2 < characters.count,
           characters[index + 2] == ContainerSyntax.matrixClose,
           let name = MatrixName(letter: characters[index + 1]) {
            return (.matrixName(name), 3)
        }

        if character == ContainerSyntax.numberedListPrefix, index + 1 < characters.count {
            let next = characters[index + 1]
            let number = Self.isDigit(next) ? next.wholeNumberValue : ContainerSyntax.subscriptDigits[next]
            if let number, let name = ListName(number: number) {
                return (.listName(name), 2)
            }
        }

        if character == ContainerSyntax.namedListPrefix {
            var length = 1
            var text = ""
            while index + length < characters.count,
                  characters[index + length].isLetter || Self.isDigit(characters[index + length]),
                  text.count < ListName.maximumNamedLength {
                text.append(characters[index + length])
                length += 1
            }
            if let name = ListName(name: text) {
                return (.listName(name), length)
            }
        }

        return nil
    }

    /// Every name the tokenizer knows: the catalog's function spellings and the statistics
    /// variables, in one longest-first table.
    ///
    /// Merging them is what makes the longest match correct across both: `minX` is the statistics
    /// variable rather than the `min(` function, `tan(` is the function rather than the `t`
    /// statistic, and `Sx1` beats `Sx`. Neither table spells a name of its own — this reads them.
    static let nameIndex: [(spelling: String, token: Token)] = {
        var pairs: [(String, Token)] = []
        for entry in FunctionCatalog.spellingIndex {
            if let token = Self.token(for: entry.definition) {
                pairs.append((entry.spelling, token))
            }
        }
        for entry in StatVariable.spellingIndex {
            pairs.append((entry.spelling, .statVariable(entry.variable)))
        }
        return pairs.sorted { $0.0.count > $1.0.count }.map { (spelling: $0.0, token: $0.1) }
    }()

    private func matchesName(_ characters: [Character], at index: Int) -> (token: Token, length: Int)? {
        for entry in Self.nameIndex {
            if let length = matchesLiteral(characters, at: index, entry.spelling) {
                return (entry.token, length)
            }
        }
        return nil
    }

    private static func token(for definition: FunctionDefinition) -> Token? {
        switch definition.form {
        case .function: .function(definition.id)
        case .infix: .infixFunction(definition.id)
        case .postfix: .postfixFunction(definition.id)
        case .constant: .constant(definition.id)
        case .displayConversion: .displayConversion(definition.id)
        case .macro: nil
        }
    }

    private func matchesPunctuation(_ characters: [Character], at index: Int) -> (token: Token, length: Int)? {
        for entry in Self.sortedPunctuation {
            if let length = matchesLiteral(characters, at: index, entry.text) {
                return (entry.token, length)
            }
        }
        return nil
    }

    private func matchesLiteral(_ characters: [Character], at index: Int, _ literal: String) -> Int? {
        let literalCharacters = Array(literal)
        guard index + literalCharacters.count <= characters.count else { return nil }
        for offset in 0..<literalCharacters.count where characters[index + offset] != literalCharacters[offset] {
            return nil
        }
        return literalCharacters.count
    }

    /// Digits, one optional decimal point, and an optional `E` exponent (`1E99`).
    private func scanNumber(_ characters: [Character], from start: Int) throws -> (value: Double, length: Int) {
        var index = start
        var text = ""
        var sawDecimalPoint = false

        while index < characters.count {
            let character = characters[index]
            if Self.isDigit(character) {
                text.append(character)
                index += 1
            } else if character == ".", !sawDecimalPoint {
                sawDecimalPoint = true
                text.append(character)
                index += 1
            } else {
                break
            }
        }

        // An exponent only if a digit actually follows, so `2e` stays `2 * e`.
        if index < characters.count, characters[index] == "E" || characters[index] == "e" {
            var lookahead = index + 1
            var exponentText = ""
            if lookahead < characters.count, characters[lookahead] == "-" || characters[lookahead] == "+"
                || characters[lookahead] == Tokenizer.negationCharacter {
                exponentText.append(characters[lookahead] == "+" ? "+" : "-")
                lookahead += 1
            }
            var digitCount = 0
            while lookahead < characters.count, Self.isDigit(characters[lookahead]) {
                exponentText.append(characters[lookahead])
                lookahead += 1
                digitCount += 1
            }
            if digitCount > 0 {
                text += "E" + exponentText
                index = lookahead
            }
        }

        guard let value = Double(text) else { throw TIError.syntax }
        return (value, index - start)
    }
}
