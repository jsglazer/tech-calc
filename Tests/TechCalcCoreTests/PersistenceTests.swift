import Foundation
import Testing
@testable import TechCalcCore

/// Persistence roundtrips through the injected provider. The core performs no file I/O and reads
/// no user defaults; the default provider here keeps the bytes in memory.
@Suite("Persistence")
struct PersistenceTests {

    /// A calculator with something in every persisted section.
    private func populatedCalculator() throws -> Calculator {
        var calculator = Fixture.calculator(mode: CalculatorMode(
            angle: .degrees,
            notation: .scientific,
            decimals: .fixed(4),
            complex: .rectangular,
            answer: .fraction
        ))
        calculator.enter("5→A")
        calculator.enter("A*3")
        calculator.enter("1/0")               // an error row must survive too
        calculator.lists[Fixture.listName(1)] = TIList(reals: [1, 2, 3])
        calculator.lists[Fixture.namedList("HEIGH")] = TIList(reals: [70.5, 68])
        calculator.matrices[Fixture.matrixName("A")] = try TIMatrix(rows: 2, columns: 2, values: [
            Complex(1), Complex(2), Complex(3), Complex(4)
        ])
        return calculator
    }

    @Test("A full document roundtrips through in-memory storage")
    func fullRoundtrip() throws {
        let original = try populatedCalculator()
        let store = DocumentStore(provider: InMemoryStorageProvider())
        try original.save(to: store)

        let restored = try Calculator.loaded(from: store, random: SeededRandomSource(seed: 1))

        #expect(restored.mode == original.mode)
        #expect(restored.context.variables == original.context.variables)
        #expect(restored.context.ans == original.context.ans)
        #expect(restored.lists == original.lists)
        #expect(restored.matrices == original.matrices)
        #expect(restored.history == original.history)
        #expect(restored.document() == original.document())
    }

    @Test("Lists and matrices entered as TI syntax survive a save and reload")
    func containerRoundtrip() throws {
        var original = Fixture.calculator()
        original.enter("{1,2,3}→L1")
        original.enter("{4.5,-6}→L6")
        original.enter("{70.5,68}→∟HEIGH")
        original.enter("[[1,2][3,4]]→[A]")
        original.enter("identity(3)→[J]")

        let store = DocumentStore(provider: InMemoryStorageProvider())
        try original.save(to: store)
        var restored = try Calculator.loaded(from: store, random: SeededRandomSource(seed: 1))

        #expect(restored.lists == original.lists)
        #expect(restored.matrices == original.matrices)
        // The restored containers are reachable by the same TI syntax that stored them.
        #expect(try restored.evaluate("L1(2)").result == .real(2))
        #expect(try restored.evaluate("L6(1)").result == .real(4.5))
        #expect(try restored.evaluate("∟HEIGH(1)").result == .real(70.5))
        #expect(try restored.evaluate("det([A])").result == .real(-2))
        #expect(try restored.evaluate("[J](3,3)").result == .real(1))
    }

    @Test("A container name the build does not recognise is dropped, not fatal")
    func unknownContainerKeysAreDropped() throws {
        var document = CalculatorDocument()
        document.lists = ["L1": TIList(reals: [1, 2]), "L9": TIList(reals: [3])]
        document.matrices = ["[A]": try TIMatrix(rows: 1, columns: 1), "[Z]": try TIMatrix(rows: 1, columns: 1)]

        let restored = Calculator.restored(from: document, random: SeededRandomSource(seed: 1))
        #expect(restored.lists.keys.sorted(by: { $0.key < $1.key }) == [Fixture.listName(1)])
        #expect(Array(restored.matrices.keys) == [Fixture.matrixName("A")])
    }

    @Test("History rows keep their inputs, results, errors and order")
    func historyRoundtrip() throws {
        let original = try populatedCalculator()
        let store = DocumentStore(provider: InMemoryStorageProvider())
        try original.save(to: store)
        let restored = try Calculator.loaded(from: store, random: SeededRandomSource(seed: 1))

        #expect(restored.history.entries.count == 3)
        #expect(restored.history.entries.map(\.input) == ["5→A", "A*3", "1/0"])
        #expect(restored.history.entries[2].errorName == "ERR:DIVIDE BY 0")
        #expect(restored.history.entries[2].result == nil)
        #expect(restored.history.entries.map(\.sequence) == [1, 2, 3])
    }

    @Test("A restored calculator continues the same sequence numbers")
    func sequenceContinuesAfterRestore() throws {
        let original = try populatedCalculator()
        let store = DocumentStore(provider: InMemoryStorageProvider())
        try original.save(to: store)

        var restored = try Calculator.loaded(from: store, random: SeededRandomSource(seed: 1))
        let entry = restored.enter("2+2")
        #expect(entry.sequence == 4)
    }

