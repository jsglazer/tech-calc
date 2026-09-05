import SwiftUI
import TechCalcCore

/// The keypad, laid out the way the hardware is.
///
/// Nothing about a key is decided here: `KeypadLayout` says where each key sits, what its three
/// printed faces read, and what each face does. This file only draws them and hands presses back
/// to the model.
struct KeypadView: View {
    let model: CalculatorModel
    @Environment(\.palette) private var palette

    /// The hardware is taller than it is wide; the pad is capped so it keeps that proportion in
    /// a wide window instead of stretching into a strip.
    private let maximumWidth: CGFloat = 380
    private let columnSpacing: CGFloat = 5
    private let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(spacing: rowSpacing) {
            KeypadRow(model: model, keys: KeypadLayout.row(1), spacing: columnSpacing)
            arrowRows
            ForEach(4...KeypadLayout.rowCount, id: \.self) { row in
                KeypadRow(model: model, keys: KeypadLayout.row(row), spacing: columnSpacing)
            }
        }
        .frame(maxWidth: maximumWidth)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(palette.caseFill)
    }

    /// Rows 2 and 3: three grid keys on the left, the arrow pad spanning both rows on the right.
    /// The split is the hardware's — three of five columns, then two.
    private var arrowRows: some View {
        GeometryReader { proxy in
            let column = (proxy.size.width - columnSpacing * 4) / 5
            HStack(spacing: columnSpacing) {
                VStack(spacing: rowSpacing) {
                    KeypadRow(model: model, keys: KeypadLayout.row(2), spacing: columnSpacing)
                    KeypadRow(model: model, keys: KeypadLayout.row(3), spacing: columnSpacing)
                }
                .frame(width: column * 3 + columnSpacing * 2)

                ArrowPad(
                    model: model,
                    diameter: min(column * 2 + columnSpacing, KeypadMetrics.cellHeight * 2 + rowSpacing)
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: KeypadMetrics.cellHeight * 2 + rowSpacing)
    }
}

enum KeypadMetrics {
    /// The printed strip above a key, where the 2nd and ALPHA faces live on the case.
    static let legendHeight: CGFloat = 11
    static let keyHeight: CGFloat = 27
    static var cellHeight: CGFloat { legendHeight + keyHeight + 2 }
}

/// One hardware row.
private struct KeypadRow: View {
    let model: CalculatorModel
    let keys: [KeypadKey]
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(keys) { key in
                KeyCell(model: model, key: key)
            }
        }
    }
}

/// One key, with the two faces the case prints above it.
private struct KeyCell: View {
    let model: CalculatorModel
    let key: KeypadKey
    @Environment(\.palette) private var palette

    private var layer: KeypadLayer { model.modifier.layer }

    var body: some View {
        VStack(spacing: 1) {
            legend
            button
        }
        .frame(maxWidth: .infinity)
    }

    /// The 2nd face on the left and the ALPHA face on the right, as they are silkscreened.
    private var legend: some View {
        HStack(spacing: 2) {
            Text(key.secondFace.map(labelText) ?? " ")
                .foregroundStyle(palette.secondLabel)
                .opacity(layer == .second ? 1 : 0.75)
            Spacer(minLength: 0)
            Text(key.alphaFace.map(labelText) ?? " ")
                .foregroundStyle(palette.alphaLabel)
                .opacity(layer == .alpha ? 1 : 0.75)
        }
        .font(.system(size: 7.5, weight: layerIsLatched ? .bold : .regular))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(height: KeypadMetrics.legendHeight)
    }

    private var layerIsLatched: Bool { layer != .primary }

    /// A face the hardware prints but this build has no feature for is shown, not hidden — that
    /// is the point of drawing the whole keypad — but it reads as unavailable.
    private func labelText(_ face: KeyFace) -> String { face.label }

    private var button: some View {
        Button { model.press(key) } label: {
            Text(key.primaryFace?.label ?? key.id)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: KeypadMetrics.keyHeight)
                .foregroundStyle(foreground)
                .background(fill, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isLatched ? palette.latchHighlight : palette.keyBorder,
                                      lineWidth: isLatched ? 1.6 : 0.7)
                )
                .opacity(isInert ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(Text(key.face(on: layer)?.label ?? key.id))
    }

    /// True while this key is the latched modifier, so the pad shows which layer is armed.
    private var isLatched: Bool {
        switch key.role {
        case .secondModifier: model.modifier == .second
        case .alphaModifier: model.modifier == .alpha || model.modifier == .alphaLock
        case .token: false
        }
    }

    private var isInert: Bool { key.face(on: layer)?.effect == .unavailable }

    private var fontSize: CGFloat {
        let length = (key.primaryFace?.label ?? "").count
        return length > 6 ? 8.5 : (length > 3 ? 10 : 12)
    }

    private var fill: Color {
        switch key.style {
        case .function: palette.functionKey
        case .digit: palette.digitKey
        case .arithmetic: palette.arithmeticKey
        case .navigation: palette.navigationKey
        case .second: palette.secondKey
        case .alpha: palette.alphaKey
        case .arrow: palette.arrowKey
        }
    }

    private var foreground: Color {
        switch key.style {
        case .digit: palette.digitKeyText
        case .arithmetic: palette.arithmeticKeyText
        case .second: palette.secondKeyText
        case .alpha: palette.alphaKeyText
        default: palette.functionKeyText
        }
    }

    private var helpText: String {
        guard let face = key.face(on: layer) else { return key.id }
        return face.effect == .unavailable ? "\(face.label) — not in this version" : face.label
    }
}

/// The round arrow pad, drawn as one control the way the hardware is.
private struct ArrowPad: View {
    let model: CalculatorModel
    /// Two grid columns wide, so the pad ends where the row above it does.
    let diameter: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle().fill(palette.arrowKey)
            Circle().strokeBorder(palette.keyBorder, lineWidth: 0.7)
            Circle()
                .fill(palette.caseFill)
                .frame(width: diameter * 0.30, height: diameter * 0.30)

            arrow(.up).offset(y: -diameter * 0.33)
            arrow(.down).offset(y: diameter * 0.33)
            arrow(.left).offset(x: -diameter * 0.33)
            arrow(.right).offset(x: diameter * 0.33)
        }
        .frame(width: diameter, height: diameter)
    }

    private func arrow(_ cursor: KeypadCursor) -> some View {
        let key = KeypadLayout.arrow(cursor)
        return Button { model.press(key) } label: {
            Text(key.primaryFace?.label ?? "")
                .font(.system(size: 9))
                .foregroundStyle(palette.functionKeyText)
                .frame(width: diameter * 0.30, height: diameter * 0.30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(cursor.rawValue))
    }
}
