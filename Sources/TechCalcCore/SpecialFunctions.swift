import Foundation

/// The special functions the continuous distributions are built from.
///
/// The pre-build decisions rule out the Abramowitz and Stegun rational approximations: they
/// cannot hold the six-decimal TI parity bar in the tails. Everything here is therefore computed
/// from the regularized incomplete gamma and regularized incomplete beta functions, evaluated by
/// modified Lentz continued fractions converged to `convergenceTolerance`.
///
/// Every loop carries an explicit iteration cap and throws `ERR:ITERATIONS` rather than spinning,
/// so no call here can starve a thread or make a test flaky.
public enum SpecialFunctions {
    /// Relative convergence bar for the series and continued fractions.
    public static let convergenceTolerance = 1e-15
    /// Hard cap on series terms and continued-fraction iterations.
    public static let maximumIterations = 300
    /// Guards a Lentz denominator against underflow to exactly zero.
    private static let tiny = 1e-300

    // MARK: - Gamma

    /// `ln Γ(x)` for x > 0, by the Lanczos approximation (g = 7, n = 9).
    ///
    /// Foundation's `lgamma` would do, but it carries a global `signgam` side effect and its
    /// tail accuracy is platform-defined; a closed-form series keeps the result identical on
    /// every architecture, which is what the determinism constraint asks for.
    public static func logGamma(_ x: Double) throws -> Double {
        guard x > 0, x.isFinite else { throw TIError.domain }
        if x < 0.5 {
            // Reflection: Γ(x)Γ(1-x) = π / sin(πx).
            return Foundation.log(Double.pi / Foundation.sin(Double.pi * x)) - (try logGamma(1 - x))
        }
        let z = x - 1
        var series = lanczosCoefficients[0]
        for index in 1..<lanczosCoefficients.count {
            series += lanczosCoefficients[index] / (z + Double(index))
        }
        let t = z + 7.5
        return 0.5 * Foundation.log(2 * Double.pi) + (z + 0.5) * Foundation.log(t) - t + Foundation.log(series)
    }

    private static let lanczosCoefficients: [Double] = [
        0.999_999_999_999_809_93,
        676.520_368_121_885_1,
        -1259.139_216_722_402_8,
        771.323_428_777_653_13,
        -176.615_029_162_140_6,
        12.507_343_278_686_905,
        -0.138_571_095_265_720_12,
        9.984_369_578_019_572e-6,
        1.505_632_735_149_311_6e-7
    ]

    // MARK: - Regularized incomplete gamma

    /// `P(a, x)` — the lower regularized incomplete gamma function.
    ///
    /// Series below the crossover, continued fraction above it: each converges quickly on its own
    /// side, and the pair is what gives the chi-square tails their accuracy.
    public static func regularizedGammaP(_ a: Double, _ x: Double) throws -> Double {
        guard a > 0, x >= 0, a.isFinite, x.isFinite else { throw TIError.domain }
        if x == 0 { return 0 }
        if x < a + 1 {
            return try lowerGammaSeries(a, x)
        }
        return 1 - (try upperGammaFraction(a, x))
    }

    /// `Q(a, x) = 1 - P(a, x)` — the upper tail, computed directly so it keeps its significant
    /// digits where `1 - P` would cancel them away.
    public static func regularizedGammaQ(_ a: Double, _ x: Double) throws -> Double {
        guard a > 0, x >= 0, a.isFinite, x.isFinite else { throw TIError.domain }
        if x == 0 { return 1 }
        if x < a + 1 {
            return 1 - (try lowerGammaSeries(a, x))
        }
        return try upperGammaFraction(a, x)
    }

