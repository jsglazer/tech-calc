import SwiftUI
import TechCalcCore

/// Draws typeset mathematics by walking the boxes `TypesetLayout` computed.
///
/// It is a renderer and only a renderer: every width, height and offset arrives already decided
/// from TechCalcCore, so nothing about the layout can be wrong here without being wrong in a test
/// first. There is no web view, no LaTeX engine and no third-party typesetting dependency —
/// fractions, radicals, scripts, fences and matrices are all drawn from the box tree.
public struct TypesetMathView: View {
    private let box: TypesetBox

    public init(
        node: TypesetNode,
        fontSize: CGFloat,
        metrics: TypesetMetrics = .default
    ) {
        self.box = TypesetLayout.layout(node, metrics: metrics, fontSize: Double(fontSize))
    }

    public var body: some View {
        TypesetBoxView(box: box)
            .frame(width: CGFloat(box.width), height: CGFloat(box.height), alignment: .topLeading)
            .fixedSize()
    }
}

/// One box and its children. Children are offset from the parent's top-left corner, which is the
/// baseline arithmetic the layout already did: `ascent - shift - childAscent`.
struct TypesetBoxView: View {
    let box: TypesetBox

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            ForEach(Array(box.children.enumerated()), id: \.offset) { _, placement in
                TypesetBoxView(box: placement.box)
                    .frame(
                        width: CGFloat(placement.box.width),
                        height: CGFloat(placement.box.height),
                        alignment: .topLeading
                    )
                    .offset(
                        x: CGFloat(placement.x),
                        y: CGFloat(box.ascent - placement.baselineShift - placement.box.ascent)
                    )
            }
        }
        .frame(width: CGFloat(box.width), height: CGFloat(box.height), alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch box.content {
        case .glyphs(let text):
            Text(text)
                .font(.system(size: CGFloat(box.fontSize), design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .frame(width: CGFloat(box.width), height: CGFloat(box.height), alignment: .leading)

        case .rule:
            Rectangle()
                .frame(width: CGFloat(box.width), height: CGFloat(box.height))

        case .radicalSign:
            RadicalShape()
                .stroke(lineWidth: CGFloat(box.fontSize) * 0.05)
                .frame(width: CGFloat(box.width), height: CGFloat(box.height))

        case .fence(let kind, let leading):
            FenceShape(kind: kind, leading: leading)
                .stroke(lineWidth: CGFloat(box.fontSize) * 0.05)
                .frame(width: CGFloat(box.width), height: CGFloat(box.height))

        case .group:
            Color.clear.frame(width: CGFloat(box.width), height: CGFloat(box.height))
        }
    }
}

/// The radical sign: a short descending stroke, the long ascending one, and the overbar that runs
/// across everything under the root.
struct RadicalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let hook = Swift.min(rect.width, rect.height * 0.55)
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: hook * 0.35, y: rect.midY + (rect.maxY - rect.midY) * 0.5))
        path.addLine(to: CGPoint(x: hook * 0.7, y: rect.maxY))
        path.addLine(to: CGPoint(x: hook, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// One half of a stretchy fence, drawn rather than set as a character so it grows with a built-up
/// fraction or a matrix instead of clipping it.
struct FenceShape: Shape {
    let kind: FenceKind
    let leading: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.25
        let x = leading ? rect.maxX - inset : rect.minX + inset
        let tip = leading ? rect.minX + inset : rect.maxX - inset

        switch kind {
        case .bar:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))

        case .bracket:
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: tip, y: rect.minY))
            path.addLine(to: CGPoint(x: tip, y: rect.maxY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))

        case .parenthesis:
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: x, y: rect.maxY),
                control: CGPoint(x: tip - (x - tip) * 0.6, y: rect.midY)
            )

        case .brace:
            let middle = CGPoint(x: tip, y: rect.midY)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addQuadCurve(to: middle, control: CGPoint(x: x, y: rect.midY - rect.height * 0.2))
            path.addQuadCurve(
                to: CGPoint(x: x, y: rect.maxY),
                control: CGPoint(x: x, y: rect.midY + rect.height * 0.2)
            )
        }
        return path
    }
}
