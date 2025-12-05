import XCTest

@testable import xcsift

/// Tests for linker error parsing functionality
final class LinkerErrorTests: XCTestCase {

    // MARK: - Basic Undefined Symbol Parsing

    func testParseBasicUndefinedSymbol() {
        let parser = OutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_OBJC_CLASS_$_SomeClass", referenced from:
                  objc-class-ref in ViewController.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.linkerErrors, 1)
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertEqual(result.linkerErrors[0].symbol, "_OBJC_CLASS_$_SomeClass")
        XCTAssertEqual(result.linkerErrors[0].architecture, "arm64")
        XCTAssertEqual(result.linkerErrors[0].referencedFrom, "ViewController.o")
    }

    func testParseMultipleUndefinedSymbols() {
        let parser = OutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_OBJC_CLASS_$_FirstClass", referenced from:
                  objc-class-ref in ViewControllerA.o
              "_OBJC_CLASS_$_SecondClass", referenced from:
                  objc-class-ref in ViewControllerB.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.linkerErrors, 2)
        XCTAssertEqual(result.linkerErrors.count, 2)
        XCTAssertEqual(result.linkerErrors[0].symbol, "_OBJC_CLASS_$_FirstClass")
        XCTAssertEqual(result.linkerErrors[1].symbol, "_OBJC_CLASS_$_SecondClass")
    }

    // MARK: - Architecture Mismatch

    func testParseArchitectureMismatch() {
        let parser = OutputParser()
        let input = """
            ld: warning: ignoring file /path/to/library.a, building for iOS Simulator-arm64 but attempting to link with file built for iOS-arm64
            ld: building for iOS Simulator, but linking in dylib built for iOS, file '/path/to/library.dylib'
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertTrue(result.linkerErrors[0].message.contains("building for iOS Simulator"))
    }

    // MARK: - Symbol Not Found Summary

    func testParseSymbolNotFoundSummary() {
        let parser = OutputParser()
        let input = """
            Undefined symbols for architecture x86_64:
              "_someFunction", referenced from:
                  _main in main.o
            ld: symbol(s) not found for architecture x86_64
            clang: error: linker command failed with exit code 1
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertEqual(result.linkerErrors[0].architecture, "x86_64")
    }

    // MARK: - JSON Encoding

    func testLinkerErrorJSONEncoding() throws {
        let parser = OutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  _caller in Caller.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"linker_errors\""))
        XCTAssertTrue(jsonString.contains("\"symbol\""))
        XCTAssertTrue(jsonString.contains("\"_MissingSymbol\""))
        XCTAssertTrue(jsonString.contains("\"architecture\""))
        XCTAssertTrue(jsonString.contains("\"arm64\""))
        XCTAssertTrue(jsonString.contains("\"referenced_from\""))
    }

    // MARK: - Duplicate Symbol Error

    func testParseDuplicateSymbol() {
        let parser = OutputParser()
        let input = """
            duplicate symbol '_someGlobalVar' in:
                /path/to/FileA.o
                /path/to/FileB.o
            ld: 1 duplicate symbol for architecture arm64
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertEqual(result.linkerErrors[0].symbol, "_someGlobalVar")
        XCTAssertEqual(result.linkerErrors[0].architecture, "arm64")
        XCTAssertEqual(result.linkerErrors[0].conflictingFiles.count, 2)
        XCTAssertEqual(result.linkerErrors[0].conflictingFiles[0], "/path/to/FileA.o")
        XCTAssertEqual(result.linkerErrors[0].conflictingFiles[1], "/path/to/FileB.o")
    }

    func testParseDuplicateSymbolWithDoubleQuotes() {
        let parser = OutputParser()
        let input = """
            duplicate symbol "_anotherSymbol" in:
                /path/to/First.o
                /path/to/Second.o
            ld: 1 duplicate symbol for architecture x86_64
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertEqual(result.linkerErrors[0].symbol, "_anotherSymbol")
        XCTAssertEqual(result.linkerErrors[0].architecture, "x86_64")
        XCTAssertEqual(result.linkerErrors[0].conflictingFiles.count, 2)
    }

    func testParseDuplicateSymbolJSONEncoding() throws {
        let parser = OutputParser()
        let input = """
            duplicate symbol '_testSymbol' in:
                /path/to/ModuleA.o
                /path/to/ModuleB.o
            ld: 1 duplicate symbol for architecture arm64
            """

        let result = parser.parse(input: input)

        // Verify parsing worked
        XCTAssertEqual(result.linkerErrors.count, 1, "Expected 1 linker error")
        XCTAssertEqual(result.linkerErrors[0].conflictingFiles.count, 2, "Expected 2 conflicting files")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"conflicting_files\""), "JSON should contain conflicting_files key")
        XCTAssertTrue(
            jsonString.contains("\\/path\\/to\\/ModuleA.o"),
            "JSON should contain ModuleA.o path (escaped)"
        )
        XCTAssertTrue(
            jsonString.contains("\\/path\\/to\\/ModuleB.o"),
            "JSON should contain ModuleB.o path (escaped)"
        )
        XCTAssertTrue(jsonString.contains("\"symbol\""), "JSON should contain symbol key")
        XCTAssertTrue(jsonString.contains("\"_testSymbol\""), "JSON should contain symbol value")
    }

    // MARK: - Framework Not Found

    func testParseFrameworkNotFound() {
        let parser = OutputParser()
        let input = """
            ld: framework not found SomeFramework
            clang: error: linker command failed with exit code 1
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertTrue(result.linkerErrors[0].message.contains("framework not found"))
    }

    // MARK: - Library Not Found

    func testParseLibraryNotFound() {
        let parser = OutputParser()
        let input = """
            ld: library not found for -lsomelib
            clang: error: linker command failed with exit code 1
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertTrue(result.linkerErrors[0].message.contains("library not found"))
    }

    // MARK: - Mixed Errors

    func testParseMixedCompilerAndLinkerErrors() {
        let parser = OutputParser()
        let input = """
            main.swift:10:5: error: use of undeclared identifier 'foo'
            Undefined symbols for architecture arm64:
              "_bar", referenced from:
                  _main in main.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.linkerErrors, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.linkerErrors.count, 1)
    }

    // MARK: - No Linker Errors

    func testNoLinkerErrorsInSuccessfulBuild() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.linkerErrors, 0)
        XCTAssertTrue(result.linkerErrors.isEmpty)
    }

    // MARK: - Swift Symbol Mangling

    func testParseSwiftMangledSymbol() {
        let parser = OutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_$s7MyModule0A5ClassCACycfC", referenced from:
                  _$s7MyModule0B7ServiceC6createAA0A5ClassCyF in MyService.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.linkerErrors.count, 1)
        XCTAssertEqual(result.linkerErrors[0].symbol, "_$s7MyModule0A5ClassCACycfC")
    }

    // MARK: - Real World Fixture Test

    func testRealWorldLinkerErrorOutput() throws {
        let parser = OutputParser()

        let fixtureURL = Bundle.module.url(forResource: "linker-error-output", withExtension: "txt")!
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.linkerErrors, 2)
        XCTAssertEqual(result.linkerErrors.count, 2)

        // Verify both symbols are parsed
        let symbols = result.linkerErrors.map { $0.symbol }
        XCTAssertTrue(symbols.contains("__another_missing_symbol"))
        XCTAssertTrue(symbols.contains("__nonexistent_function"))

        // Verify architecture
        XCTAssertTrue(result.linkerErrors.allSatisfy { $0.architecture == "arm64" })

        // Verify referenced from
        XCTAssertTrue(result.linkerErrors.allSatisfy { $0.referencedFrom == "main-1.o" })
    }
}
