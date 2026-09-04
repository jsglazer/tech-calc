import Testing
@testable import TechCalcCore

@Suite("History")
struct HistoryTests {

    @Test("Entries are appended with increasing sequence numbers")
    func appendAssignsSequence() {
        var log = HistoryLog()
        let first = log.append(input: "1+1", result: .real(2), display: "2")
        let second = log.append(input: "2+2", result: .real(4), display: "4")
        #expect(first.sequence == 1)
        #expect(second.sequence == 2)
        #expect(log.count == 2)
    }

    @Test("History is capped at 500 entries, oldest evicted first")
    func capacityEvictsOldest() {
        var log = HistoryLog()
        for index in 1...(HistoryLog.capacity + 25) {
            log.append(input: "\(index)", result: .real(Double(index)), display: "\(index)")
        }
        #expect(log.count == HistoryLog.capacity)
        #expect(HistoryLog.capacity == 500)
        // The first 25 are gone; sequence numbers keep counting.
        #expect(log.entries.first?.input == "26")
        #expect(log.entries.last?.input == "525")
        #expect(log.entries.last?.sequence == 525)
    }

    @Test("The pane can ask for at least the most recent twelve pairs")
    func mostRecentWindow() {
        var log = HistoryLog()
        for index in 1...30 {
            log.append(input: "\(index)", result: .real(Double(index)), display: "\(index)")
        }
        let recent = log.mostRecent(12)
        #expect(recent.count == 12)
        #expect(recent.first?.input == "19")
        #expect(recent.last?.input == "30")
    }

    @Test("2ND ENTRY recall lists previous inputs newest first")
    func entryRecall() {
        var calculator = Fixture.calculator()
        calculator.enter("1+1")
        calculator.enter("2+2")
        #expect(calculator.history.recallableInputs == ["2+2", "1+1"])
    }

    @Test("Errors are recorded as rows rather than thrown out of enter()")
    func errorsBecomeRows() {
        var calculator = Fixture.calculator()
        let entry = calculator.enter("1/0")
        #expect(entry.isError)
        #expect(entry.display == "ERR:DIVIDE BY 0")
        #expect(calculator.history.count == 1)
    }

    @Test("Clearing empties the pane but keeps counting sequence numbers")
    func clearing() {
        var calculator = Fixture.calculator()
        calculator.enter("1+1")
        calculator.clearHistory()
        #expect(calculator.history.count == 0)
        #expect(calculator.enter("2+2").sequence == 2)
    }
}
