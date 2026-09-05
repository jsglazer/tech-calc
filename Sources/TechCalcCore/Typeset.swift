import Foundation

/// A fence around a sub-expression. The glyph itself is drawn by the renderer as a stroke, not
/// set as a character, so it stretches to whatever it encloses.
public enum FenceKind: String, Equatable, Hashable, Sendable {
    case parenthesis
    case bracket
    case brace
    /// The pair of vertical rules `abs(` is set between.
    case bar
}

/// The shape of typeset mathematics, independent of how it is drawn.
///
/// This is what a recursive renderer walks. It carries no geometry: `TypesetLayout` turns it into
/// positioned boxes, and every measurement is therefore computable — and assertable — without a
/// view, a font object or a screen.
public indirect enum TypesetNode: Equatable, Sendable {
    case text(String)
    case row([TypesetNode])
    case fraction(numerator: TypesetNode, denominator: TypesetNode)
    case radical(index: TypesetNode?, radicand: TypesetNode)
    case superscripted(base: TypesetNode, exponent: TypesetNode)
    case subscripted(base: TypesetNode, index: TypesetNode)
    case fenced(FenceKind, TypesetNode)
    case matrix([[TypesetNode]])

    public static let empty = TypesetNode.row([])
}

/// The font-independent proportions the layout is computed from.
///
/// Every value is a ratio of the current font size, so the layout is a pure function of the node
/// and this struct: two runs with the same metrics produce byte-identical boxes, and a test can
/// assert a fraction's height in closed form.
public struct TypesetMetrics: Equatable, Sendable {
    /// Advance width of one character, as a fraction of the font size. The renderer draws in a
    /// monospaced face, where this is exact rather than an approximation.
    public var advance: Double
    public var ascent: Double
    public var descent: Double
    /// How much smaller a script (exponent, index, radical degree) is set.
    public var scriptScale: Double
    /// Scripts stop shrinking here, so a deeply nested exponent stays legible.
    public var minimumFontSize: Double
    /// Height of the maths axis — where a fraction bar sits — above the baseline.
    public var axis: Double
    public var ruleThickness: Double
    /// Vertical clearance between a fraction bar and its numerator or denominator.
    public var fractionGap: Double
    /// Horizontal padding either side of a fraction's shorter part.
    public var fractionPadding: Double
    public var superscriptShift: Double
    public var subscriptShift: Double
    /// Width of the radical's hook, before its overbar starts.
    public var radicalHook: Double
    public var radicalGap: Double
    public var fenceWidth: Double
    public var fencePadding: Double
    public var matrixColumnGap: Double
    public var matrixRowGap: Double

    public init(
        advance: Double = 0.60,
        ascent: Double = 0.78,
        descent: Double = 0.22,
        scriptScale: Double = 0.72,
        minimumFontSize: Double = 7,
        axis: Double = 0.28,
        ruleThickness: Double = 0.05,
        fractionGap: Double = 0.12,
        fractionPadding: Double = 0.12,
        superscriptShift: Double = 0.45,
        subscriptShift: Double = 0.20,
        radicalHook: Double = 0.55,
        radicalGap: Double = 0.10,
        fenceWidth: Double = 0.30,
        fencePadding: Double = 0.06,
        matrixColumnGap: Double = 0.50,
        matrixRowGap: Double = 0.30
    ) {
        self.advance = advance
        self.ascent = ascent
        self.descent = descent
        self.scriptScale = scriptScale
        self.minimumFontSize = minimumFontSize
        self.axis = axis
        self.ruleThickness = ruleThickness
        self.fractionGap = fractionGap
        self.fractionPadding = fractionPadding
        self.superscriptShift = superscriptShift
        self.subscriptShift = subscriptShift
        self.radicalHook = radicalHook
        self.radicalGap = radicalGap
        self.fenceWidth = fenceWidth
        self.fencePadding = fencePadding
        self.matrixColumnGap = matrixColumnGap
        self.matrixRowGap = matrixRowGap
    }

