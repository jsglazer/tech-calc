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
    private static var coreSourceFiles: [URL] {
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
                         "\"det\"", "\"rref\"", "\"cumSum\"", "\"SortA\"", "\"stdDev\"", "\"randM\""]
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
