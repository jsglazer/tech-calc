import Foundation

/// The AST-to-LaTeX serializer.
///
/// It exists for export — Copy as LaTeX, and the Markdown history export — and for nothing else.
/// What the history pane *draws* is laid out by `TypesetLayout` walking the same tree directly;
/// no on-screen rendering path goes through this file, and nothing here imports a UI framework.
///
/// It is a pure string transform: `Expression` in, LaTeX out, no context and no formatter state
/// beyond the one handed in for values.
public enum LaTeXSerializer {

    // MARK: - Entry points

    /// The LaTeX for a parsed entry.
    public static func latex(for expression: Expression) -> String {
        latex(expression, minimumBindingPower: 0)
    }

    /// The LaTeX for an entry line, or `nil` when it does not parse.
    public static func latex(forInput input: String) -> String? {
        guard let parsed = try? Parser.parse(input) else { return nil }
        return latex(for: parsed.expression)
    }

    /// The LaTeX for a computed value. Lists and matrices become their bracketed forms; a scalar
    /// is set with the same digits the display shows, so the export and the screen agree.
    public static func latex(for value: TIValue, formatter: DisplayFormatter = DisplayFormatter()) -> String {
        switch value {
        case .real(let x):
            return number(x, formatter: formatter)
        case .complex(let z):
            return escaped(formatter.string(forComplex: z))
        case .list(let list):
            let elements = list.values.map { escaped(formatter.string(forComplex: $0)) }
            return "\\left\\" + openBrace + elements.joined(separator: ",\\;") + "\\right\\" + closeBrace
        case .matrix(let matrix):
            var rows: [String] = []
            for row in 1...Swift.max(1, matrix.rows) {
                var cells: [String] = []
                for column in 1...Swift.max(1, matrix.columns) {
                    let element = (try? matrix[tiRow: row, tiColumn: column]) ?? .zero
                    cells.append(escaped(formatter.string(forComplex: element)))
                }
                rows.append(cells.joined(separator: " & "))
            }
            return "\\begin{bmatrix}" + rows.joined(separator: " \\\\ ") + "\\end{bmatrix}"
        case .string(let text):
            return "\\text" + openBrace + escaped(text) + closeBrace
        }
    }

    // MARK: - Expressions

    /// `minimumBindingPower` is the parser's own precedence scale, so the parenthesisation here
    /// is decided by the same numbers that decided the parse rather than by a second table.
    private static func latex(_ expression: Expression, minimumBindingPower: Int) -> String {
        switch expression {
        case .number(let value):
            return number(value)

        case .variable(let name):
            return variable(name)

        case .ans:
            return "\\mathrm" + braced(Tokenizer.answerSpelling)

        case .constant(let id):
            return FunctionCatalog.latexCommand(for: id) ?? operatorName(id)

        case .binary(let op, let lhs, let rhs):
            return binary(op, lhs, rhs, minimumBindingPower: minimumBindingPower)

        case .negation(let operand):
            let inner = "-" + latex(operand, minimumBindingPower: BindingPower.negation)
            return parenthesise(inner, when: minimumBindingPower > BindingPower.negation)

        case .call(let id, let arguments):
            return call(id, arguments, minimumBindingPower: minimumBindingPower)

        case .displayConversion(let id, let inner):
            let mark = FunctionCatalog.definition(for: id).map { conversionMark($0.name) } ?? ""
            return latex(inner, minimumBindingPower: BindingPower.displayConversion) + mark

        case .store(let value, let target):
            return latex(value, minimumBindingPower: 0) + " \\rightarrow " + latex(storeTarget: target)

        case .listLiteral(let elements):
            let parts = elements.map { latex($0, minimumBindingPower: 0) }
            return "\\left\\" + openBrace + parts.joined(separator: ",\\;") + "\\right\\" + closeBrace

        case .matrixLiteral(let rows):
            let body = rows.map { row in
                row.map { latex($0, minimumBindingPower: 0) }.joined(separator: " & ")
            }
            return "\\begin{bmatrix}" + body.joined(separator: " \\\\ ") + "\\end{bmatrix}"

        case .statVariable(let variable):
            return variable.latexName

        case .listVariable(let name):
            return container(name.key)

        case .matrixVariable(let name):
            return container(name.key)

        case .element(let base, let subscripts):
            let indices = subscripts.map { latex($0, minimumBindingPower: 0) }.joined(separator: ",")
            return latex(base, minimumBindingPower: BindingPower.postfix) + "\\left(" + indices + "\\right)"
        }
    }

    private static func binary(
        _ op: BinaryOperator, _ lhs: Expression, _ rhs: Expression, minimumBindingPower: Int
    ) -> String {
        // A quotient becomes a fraction and a power becomes a script, and both of those carry
        // their own grouping, so neither needs the operand parentheses the flat operators do.
        switch op {
        case .divide:
            return "\\frac" + braced(latex(lhs, minimumBindingPower: 0)) + braced(latex(rhs, minimumBindingPower: 0))
        case .power:
            let base = latex(lhs, minimumBindingPower: BindingPower.postfix)
            return base + "^" + braced(latex(rhs, minimumBindingPower: 0))
        default:
            break
        }
        let power = op.bindingPower
        let left = latex(lhs, minimumBindingPower: power)
        let right = latex(rhs, minimumBindingPower: op.isRightAssociative ? power : power + 1)
        let body = left + " " + symbol(op) + " " + right
        return parenthesise(body, when: minimumBindingPower > power)
    }

