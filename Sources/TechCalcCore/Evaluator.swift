import Foundation

/// Evaluates a parsed expression.
///
/// Complex arithmetic runs unconditionally; `ComplexMode` is applied afterwards, by
/// `Calculator`, to decide whether a complex answer is shown or rejected as `ERR:NONREAL ANS`.
/// There is no real-only code path to keep in step with the complex one.
public struct Evaluator: Sendable {
    public var context: EvaluationContext
    /// The only source of randomness; injected so a seeded generator gives exact sequences.
    public let random: RandomSource

    public init(context: EvaluationContext = EvaluationContext(), random: RandomSource) {
        self.context = context
        self.random = random
    }

    // MARK: - Entry points

    public mutating func evaluate(_ expression: Expression) throws -> TIValue {
        switch expression {
        case .number(let value):
            return .real(value)

        case .variable(let name):
            return .number(try context.value(of: name))

        case .ans:
            return context.ans.value

        case .constant(let id):
            return try evaluateConstant(id)

        case .negation(let inner):
            return .number(-(try evaluate(inner).asComplex))

        case .binary(let op, let left, let right):
            let lhs = try evaluate(left)
            let rhs = try evaluate(right)
            return try apply(op, lhs, rhs)

        case .displayConversion(_, let inner):
            // Presentation only: the value itself is unchanged.
            return try evaluate(inner)

        case .store(let inner, let target):
            let value = try evaluate(inner)
            switch target {
            case .variable(let name):
                try context.setValue(try value.asComplex, for: name)
            case .randomSeed:
                random.reseed(UInt64(bitPattern: Int64(try value.asInteger)))
            }
            return value

        case .call(let id, let arguments):
            guard let definition = FunctionCatalog.definition(for: id) else { throw TIError.undefined }
            guard definition.arity.contains(arguments.count) else { throw TIError.syntax }
            if definition.takesUnevaluatedArguments {
                return try evaluateBinding(id, arguments)
            }
            let values = try arguments.map { try evaluate($0) }
            return try apply(id, values)
        }
    }

    /// Pure evaluation of an expression under a supplied variable binding, leaving this
    /// evaluator's own state untouched.
    ///
    /// This is the seam the deferred graphing layer plots through: a future `Y=` renderer samples
    /// a function by calling here, and needs nothing else from the evaluator.
    public func value(of expression: Expression, binding: [Character: Complex] = [:]) throws -> TIValue {
        var local = self
        for (name, value) in binding {
            try local.context.setValue(value, for: name)
        }
        return try local.evaluate(expression)
    }

    // MARK: - Operators

    private func apply(_ op: BinaryOperator, _ lhs: TIValue, _ rhs: TIValue) throws -> TIValue {
        let a = try lhs.asComplex
        let b = try rhs.asComplex
        switch op {
        case .add: return .number(a + b)
        case .subtract: return .number(a - b)
        case .multiply: return .number(a * b)
        case .divide: return .number(try a / b)
        case .power: return .number(try Complex.pow(a, b))
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual:
            return .real(try compare(op, a, b) ? 1 : 0)
        }
    }

    private func compare(_ op: BinaryOperator, _ a: Complex, _ b: Complex) throws -> Bool {
        switch op {
        case .equal: return a == b
        case .notEqual: return a != b
        default: break
        }
        // Ordering comparisons are real-only on the TI.
        guard a.isReal, b.isReal else { throw TIError.dataType }
        switch op {
        case .less: return a.re < b.re
        case .lessEqual: return a.re <= b.re
        case .greater: return a.re > b.re
        case .greaterEqual: return a.re >= b.re
        default: throw TIError.syntax
        }
    }

    // MARK: - Constants

    private func evaluateConstant(_ id: FunctionID) throws -> TIValue {
        switch id {
        case .pi: return .real(Double.pi)
        case .eulersNumber: return .real(M_E)
        case .imaginaryUnit: return .complex(Complex.i)
        case .random: return .real(random.nextUniform())
        default: throw TIError.undefined
        }
    }

    // MARK: - Functions

