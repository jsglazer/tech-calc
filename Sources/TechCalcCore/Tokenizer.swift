import Foundation

/// Turns source text into tokens.
///
/// This is the single normalization point for input: a keypad press is rendered into the edit
/// buffer as its catalog `keypadToken` and then tokenized by exactly this code, so keypad entry
/// and typed entry cannot diverge. No function name is spelled here — every name comes from
/// `FunctionCatalog.spellingIndex`.
public struct Tokenizer: Sendable {
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
        (",", .comma)
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

            if Self.isDigit(character)
                || (character == "." && index + 1 < characters.count && Self.isDigit(characters[index + 1])) {
                let (value, length) = try scanNumber(characters, from: index)
                tokens.append(.number(value))
                index += length
                continue
            }

            if let match = matchesCatalog(characters, at: index), let matched = token(for: match.definition) {
                tokens.append(matched)
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

            if let ansLength = matchesLiteral(characters, at: index, "Ans") {
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

    private func token(for definition: FunctionDefinition) -> Token? {
        switch definition.form {
        case .function: .function(definition.id)
        case .infix: .infixFunction(definition.id)
        case .postfix: .postfixFunction(definition.id)
        case .constant: .constant(definition.id)
        case .displayConversion: .displayConversion(definition.id)
        case .macro: nil
        }
    }

    private func matchesCatalog(_ characters: [Character], at index: Int) -> (definition: FunctionDefinition, length: Int)? {
        for entry in FunctionCatalog.spellingIndex {
            if let length = matchesLiteral(characters, at: index, entry.spelling) {
                return (entry.definition, length)
            }
        }
        return nil
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
