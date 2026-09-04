import Foundation

/// The single source of randomness in TechCalcCore.
///
/// Every random-producing function (`rand`, `randInt(`, and later `randNorm(`, `randBin(`,
/// `randIntNoRep(`, `randM(`) draws from an injected conformer. `SystemRandomNumberGenerator`,
/// `Int.random` and `Double.random` appear nowhere in this module, so a test that injects a
/// fixed seed gets an exact, repeatable sequence. `STO>rand` reseeds.
public protocol RandomSource: AnyObject, Sendable {
    /// The next uniform variate in [0, 1).
    func nextUniform() -> Double
    /// Restarts the stream, as `STO>rand` does on the TI.
    func reseed(_ seed: UInt64)
}

extension RandomSource {
    /// A uniform integer in `lower...upper`, inclusive at both ends as `randInt(` is.
    public func nextInteger(lower: Int, upper: Int) throws -> Int {
        guard lower <= upper else { throw TIError.domain }
        let span = Double(upper) - Double(lower) + 1
        let offset = Int((nextUniform() * span).rounded(.down))
        return lower + Swift.min(offset, upper - lower)
    }
}

/// A deterministic, seedable generator: SplitMix64, chosen because its state advance is a
/// closed-form function of the seed, so a sequence is reproducible across platforms and
/// architectures with no dependence on the standard library's generator.
public final class SeededRandomSource: RandomSource, @unchecked Sendable {
    private let lock = NSLock()
    private var state: UInt64

    public init(seed: UInt64 = 0) {
        self.state = seed
    }

    public func reseed(_ seed: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        state = seed
    }

    public func nextUniform() -> Double {
        // 53 significant bits, matching the mantissa, so the result is uniform in [0, 1).
        Double(nextBits() >> 11) * (1.0 / 9007199254740992.0)
    }

    private func nextBits() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
