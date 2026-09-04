import Testing
@testable import TechCalcCore

/// All randomness flows through the injected `RandomSource`; a fixed seed gives an exact sequence.
@Suite("Seeded randomness")
struct RandomSourceTests {

    @Test("The same seed produces the same sequence")
    func seedDeterminesSequence() {
        let first = SeededRandomSource(seed: 42)
        let second = SeededRandomSource(seed: 42)
        let a = (0..<8).map { _ in first.nextUniform() }
        let b = (0..<8).map { _ in second.nextUniform() }
        #expect(a == b)
        #expect(Set(a).count == a.count, "a seeded stream should not repeat immediately")
    }

    @Test("Different seeds produce different sequences")
    func differentSeedsDiffer() {
        let a = (0..<4).map { _ in SeededRandomSource(seed: 1).nextUniform() }
        let b = (0..<4).map { _ in SeededRandomSource(seed: 2).nextUniform() }
        #expect(a != b)
    }

    @Test("Uniform variates stay in [0, 1)")
    func uniformRange() {
        let source = SeededRandomSource(seed: 7)
        for _ in 0..<1000 {
            let value = source.nextUniform()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test("rand and randInt draw from the injected source, so results are exactly reproducible")
    func evaluatorUsesInjectedSource() throws {
        var first = Fixture.calculator(seed: 99)
        var second = Fixture.calculator(seed: 99)
        let a = (0..<5).map { _ in first.enter("rand").display }
        let b = (0..<5).map { _ in second.enter("rand").display }
        #expect(a == b)

        var dice = Fixture.calculator(seed: 5)
        let rolls = (0..<50).map { _ in (try? dice.evaluate("randInt(1,6)").result.asReal) ?? .nan }
        #expect(rolls.allSatisfy { $0 >= 1 && $0 <= 6 && $0 == $0.rounded() })

        var repeated = Fixture.calculator(seed: 5)
        let sameRolls = (0..<50).map { _ in (try? repeated.evaluate("randInt(1,6)").result.asReal) ?? .nan }
        #expect(rolls == sameRolls)
    }

    @Test("STO▸rand reseeds the stream")
    func storingToRandReseeds() throws {
        var calculator = Fixture.calculator(seed: 0)
        calculator.enter("17→rand")
        let first = (0..<4).map { _ in calculator.enter("rand").display }

        calculator.enter("17→rand")
        let second = (0..<4).map { _ in calculator.enter("rand").display }
        #expect(first == second)

        calculator.enter("18→rand")
        let third = (0..<4).map { _ in calculator.enter("rand").display }
        #expect(first != third)
    }

    @Test("randInt covers both ends of its inclusive range")
    func randIntIsInclusive() throws {
        let source = SeededRandomSource(seed: 3)
        var seen: Set<Int> = []
        for _ in 0..<400 {
            seen.insert(try source.nextInteger(lower: 1, upper: 3))
        }
        #expect(seen == [1, 2, 3])
        #expect(throws: TIError.domain) { try source.nextInteger(lower: 5, upper: 1) }
    }
}
