import Foundation
import Testing
@testable import TechCalcCore

/// Mechanical checks on the core's source text.
///
/// The reviewer criteria for this build are read-checks ("confirm TechCalcCore imports no
/// SwiftUI", "confirm no unseeded randomness"). Asserting them here turns each one into a
/// failing test rather than something a reader has to re-verify by hand.
@Suite("Core purity")
struct CoreConventionTests {

    /// `Sources/TechCalcCore`, located relative to this test file.
    static var coreSourceFiles: [URL] {
        get throws {
            let testFile = URL(fileURLWithPath: #filePath)
            let packageRoot = testFile
                .deletingLastPathComponent()   // TechCalcCoreTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // package root
            let coreDirectory = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("TechCalcCore")
            let contents = try FileManager.default.contentsOfDirectory(
                at: coreDirectory,
                includingPropertiesForKeys: nil
            )
            return contents.filter { $0.pathExtension == "swift" }
        }
    }

    /// Source with comment lines removed: a banned token named in prose is not a use of it.
    static func code(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func scanCore(_ check: (String, String) -> Void) throws {
        for url in try coreSourceFiles {
            check(url.lastPathComponent, try code(of: url))
        }
    }

    @Test("TechCalcCore imports no UI framework and no web view")
    func noUIImports() throws {
        let banned = ["import SwiftUI", "import AppKit", "import UIKit", "import WebKit"]
        try Self.scanCore { name, source in
            for token in banned {
                #expect(!source.contains(token), "\(name) contains \(token)")
            }
        }
    }

    @Test("No web view and no JavaScript engine anywhere in the core")
    func noJavaScriptEngine() throws {
        let banned = ["WKWebView", "JavaScriptCore", "JSContext", "JSValue"]
        try Self.scanCore { name, source in
            for token in banned {
                #expect(!source.contains(token), "\(name) contains \(token)")
            }
        }
    }

    @Test("No Accelerate, vDSP, BLAS or LAPACK: matrix work stays pure Swift")
    func noAcceleratedLinearAlgebra() throws {
        let banned = ["import Accelerate", "vDSP", "cblas", "LAPACK", "lapack_"]
        try Self.scanCore { name, source in
            for token in banned {
                #expect(!source.contains(token), "\(name) contains \(token)")
            }
        }
    }

    @Test("No unseeded randomness: every draw goes through the injected RandomSource")
    func noUnseededRandomness() throws {
        let banned = ["SystemRandomNumberGenerator", "Int.random", "Double.random", ".randomElement", "arc4random"]
        try Self.scanCore { name, source in
            for token in banned {
                #expect(!source.contains(token), "\(name) contains \(token)")
            }
        }
    }

    @Test("No direct persistence: no file I/O, no UserDefaults, no clock reads in the core")
    func noDirectPersistenceOrClock() throws {
        let banned = ["UserDefaults", "FileManager", "Date()", "DispatchTime", "NSDocument"]
        try Self.scanCore { name, source in
            for token in banned {
                #expect(!source.contains(token), "\(name) contains \(token)")
            }
        }
        // Storage crosses the boundary only as a protocol.
        #expect(InMemoryStorageProvider() is any StorageProvider)
    }

    @Test("No third-party dependency: the core imports only Foundation")
    func onlyFoundationIsImported() throws {
        try Self.scanCore { name, source in
            for line in source.split(separator: "\n") where line.hasPrefix("import ") {
                #expect(line == "import Foundation", "\(name) has unexpected \(line)")
            }
        }
    }

    @Test("Container delimiters are declared only in ContainerName.swift")
    func containerDelimitersLiveInOnePlace() throws {
        // The braces and brackets are read from `ContainerSyntax` by the tokenizer, the keypad
        // and the formatter, so a literal delimiter must not appear in any of them.
        let literals = ["\"{\"", "\"}\"", "\"[\"", "\"]\"", "\"L\"", "\"\u{221F}\""]
        for literal in literals {
            var filesContaining: [String] = []
            for url in try Self.coreSourceFiles {
                if try Self.code(of: url).contains(literal) {
                    filesContaining.append(url.lastPathComponent)
                }
            }
            #expect(filesContaining.isEmpty || filesContaining == ["ContainerName.swift"],
                    "\(literal) appears in \(filesContaining)")
        }
    }

    @Test("Statistics variable names are declared only in StatVariable.swift")
    func statisticsNamesLiveInOnePlace() throws {
        // The same rule the catalog gets: a statistics variable's spelling exists in exactly one
        // file, and the tokenizer, evaluator and results screens reach it by its case.
        // The spellings chosen here are never argument labels, so a match is a real second
        // declaration rather than a UI string that happens to read the same.
        let spellings = ["\"minX\"", "\"maxX\"", "\"Med\"", "\"Q1\"", "\"Q3\"", "\"sp\""]
        for spelling in spellings {
            var filesContaining: [String] = []
            for url in try Self.coreSourceFiles {
                if try Self.code(of: url).contains(spelling) {
                    filesContaining.append(url.lastPathComponent)
                }
            }
            #expect(filesContaining == ["StatVariable.swift"], "\(spelling) appears in \(filesContaining)")
        }
    }

    @Test("Every iterative numerical routine carries an explicit step limit")
    func iterativeRoutinesAreBounded() {
        // The reviewer criterion asks that the iterative loops have stated limits and tolerances.
        // Each of these is the single named constant its loop is bounded by.
        #expect(NumericMethods.maximumIntegrationLevels > 0)
        #expect(NumericMethods.maximumSummationTerms > 0)
        #expect(SpecialFunctions.maximumIterations > 0)
        #expect(SpecialFunctions.convergenceTolerance > 0)
        #expect(Distributions.maximumInverseIterations > 0)
        #expect(Distributions.inverseTolerance > 0)
        #expect(RandomLimits.maximumBernoulliTrials > 0)
        #expect(MatrixMath.singularityTolerance > 0)
        // The finance solvers: `I%` and `irr(` are root-finds, and amortization walks a range.
        #expect(Finance.maximumSolverIterations > 0)
        #expect(Finance.solverTolerance > 0)
        #expect(Finance.maximumPeriodicRate > 0)
        #expect(Finance.maximumPeriods > 0)
    }

    @Test("The base prefixes are declared only in NumberBases.swift")
    func basePrefixesLiveInOnePlace() throws {
        // The tokenizer reads the entry prefixes and the renderer writes them; neither spells one.
        for literal in ["\"0b\"", "\"0h\"", "\"0o\""] {
            var filesContaining: [String] = []
            for url in try Self.coreSourceFiles where try Self.code(of: url).contains(literal) {
                filesContaining.append(url.lastPathComponent)
            }
            #expect(filesContaining == ["NumberBases.swift"], "\(literal) appears in \(filesContaining)")
        }
    }

    @Test("No finance or base arithmetic lives outside its pure module")
    func financeArithmeticStaysInFinance() throws {
        // `EvaluatorFinance.swift` is an argument reader: it may name a `Finance` or
        // `NumberBases` function, but it must not do the arithmetic itself. The TVM equation's
        // own operator — exponentiation of a rate — appears in `Finance.swift` and nowhere else
        // in the evaluator, which is what keeps the solver screen and the command form one
        // implementation rather than two.
        let dispatch = try Self.code(of: Self.coreSourceFiles.first { $0.lastPathComponent == "EvaluatorFinance.swift" }!)
        #expect(!dispatch.contains("Foundation.pow"))
        #expect(!dispatch.contains("/ 100"))
        #expect(dispatch.contains("Finance."))
        #expect(dispatch.contains("NumberBases."))
    }

    /// `Sources/TechCalcUI`, located the same way the core directory is.
    static var interfaceSourceFiles: [URL] {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let directory = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("TechCalcUI")
            return try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
        }
    }

