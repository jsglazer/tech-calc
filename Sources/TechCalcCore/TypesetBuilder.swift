import Foundation

/// Builds the typeset shape of an expression or a value.
///
/// This is the *drawing* path: the history pane renders what comes out of here directly, without
/// ever going through LaTeX. `LaTeXSerializer` is the export path and the two are independent
/// walks of the same AST, which is what Decision 16 asks for.
public struct TypesetBuilder: Sendable {
    public let formatter: DisplayFormatter

    public init(formatter: DisplayFormatter = DisplayFormatter()) {
        self.formatter = formatter
    }

    // MARK: - Entry points

    public func node(for expression: Expression) -> TypesetNode {
        node(expression, minimumBindingPower: 0)
    }

    /// The typeset shape of an entry line, or `nil` when it does not parse — in which case the
    /// pane falls back to showing the text as typed.
    public func node(forInput input: String) -> TypesetNode? {
        guard let parsed = try? Parser.parse(input) else { return nil }
        return node(for: parsed.expression)
    }

    public func node(for value: TIValue) -> TypesetNode {
        switch value {
        case .real, .complex, .string:
            return .text(formatter.string(for: value))
        case .list(let list):
            return .fenced(.brace, .row(commaSeparated(list.values.map {
                TypesetNode.text(formatter.string(forComplex: $0))
            })))
        case .matrix(let matrix):
            var rows: [[TypesetNode]] = []
            for row in 1...Swift.max(1, matrix.rows) {
                var cells: [TypesetNode] = []
                for column in 1...Swift.max(1, matrix.columns) {
                    let element = (try? matrix[tiRow: row, tiColumn: column]) ?? .zero
                    cells.append(.text(formatter.string(forComplex: element)))
                }
                rows.append(cells)
            }
            return .matrix(rows)
        }
    }

    // MARK: - Expressions

    private func node(_ expression: Expression, minimumBindingPower: Int) -> TypesetNode {
        switch expression {
        case .number(let value):
            return .text(formatter.string(forReal: value))

        case .variable(let name):
            return .text(String(name))

        case .ans:
            return .text(Tokenizer.answerSpelling)

        case .constant(let id):
            return .text(name(of: id))

        case .binary(let op, let lhs, let rhs):
            return binary(op, lhs, rhs, minimumBindingPower: minimumBindingPower)

        case .negation(let operand):
            let inner = TypesetNode.row([.text(Self.minus), node(operand, minimumBindingPower: BindingPower.negation)])
            return fence(inner, when: minimumBindingPower > BindingPower.negation)

        case .call(let id, let arguments):
            return call(id, arguments)

        case .displayConversion(let id, let inner):
            return .row([node(inner, minimumBindingPower: BindingPower.displayConversion), .text(name(of: id))])

        case .store(let value, let target):
            return .row([node(value, minimumBindingPower: 0), .text(Self.storeArrow), node(storeTarget: target)])

        case .listLiteral(let elements):
            return .fenced(.brace, .row(commaSeparated(elements.map { node($0, minimumBindingPower: 0) })))

        case .matrixLiteral(let rows):
            return .matrix(rows.map { $0.map { node($0, minimumBindingPower: 0) } })

        case .statVariable(let variable):
            return .text(variable.name)

        case .listVariable(let name):
            return .text(name.key)

        case .matrixVariable(let name):
            return .text(name.key)

        case .element(let base, let subscripts):
            return .row([
                node(base, minimumBindingPower: BindingPower.postfix),
                .fenced(.parenthesis, .row(commaSeparated(subscripts.map { node($0, minimumBindingPower: 0) })))
            ])
        }
    }

