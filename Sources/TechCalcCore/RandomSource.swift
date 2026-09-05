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

    /// A standard normal variate by the Box-Muller transform — `randNorm(`.
    ///
    /// One uniform pair yields one variate rather than the two the transform can produce: caching
    /// the second would make a draw depend on how many draws preceded it, and the sequence has to
    /// be a function of the seed alone.
    public func nextNormal() -> Double {
        var uniform = nextUniform()
        // The transform needs a strictly positive argument for the logarithm.
        if uniform <= 0 { uniform = Double.leastNormalMagnitude }
        let radius = (-2 * Foundation.log(uniform)).squareRoot()
        return radius * Foundation.cos(2 * Double.pi * nextUniform())
    }

    /// The number of successes in `trials` Bernoulli trials — `randBin(`.
    ///
    /// Counted trial by trial, with an explicit cap, so the draw cannot spin on a mistyped count.
    public func nextBinomial(trials: Int, probability: Double) throws -> Int {
        guard trials >= 0, trials <= RandomLimits.maximumBernoulliTrials,
              probability >= 0, probability <= 1 else { throw TIError.domain }
        var successes = 0
        for _ in 0..<trials where nextUniform() < probability {
            successes += 1
        }
        return successes
    }

    /// A random permutation of `lower...upper` — `randIntNoRep(`.
    public func nextPermutation(lower: Int, upper: Int) throws -> [Int] {
        guard lower <= upper else { throw TIError.domain }
        let count = upper - lower + 1
        guard count <= TILimits.maxListLength else { throw TIError.invalidDimension }
        var values = Array(lower...upper)
        // Fisher-Yates, drawing through the injected source so the shuffle is seed-reproducible.
        for index in stride(from: values.count - 1, to: 0, by: -1) {
            let pick = try nextInteger(lower: 0, upper: index)
            values.swapAt(index, pick)
        }
        return values
    }
}

/// Bounds on the loops the seeded draws run, so no draw is unbounded.
public enum RandomLimits {
    public static let maximumBernoulliTrials = 1_000_000
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
