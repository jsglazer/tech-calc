import Testing
@testable import TechCalcCore

/// The 2nd / ALPHA modifier state machine, exercised headlessly with no view attached.
@Suite("Keypad modifier state machine")
struct KeypadStateMachineTests {

    private let digitOne = KeypadKey(id: "digit-1", primary: "1", second: "1", alpha: "Y")
    private let sinKey = KeypadKey(id: "sin", primary: "sin(", second: "sin⁻¹(", alpha: "E")

    @Test("A press with no modifier emits the primary layer")
    func primaryLayer() {
        var state = KeypadState()
        #expect(state.press(digitOne) == KeypadPressResult(token: "1", modifier: .none))
        #expect(state.press(sinKey) == KeypadPressResult(token: "sin(", modifier: .none))
    }

    @Test("2nd is single-shot: it applies to one key and then clears")
    func secondIsSingleShot() {
        var state = KeypadState()
        #expect(state.press(KeypadLayout.second).token == nil)
        #expect(state.modifier == .second)
        #expect(state.press(sinKey) == KeypadPressResult(token: "sin⁻¹(", modifier: .none))
        // The next press is back on the primary layer.
        #expect(state.press(sinKey) == KeypadPressResult(token: "sin(", modifier: .none))
    }

    @Test("Pressing 2nd twice cancels it")
    func secondTogglesOff() {
        var state = KeypadState()
        state.press(KeypadLayout.second)
        state.press(KeypadLayout.second)
        #expect(state.modifier == .none)
        #expect(state.press(sinKey).token == "sin(")
    }

    @Test("ALPHA is single-shot")
    func alphaIsSingleShot() {
        var state = KeypadState()
        state.press(KeypadLayout.alpha)
        #expect(state.modifier == .alpha)
        #expect(state.press(digitOne) == KeypadPressResult(token: "Y", modifier: .none))
        #expect(state.press(digitOne).token == "1")
    }

    @Test("Pressing ALPHA twice cancels it")
    func alphaTogglesOff() {
        var state = KeypadState()
        state.press(KeypadLayout.alpha)
        state.press(KeypadLayout.alpha)
        #expect(state.modifier == .none)
    }

    @Test("2nd then ALPHA engages A-LOCK, which survives key presses until pressed off")
    func alphaLock() {
        var state = KeypadState()
        state.press(KeypadLayout.second)
        state.press(KeypadLayout.alpha)
        #expect(state.modifier == .alphaLock)
        #expect(state.press(digitOne) == KeypadPressResult(token: "Y", modifier: .alphaLock))
        #expect(state.press(sinKey) == KeypadPressResult(token: "E", modifier: .alphaLock))
        // ALPHA releases the lock.
        state.press(KeypadLayout.alpha)
        #expect(state.modifier == .none)
        #expect(state.press(digitOne).token == "1")
    }

    @Test("2nd replaces an engaged ALPHA rather than stacking with it")
    func secondReplacesAlpha() {
        var state = KeypadState()
        state.press(KeypadLayout.alpha)
        state.press(KeypadLayout.second)
        #expect(state.modifier == .second)
        #expect(state.press(sinKey).token == "sin⁻¹(")
    }

    @Test("clear() drops any latch")
    func clearDropsLatch() {
        var state = KeypadState()
        state.press(KeypadLayout.second)
        state.clear()
        #expect(state.modifier == .none)
    }

    @Test("A key with no token on a layer falls back to its primary")
    func layerFallback() {
        let key = KeypadKey(id: "power", primary: "^")
        #expect(key.token(on: .second) == "^")
        #expect(key.token(on: .alpha) == "^")
    }

    @Test("Keypad presses and typed text produce the same evaluated result")
    func keypadAndTypingAreOneInputPath() throws {
        // Drive the buffer entirely from keypad presses: 2nd, sin⁻¹, .5, )
        var state = KeypadState()
        var buffer = EditBuffer()
        for key in [KeypadLayout.second, sinKey] {
            if let token = state.press(key).token { buffer.insert(token) }
        }
        buffer.insert(".5)")
        #expect(buffer.text == "sin⁻¹(.5)")

        var typed = Fixture.calculator()
        var pressed = Fixture.calculator()
        expectClose(
            try pressed.evaluate(buffer.text).result.asReal,
            try typed.evaluate("asin(.5)").result.asReal
        )
    }
}