    private func binary(
        _ op: BinaryOperator, _ lhs: Expression, _ rhs: Expression, minimumBindingPower: Int
    ) -> TypesetNode {
        // Division becomes a built-up fraction and a power becomes a raised script; both carry
        // their own grouping, so neither needs the parentheses a flat operator would.
        switch op {
        case .divide:
            return .fraction(
                numerator: node(lhs, minimumBindingPower: 0),
                denominator: node(rhs, minimumBindingPower: 0)
            )
        case .power:
            return .superscripted(
                base: node(lhs, minimumBindingPower: BindingPower.postfix),
                exponent: node(rhs, minimumBindingPower: 0)
            )
        default:
            break
        }
        let power = op.bindingPower
        let body = TypesetNode.row([
            node(lhs, minimumBindingPower: power),
            .text(" " + symbol(op) + " "),
            node(rhs, minimumBindingPower: op.isRightAssociative ? power : power + 1)
        ])
        return fence(body, when: minimumBindingPower > power)
    }

    private func call(_ id: FunctionID, _ arguments: [Expression]) -> TypesetNode {
        let parts = arguments.map { node($0, minimumBindingPower: 0) }

        switch id {
        case .squareRoot where parts.count == 1:
            return .radical(index: nil, radicand: parts[0])
        case .cubeRoot where parts.count == 1:
            return .radical(index: .text("3"), radicand: parts[0])
        case .nthRoot where parts.count == 2:
            return .radical(index: parts[0], radicand: parts[1])
        case .absoluteValue where parts.count == 1:
            return .fenced(.bar, parts[0])
        case .square where parts.count == 1:
            return .superscripted(base: parts[0], exponent: .text("2"))
        case .cube where parts.count == 1:
            return .superscripted(base: parts[0], exponent: .text("3"))
        case .reciprocal where parts.count == 1:
            return .superscripted(base: parts[0], exponent: .text(Self.minus + "1"))
        case .factorial where parts.count == 1:
            return .row([parts[0], .text(name(of: .factorial))])
        case .logBase where parts.count == 2:
            return .row([
                .subscripted(base: .text(name(of: .log)), index: parts[1]),
                .fenced(.parenthesis, parts[0])
            ])
        default:
            break
        }

        guard !parts.isEmpty else { return .text(name(of: id)) }
        return .row([.text(name(of: id)), .fenced(.parenthesis, .row(commaSeparated(parts)))])
    }

    private func node(storeTarget target: StoreTarget) -> TypesetNode {
        switch target {
        case .variable(let name):
            return .text(String(name))
        case .randomSeed:
            return .text(name(of: .random))
        case .list(let name), .listDimension(let name):
            return .text(name.key)
        case .matrix(let name), .matrixDimension(let name):
            return .text(name.key)
        case .listElement(let name, let index):
            return .row([.text(name.key), .fenced(.parenthesis, node(index, minimumBindingPower: 0))])
        case .matrixElement(let name, let row, let column):
            return .row([
                .text(name.key),
                .fenced(.parenthesis, .row(commaSeparated([
                    node(row, minimumBindingPower: 0), node(column, minimumBindingPower: 0)
                ])))
            ])
        }
    }

    // MARK: - Pieces

    /// A function's spelling comes from the catalog, here as everywhere else.
    private func name(of id: FunctionID) -> String {
        FunctionCatalog.definition(for: id)?.name ?? id.rawValue
    }

    private func symbol(_ op: BinaryOperator) -> String {
        switch op {
        case .add: "+"
        case .subtract: Self.minus
        case .multiply: "\u{00D7}"
        case .divide: "\u{00F7}"
        case .power: "^"
        case .equal: "="
        case .notEqual: "\u{2260}"
        case .less: "<"
        case .lessEqual: "\u{2264}"
        case .greater: ">"
        case .greaterEqual: "\u{2265}"
        }
    }

    private func fence(_ node: TypesetNode, when needed: Bool) -> TypesetNode {
        needed ? .fenced(.parenthesis, node) : node
    }

    private func commaSeparated(_ parts: [TypesetNode]) -> [TypesetNode] {
        var result: [TypesetNode] = []
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(.text(", ")) }
            result.append(part)
        }
        return result
    }

    /// The TI's minus is a true minus sign, not a hyphen.
    static let minus = "\u{2212}"
    static let storeArrow = "\u{2192}"
}
