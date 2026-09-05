import Foundation

/// The outcome of parsing one line of input.
public struct ParseResult: Equatable, Sendable {
    public let expression: Expression
    /// True when the parser supplied closing parentheses the user omitted, as the TI does on ENTER.
    public let autoClosedParentheses: Bool
}

/// A Pratt (precedence-climbing) parser over the token stream.
///
/// Precedence follows the TI-84 Plus CE table exactly. The four cases the pre-build decisions
/// call out are direct consequences of the binding powers in `BindingPower` and
/// `BinaryOperator.bindingPower`:
///   * implicit multiplication binds as `*` does, left to right, so `1/2X` is `(1/2)*X`;
///   * negation binds looser than `^`, so `-3^2` is `-9` and `(-3)^2` is `9`;
///   * `^` is right-associative, so `2^3^2` is `512`;
///   * adjacent calls such as `sin(2)cos(2)` are a product.
public struct Parser: Sendable {
    private let tokens: [Token]

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    public static func parse(_ source: String) throws -> ParseResult {
        let tokens = try Tokenizer().tokenize(source)
        var parser = ParserState(tokens: tokens)
        let expression = try parser.parseLine()
        return ParseResult(expression: expression, autoClosedParentheses: parser.autoClosedParentheses)
    }

    public func parse() throws -> ParseResult {
        var parser = ParserState(tokens: tokens)
        let expression = try parser.parseLine()
        return ParseResult(expression: expression, autoClosedParentheses: parser.autoClosedParentheses)
    }
}

private struct ParserState {
    let tokens: [Token]
    var position = 0
    var autoClosedParentheses = false

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    var current: Token? { position < tokens.count ? tokens[position] : nil }

    mutating func advance() { position += 1 }

    /// A whole input line: an expression, optionally stored into a variable.
    mutating func parseLine() throws -> Expression {
        guard current != nil else { throw TIError.syntax }
        var expression = try parseExpression(minimumBindingPower: 0)

        if case .store = current {
            advance()
            expression = .store(expression, try parseStoreTarget())
        }

        guard position == tokens.count else { throw TIError.syntax }
        return expression
    }

    /// What follows `STO▸`: a variable, `rand`, a whole container, one container element, or a
    /// container's `dim(`.
    private mutating func parseStoreTarget() throws -> StoreTarget {
        switch current {
        case .variable(let name):
            advance()
            return .variable(name)

        case .constant(.random):
            // `seed STO▸ rand` restarts the random stream, as on the TI.
            advance()
            return .randomSeed

        case .listName(let name):
            advance()
            guard case .leftParenthesis = current else { return .list(name) }
            advance()
            let index = try parseExpression(minimumBindingPower: 0)
            try consumeClosingParenthesis()
            return .listElement(name, index)

        case .matrixName(let name):
            advance()
            guard case .leftParenthesis = current else { return .matrix(name) }
            advance()
            let row = try parseExpression(minimumBindingPower: 0)
            guard case .comma = current else { throw TIError.syntax }
            advance()
            let column = try parseExpression(minimumBindingPower: 0)
            try consumeClosingParenthesis()
            return .matrixElement(name, row, column)

        case .function(.dimension):
            // `5→dim(L1)` resizes; `{2,3}→dim([A])` reshapes.
            advance()
            guard case .leftParenthesis = current else { throw TIError.syntax }
            advance()
            let target: StoreTarget
            switch current {
            case .listName(let name): target = .listDimension(name)
            case .matrixName(let name): target = .matrixDimension(name)
            default: throw TIError.syntax
            }
            advance()
            try consumeClosingParenthesis()
            return target

        default:
            throw TIError.syntax
        }
    }

    /// Only a container can be subscripted, which is what keeps `L1(2)` an element access while
    /// `2(3)` stays implicit multiplication.
    private func isIndexable(_ expression: Expression) -> Bool {
        switch expression {
        case .listVariable, .matrixVariable, .listLiteral, .matrixLiteral, .element: true
        default: false
        }
    }

    /// `{1,2,3}`. An unclosed brace auto-closes, as ENTER does with parentheses.
    private mutating func parseListLiteral() throws -> Expression {
        advance()
        var elements: [Expression] = []
        if case .rightBrace = current {
            advance()
            return .listLiteral(elements)
        }
        while true {
            elements.append(try parseExpression(minimumBindingPower: 0))
            if case .comma = current {
                advance()
                continue
            }
            try consumeClosing(.rightBrace)
            break
        }
        return .listLiteral(elements)
    }

    /// `[[1,2][3,4]]`, with the comma between rows the TI also accepts.
    private mutating func parseMatrixLiteral() throws -> Expression {
        advance()
        var rows: [[Expression]] = []
        while true {
            guard case .leftBracket = current else { throw TIError.syntax }
            advance()
            var row: [Expression] = []
            while true {
                row.append(try parseExpression(minimumBindingPower: 0))
                if case .comma = current {
                    advance()
                    continue
                }
                try consumeClosing(.rightBracket)
                break
            }
            rows.append(row)
            if case .comma = current { advance() }
            if case .leftBracket = current { continue }
            try consumeClosing(.rightBracket)
            break
        }
        // A ragged literal is a dimension error, not a silently padded matrix.
        guard let width = rows.first?.count, width >= 1, rows.allSatisfy({ $0.count == width }) else {
            throw TIError.invalidDimension
        }
        return .matrixLiteral(rows)
    }

