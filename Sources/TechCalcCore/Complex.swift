import Foundation

/// A complex number in rectangular form.
///
/// Complex arithmetic is *always* computed — the evaluator is never forked into separate real
/// and complex code paths. The REAL / a+bi / re^(theta)i mode governs presentation only, and
/// whether a complex result raises `ERR:NONREAL ANS`.
///
/// Real-valued fast paths exist not to fork the evaluator but to keep results exact: a general
/// polar formula would leave a 1e-17 imaginary residue on `sqrt(4)`, which would then print as
/// a complex number.
public struct Complex: Equatable, Hashable, Sendable, Codable {
    public var re: Double
    public var im: Double

    public init(_ re: Double, _ im: Double = 0) {
        self.re = re
        self.im = im
    }

    public static let zero = Complex(0)
    public static let one = Complex(1)
    public static let i = Complex(0, 1)

    public var isReal: Bool { im == 0 }
    public var magnitude: Double { isReal ? Swift.abs(re) : (re * re + im * im).squareRoot() }
    public var argument: Double { Foundation.atan2(im, re) }
    public var conjugate: Complex { Complex(re, -im) }
    public var isFinite: Bool { re.isFinite && im.isFinite }

    // MARK: - Field arithmetic

    public static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    public static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    public static prefix func - (a: Complex) -> Complex { Complex(-a.re, -a.im) }

    public static func * (a: Complex, b: Complex) -> Complex {
        if a.isReal && b.isReal { return Complex(a.re * b.re) }
        return Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
    }

    public static func / (a: Complex, b: Complex) throws -> Complex {
        if b.re == 0 && b.im == 0 { throw TIError.divideByZero }
        if a.isReal && b.isReal { return Complex(a.re / b.re) }
        // Smith's algorithm: scale by the larger component to avoid intermediate overflow.
        if Swift.abs(b.re) >= Swift.abs(b.im) {
            let r = b.im / b.re
            let d = b.re + b.im * r
            return Complex((a.re + a.im * r) / d, (a.im - a.re * r) / d)
        } else {
            let r = b.re / b.im
            let d = b.re * r + b.im
            return Complex((a.re * r + a.im) / d, (a.im * r - a.re) / d)
        }
    }

    // MARK: - Transcendental functions

    /// Natural logarithm. `ln(0)` is a TI domain error rather than -infinity.
    public static func log(_ z: Complex) throws -> Complex {
        if z.re == 0 && z.im == 0 { throw TIError.domain }
        if z.isReal && z.re > 0 { return Complex(Foundation.log(z.re)) }
        if z.isReal { return Complex(Foundation.log(-z.re), Double.pi) }
        return Complex(Foundation.log(z.magnitude), z.argument)
    }

    public static func exp(_ z: Complex) -> Complex {
        if z.isReal { return Complex(Foundation.exp(z.re)) }
        let m = Foundation.exp(z.re)
        return Complex(m * Foundation.cos(z.im), m * Foundation.sin(z.im))
    }

    public static func sqrt(_ z: Complex) -> Complex {
        if z.isReal {
            return z.re >= 0 ? Complex(z.re.squareRoot()) : Complex(0, (-z.re).squareRoot())
        }
        let m = z.magnitude.squareRoot()
        let a = z.argument / 2
        return Complex(m * Foundation.cos(a), m * Foundation.sin(a))
    }

    /// `a ^ b`, staying on the real line wherever the result is real.
    public static func pow(_ a: Complex, _ b: Complex) throws -> Complex {
        if a.re == 0 && a.im == 0 {
            if b.re == 0 && b.im == 0 { throw TIError.domain }   // 0^0 is ERR:DOMAIN on the TI
            if b.isReal && b.re > 0 { return .zero }
            throw TIError.divideByZero
        }
        if a.isReal && b.isReal {
            // Positive base, or an integral exponent: the real power is exact and real.
            if a.re > 0 || b.re == b.re.rounded() {
                return Complex(Foundation.pow(a.re, b.re))
            }
            // Negative base with a fractional exponent: odd roots stay real on the TI.
            let inverse = 1 / b.re
            if inverse.isFinite, inverse == inverse.rounded(), Int(inverse) % 2 != 0 {
                return Complex(-Foundation.pow(-a.re, b.re))
            }
        }
        return exp(try log(a) * b)
    }