    public static let `default` = TypesetMetrics()

    /// The font size a script is set at, floored so nesting cannot shrink to nothing.
    public func scriptSize(from fontSize: Double) -> Double {
        Swift.max(minimumFontSize, fontSize * scriptScale)
    }
}

/// A laid-out box: what to draw, how big it is, and where its children sit.
///
/// Positions are given as an offset from the parent's left edge and a shift from the parent's
/// baseline (positive is up), which is all a renderer needs and is directly assertable in a test.
public struct TypesetBox: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        /// Characters, set at this box's font size.
        case glyphs(String)
        /// A filled rectangle: the fraction bar.
        case rule
        /// The radical sign — hook and overbar — stroked across the box.
        case radicalSign
        /// One half of a fence pair, stroked to the box's height.
        case fence(FenceKind, leading: Bool)
        /// Structure only; nothing of its own is drawn.
        case group
    }

    public struct Placement: Equatable, Sendable {
        public let box: TypesetBox
        /// Offset from the parent box's left edge.
        public let x: Double
        /// Offset from the parent box's baseline; positive raises the child.
        public let baselineShift: Double

        public init(box: TypesetBox, x: Double, baselineShift: Double) {
            self.box = box
            self.x = x
            self.baselineShift = baselineShift
        }
    }

    public let content: Content
    public let fontSize: Double
    public let width: Double
    public let ascent: Double
    public let descent: Double
    public let children: [Placement]

    public init(
        content: Content,
        fontSize: Double,
        width: Double,
        ascent: Double,
        descent: Double,
        children: [Placement] = []
    ) {
        self.content = content
        self.fontSize = fontSize
        self.width = width
        self.ascent = ascent
        self.descent = descent
        self.children = children
    }

    public var height: Double { ascent + descent }
}

/// Turns a `TypesetNode` into positioned boxes.
///
/// Pure value computation: no view, no font object, no platform call. The renderer's only job is
/// to draw the boxes this returns, which is what keeps "what the maths looks like" testable.
public enum TypesetLayout {

    public static func layout(
        _ node: TypesetNode,
        metrics: TypesetMetrics = .default,
        fontSize: Double
    ) -> TypesetBox {
        switch node {
        case .text(let text):
            return glyphs(text, metrics: metrics, fontSize: fontSize)

        case .row(let parts):
            return row(parts.map { layout($0, metrics: metrics, fontSize: fontSize) },
                       metrics: metrics, fontSize: fontSize)

        case .fraction(let numerator, let denominator):
            return fraction(
                layout(numerator, metrics: metrics, fontSize: fontSize),
                layout(denominator, metrics: metrics, fontSize: fontSize),
                metrics: metrics, fontSize: fontSize
            )

        case .radical(let index, let radicand):
            return radical(
                index.map { layout($0, metrics: metrics, fontSize: metrics.scriptSize(from: fontSize)) },
                layout(radicand, metrics: metrics, fontSize: fontSize),
                metrics: metrics, fontSize: fontSize
            )

        case .superscripted(let base, let exponent):
            return script(
                layout(base, metrics: metrics, fontSize: fontSize),
                layout(exponent, metrics: metrics, fontSize: metrics.scriptSize(from: fontSize)),
                shift: metrics.superscriptShift * fontSize,
                metrics: metrics, fontSize: fontSize
            )

        case .subscripted(let base, let index):
            return script(
                layout(base, metrics: metrics, fontSize: fontSize),
                layout(index, metrics: metrics, fontSize: metrics.scriptSize(from: fontSize)),
                shift: -metrics.subscriptShift * fontSize,
                metrics: metrics, fontSize: fontSize
            )

        case .fenced(let kind, let inner):
            return fenced(kind, layout(inner, metrics: metrics, fontSize: fontSize),
                          metrics: metrics, fontSize: fontSize)

        case .matrix(let rows):
            let cells = rows.map { $0.map { layout($0, metrics: metrics, fontSize: fontSize) } }
            return matrix(cells, metrics: metrics, fontSize: fontSize)
        }
    }

