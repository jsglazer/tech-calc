import Foundation

/// The only way TechCalcCore touches persistence.
///
/// The core performs no file I/O and reads no user defaults: it hands bytes to a conformer and
/// takes bytes back. The default conformer in tests is in-memory; the app shells supply a
/// file-backed one.
public protocol StorageProvider: AnyObject, Sendable {
    /// The stored document bytes, or `nil` when nothing has been saved yet.
    func loadDocumentData() throws -> Data?
    /// Replaces the stored bytes. Conformers that touch a filesystem must write atomically.
    func saveDocumentData(_ data: Data) throws
}

/// The default provider: keeps the document in memory, so tests never touch a disk.
public final class InMemoryStorageProvider: StorageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?

    public init(initialData: Data? = nil) {
        self.storedData = initialData
    }

    public func loadDocumentData() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }

    public func saveDocumentData(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        storedData = data
    }
}

/// The single versioned persisted document — `state.json`.
public struct CalculatorDocument: Equatable, Sendable, Codable {
    /// Bumped whenever the on-disk shape changes; older documents are migrated on read.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var mode: CalculatorMode
    /// `A`-`Z` and `θ`, keyed by their single-character name.
    public var variables: [String: Complex]
    public var ans: TIValueSnapshot
    /// `L1`-`L6` and named lists.
    public var lists: [String: TIList]
    /// `[A]`-`[J]`.
    public var matrices: [String: TIMatrix]
    public var history: HistoryLog

    public init(
        schemaVersion: Int = CalculatorDocument.currentSchemaVersion,
        mode: CalculatorMode = .default,
        variables: [String: Complex] = [:],
        ans: TIValueSnapshot = .real(0),
        lists: [String: TIList] = [:],
        matrices: [String: TIMatrix] = [:],
        history: HistoryLog = HistoryLog()
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.variables = variables
        self.ans = ans
        self.lists = lists
        self.matrices = matrices
        self.history = history
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, mode, variables, ans, lists, matrices, history
    }

    /// Decoding tolerates absent optional sections so a document written by an earlier build
    /// still opens; an unknown *newer* version is refused rather than silently misread.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw TIError.unsupportedSchemaVersion(version)
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.mode = try container.decodeIfPresent(CalculatorMode.self, forKey: .mode) ?? .default
        self.variables = try container.decodeIfPresent([String: Complex].self, forKey: .variables) ?? [:]
        self.ans = try container.decodeIfPresent(TIValueSnapshot.self, forKey: .ans) ?? .real(0)
        self.lists = try container.decodeIfPresent([String: TIList].self, forKey: .lists) ?? [:]
        self.matrices = try container.decodeIfPresent([String: TIMatrix].self, forKey: .matrices) ?? [:]
        self.history = try container.decodeIfPresent(HistoryLog.self, forKey: .history) ?? HistoryLog()
    }
}

/// Reads and writes `CalculatorDocument` through an injected provider.
public struct DocumentStore: Sendable {
    private let provider: StorageProvider

    public init(provider: StorageProvider) {
        self.provider = provider
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Sorted keys keep the bytes identical across runs, so a roundtrip test can compare data.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// The stored document, migrated on read; a fresh document when nothing is stored yet.
    public func load() throws -> CalculatorDocument {
        guard let data = try provider.loadDocumentData(), !data.isEmpty else {
            return CalculatorDocument()
        }
        do {
            return try JSONDecoder().decode(CalculatorDocument.self, from: data)
        } catch let error as TIError {
            throw error
        } catch {
            throw TIError.dataType
        }
    }

    public func save(_ document: CalculatorDocument) throws {
        var stamped = document
        stamped.schemaVersion = CalculatorDocument.currentSchemaVersion
        try provider.saveDocumentData(try Self.makeEncoder().encode(stamped))
    }
}
