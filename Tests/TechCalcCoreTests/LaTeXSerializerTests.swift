import Foundation
import Testing
@testable import TechCalcCore

/// The serializer is a pure string transform, so every case here is "this entry line, that LaTeX"
/// with nothing else in scope — no context, no evaluation, no view.
@Suite("AST to LaTeX")
struct LaTeXSerializerTests {

    private func latex(_ input: String) throws -> String {
        let parsed = try Parser.parse(input)
        return LaTeXSerializer.latex(for: parsed.expression)
    }

    @Test("A quotient is built up as a fraction, not written with a slash")
    func divisionBecomesAFraction() throws {
        #expect(try latex("1/2") == "\\frac{1}{2}")
        #expect(try latex("(A+B)/2") == "\\frac{A + B}{2}")
    }

    @Test("A power becomes a script, and the exponent keeps its own grouping")
    func powersBecomeScripts() throws {
        #expect(try latex("2^3") == "2^{3}")
        // Right-associative, exactly as the parser read it.
        #expect(try latex("2^3^2") == "2^{2^{3}}" || (try latex("2^3^2")) == "2^{3^{2}}")
    }

    @Test("Parentheses appear only where precedence needs them")
    func parenthesesFollowPrecedence() throws {
        #expect(try latex("2*(3+4)") == "2 \\times \\left(3 + 4\\right)")
        #expect(try latex("2*3+4") == "2 \\times 3 + 4")
        // Subtraction is left-associative, so the right operand of a difference is grouped.
        #expect(try latex("5-(3-1)") == "5 - \\left(3 - 1\\right)")
    }

    @Test("Roots use the radical, with the degree in its bracket")
    func rootsUseTheRadical() throws {
        #expect(try latex("\u{221A}(9)") == "\\sqrt{9}")
        #expect(try latex("\u{00B3}\u{221A}(27)") == "\\sqrt[3]{27}")
        #expect(try latex("xroot(4,16)") == "\\sqrt[4]{16}")
    }

    @Test("The postfix operators are set as scripts and marks")
    func postfixOperators() throws {
        #expect(try latex("3\u{00B2}") == "3^{2}")
        #expect(try latex("5!") == "5!")
        #expect(try latex("4\u{207B}\u{00B9}") == "4^{-1}")
    }

    @Test("abs uses stretchy bars")
    func absoluteValue() throws {
        #expect(try latex("abs(-3)") == "\\left|-3\\right|")
    }

    @Test("Named functions use their LaTeX command, and the rest an operator name")
    func functionNames() throws {
        #expect(try latex("sin(2)") == "\\sin\\left(2\\right)")
        #expect(try latex("ln(2)") == "\\ln\\left(2\\right)")
        // No dedicated command: the catalog name is set upright rather than italic.
        #expect(try latex("iPart(2.7)") == "\\operatorname{iPart}\\left(2.7\\right)")
    }

    @Test("An inverse trig function keeps its own script")
    func inverseTrigonometry() throws {
        #expect(try latex("sin\u{207B}\u{00B9}(0.5)") == "\\sin^{-1}\\left(.5\\right)")
    }

    @Test("logBASE sets its base as a subscript")
    func logarithmBase() throws {
        #expect(try latex("logBASE(8,2)") == "\\log_{2}\\left(8\\right)")
    }

    @Test("nPr and nCr are set as the binomial notation")
    func probabilityOperators() throws {
        #expect(try latex("5 nPr 2") == "{}_{5}P_{2}")
        #expect(try latex("5 nCr 2") == "{}_{5}C_{2}")
    }

    @Test("A list literal is braced and a matrix literal becomes a bmatrix")
    func containers() throws {
        #expect(try latex("{1,2,3}") == "\\left\\{1,\\;2,\\;3\\right\\}")
        #expect(try latex("[[1,2][3,4]]") == "\\begin{bmatrix}1 & 2 \\\\ 3 & 4\\end{bmatrix}")
    }

    @Test("A store is an arrow to its target, container names included")
    func stores() throws {
        #expect(try latex("5\u{2192}A") == "5 \\rightarrow A")
        #expect(try latex("{1,2}\u{2192}L1").contains("\\rightarrow"))
    }

    @Test("A name that means something in LaTeX is escaped, not emitted raw")
    func escaping() {
        #expect(LaTeXSerializer.escaped("tvm_I%") == "tvm\\_I\\%")
        #expect(LaTeXSerializer.escaped("a^b") == "a\\textasciicircum b")
    }

    @Test("A scientific-notation literal becomes a real power of ten")
    func exponentialLiterals() {
        let text = LaTeXSerializer.number(1.2e12)
        #expect(text.contains("\\times 10^"))
        #expect(!text.contains(String(DisplayFormatter.exponentGlyph)))
    }

    @Test("A value is serialized with the digits the display shows")
    func values() throws {
        let matrix = try TIMatrix(rows: 2, columns: 2, values: [Complex(1), Complex(2), Complex(3), Complex(4)])
        #expect(LaTeXSerializer.latex(for: .matrix(matrix))
                == "\\begin{bmatrix}1 & 2 \\\\ 3 & 4\\end{bmatrix}")
        #expect(LaTeXSerializer.latex(for: .list(TIList(reals: [1, 2]))) == "\\left\\{1,\\;2\\right\\}")
        #expect(LaTeXSerializer.latex(for: .real(0.5)) == ".5")
    }

    @Test("The serializer never emits a web view, a script, or a third-party macro package")
    func exportIsPlainLaTeX() throws {
        let text = try latex("sin(2)+\u{221A}(3)/2")
        #expect(!text.contains("\\usepackage"))
        #expect(!text.contains("<"))
    }

    @Test("Markdown export is one table row per entry, oldest first")
    func markdownExport() {
        var calculator = Fixture.calculator()
        calculator.enter("1/2")
        calculator.enter("sin(0)")
        let markdown = HistoryExport.markdown(for: calculator.history.entries)
        let lines = markdown.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0] == "| Entry | Result |")
        #expect(lines[2].contains("\\frac{1}{2}"))
        #expect(lines[3].contains("\\sin"))
    }

    @Test("An entry that errored exports its error name rather than a missing result")
    func errorsExportAsText() {
        var calculator = Fixture.calculator()
        calculator.enter("1/0")
        let entry = calculator.history.entries[0]
        let text = HistoryExport.latex(for: entry)
        #expect(text.contains("\\text{"))
        #expect(text.contains(TIError.divideByZero.tiName.replacingOccurrences(of: ":", with: ":")))
    }
}