    // MARK: - Pieces

    private static func glyphs(_ text: String, metrics: TypesetMetrics, fontSize: Double) -> TypesetBox {
        TypesetBox(
            content: .glyphs(text),
            fontSize: fontSize,
            width: Double(text.count) * metrics.advance * fontSize,
            ascent: metrics.ascent * fontSize,
            descent: metrics.descent * fontSize
        )
    }

    private static func row(_ boxes: [TypesetBox], metrics: TypesetMetrics, fontSize: Double) -> TypesetBox {
        var placements: [TypesetBox.Placement] = []
        var x = 0.0
        var ascent = metrics.ascent * fontSize
        var descent = metrics.descent * fontSize
        for box in boxes {
            placements.append(TypesetBox.Placement(box: box, x: x, baselineShift: 0))
            x += box.width
            ascent = Swift.max(ascent, box.ascent)
            descent = Swift.max(descent, box.descent)
        }
        return TypesetBox(
            content: .group, fontSize: fontSize,
            width: x, ascent: ascent, descent: descent, children: placements
        )
    }

    private static func fraction(
        _ numerator: TypesetBox, _ denominator: TypesetBox,
        metrics: TypesetMetrics, fontSize: Double
    ) -> TypesetBox {
        let padding = metrics.fractionPadding * fontSize
        let thickness = metrics.ruleThickness * fontSize
        let gap = metrics.fractionGap * fontSize
        let axis = metrics.axis * fontSize
        let width = Swift.max(numerator.width, denominator.width) + 2 * padding

        let bar = TypesetBox(
            content: .rule, fontSize: fontSize,
            width: width, ascent: thickness, descent: 0
        )
        let children = [
            TypesetBox.Placement(
                box: numerator,
                x: (width - numerator.width) / 2,
                baselineShift: axis + thickness / 2 + gap + numerator.descent
            ),
            TypesetBox.Placement(box: bar, x: 0, baselineShift: axis - thickness / 2),
            TypesetBox.Placement(
                box: denominator,
                x: (width - denominator.width) / 2,
                baselineShift: axis - thickness / 2 - gap - denominator.ascent
            )
        ]
        return TypesetBox(
            content: .group, fontSize: fontSize, width: width,
            ascent: axis + thickness / 2 + gap + numerator.height,
            descent: -axis + thickness / 2 + gap + denominator.height,
            children: children
        )
    }

    private static func radical(
        _ index: TypesetBox?, _ radicand: TypesetBox,
        metrics: TypesetMetrics, fontSize: Double
    ) -> TypesetBox {
        let thickness = metrics.ruleThickness * fontSize
        let gap = metrics.radicalGap * fontSize
        // A degree wider than the hook pushes the radicand right rather than overprinting it.
        let hook = Swift.max(metrics.radicalHook * fontSize, (index?.width ?? 0) + thickness)
        let ascent = radicand.ascent + gap + thickness
        let sign = TypesetBox(
            content: .radicalSign, fontSize: fontSize,
            width: hook + radicand.width, ascent: ascent, descent: radicand.descent
        )
        var children = [
            TypesetBox.Placement(box: sign, x: 0, baselineShift: 0),
            TypesetBox.Placement(box: radicand, x: hook, baselineShift: 0)
        ]
        if let index {
            children.append(TypesetBox.Placement(
                box: index, x: 0, baselineShift: radicand.ascent * 0.6
            ))
        }
        return TypesetBox(
            content: .group, fontSize: fontSize,
            width: hook + radicand.width,
            ascent: Swift.max(ascent, (index.map { radicand.ascent * 0.6 + $0.ascent }) ?? 0),
            descent: radicand.descent,
            children: children
        )
    }