    private static func call(_ id: FunctionID, _ arguments: [Expression], minimumBindingPower: Int) -> String {
        let rendered = arguments.map { latex($0, minimumBindingPower: 0) }

        switch id {
        case .squareRoot where rendered.count == 1:
            return "\\sqrt" + braced(rendered[0])
        case .cubeRoot where rendered.count == 1:
            return "\\sqrt[3]" + braced(rendered[0])
        case .nthRoot where rendered.count == 2:
            return "\\sqrt\u{5B}" + rendered[0] + "\u{5D}" + braced(rendered[1])
        case .absoluteValue where rendered.count == 1:
            return "\\left|" + rendered[0] + "\\right|"
        case .square, .cube, .reciprocal, .factorial:
            guard let first = arguments.first else { break }
            let base = latex(first, minimumBindingPower: BindingPower.postfix)
            switch id {
            case .square: return base + "^" + braced("2")
            case .cube: return base + "^" + braced("3")
            case .reciprocal: return base + "^" + braced("-1")
            default: return base + "!"
            }
        case .logBase where rendered.count == 2:
            return "\\log_" + braced(rendered[1]) + "\\left(" + rendered[0] + "\\right)"
        case .permutations where rendered.count == 2:
            return "{}_" + braced(rendered[0]) + "P_" + braced(rendered[1])
        case .combinations where rendered.count == 2:
            return "{}_" + braced(rendered[0]) + "C_" + braced(rendered[1])
        case .conjugate where rendered.count == 1:
            return "\\overline" + braced(rendered[0])
        case .summation where rendered.count >= 4:
            // summation(expression, variable, lower, upper)
            return "\\sum_" + braced(rendered[1] + "=" + rendered[2]) + "^" + braced(rendered[3])
                + "\\left(" + rendered[0] + "\\right)"
        case .numericIntegral where rendered.count >= 4:
            // fnInt(expression, variable, lower, upper)
            return "\\int_" + braced(rendered[2]) + "^" + braced(rendered[3])
                + "\\left(" + rendered[0] + "\\right)\\,d" + rendered[1]
        default:
            break
        }

        let head = FunctionCatalog.latexCommand(for: id) ?? operatorName(id)
        guard !rendered.isEmpty else { return head }
        let body = head + "\\left(" + rendered.joined(separator: ",\\;") + "\\right)"
        return parenthesise(body, when: minimumBindingPower > BindingPower.postfix)
    }

    private static func latex(storeTarget target: StoreTarget) -> String {
        switch target {
        case .variable(let name):
            return variable(name)
        case .randomSeed:
            return FunctionCatalog.definition(for: .random).map { operatorName($0.name) } ?? ""
        case .list(let name), .listDimension(let name):
            return container(name.key)
        case .matrix(let name), .matrixDimension(let name):
            return container(name.key)
        case .listElement(let name, let index):
            return container(name.key) + "\\left(" + latex(index, minimumBindingPower: 0) + "\\right)"
        case .matrixElement(let name, let row, let column):
            return container(name.key) + "\\left("
                + latex(row, minimumBindingPower: 0) + "," + latex(column, minimumBindingPower: 0)
                + "\\right)"
        }
    }

    // MARK: - Pieces

    private static func symbol(_ op: BinaryOperator) -> String {
        switch op {
        case .add: "+"
        case .subtract: "-"
        case .multiply: "\\times"
        case .divide: "\\div"
        case .power: "^"
        case .equal: "="
        case .notEqual: "\\ne"
        case .less: "<"
        case .lessEqual: "\\le"
        case .greater: ">"
        case .greaterEqual: "\\ge"
        }
    }

    /// The TI writes θ; LaTeX has a command for it and for nothing else in the variable set.
    private static func variable(_ name: Character) -> String {
        name == "\u{03B8}" ? "\\theta" : String(name)
    }

    /// A container name is set upright and whole — the stored spelling comes from `ContainerName`,
    /// so the brackets and the list mark are never written down here.
    private static func container(_ key: String) -> String {
        "\\mathrm" + braced(escaped(key))
    }

    private static func operatorName(_ id: FunctionID) -> String {
        operatorName(FunctionCatalog.definition(for: id)?.name ?? id.rawValue)
    }

    private static func operatorName(_ name: String) -> String {
        "\\operatorname" + braced(escaped(name))
    }

    /// A display conversion is a mark on the answer, not a function of it: `2/3 ▸Frac` is set as
    /// the expression followed by the same mark the entry line shows.
    private static func conversionMark(_ name: String) -> String {
        let label = String(name.drop { !$0.isLetter && !$0.isNumber })
        return "\\;\\blacktriangleright\\mathrm" + braced(escaped(label))
    }

    private static func parenthesise(_ body: String, when needed: Bool) -> String {
        needed ? "\\left(" + body + "\\right)" : body
    }

    private static func braced(_ body: String) -> String {
        openBrace + body + closeBrace
    }

    private static let openBrace = "\u{7B}"
    private static let closeBrace = "\u{7D}"

    /// The characters LaTeX reads as markup. A TI name like `tvm_I%` has to survive export.
    static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\\": result += "\\textbackslash "
            case "_", "%", "&", "#", "$": result += "\\" + String(character)
            case "^": result += "\\textasciicircum "
            case "~": result += "\\textasciitilde "
            default: result.append(character)
            }
        }
        return result
    }

    /// A literal, set the way the display formatter would write it and then made LaTeX-safe.
    /// The TI's exponent glyph becomes a real power of ten rather than a stray character.
    static func number(_ value: Double, formatter: DisplayFormatter = DisplayFormatter()) -> String {
        let text = formatter.string(forReal: value)
        guard let exponentIndex = text.firstIndex(of: DisplayFormatter.exponentGlyph) else {
            return escaped(text)
        }
        let mantissa = String(text[text.startIndex..<exponentIndex])
        let exponent = String(text[text.index(after: exponentIndex)...])
        return escaped(mantissa) + " \\times 10^" + braced(escaped(exponent))
    }
}
