import Testing
@testable import TechCalcCore

/// The TI-84 Plus keypad, checked key for key against the hardware.
///
/// The layout is the one thing in this module that is judged by eye against a photograph, so the
/// facts a reader would otherwise have to re-check — every position filled exactly once, the
/// ALPHA letters in the printed order, the 2nd faces on the right keys — are asserted here.
@Suite("TI-84 keypad layout")
struct KeypadLayoutTests {

    private func key(_ id: String) throws -> KeypadKey {
        try #require(KeypadLayout.key(id: id), "no key \(id)")
    }

    // MARK: - The grid

    @Test("The grid is ten rows of five, less the two cells the arrow pad covers")
    func gridIsComplete() {
        for row in 1...KeypadLayout.rowCount {
            let columns = KeypadLayout.row(row).map(\.column)
            // Rows 2 and 3 stop at column 3: the arrow pad spans columns 4-5 of both.
            let expected = (row == 2 || row == 3) ? Array(1...3) : Array(1...KeypadLayout.columnCount)
            #expect(columns == expected, "row \(row) is \(columns)")
        }
    }

    @Test("No two keys claim the same cell")
    func positionsAreUnique() {
        let cells = KeypadLayout.keys
            .filter { $0.style != .arrow }
            .map { "\($0.row),\($0.column)" }
        #expect(Set(cells).count == cells.count)
    }

    @Test("The arrow pad is four keys over one span, and each moves a different way")
    func arrowPad() {
        #expect(KeypadLayout.arrowKeys.count == 4)
        for key in KeypadLayout.arrowKeys {
            #expect(key.row == 2 && key.column == 4)
            #expect(key.rowSpan == 2 && key.columnSpan == 2)
        }
        let moves = KeypadLayout.arrowKeys.compactMap(\.primaryFace?.effect)
        #expect(Set(KeypadLayout.arrowKeys.map(\.id)).count == 4)
        #expect(moves == [.move(.up), .move(.left), .move(.right), .move(.down)])
    }

    // MARK: - The ALPHA layer

    @Test("ALPHA spells A through Z then θ, in the order the hardware prints them")
    func alphaLettersRunInReadingOrder() {
        let printed = KeypadLayout.keys
            .filter { $0.style != .arrow }
            .compactMap { $0.alphaFace?.effect.insertedText }
            .filter { $0.count == 1 && EvaluationContext.isVariableName(Character($0)) }
        #expect(printed == EvaluationContext.variableNames.map(String.init))
    }

    @Test("Every ALPHA face that types a letter types a name the evaluator accepts")
    func alphaLettersAreEvaluatorVariables() throws {
        for key in KeypadLayout.keys {
            guard let text = key.alphaFace?.effect.insertedText, text.count == 1,
                  let character = text.first, character.isLetter else { continue }
            #expect(EvaluationContext.isVariableName(character), "\(key.id) types \(text)")
        }
    }

    // MARK: - The 2nd layer

    @Test("2nd on the trig keys gives the inverse the catalog declares")
    func inverseTrigOnSecondLayer() throws {
        for (id, inverse) in [(FunctionID.sin, FunctionID.asin),
                              (.cos, .acos),
                              (.tan, .atan)] {
            let expected = FunctionCatalog.definition(for: inverse)?.keypadToken
            #expect(try key(id.rawValue).token(on: .second) == expected)
        }
    }

    @Test("2nd on the parenthesis keys gives the list braces")
    func bracesOnSecondLayer() throws {
        #expect(try key("leftParenthesis").token(on: .second) == String(ContainerSyntax.listOpen))
        #expect(try key("rightParenthesis").token(on: .second) == String(ContainerSyntax.listClose))
    }

    @Test("2nd on × and − gives the matrix brackets")
    func bracketsOnSecondLayer() throws {
        #expect(try key("multiply").token(on: .second) == String(ContainerSyntax.matrixOpen))
        #expect(try key("subtract").token(on: .second) == String(ContainerSyntax.matrixClose))
    }