    private func apply(_ id: FunctionID, _ values: [TIValue]) throws -> TIValue {
        switch id {
        // Trigonometry — the argument is converted from the current angle unit to radians.
        case .sin: return .number(Complex.sin(try angleArgument(values, 0)))
        case .cos: return .number(Complex.cos(try angleArgument(values, 0)))
        case .tan: return .number(try Complex.tan(try angleArgument(values, 0)))
        case .asin: return .number(inAngleUnit(try Complex.asin(try complex(values, 0))))
        case .acos: return .number(inAngleUnit(try Complex.acos(try complex(values, 0))))
        case .atan: return .number(inAngleUnit(try Complex.atan(try complex(values, 0))))
        case .sinh: return .number(Complex.sinh(try complex(values, 0)))
        case .cosh: return .number(Complex.cosh(try complex(values, 0)))
        case .tanh: return .number(try Complex.tanh(try complex(values, 0)))
        case .asinh: return .number(try Complex.asinh(try complex(values, 0)))
        case .acosh: return .number(try Complex.acosh(try complex(values, 0)))
        case .atanh: return .number(try Complex.atanh(try complex(values, 0)))

        // Logarithms and exponentials
        case .ln: return .number(try Complex.log(try complex(values, 0)))
        case .log: return .number(try Complex.log(try complex(values, 0)) / Complex(Foundation.log(10.0)))
        case .logBase:
            let value = try Complex.log(try complex(values, 0))
            let base = try Complex.log(try complex(values, 1))
            return .number(try value / base)

        // Roots and powers
        case .squareRoot: return .number(Complex.sqrt(try complex(values, 0)))
        case .cubeRoot: return .number(try Complex.pow(try complex(values, 0), Complex(1.0 / 3.0)))
        case .nthRoot:
            let index = try complex(values, 0)
            let value = try complex(values, 1)
            return .number(try Complex.pow(value, try Complex.one / index))
        case .square:
            let z = try complex(values, 0)
            return .number(z * z)
        case .cube:
            let z = try complex(values, 0)
            return .number(z * z * z)
        case .reciprocal: return .number(try Complex.one / (try complex(values, 0)))

        // MATH NUM
        case .absoluteValue: return .real((try complex(values, 0)).magnitude)
        case .round:
            let value = try real(values, 0)
            let places = values.count == 2 ? try values[1].asInteger : 9
            guard (0...9).contains(places) else { throw TIError.domain }
            let scale = Foundation.pow(10.0, Double(places))
            return .real((value * scale).rounded() / scale)
        case .integerPart: return .real((try real(values, 0)).rounded(.towardZero))
        case .fractionalPart:
            let value = try real(values, 0)
            return .real(value - value.rounded(.towardZero))
        case .floorInt: return .real((try real(values, 0)).rounded(.down))
        case .minimum: return .real(Swift.min(try real(values, 0), try real(values, 1)))
        case .maximum: return .real(Swift.max(try real(values, 0), try real(values, 1)))
        case .gcd: return .real(Double(try greatestCommonDivisor(try values[0].asInteger, try values[1].asInteger)))
        case .lcm:
            let a = try values[0].asInteger, b = try values[1].asInteger
            let divisor = try greatestCommonDivisor(a, b)
            if divisor == 0 { return .real(0) }
            return .real(Double(Swift.abs(a / divisor * b)))
        case .remainder:
            let divisor = try real(values, 1)
            guard divisor != 0 else { throw TIError.divideByZero }
            return .real((try real(values, 0)).truncatingRemainder(dividingBy: divisor))

        // MATH PROB
        case .permutations:
            let (n, r) = try countArguments(values)
            return .real(try fallingFactorial(n: n, r: r))
        case .combinations:
            let (n, r) = try countArguments(values)
            let numerator = try fallingFactorial(n: n, r: r)
            return .real(numerator / (try factorial(Double(r))))
        case .factorial: return .real(try factorial(try real(values, 0)))
        case .random: return .real(random.nextUniform())
        case .randomInteger:
            let lower = try values[0].asInteger
            let upper = try values[1].asInteger
            return .real(Double(try random.nextInteger(lower: lower, upper: upper)))

        // MATH CMPLX
        case .conjugate: return .number((try complex(values, 0)).conjugate)
        case .realPart: return .real((try complex(values, 0)).re)
        case .imaginaryPart: return .real((try complex(values, 0)).im)
        case .argument: return .real(inAngleUnit(Complex((try complex(values, 0)).argument)).re)

        // ANGLE
        case .degreeUnit:
            // `x°` is x degrees, expressed in whatever unit the current mode uses.
            return .number(try complex(values, 0) * Complex((Double.pi / 180) / context.mode.radiansPerUnit))
        case .radianUnit:
            return .number(try complex(values, 0) * Complex(1 / context.mode.radiansPerUnit))
        case .toPolarRadius:
            let x = try real(values, 0), y = try real(values, 1)
            return .real((x * x + y * y).squareRoot())
        case .toPolarAngle:
            let x = try real(values, 0), y = try real(values, 1)
            return .real(Foundation.atan2(y, x) / context.mode.radiansPerUnit)
        case .toRectangularX:
            let r = try real(values, 0), theta = try real(values, 1) * context.mode.radiansPerUnit
            return .real(r * Foundation.cos(theta))
        case .toRectangularY:
            let r = try real(values, 0), theta = try real(values, 1) * context.mode.radiansPerUnit
            return .real(r * Foundation.sin(theta))

        // TEST LOGIC
        case .logicalAnd: return .real(try isTrue(values, 0) && (try isTrue(values, 1)) ? 1 : 0)
        case .logicalOr: return .real(try isTrue(values, 0) || (try isTrue(values, 1)) ? 1 : 0)
        case .logicalXor: return .real((try isTrue(values, 0)) != (try isTrue(values, 1)) ? 1 : 0)
        case .logicalNot: return .real(try isTrue(values, 0) ? 0 : 1)

        // Presentation-only ids and constants never reach here as calls.
        case .powerOfTen, .powerOfE, .pi, .eulersNumber, .imaginaryUnit, .toFraction, .toDecimal, .toRectangular, .toPolar,
             .numericIntegral, .numericDerivative, .summation:
            throw TIError.undefined
        }
    }