    private static func script(
        _ base: TypesetBox, _ script: TypesetBox, shift: Double,
        metrics: TypesetMetrics, fontSize: Double
    ) -> TypesetBox {
        let children = [
            TypesetBox.Placement(box: base, x: 0, baselineShift: 0),
            TypesetBox.Placement(box: script, x: base.width, baselineShift: shift)
        ]
        return TypesetBox(
            content: .group, fontSize: fontSize,
            width: base.width + script.width,
            ascent: Swift.max(base.ascent, shift + script.ascent),
            descent: Swift.max(base.descent, script.descent - shift),
            children: children
        )
    }

    private static func fenced(
        _ kind: FenceKind, _ inner: TypesetBox,
        metrics: TypesetMetrics, fontSize: Double
    ) -> TypesetBox {
        let width = metrics.fenceWidth * fontSize
        let padding = metrics.fencePadding * fontSize
        let ascent = inner.ascent + padding
        let descent = inner.descent + padding
        let leading = TypesetBox(
            content: .fence(kind, leading: true), fontSize: fontSize,
            width: width, ascent: ascent, descent: descent
        )
        let trailing = TypesetBox(
            content: .fence(kind, leading: false), fontSize: fontSize,
            width: width, ascent: ascent, descent: descent
        )
        let children = [
            TypesetBox.Placement(box: leading, x: 0, baselineShift: 0),
            TypesetBox.Placement(box: inner, x: width, baselineShift: 0),
            TypesetBox.Placement(box: trailing, x: width + inner.width, baselineShift: 0)
        ]
        return TypesetBox(
            content: .group, fontSize: fontSize,
            width: inner.width + 2 * width, ascent: ascent, descent: descent, children: children
        )
    }

    private static func matrix(
        _ rows: [[TypesetBox]], metrics: TypesetMetrics, fontSize: Double
    ) -> TypesetBox {
        let columnGap = metrics.matrixColumnGap * fontSize
        let rowGap = metrics.matrixRowGap * fontSize
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0, !rows.isEmpty else {
            return TypesetBox(content: .group, fontSize: fontSize, width: 0,
                              ascent: metrics.ascent * fontSize, descent: metrics.descent * fontSize)
        }

        // One width per column and one baseline per row, so a column stays aligned however wide
        // any single entry is.
        var columnWidths = Array(repeating: 0.0, count: columnCount)
        for row in rows {
            for (index, cell) in row.enumerated() {
                columnWidths[index] = Swift.max(columnWidths[index], cell.width)
            }
        }
        let rowAscents = rows.map { $0.map(\.ascent).max() ?? 0 }
        let rowDescents = rows.map { $0.map(\.descent).max() ?? 0 }
        let gridWidth = columnWidths.reduce(0, +) + columnGap * Double(columnCount - 1)
        let gridHeight = zip(rowAscents, rowDescents).map(+).reduce(0, +)
            + rowGap * Double(rows.count - 1)

        // Centred on the maths axis, as a matrix is set.
        let axis = metrics.axis * fontSize
        let ascent = gridHeight / 2 + axis
        let descent = gridHeight / 2 - axis

        var children: [TypesetBox.Placement] = []
        var top = 0.0
        for (rowIndex, row) in rows.enumerated() {
            var x = 0.0
            for (columnIndex, cell) in row.enumerated() {
                children.append(TypesetBox.Placement(
                    box: cell,
                    x: x + (columnWidths[columnIndex] - cell.width) / 2,
                    baselineShift: ascent - (top + rowAscents[rowIndex])
                ))
                x += columnWidths[columnIndex] + columnGap
            }
            top += rowAscents[rowIndex] + rowDescents[rowIndex] + rowGap
        }
        let grid = TypesetBox(
            content: .group, fontSize: fontSize, width: gridWidth,
            ascent: ascent, descent: descent, children: children
        )
        return fenced(.bracket, grid, metrics: metrics, fontSize: fontSize)
    }
}