    /// The ascending series for `P(a, x)`, valid for x < a + 1.
    private static func lowerGammaSeries(_ a: Double, _ x: Double) throws -> Double {
        var term = 1.0 / a
        var sum = term
        var denominator = a
        for _ in 0..<maximumIterations {
            denominator += 1
            term *= x / denominator
            sum += term
            if Swift.abs(term) < Swift.abs(sum) * convergenceTolerance {
                return sum * Foundation.exp(-x + a * Foundation.log(x) - (try logGamma(a)))
            }
        }
        throw TIError.iterations
    }

    /// The modified Lentz continued fraction for `Q(a, x)`, valid for x >= a + 1.
    private static func upperGammaFraction(_ a: Double, _ x: Double) throws -> Double {
        var b = x + 1 - a
        var c = 1 / tiny
        var d = 1 / b
        var result = d

        for index in 1...maximumIterations {
            let n = Double(index)
            let an = -n * (n - a)
            b += 2
            d = an * d + b
            if Swift.abs(d) < tiny { d = tiny }
            c = b + an / c
            if Swift.abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            result *= delta
            if Swift.abs(delta - 1) < convergenceTolerance {
                return result * Foundation.exp(-x + a * Foundation.log(x) - (try logGamma(a)))
            }
        }
        throw TIError.iterations
    }

    // MARK: - Regularized incomplete beta

    /// `I_x(a, b)` — the regularized incomplete beta function, the backbone of the Student t and
    /// F distributions.
    public static func regularizedBeta(_ x: Double, _ a: Double, _ b: Double) throws -> Double {
        guard a > 0, b > 0, a.isFinite, b.isFinite else { throw TIError.domain }
        guard x >= 0, x <= 1 else { throw TIError.domain }
        if x == 0 { return 0 }
        if x == 1 { return 1 }

        let front = Foundation.exp(
            (try logGamma(a + b)) - (try logGamma(a)) - (try logGamma(b))
                + a * Foundation.log(x) + b * Foundation.log(1 - x)
        )
        // The fraction converges fastest on the side where x is below the distribution's mean;
        // the symmetry I_x(a,b) = 1 - I_(1-x)(b,a) moves the argument there when it is not.
        if x < (a + 1) / (a + b + 2) {
            return front * (try betaFraction(x, a, b)) / a
        }
        return 1 - front * (try betaFraction(1 - x, b, a)) / b
    }

    /// Lentz evaluation of the continued fraction in the incomplete beta expansion.
    private static func betaFraction(_ x: Double, _ a: Double, _ b: Double) throws -> Double {
        var c = 1.0
        var d = 1 - (a + b) * x / (a + 1)
        if Swift.abs(d) < tiny { d = tiny }
        d = 1 / d
        var result = d

        for index in 1...maximumIterations {
            let m = Double(index)
            // Even and odd steps use different numerators; both are folded into one iteration.
            let even = m * (b - m) * x / ((a + 2 * m - 1) * (a + 2 * m))
            d = 1 + even * d
            if Swift.abs(d) < tiny { d = tiny }
            c = 1 + even / c
            if Swift.abs(c) < tiny { c = tiny }
            d = 1 / d
            result *= d * c

            let odd = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 2 * m + 1))
            d = 1 + odd * d
            if Swift.abs(d) < tiny { d = tiny }
            c = 1 + odd / c
            if Swift.abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            result *= delta

            if Swift.abs(delta - 1) < convergenceTolerance { return result }
        }
        throw TIError.iterations
    }

    // MARK: - Combinatorics

    /// `ln n!`, used by the discrete distributions so `binompdf(` stays accurate for large n
    /// where the factorials themselves would overflow.
    public static func logFactorial(_ n: Int) throws -> Double {
        guard n >= 0 else { throw TIError.domain }
        return try logGamma(Double(n) + 1)
    }

    /// `ln C(n, k)`.
    public static func logBinomialCoefficient(n: Int, k: Int) throws -> Double {
        guard n >= 0, k >= 0, k <= n else { throw TIError.domain }
        return (try logFactorial(n)) - (try logFactorial(k)) - (try logFactorial(n - k))
    }
}