    // MARK: - Trigonometry (arguments are always radians here; angle mode is applied above)

    public static func sin(_ z: Complex) -> Complex {
        if z.isReal { return Complex(Foundation.sin(z.re)) }
        return Complex(Foundation.sin(z.re) * Foundation.cosh(z.im),
                       Foundation.cos(z.re) * Foundation.sinh(z.im))
    }

    public static func cos(_ z: Complex) -> Complex {
        if z.isReal { return Complex(Foundation.cos(z.re)) }
        return Complex(Foundation.cos(z.re) * Foundation.cosh(z.im),
                       -Foundation.sin(z.re) * Foundation.sinh(z.im))
    }

    public static func tan(_ z: Complex) throws -> Complex {
        if z.isReal { return Complex(Foundation.tan(z.re)) }
        return try sin(z) / cos(z)
    }

    public static func asin(_ z: Complex) throws -> Complex {
        if z.isReal && Swift.abs(z.re) <= 1 { return Complex(Foundation.asin(z.re)) }
        // asin(z) = -i * ln(iz + sqrt(1 - z^2))
        let root = sqrt(Complex.one - z * z)
        return Complex(0, -1) * (try log(Complex.i * z + root))
    }

    public static func acos(_ z: Complex) throws -> Complex {
        if z.isReal && Swift.abs(z.re) <= 1 { return Complex(Foundation.acos(z.re)) }
        return Complex(Double.pi / 2) - (try asin(z))
    }

    public static func atan(_ z: Complex) throws -> Complex {
        if z.isReal { return Complex(Foundation.atan(z.re)) }
        if z == Complex.i || z == -Complex.i { throw TIError.domain }
        // atan(z) = (i/2) * ln((i + z)/(i - z))
        let quotient = try (Complex.i + z) / (Complex.i - z)
        return Complex(0, 0.5) * (try log(quotient))
    }

    public static func sinh(_ z: Complex) -> Complex {
        if z.isReal { return Complex(Foundation.sinh(z.re)) }
        return Complex(Foundation.sinh(z.re) * Foundation.cos(z.im),
                       Foundation.cosh(z.re) * Foundation.sin(z.im))
    }

    public static func cosh(_ z: Complex) -> Complex {
        if z.isReal { return Complex(Foundation.cosh(z.re)) }
        return Complex(Foundation.cosh(z.re) * Foundation.cos(z.im),
                       Foundation.sinh(z.re) * Foundation.sin(z.im))
    }

    public static func tanh(_ z: Complex) throws -> Complex {
        if z.isReal { return Complex(Foundation.tanh(z.re)) }
        return try sinh(z) / cosh(z)
    }

    public static func asinh(_ z: Complex) throws -> Complex {
        if z.isReal { return Complex(Foundation.asinh(z.re)) }
        return try log(z + sqrt(z * z + Complex.one))
    }

    public static func acosh(_ z: Complex) throws -> Complex {
        if z.isReal && z.re >= 1 { return Complex(Foundation.acosh(z.re)) }
        return try log(z + sqrt(z * z - Complex.one))
    }

    public static func atanh(_ z: Complex) throws -> Complex {
        if z.isReal && Swift.abs(z.re) < 1 { return Complex(Foundation.atanh(z.re)) }
        if z == Complex.one || z == -Complex.one { throw TIError.domain }
        let quotient = try (Complex.one + z) / (Complex.one - z)
        return Complex(0.5) * (try log(quotient))
    }
}