    @Test("2nd on the number pad gives L1-L6, on the rows the hardware prints them")
    func listsOnSecondLayer() throws {
        let names = ListName.numberedNames.map(\.key)
        for (offset, digit) in ["1", "2", "3", "4", "5", "6"].enumerated() {
            #expect(try key("digit-\(digit)").token(on: .second) == names[offset])
        }
    }

    @Test("2nd on the constants keys gives π, e and i")
    func constantsOnSecondLayer() throws {
        #expect(try key("power").token(on: .second) == FunctionCatalog.definition(for: .pi)?.keypadToken)
        #expect(try key("divide").token(on: .second) == FunctionCatalog.definition(for: .eulersNumber)?.keypadToken)
        #expect(try key("decimal").token(on: .second) == FunctionCatalog.definition(for: .imaginaryUnit)?.keypadToken)
    }

    @Test("2nd (-) recalls Ans, spelled the way the tokenizer reads it")
    func ansOnSecondLayer() throws {
        #expect(try key("negate").token(on: .second) == Tokenizer.answerSpelling)
        #expect(try key("negate").token(on: .primary) == String(Tokenizer.negationCharacter))
    }

    // MARK: - The keys that act rather than type

    @Test("The editing and menu keys carry the effect the hardware's face names")
    func actionKeys() throws {
        #expect(try key("enter").primaryFace?.effect == .enter)
        #expect(try key("enter").secondFace?.effect == .recallEntry)
        #expect(try key("clear").primaryFace?.effect == .clear)
        #expect(try key("del").primaryFace?.effect == .delete)
        #expect(try key("del").secondFace?.effect == .toggleInsertMode)
        #expect(try key("mode").primaryFace?.effect == .open(.mode))
        #expect(try key("mode").secondFace?.effect == .open(.calculator))
        #expect(try key("stat").primaryFace?.effect == .open(.lists))
        #expect(try key(FunctionID.reciprocal.rawValue).secondFace?.effect == .open(.matrices))
        #expect(try key("vars").secondFace?.effect == .open(.statTests))
        #expect(try key("apps").primaryFace?.effect == .open(.finance))
    }

    @Test("2nd and ALPHA are the only modifier keys, and they sit where the hardware puts them")
    func modifierKeys() {
        let modifiers = KeypadLayout.keys.filter { $0.role != .token }
        #expect(modifiers.map(\.id) == ["2nd", "alpha"])
        #expect(KeypadLayout.second.row == 2 && KeypadLayout.second.column == 1)
        #expect(KeypadLayout.alpha.row == 3 && KeypadLayout.alpha.column == 1)
    }

    @Test("Faces this build has no feature for are present and inert, never missing")
    func unavailableFacesAreDrawn() throws {
        // The graphing row is drawn in full so the layout matches the hardware, but none of it
        // does anything: this build has no grapher.
        for id in ["graph-y", "graph-window", "graph-zoom", "graph-trace", "graph-graph"] {
            let graphKey = try key(id)
            for layer in [KeypadLayer.primary, .second, .alpha] {
                #expect(graphKey.face(on: layer)?.effect == .unavailable, "\(id) on \(layer)")
                #expect(graphKey.face(on: layer)?.label.isEmpty == false)
            }
        }
    }

    @Test("Every key prints something on its primary face")
    func everyKeyIsLabelled() {
        for key in KeypadLayout.keys {
            #expect(key.primaryFace?.label.isEmpty == false, "\(key.id) has no label")
        }
    }

    // MARK: - Pressing

    @Test("A press reports the face that fired, not the face the cleared latch would select")
    func outcomeReportsTheFiredFace() throws {
        var state = KeypadState()
        state.press(KeypadLayout.second)
        let outcome = state.activate(try key("power"))
        #expect(outcome.face?.effect == .insert(FunctionCatalog.definition(for: .pi)?.keypadToken ?? ""))
        #expect(outcome.modifier == .none)
    }

    @Test("An inert face still consumes the latch, as a real key press does")
    func inertFaceConsumesTheLatch() throws {
        var state = KeypadState()
        state.press(KeypadLayout.second)
        let outcome = state.activate(try key("graph-y"))
        #expect(outcome.effect == .unavailable)
        #expect(state.modifier == .none)
    }
}
