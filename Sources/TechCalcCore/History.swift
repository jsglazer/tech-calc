import Foundation

/// One entry/result pair in the history pane.
///
/// Identity is a monotonic sequence number rather than a UUID or a timestamp: the core reads no
/// clock and generates no randomness outside the injected `RandomSource`, so two identical runs
/// produce byte-identical history.
public struct HistoryEntry: Equatable, Sendable, Codable, Identifiable {
    public let sequence: Int
    /// Exactly what the user entered, keypad presses and typed characters alike.
    public let input: String
    /// The value, absent when the entry errored.
    public let result: TIValueSnapshot?
    /// The formatted answer, or the TI error name.
    public let display: String
    /// The TI error name (`ERR:SYNTAX`, …) when this entry failed.
    public let errorName: String?

    public var id: Int { sequence }
    public var isError: Bool { errorName != nil }

    public init(sequence: Int, input: String, result: TIValueSnapshot?, display: String, errorName: String? = nil) {
        self.sequence = sequence
        self.input = input
        self.result = result
        self.display = display
        self.errorName = errorName
    }
}

/// The history pane's model: append-only, capped, oldest evicted first.
public struct HistoryLog: Equatable, Sendable, Codable {
    public private(set) var entries: [HistoryEntry]
    private var nextSequence: Int

    public init(entries: [HistoryEntry] = [], nextSequence: Int = 1) {
        self.entries = entries
        self.nextSequence = nextSequence
    }

    public static let capacity = TILimits.maxHistoryEntries

    public var count: Int { entries.count }

    /// The most recent entries, newest last.
    public func mostRecent(_ limit: Int) -> [HistoryEntry] {
        Array(entries.suffix(Swift.max(0, limit)))
    }

    @discardableResult
    public mutating func append(input: String, result: TIValueSnapshot?, display: String, errorName: String? = nil) -> HistoryEntry {
        let entry = HistoryEntry(
            sequence: nextSequence,
            input: input,
            result: result,
            display: display,
            errorName: errorName
        )
        nextSequence += 1
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        return entry
    }

    /// `2ND ENTRY`: previous inputs, most recent first.
    public var recallableInputs: [String] {
        entries.reversed().map(\.input)
    }

    public mutating func clear() {
        entries.removeAll()
    }
}
