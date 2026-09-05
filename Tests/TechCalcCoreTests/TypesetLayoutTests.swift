import Foundation
import Testing
@testable import TechCalcCore

/// The renderer draws boxes it does not compute. Every measurement below is therefore checkable
/// without a view, a font object or a screen — which is the point of computing the geometry in the
/// core rather than inside SwiftUI.
@Suite("Typeset layout")
struct TypesetLayoutTests {
    private let metrics = TypesetMetrics.default
    private let size = 20.0

    private func layout(_ node: TypesetNode) -> TypesetBox {
        TypesetLayout.layout(node, metrics: metrics, fontSize: size)
    }

    private func layout(_ input: String) throws -> TypesetBox {
        let parsed = try Parser.parse(input)
        return layout(TypesetBuilder().node(for: parsed.expression))
    }

    @Test("A run of text is as wide as its advance width and as tall as the face")
    func textGeometry() {
        let box = layout(.text("abc"))
        #expect(box.width == 3 * metrics.advance * size)
        #expect(box.ascent == metrics.ascent * size)
        #expect(box.descent == metrics.descent * size)
        #expect(box.height == box.ascent + box.descent)
    }

    @Test("A row is the sum of its parts, laid left to right on one baseline")
    func rowGeometry() {
        let box = layout(.row([.text("ab"), .text("c")]))
        #expect(box.width == 3 * metrics.advance * size)
        #expect(box.children.count == 2)
        #expect(box.children[0].x == 0)
        #expect(box.children[1].x == 2 * metrics.advance * size)
        #expect(box.children.allSatisfy { $0.baselineShift == 0 })
    }

    @Test("A fraction is as wide as its wider part plus padding, and taller than both")
    func fractionGeometry() {
        let numerator = TypesetNode.text("1")
        let denominator = TypesetNode.text("100")
        let box = layout(.fraction(numerator: numerator, denominator: denominator))
        let denominatorWidth = layout(denominator).width
        #expect(box.width == denominatorWidth + 2 * metrics.fractionPadding * size)
        #expect(box.height > layout(numerator).height + layout(denominator).height)
        // Numerator above the bar, denominator below it, bar on the maths axis.
        #expect(box.children[0].baselineShift > 0)
        #expect(box.children[2].baselineShift < 0)
        #expect(box.children[1].box.content == .rule)
    }

    @Test("The shorter part of a fraction is centred over the longer one")
    func fractionCentring() {
        let box = layout(.fraction(numerator: .text("1"), denominator: .text("100")))
        let numerator = box.children[0]
        let denominator = box.children[2]
        #expect(numerator.x > denominator.x)
        #expect(abs((numerator.x + numerator.box.width / 2) - (denominator.x + denominator.box.width / 2)) < 1e-9)
    }

    @Test("A nested fraction grows the outer one")
    func nestedFractions() {
        let inner = TypesetNode.fraction(numerator: .text("1"), denominator: .text("2"))
        let flat = layout(.fraction(numerator: .text("1"), denominator: .text("2")))
        let nested = layout(.fraction(numerator: inner, denominator: .text("2")))
        #expect(nested.height > flat.height)
    }

    @Test("An exponent is set smaller and raised; a subscript is set smaller and dropped")
    func scriptGeometry() {
        let superscript = layout(.superscripted(base: .text("2"), exponent: .text("3")))
        #expect(superscript.children[1].box.fontSize == metrics.scriptSize(from: size))
        #expect(superscript.children[1].baselineShift == metrics.superscriptShift * size)
        #expect(superscript.ascent > layout(.text("2")).ascent)

        let subscripted = layout(.subscripted(base: .text("L"), index: .text("1")))
        #expect(subscripted.children[1].baselineShift == -metrics.subscriptShift * size)
        #expect(subscripted.descent > layout(.text("L")).descent)
    }

    @Test("Scripts stop shrinking at the minimum size, however deeply they nest")
    func scriptsHaveAFloor() {
        var node = TypesetNode.text("2")
        for _ in 0..<12 { node = .superscripted(base: .text("2"), exponent: node) }
        let box = layout(node)
        func smallest(_ box: TypesetBox) -> Double {
            box.children.reduce(box.fontSize) { Swift.min($0, smallest($1.box)) }
        }
        #expect(smallest(box) >= metrics.minimumFontSize)
    }