    // MARK: - Functions that bind a variable over an expression

    private func evaluateBinding(_ id: FunctionID, _ arguments: [Expression]) throws -> TIValue {
        guard case .variable(let name) = arguments[1] else { throw TIError.syntax }
        let body = arguments[0]
        var local = self

        switch id {
        case .numericIntegral:
            let lower = try local.evaluate(arguments[2]).asReal
            let upper = try local.evaluate(arguments[3]).asReal
            let result = try NumericMethods.integrate(lower: lower, upper: upper) { x in
                try local.sample(body, name, x)
            }
            return .real(result)

        case .numericDerivative:
            let point = try local.evaluate(arguments[2]).asReal
            let step = arguments.count == 4
                ? try local.evaluate(arguments[3]).asReal
                : NumericMethods.derivativeStep
            let result = try NumericMethods.derivative(at: point, step: step) { x in
                try local.sample(body, name, x)
            }
            return .real(result)

        case .summation:
            let start = try local.evaluate(arguments[2]).asInteger
            let end = try local.evaluate(arguments[3]).asInteger
            let result = try NumericMethods.summation(from: start, through: end) { index in
                var inner = local
                try inner.context.setValue(Complex(Double(index)), for: name)
                return try inner.evaluate(body).asComplex
            }
            return .number(result)

        default:
            throw TIError.undefined
        }
    }

    /// Evaluates `body` with `name` bound to `x`, without disturbing the caller's variables.
    private func sample(_ body: Expression, _ name: Character, _ x: Double) throws -> Double {
        var local = self
        try local.context.setValue(Complex(x), for: name)
        return try local.evaluate(body).asReal
    }

    // MARK: - Argument helpers

    private func complex(_ values: [TIValue], _ index: Int) throws -> Complex {
        guard values.indices.contains(index) else { throw TIError.syntax }
        return try values[index].asComplex
    }

    private func real(_ values: [TIValue], _ index: Int) throws -> Double {
        guard values.indices.contains(index) else { throw TIError.syntax }
        return try values[index].asReal
    }

    private func isTrue(_ values: [TIValue], _ index: Int) throws -> Bool {
        try real(values, index) != 0
    }

    /// A trig argument, converted from the current angle unit into radians.
    private func angleArgument(_ values: [TIValue], _ index: Int) throws -> Complex {
        try complex(values, index) * Complex(context.mode.radiansPerUnit)
    }

    /// A radian result, converted back into the current angle unit.
    private func inAngleUnit(_ z: Complex) -> Complex {
        z * Complex(1 / context.mode.radiansPerUnit)
    }

    private func countArguments(_ values: [TIValue]) throws -> (n: Int, r: Int) {
        let n = try values[0].asInteger
        let r = try values[1].asInteger
        guard n >= 0, r >= 0, r <= n else { throw TIError.domain }
        return (n, r)
    }

    private func fallingFactorial(n: Int, r: Int) throws -> Double {
        var product = 1.0
        for step in 0..<r {
            product *= Double(n - step)
        }
        return product
    }

    /// Non-negative integers, plus the half-integers the TI accepts via the gamma function.
    private func factorial(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 0 else { throw TIError.domain }
        if value == value.rounded() {
            guard value <= 170 else { return .infinity }
            var product = 1.0
            var step = 2.0
            while step <= value {
                product *= step
                step += 1
            }
            return product
        }
        guard value - value.rounded(.down) == 0.5 else { throw TIError.domain }
        return Foundation.tgamma(value + 1)
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) throws -> Int {
        var x = Swift.abs(a)
        var y = Swift.abs(b)
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return x
    }
}
