import Foundation

/// The entry line.
///
/// Keypad presses and typed characters both arrive here as text and leave as one string, which
/// is why there is a single input path into the tokenizer rather than two.
public struct EditBuffer: Equatable, Sendable {
    public private(set) var text: String
    /// Cursor offset in characters, `0...text.count`.
    public private(set) var cursor: Int
    /// The TI's `2nd INS` toggle: insert (default) or overwrite.
    public var isOverwriting: Bool

    public init(text: String = "", cursor: Int? = nil, isOverwriting: Bool = false) {
        self.text = text
        self.cursor = Swift.min(Swift.max(0, cursor ?? text.count), text.count)
        self.isOverwriting = isOverwriting
    }

    public var isEmpty: Bool { text.isEmpty }

    public mutating func insert(_ fragment: String) {
        guard !fragment.isEmpty else { return }
        var characters = Array(text)
        let replaced = isOverwriting ? Swift.min(fragment.count, characters.count - cursor) : 0
        characters.replaceSubrange(cursor..<(cursor + replaced), with: Array(fragment))
        text = String(characters)
        cursor += fragment.count
    }

    public mutating func backspace() {
        guard cursor > 0 else { return }
        var characters = Array(text)
        characters.remove(at: cursor - 1)
        text = String(characters)
        cursor -= 1
    }

    /// `DEL`: removes the character under the cursor.
    public mutating func delete() {
        var characters = Array(text)
        guard cursor < characters.count else { return }
        characters.remove(at: cursor)
        text = String(characters)
    }

    public mutating func moveLeft() { cursor = Swift.max(0, cursor - 1) }
    public mutating func moveRight() { cursor = Swift.min(text.count, cursor + 1) }
    public mutating func moveToStart() { cursor = 0 }
    public mutating func moveToEnd() { cursor = text.count }

    public mutating func clear() {
        text = ""
        cursor = 0
    }

    /// Replaces the whole line, as `2ND ENTRY` recall and history re-insertion do.
    public mutating func replace(with newText: String) {
        text = newText
        cursor = newText.count
    }
}