    @Test("Saving is byte-stable, so an unchanged document rewrites identically")
    func encodingIsDeterministic() throws {
        let calculator = try populatedCalculator()
        let encoder = DocumentStore.makeEncoder()
        let first = try encoder.encode(calculator.document())
        let second = try encoder.encode(calculator.document())
        #expect(first == second)
    }

    @Test("An empty store yields a fresh document rather than an error")
    func emptyStoreLoadsDefaults() throws {
        let store = DocumentStore(provider: InMemoryStorageProvider())
        let document = try store.load()
        #expect(document.schemaVersion == CalculatorDocument.currentSchemaVersion)
        #expect(document.history.entries.isEmpty)
        #expect(document.mode == .default)
    }

    @Test("Migrate-on-read: absent sections take their defaults")
    func absentSectionsDefault() throws {
        let legacy = Data(#"{"schemaVersion":1,"variables":{"A":{"re":2,"im":0}}}"#.utf8)
        let store = DocumentStore(provider: InMemoryStorageProvider(initialData: legacy))
        let document = try store.load()
        #expect(document.variables["A"] == Complex(2))
        #expect(document.mode == .default)
        #expect(document.lists.isEmpty)
        #expect(document.history.entries.isEmpty)
    }

    @Test("A document from a newer schema is refused rather than misread")
    func newerSchemaIsRefused() throws {
        let future = Data(#"{"schemaVersion":99}"#.utf8)
        let store = DocumentStore(provider: InMemoryStorageProvider(initialData: future))
        #expect(throws: TIError.unsupportedSchemaVersion(99)) { try store.load() }
    }

    @Test("Corrupt bytes are ERR:DATA TYPE, not a crash")
    func corruptDataIsAnError() throws {
        let store = DocumentStore(provider: InMemoryStorageProvider(initialData: Data("not json".utf8)))
        #expect(throws: TIError.dataType) { try store.load() }
    }

    @Test("Saving always stamps the current schema version")
    func savingStampsCurrentVersion() throws {
        let provider = InMemoryStorageProvider()
        var document = CalculatorDocument()
        document.schemaVersion = 0
        try DocumentStore(provider: provider).save(document)

        let data = try #require(try provider.loadDocumentData())
        let reloaded = try JSONDecoder().decode(CalculatorDocument.self, from: data)
        #expect(reloaded.schemaVersion == CalculatorDocument.currentSchemaVersion)
    }
}

/// The TVM solver's fields are part of the document; the statistics results are not.
///
/// That split is the developer's resolution of the fork D28 left open: solver *inputs* are a
/// screen the user fills in and comes back to, computed *results* are not. Both halves are
/// asserted here so the decision cannot drift silently.
@Suite("Finance persistence")
struct FinancePersistenceTests {

    private func scenario() -> FinanceVariables {
        FinanceVariables(
            n: 360, interestPercent: 6.5, presentValue: 250_000,
            payment: -1580.17, futureValue: 0,
            paymentsPerYear: 12, compoundsPerYear: 12, timing: .begin
        )
    }

    @Test("The TVM fields survive a save and reload")
    func financeRoundtrips() throws {
        var calculator = Fixture.calculator()
        calculator.context.finance = scenario()
        let store = DocumentStore(provider: InMemoryStorageProvider())
        try calculator.save(to: store)

        let restored = try Calculator.loaded(from: store, random: SeededRandomSource(seed: 1))
        #expect(restored.context.finance == scenario())
        #expect(restored.context.finance.timing == .begin)
    }

    @Test("A version 1 document, written before the solver screen existed, still opens")
    func migratesFromVersionOne() throws {
        // Exactly what the previous build wrote: no `finance` section, and version 1.
        let legacy = Data("""
        {"ans":{"real":{"_0":7}},"schemaVersion":1}
        """.utf8)
        let store = DocumentStore(provider: InMemoryStorageProvider(initialData: legacy))
        let document = try store.load()

        #expect(document.finance == FinanceVariables())
        #expect(document.ans == .real(7))
        // Migrate-on-read stamps the current version, so the next save is a version 2 document.
        #expect(document.schemaVersion == CalculatorDocument.currentSchemaVersion)
        #expect(CalculatorDocument.currentSchemaVersion == 2)
    }

    @Test("A document from a newer build is refused rather than silently misread")
    func refusesANewerSchema() {
        let future = Data("""
        {"schemaVersion":99}
        """.utf8)
        let store = DocumentStore(provider: InMemoryStorageProvider(initialData: future))
        #expect(throws: TIError.self) { try store.load() }
    }

    @Test("Statistics results stay session-only: they are computed, not entered")
    func statisticsResultsAreNotPersisted() throws {
        var calculator = Fixture.calculator()
        calculator.enter("T-Test(10,12,2,30,1)")
        #expect(!calculator.context.statistics.isEmpty)

        let store = DocumentStore(provider: InMemoryStorageProvider())
        try calculator.save(to: store)
        let restored = try Calculator.loaded(from: store, random: SeededRandomSource(seed: 1))
        #expect(restored.context.statistics.isEmpty)
    }
}
