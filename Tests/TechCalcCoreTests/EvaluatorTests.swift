import Foundation
import Testing
@testable import TechCalcCore

@Suite("Scalar evaluation")
struct EvaluatorTests {

    @Test("Arithmetic and roots")
    func arithmetic() throws {
        expectClose(try Fixture.real("2+3*4-6/3"), 12)
        expectClose(try Fixture.real("√(2)"), 2.0.squareRoot())
        expectClose(try Fixture.real("³√(27)"), 3)
        expectClose(try Fixture.real("³√(-27)"), -3)
        expectClose(try Fixture.real("ˣ√(3,8)"), 2)
        expectClose(try Fixture.real("4⁻¹"), 0.25)
        expectClose(try Fixture.real("3²"), 9)
        expectClose(try Fixture.real("3³"), 27)
    }

    @Test("Trigonometry honours the angle mode")
    func trigonometryUsesAngleMode() throws {
        let degrees = CalculatorMode(angle: .degrees)
        expectClose(try Fixture.real("sin(30)", mode: degrees), 0.5)
        expectClose(try Fixture.real("cos(60)", mode: degrees), 0.5)
        expectClose(try Fixture.real("tan⁻¹(1)", mode: degrees), 45)

        let radians = CalculatorMode(angle: .radians)
        expectClose(try Fixture.real("sin(π/6)", mode: radians), 0.5)
        expectClose(try Fixture.real("sin⁻¹(.5)", mode: radians), Double.pi / 6)

        // The ° mark makes its operand degrees whatever the mode is.
        expectClose(try Fixture.real("sin(90°)", mode: radians), 1)
        expectClose(try Fixture.real("sin(90°)", mode: degrees), 1)
        expectClose(try Fixture.real("sin(1ʳ)", mode: degrees), Foundation.sin(1))
    }

    @Test("Hyperbolics, logarithms and exponentials")
    func transcendentals() throws {
        expectClose(try Fixture.real("ln(e^(2))"), 2)
        expectClose(try Fixture.real("log(1000)"), 3)
        expectClose(try Fixture.real("10^(3)"), 1000)
        expectClose(try Fixture.real("logBASE(8,2)"), 3)
        expectClose(try Fixture.real("sinh(1)"), Foundation.sinh(1))
        expectClose(try Fixture.real("cosh⁻¹(1)"), 0)
        expectClose(try Fixture.real("tanh⁻¹(.5)"), Foundation.atanh(0.5))
    }

    @Test("MATH NUM functions")
    func numberFunctions() throws {
        expectClose(try Fixture.real("abs(-7)"), 7)
        expectClose(try Fixture.real("round(π,4)"), 3.1416)
        expectClose(try Fixture.real("iPart(-3.7)"), -3)
        expectClose(try Fixture.real("fPart(-3.75)"), -0.75)
        expectClose(try Fixture.real("int(-3.2)"), -4)
        expectClose(try Fixture.real("min(3,8)"), 3)
        expectClose(try Fixture.real("max(3,8)"), 8)
        expectClose(try Fixture.real("gcd(24,36)"), 12)
        expectClose(try Fixture.real("lcm(4,6)"), 12)
        expectClose(try Fixture.real("remainder(17,5)"), 2)
    }

    @Test("MATH PROB counting functions")
    func probabilityFunctions() throws {
        expectClose(try Fixture.real("5 nPr 2"), 20)
        expectClose(try Fixture.real("5 nCr 2"), 10)
        expectClose(try Fixture.real("5!"), 120)
        expectClose(try Fixture.real("0!"), 1)
        expectTIError("(-1)!", .domain)
        expectTIError("5 nCr 7", .domain)
    }