    /// Consumes a specific closing delimiter, recording an auto-close when the input just ended.
    private mutating func consumeClosing(_ token: Token) throws {
        if current == token {
            advance()
            return
        }
        guard current == nil else { throw TIError.syntax }
        autoClosedParentheses = true
    }

    mutating func parseExpression(minimumBindingPower: Int) throws -> Expression {
        var left = try parsePrefix()

        loop: while let token = current {
            switch token {
            case .binaryOperator(let op):
                let power = op.bindingPower
                if power < minimumBindingPower { break loop }
                advance()
                let right = try parseExpression(
                    minimumBindingPower: op.isRightAssociative ? power : power + 1
                )
                left = .binary(op, left, right)

            case .infixFunction(let id):
                let power = bindingPower(forInfix: id)
                if power < minimumBindingPower { break loop }
                advance()
                let right = try parseExpression(minimumBindingPower: power + 1)
                left = .call(id, [left, right])

            case .postfixFunction(let id):
                if BindingPower.postfix < minimumBindingPower { break loop }
                advance()
                left = .call(id, [left])

            case .displayConversion(let id):
                if BindingPower.displayConversion < minimumBindingPower { break loop }
                advance()
                left = .displayConversion(id, left)

            case .leftParenthesis where isIndexable(left):
                // `L1(2)` and `[A](1,2)` are element access, not a product with a parenthesis.
                if BindingPower.postfix < minimumBindingPower { break loop }
                advance()
                var subscripts: [Expression] = []
                while true {
                    subscripts.append(try parseExpression(minimumBindingPower: 0))
                    if case .comma = current {
                        advance()
                        continue
                    }
                    try consumeClosingParenthesis()
                    break
                }
                left = .element(left, subscripts)

            default:
                // Implicit multiplication: two operands with nothing between them.
                guard startsOperand(token), BindingPower.implicitMultiplication >= minimumBindingPower else {
                    break loop
                }
                let right = try parseExpression(
                    minimumBindingPower: BindingPower.implicitMultiplication + 1
                )
                left = .binary(.multiply, left, right)
            }
        }

        return left
    }

    private mutating func parsePrefix() throws -> Expression {
        guard let token = current else { throw TIError.syntax }

        switch token {
        case .number(let value):
            advance()
            return .number(value)

        case .variable(let name):
            advance()
            return .variable(name)

        case .ans:
            advance()
            return .ans

        case .constant(let id):
            advance()
            return .constant(id)

        case .negation:
            advance()
            return .negation(try parseExpression(minimumBindingPower: BindingPower.negation))

        case .binaryOperator(.subtract):
            // The subtraction key in prefix position reads as negation, as on the TI.
            advance()
            return .negation(try parseExpression(minimumBindingPower: BindingPower.negation))

        case .leftParenthesis:
            advance()
            let inner = try parseExpression(minimumBindingPower: 0)
            try consumeClosingParenthesis()
            return inner

        case .function(let id):
            advance()
            return .call(id, try parseArguments(for: id))

        case .statVariable(let variable):
            advance()
            return .statVariable(variable)

        case .listName(let name):
            advance()
            return .listVariable(name)

        case .matrixName(let name):
            advance()
            return .matrixVariable(name)

        case .leftBrace:
            return try parseListLiteral()

        case .leftBracket:
            return try parseMatrixLiteral()

        default:
            throw TIError.syntax
        }
    }

    /// Arguments of a prefix call. Arity is checked against the catalog here, so the parser never
    /// spells a function's name or its argument count itself.
    private mutating func parseArguments(for id: FunctionID) throws -> [Expression] {
        guard let definition = FunctionCatalog.definition(for: id) else { throw TIError.undefined }
        guard case .leftParenthesis = current else { throw TIError.syntax }
        advance()

        var arguments: [Expression] = []
        if case .rightParenthesis = current {
            advance()
        } else {
            while true {
                arguments.append(try parseExpression(minimumBindingPower: 0))
                if case .comma = current {
                    advance()
                    continue
                }
                try consumeClosingParenthesis()
                break
            }
        }

        guard definition.arity.contains(arguments.count) else { throw TIError.syntax }
        return arguments
    }

    /// Consumes `)`, or records an auto-close when the input simply ended — pressing ENTER on the
    /// TI closes any parentheses still open.
    private mutating func consumeClosingParenthesis() throws {
        if case .rightParenthesis = current {
            advance()
            return
        }
        guard current == nil else { throw TIError.syntax }
        autoClosedParentheses = true
    }

    /// Named infix operators sit between `*` `/` and negation, as `nPr`/`nCr` do on the TI;
    /// `and` and `or`/`xor` sit below the relational operators.
    private func bindingPower(forInfix id: FunctionID) -> Int {
        switch id {
        case .logicalOr, .logicalXor: BindingPower.logicalOr
        case .logicalAnd: BindingPower.logicalAnd
        default: BindingPower.permutation
        }
    }

    /// Whether a token can begin an operand, which is what makes juxtaposition a product.
    private func startsOperand(_ token: Token) -> Bool {
        switch token {
        case .number, .variable, .ans, .constant, .function, .leftParenthesis: true
        case .statVariable: true
        case .listName, .matrixName, .leftBrace, .leftBracket: true
        default: false
        }
    }
}
