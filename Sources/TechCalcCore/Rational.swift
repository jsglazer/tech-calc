import Foundation

/// Rational reconstruction for `>Frac`.
///
/// Continued-fraction expansion of the `Double`, capped at the TI-84's maximum denominator of
/// 9999. When no rational within that limit reproduces the value, the caller shows the decimal
/// unchanged. This is deliberately not a symbolic exact-rational tower.
public struct Rational: Equatable, Sendable {
    public let numerator: Int
    public let denominator: Int

    public init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let maxDenominator = 9999

    /// Relative tolerance at which the reconstructed rational is accepted as equal to `value`.
    public static let tolerance = 1e-10

    /// Returns the rational form of `value`, or `nil` when none exists within the denominator cap.
    public static func reconstruct(_ value: Double) -> Rational? {
        guard value.isFinite else { return nil }
        guard Swift.abs(value) < 1e12 else { return nil }

        let sign = value < 0 ? -1 : 1
        let x = Swift.abs(value)

        // Convergents of the continued fraction: h/k, tracked one step back as hPrev/kPrev.
        var hPrev = 0, h = 1
        var kPrev = 1, k = 0
        var remainder = x

        // Bounded loop: the denominator cap terminates the expansion, and 64 steps is far beyond
        // what a denominator below 10000 can require.
        for _ in 0..<64 {
            let whole = remainder.rounded(.down)
            guard whole.isFinite, Swift.abs(whole) < 1e15 else { return nil }
            let a = Int(whole)

            let nextH = a * h + hPrev
            let nextK = a * k + kPrev
            if nextK > maxDenominator { return nil }

            hPrev = h; h = nextH
            kPrev = k; k = nextK

            if k > 0 {
                let approximation = Double(h) / Double(k)
                if Swift.abs(approximation - x) <= tolerance * Swift.max(1, x) {
                    return Rational(numerator: sign * h, denominator: k)
                }
            }

            let fraction = remainder - whole
            if fraction == 0 { break }
            remainder = 1 / fraction
        }
        return nil
    }
}