    @Test("Complex arithmetic is always computed; REAL mode governs presentation only")
    func complexArithmetic() throws {
        let rectangular = CalculatorMode(complex: .rectangular)
        // In REAL mode a complex answer is refused rather than shown.
        expectTIError("√(-4)", .nonrealAnswer)
        // The same expression computes fine when the mode allows showing it.
        let value = try Fixture.value("√(-4)", mode: rectangular)
        #expect(value == .complex(Complex(0, 2)))
        #expect(Fixture.display("√(-4)", mode: rectangular) == "2i")
        expectClose(try Fixture.real("real(3+4i)", mode: rectangular), 3)
        expectClose(try Fixture.real("imag(3+4i)", mode: rectangular), 4)
        expectClose(try Fixture.real("abs(3+4i)", mode: rectangular), 5)
        #expect(try Fixture.value("conj(3+4i)", mode: rectangular) == .complex(Complex(3, -4)))
    }

    @Test("ANGLE conversions between rectangular and polar")
    func angleConversions() throws {
        let degrees = CalculatorMode(angle: .degrees)
        expectClose(try Fixture.real("R▸Pr(3,4)"), 5)
        expectClose(try Fixture.real("R▸Pθ(0,1)", mode: degrees), 90)
        expectClose(try Fixture.real("P▸Rx(2,60)", mode: degrees), 1)
        expectClose(try Fixture.real("P▸Ry(2,90)", mode: degrees), 2)
    }

    @Test("TEST and LOGIC operators return 1 or 0")
    func logic() throws {
        expectClose(try Fixture.real("3>2"), 1)
        expectClose(try Fixture.real("3≤2"), 0)
        expectClose(try Fixture.real("3≠2"), 1)
        expectClose(try Fixture.real("1 and 0"), 0)
        expectClose(try Fixture.real("1 or 0"), 1)
        expectClose(try Fixture.real("1 xor 1"), 0)
        expectClose(try Fixture.real("not(0)"), 1)
    }

    @Test("Iterative numerics: fnInt, nDeriv and summation")
    func iterativeNumerics() throws {
        expectClose(try Fixture.real("fnInt(X²,X,0,1)"), 1.0 / 3.0, tolerance: 1e-8)
        expectClose(try Fixture.real("fnInt(sin(X),X,0,π)"), 2, tolerance: 1e-8)
        expectClose(try Fixture.real("nDeriv(X²,X,3)"), 6, tolerance: 1e-6)
        expectClose(try Fixture.real("Σ(X,X,1,10)"), 55)
        expectClose(try Fixture.real("Σ(X²,X,1,5)"), 55)
    }

    @Test("A binding function leaves the caller's variables untouched")
    func bindingFunctionsDoNotLeak() throws {
        var calculator = Fixture.calculator()
        calculator.enter("7→X")
        expectClose(try calculator.evaluate("fnInt(X²,X,0,1)").result.asReal, 1.0 / 3.0, tolerance: 1e-8)
        expectClose(try calculator.evaluate("X").result.asReal, 7)
    }

    @Test("The pure evaluation entry point evaluates an AST over a supplied binding")
    func pureFunctionEvaluationEntryPoint() throws {
        // This is the seam a future plotting layer samples through; it must not mutate state.
        let expression = try Parser.parse("X²+1").expression
        let evaluator = Fixture.evaluator()
        expectClose(try evaluator.value(of: expression, binding: ["X": Complex(3)]).asReal, 10)
        expectClose(try evaluator.value(of: expression, binding: ["X": Complex(4)]).asReal, 17)
        // The evaluator's own X is still unset.
        expectClose(try evaluator.value(of: expression).asReal, 1)
    }

    @Test("Error names match the TI exactly")
    func errorParity() {
        expectTIError("1/0", .divideByZero)
        expectTIError("ln(0)", .domain)
        expectTIError("√(-1)", .nonrealAnswer)
        expectTIError("round(1,12)", .domain)
        expectTIError("2+", .syntax)
        #expect(TIError.dimensionMismatch.tiName == "ERR:DIM MISMATCH")
        #expect(TIError.invalidDimension.tiName == "ERR:INVALID DIM")
        #expect(TIError.singularMatrix.tiName == "ERR:SINGULAR MAT")
        #expect(TIError.dataType.tiName == "ERR:DATA TYPE")
        #expect(TIError.noSignChange.tiName == "ERR:NO SIGN CHNG")
        #expect(TIError.iterations.tiName == "ERR:ITERATIONS")
    }
}
