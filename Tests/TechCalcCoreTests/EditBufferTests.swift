import Testing
@testable import TechCalcCore

@Suite("Edit buffer")
struct EditBufferTests {

    @Test("Insertion happens at the cursor and advances it")
    func insertAtCursor() {
        var buffer = EditBuffer()
        buffer.insert("123")
        #expect(buffer.text == "123")
        #expect(buffer.cursor == 3)
        buffer.moveLeft()
        buffer.insert("45")
        #expect(buffer.text == "12453")
        #expect(buffer.cursor == 4)
    }

    @Test("Overwrite mode replaces instead of inserting")
    func overwriteMode() {
        var buffer = EditBuffer(text: "12345", cursor: 0)
        buffer.isOverwriting = true
        buffer.insert("ab")
        #expect(buffer.text == "ab345")
        #expect(buffer.cursor == 2)
    }

    @Test("Backspace and delete act on either side of the cursor")
    func backspaceAndDelete() {
        var buffer = EditBuffer(text: "abcd", cursor: 2)
        buffer.backspace()
        #expect(buffer.text == "acd")
        #expect(buffer.cursor == 1)
        buffer.delete()
        #expect(buffer.text == "ad")
        #expect(buffer.cursor == 1)
    }

    @Test("Cursor movement is clamped to the text")
    func cursorClamping() {
        var buffer = EditBuffer(text: "ab")
        buffer.moveRight()
        #expect(buffer.cursor == 2)
        buffer.moveToStart()
        buffer.moveLeft()
        #expect(buffer.cursor == 0)
        buffer.moveToEnd()
        #expect(buffer.cursor == 2)
    }

    @Test("Replacing the line puts the cursor at the end, as ENTRY recall does")
    func replaceLine() {
        var buffer = EditBuffer(text: "old", cursor: 0)
        buffer.replace(with: "sin(2)")
        #expect(buffer.text == "sin(2)")
        #expect(buffer.cursor == 6)
        buffer.clear()
        #expect(buffer.isEmpty)
        #expect(buffer.cursor == 0)
    }

    @Test("Backspace at the start and delete at the end are no-ops")
    func boundaryNoOps() {
        var buffer = EditBuffer(text: "a", cursor: 0)
        buffer.backspace()
        #expect(buffer.text == "a")
        buffer.moveToEnd()
        buffer.delete()
        #expect(buffer.text == "a")
    }
}