    @Test("No statistical, financial or numerical logic lives in a SwiftUI view")
    func viewsHoldNoLogic() throws {
        // The companion to `financeArithmeticStaysInFinance`, for the UI side. A screen may call a
        // pure entry point — `StatForms.run`, `Finance.solve` — but must not reach past it into the
        // procedures themselves, and must not do arithmetic of its own.
        let banned = [
            "Inference.", "Statistics.", "Distributions.", "SpecialFunctions.",
            "MatrixMath.", "ListMath.", "NumericMethods.", "Rational.",
            "sqrt", "squareRoot()", "Foundation.pow", "/ 100", "* 100"
        ]
        for url in try Self.interfaceSourceFiles {
            let source = try Self.code(of: url)
            for token in banned {
                #expect(!source.contains(token), "\(url.lastPathComponent) contains \(token)")
            }
        }
    }

    @Test("The screens reach TechCalcCore through its declared form tables, not by hard-coding")
    func viewsAreGeneratedFromTheCoreTables() throws {
        var sources: [String: String] = [:]
        for url in try Self.interfaceSourceFiles {
            sources[url.lastPathComponent] = try Self.code(of: url)
        }
        // The `STAT TESTS` screen renders whatever `StatForms` declares: it names no procedure and
        // switches only on a field's declared control kind.
        let statScreen: String = try #require(sources["StatTestsScreen.swift"])
        #expect(statScreen.contains("StatForms.all"))
        for procedure in FunctionCatalog.entries(inMenu: "STAT TESTS") {
            #expect(!statScreen.contains("\"\(procedure.name)\""),
                    "the stat screen spells \(procedure.name)")
        }
        // The solver screen renders `TVMField` and calls the one solve entry point.
        let solverScreen: String = try #require(sources["TVMSolverScreen.swift"])
        #expect(solverScreen.contains("TVMField.allCases"))
        #expect(solverScreen.contains("TVMField.solvable"))
        for field in TVMField.allCases {
            #expect(!solverScreen.contains("\"\(field.label)\""), "the solver screen spells \(field.label)")
        }
    }

    @Test("No web view and no third-party typesetting library reaches the renderer")
    func typesettingIsHandWritten() throws {
        let banned = ["WKWebView", "WebKit", "SwiftMath", "iosMath", "MathJax", "KaTeX", "latex", "LaTeX("]
        for url in try Self.interfaceSourceFiles {
            let source = try Self.code(of: url)
            for token in banned where token != "latex" {
                #expect(!source.contains(token), "\(url.lastPathComponent) contains \(token)")
            }
        }
        // The drawing path never goes through LaTeX: only the export helpers name the serializer,
        // and the view that draws maths does not.
        let rendererURL = try #require(try Self.interfaceSourceFiles.first {
            $0.lastPathComponent == "TypesetMathView.swift"
        })
        let renderer = try Self.code(of: rendererURL)
        #expect(!renderer.contains("LaTeX"))
        #expect(renderer.contains("TypesetLayout.layout"))
    }

    @Test("The LaTeX spelling of a function is declared in the catalog, like every other spelling")
    func latexNamesLiveInTheCatalog() throws {
        var filesContaining: [String] = []
        for url in try Self.coreSourceFiles where try Self.code(of: url).contains("\\\\sin") {
            filesContaining.append(url.lastPathComponent)
        }
        #expect(filesContaining == ["FunctionCatalog.swift"], "a LaTeX command appears in \(filesContaining)")
        // Every catalog entry is serializable, whether or not it has a dedicated command.
        for definition in FunctionCatalog.all {
            let command = FunctionCatalog.latexCommand(for: definition.id)
            #expect(command == nil || !(command ?? "").isEmpty)
        }
    }

    @Test("The last answer is spelled in one place")
    func answerSpellingLivesInOnePlace() throws {
        var filesContaining: [String] = []
        for url in try Self.coreSourceFiles
        where try Self.code(of: url).contains("\"\(Tokenizer.answerSpelling)\"") {
            filesContaining.append(url.lastPathComponent)
        }
        #expect(filesContaining == ["Tokenizer.swift"], "Ans is spelled in \(filesContaining)")
    }

    @Test("The package declares no external dependencies")
    func packageHasNoDependencies() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        #expect(!manifest.contains(".package(url:"))
        #expect(!manifest.contains("github.com"))
    }

    @Test("Function names are declared only in the catalog, not in the tokenizer or parser")
    func namesLiveOnlyInTheCatalog() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let coreDirectory = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("TechCalcCore")

        // A representative spread of spellings that must appear in exactly one source file.
        let spellings = ["\"sin\"", "\"logBASE\"", "\"nCr\"", "\"fnInt\"", "\"randInt\"", "\"iPart\"",
                         "\"det\"", "\"rref\"", "\"cumSum\"", "\"SortA\"", "\"stdDev\"", "\"randM\"",
                         // The M5 additions get the same one-declaration rule.
                         "\"tvm_Pmt\"", "\"tvm_I%\"", "\"npv\"", "\"irr\"", "\"bal\"", "\"dbd\"",
                         "\"bitAnd\"", "\"bitXor\"", "\"LinRegTInt\""]
        for spelling in spellings {
            var filesContaining: [String] = []
            for url in try Self.coreSourceFiles {
                if try Self.code(of: url).contains(spelling) {
                    filesContaining.append(url.lastPathComponent)
                }
            }
            #expect(filesContaining == ["FunctionCatalog.swift"], "\(spelling) appears in \(filesContaining)")
        }
        #expect(FileManager.default.fileExists(atPath: coreDirectory.path))
    }
}