    @Test("A radical reserves its hook and clears its radicand")
    func radicalGeometry() {
        let radicand = TypesetNode.text("16")
        let box = layout(.radical(index: nil, radicand: radicand))
        let inner = layout(radicand)
        #expect(box.width == metrics.radicalHook * size + inner.width)
        #expect(box.ascent > inner.ascent)
        #expect(box.children[0].box.content == .radicalSign)
        #expect(box.children[1].x == metrics.radicalHook * size)
    }

    @Test("A degree wider than the hook pushes the radicand right rather than overprinting it")
    func radicalDegree() {
        let plain = layout(.radical(index: nil, radicand: .text("16")))
        let wide = layout(.radical(index: .text("1000"), radicand: .text("16")))
        #expect(wide.width > plain.width)
        #expect(wide.children.count == 3)
        #expect(wide.children[2].baselineShift > 0)
    }

    @Test("A fence adds one width either side and stretches to what it encloses")
    func fenceGeometry() {
        let inner = TypesetNode.fraction(numerator: .text("1"), denominator: .text("2"))
        let box = layout(.fenced(.parenthesis, inner))
        let content = layout(inner)
        #expect(box.width == content.width + 2 * metrics.fenceWidth * size)
        #expect(box.children[0].box.content == .fence(.parenthesis, leading: true))
        #expect(box.children[2].box.content == .fence(.parenthesis, leading: false))
        #expect(box.children[0].box.height > layout(.text("1")).height)
    }

    @Test("Matrix columns align on the widest entry in the column")
    func matrixAlignment() {
        let box = layout(.matrix([[.text("1"), .text("2")], [.text("300"), .text("4")]]))
        // The bracket fence wraps the grid; the grid itself is its middle child.
        let grid = box.children[1].box
        #expect(grid.children.count == 4)
        let firstColumn = [grid.children[0], grid.children[2]]
        let secondColumn = [grid.children[1], grid.children[3]]
        // Centres of a column line up, and the second column starts after the widest first entry.
        let firstCentres = firstColumn.map { $0.x + $0.box.width / 2 }
        #expect(abs(firstCentres[0] - firstCentres[1]) < 1e-9)
        #expect(secondColumn.allSatisfy { $0.x > firstColumn.map(\.box.width).max()! })
    }

    @Test("A matrix is bracketed and centred on the maths axis")
    func matrixFraming() {
        let box = layout(.matrix([[.text("1")], [.text("2")]]))
        #expect(box.children[0].box.content == .fence(.bracket, leading: true))
        let grid = box.children[1].box
        #expect(abs((grid.ascent - grid.descent) / 2 - metrics.axis * size) < 1e-9)
    }

    @Test("An empty matrix lays out without dividing by zero")
    func emptyMatrix() {
        let box = layout(.matrix([]))
        #expect(box.width == 0)
        #expect(box.height > 0)
    }

    @Test("The builder turns division into a fraction and a power into a script")
    func builderShapes() throws {
        let box = try layout("1/2")
        #expect(box.children.count == 3)
        #expect(box.children[1].box.content == .rule)

        let power = try layout("2^3")
        #expect(power.children[1].baselineShift > 0)
    }

    @Test("The builder draws a matrix result as a matrix, not as a line of text")
    func builderValues() throws {
        let matrix = try TIMatrix(rows: 2, columns: 2, values: [Complex(1), Complex(2), Complex(3), Complex(4)])
        let node = TypesetBuilder().node(for: .matrix(matrix))
        guard case .matrix(let rows) = node else {
            Issue.record("a matrix value should typeset as a matrix")
            return
        }
        #expect(rows.count == 2)
        #expect(rows[0].count == 2)
        let box = layout(node)
        #expect(box.height > layout(.text("1")).height * 2)
    }

    @Test("A layout is a pure function: the same node lays out identically every time")
    func layoutIsDeterministic() throws {
        let node = TypesetBuilder().node(forInput: "\u{221A}(1/2)+3\u{00B2}")
        #expect(node != nil)
        #expect(layout(node!) == layout(node!))
    }
}
