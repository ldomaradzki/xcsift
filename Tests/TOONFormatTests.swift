import XCTest
import TOONEncoder
@testable import xcsift

/// Tests for TOON format encoding and configuration
final class TOONFormatTests: XCTestCase {

    // MARK: - Basic TOON Encoding Tests

    func testTOONEncoderBasic() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        """
        let result = parser.parse(input: input)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("errors[1]{"))
        XCTAssertTrue(toonString!.contains("main.swift"))
    }

    func testTOONEncoderWithWarnings() throws {
        let parser = OutputParser()
        let input = """
        Parser.swift:20:10: warning: immutable value 'result' was never used
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: success"))
        XCTAssertTrue(toonString!.contains("warnings: 2"))
        XCTAssertTrue(toonString!.contains("warnings[2]{"))
        XCTAssertTrue(toonString!.contains("Parser.swift"))
    }

    func testTOONEncoderWithErrorsAndWarnings() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        ** BUILD FAILED **
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("errors: 1"))
        XCTAssertTrue(toonString!.contains("warnings: 1"))
        XCTAssertTrue(toonString!.contains("errors[1]{file,line,message}"))
        XCTAssertTrue(toonString!.contains("warnings[1]{file,line,message}"))
    }

    func testTOONEncoderWithCoverage() throws {
        let parser = OutputParser()
        let input = "Build complete!"
        let coverage = CodeCoverage(
            lineCoverage: 85.5,
            files: [
                FileCoverage(path: "/path/to/file.swift", name: "file.swift", lineCoverage: 85.5, coveredLines: 85, executableLines: 100)
            ]
        )
        let result = parser.parse(input: input, printWarnings: false, coverage: coverage, printCoverageDetails: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("coverage_percent: 85.5"))
        XCTAssertTrue(toonString!.contains("line_coverage: 85.5"))
        XCTAssertTrue(toonString!.contains("files[1]{"))
        XCTAssertTrue(toonString!.contains("file.swift"))
    }

    func testTOONTokenEfficiency() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        Model.swift:30:15: warning: initialization of immutable value 'bar' was never used
        ** BUILD FAILED **
        """
        let result = parser.parse(input: input, printWarnings: true)

        // JSON encoding
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        let jsonData = try jsonEncoder.encode(result)
        let jsonSize = jsonData.count

        // TOON encoding
        let toonEncoder = TOONEncoder()
        toonEncoder.indent = 2
        toonEncoder.delimiter = .comma
        let toonData = try toonEncoder.encode(result)
        let toonSize = toonData.count

        // TOON should be significantly smaller (30-60% reduction)
        let reduction = Double(jsonSize - toonSize) / Double(jsonSize) * 100.0
        XCTAssertGreaterThan(reduction, 20.0, "TOON should save at least 20% tokens")
        XCTAssertLessThan(toonSize, jsonSize, "TOON output should be smaller than JSON")
    }

    func testTOONEncoderWithFailedTests() throws {
        let parser = OutputParser()
        let input = """
        Test Case 'LoginTests.testInvalidCredentials' failed (0.045 seconds).
        XCTAssertEqual failed: Expected valid login
        """
        let result = parser.parse(input: input)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("failed_tests: 2"))
        XCTAssertTrue(toonString!.contains("failed_tests[2]{"))
        XCTAssertTrue(toonString!.contains("LoginTests.testInvalidCredentials"))
    }

    func testTOONEncoderSuccessfulBuild() throws {
        let parser = OutputParser()
        let input = """
        Building for debugging...
        Build complete!
        """
        let result = parser.parse(input: input)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: success"))
        XCTAssertTrue(toonString!.contains("errors: 0"))
        XCTAssertTrue(toonString!.contains("warnings: 0"))
        XCTAssertTrue(toonString!.contains("failed_tests: 0"))
    }

    func testTOONCoverageOnlyPrintsCoveragePercentInSummary() throws {
        let parser = OutputParser()
        let input = "Build complete!"
        let coverage = CodeCoverage(
            lineCoverage: 75.5,
            files: [
                FileCoverage(path: "/path/to/file.swift", name: "file.swift", lineCoverage: 75.5, coveredLines: 75, executableLines: 100)
            ]
        )
        let result = parser.parse(input: input, printWarnings: false, coverage: coverage, printCoverageDetails: false)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("coverage_percent: 75.5"))
        // Should NOT contain detailed coverage section in summary-only mode
        XCTAssertFalse(toonString!.contains("line_coverage:"))
        XCTAssertFalse(toonString!.contains("files["))
    }

    // MARK: - TOON Configuration Tests

    func testTOONWithTabDelimiter() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .tab
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("\t"), "Should use tab delimiter")
        XCTAssertFalse(toonString!.contains(",15,"), "Should not use comma for values")
    }

    func testTOONWithPipeDelimiter() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .pipe
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("|"), "Should use pipe delimiter")
        XCTAssertFalse(toonString!.contains(",15,"), "Should not use comma for values")
    }

    func testTOONWithHashLengthMarker() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: unused variable
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        encoder.lengthMarker = .hash
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("[#"), "Should use hash length marker")
        XCTAssertTrue(toonString!.contains("[#1]{"), "Should show [#1]{ for array of 1 element")
    }

    // MARK: - TOON 3.0 Key Folding Tests

    func testTOONKeyFoldingDisabledByDefault() throws {
        let encoder = TOONEncoder()
        // Verify default value is disabled
        XCTAssertEqual(encoder.keyFolding, .disabled, "Key folding should be disabled by default")
    }

    func testTOONKeyFoldingSafe() throws {
        // Test that safe key folding can be configured
        let encoder = TOONEncoder()
        encoder.keyFolding = .safe
        XCTAssertEqual(encoder.keyFolding, .safe, "Key folding should be set to safe")
    }

    func testTOONFlattenDepthDefault() throws {
        let encoder = TOONEncoder()
        // Default flattenDepth should be Int.max (unlimited)
        XCTAssertEqual(encoder.flattenDepth, Int.max, "Flatten depth should default to max")
    }

    func testTOONFlattenDepthCustom() throws {
        let encoder = TOONEncoder()
        encoder.flattenDepth = 3
        XCTAssertEqual(encoder.flattenDepth, 3, "Flatten depth should be set to custom value")
    }

    func testTOONKeyFoldingWithBuildResult() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        """
        let result = parser.parse(input: input)

        // Test with key folding enabled
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        encoder.keyFolding = .safe

        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        // Output should still be valid TOON
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("errors"))
    }

    func testTOONKeyFoldingWithFlattenDepth() throws {
        let parser = OutputParser()
        let input = "Build complete!"
        let coverage = CodeCoverage(
            lineCoverage: 85.5,
            files: [
                FileCoverage(path: "/path/to/file.swift", name: "file.swift", lineCoverage: 85.5, coveredLines: 85, executableLines: 100)
            ]
        )
        let result = parser.parse(input: input, printWarnings: false, coverage: coverage, printCoverageDetails: true)

        // Test with key folding and custom flatten depth
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        encoder.keyFolding = .safe
        encoder.flattenDepth = 2

        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        // Output should still be valid TOON with coverage data
        XCTAssertTrue(toonString!.contains("status: success"))
        XCTAssertTrue(toonString!.contains("coverage_percent: 85.5"))
    }

    func testTOON30CombinedConfiguration() throws {
        // Test combining all TOON 3.0 features
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: unused variable
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .pipe
        encoder.lengthMarker = .hash
        encoder.keyFolding = .safe
        encoder.flattenDepth = 5

        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        // Verify basic structure is preserved
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("|"), "Should use pipe delimiter")
        XCTAssertTrue(toonString!.contains("[#"), "Should use hash length marker")
    }

    // MARK: - Benchmark Tests

    func testBenchmarkSmallOutput() throws {
        let parser = OutputParser()
        let input = "main.swift:15:5: error: use of undeclared identifier 'unknown'"
        let result = parser.parse(input: input)

        let jsonSize = try measureJSONSize(result)
        let toonSize = try measureTOONSize(result)
        let reduction = calculateReduction(jsonSize: jsonSize, toonSize: toonSize)

        XCTAssertGreaterThan(reduction, 10.0, "TOON should save at least 10% on small output")
        XCTAssertLessThan(toonSize, jsonSize, "TOON should be smaller than JSON")
    }

    func testBenchmarkMediumOutput() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        Model.swift:30:15: warning: initialization of immutable value 'bar' was never used
        View.swift:40:8: warning: 'oldFunction()' is deprecated
        Controller.swift:50:12: warning: missing documentation
        Test Case 'LoginTests.testInvalidCredentials' failed (0.045 seconds).
        Test Case 'UITests.testButtonTap' failed (0.032 seconds).
        """
        let result = parser.parse(input: input, printWarnings: true)

        let jsonSize = try measureJSONSize(result)
        let toonSize = try measureTOONSize(result)
        let reduction = calculateReduction(jsonSize: jsonSize, toonSize: toonSize)

        XCTAssertGreaterThan(reduction, 25.0, "TOON should save at least 25% on medium output")
        XCTAssertLessThan(toonSize, jsonSize, "TOON should be smaller than JSON")
    }

    func testBenchmarkLargeOutputWithCoverage() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        main.swift:20:5: error: cannot find 'invalidFunc' in scope
        main.swift:25:5: error: type 'String' has no member 'invalidProperty'
        Parser.swift:20:10: warning: unused variable 'result'
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        Model.swift:30:15: warning: 'bar' was never used
        View.swift:40:8: warning: 'oldFunction()' is deprecated
        Controller.swift:50:12: warning: missing documentation
        Service.swift:60:5: warning: unused import 'Foundation'
        Helper.swift:70:10: warning: variable 'temp' was never mutated
        Test Case 'LoginTests.test1' failed (0.045 seconds).
        Test Case 'LoginTests.test2' failed (0.032 seconds).
        Test Case 'UITests.test1' failed (0.050 seconds).
        """

        let coverage = CodeCoverage(
            lineCoverage: 75.5,
            files: [
                FileCoverage(path: "/path/to/file1.swift", name: "file1.swift", lineCoverage: 85.0, coveredLines: 85, executableLines: 100),
                FileCoverage(path: "/path/to/file2.swift", name: "file2.swift", lineCoverage: 70.0, coveredLines: 70, executableLines: 100),
                FileCoverage(path: "/path/to/file3.swift", name: "file3.swift", lineCoverage: 90.0, coveredLines: 90, executableLines: 100)
            ]
        )

        let result = parser.parse(input: input, printWarnings: true, coverage: coverage, printCoverageDetails: true)

        let jsonSize = try measureJSONSize(result)
        let toonSize = try measureTOONSize(result)
        let reduction = calculateReduction(jsonSize: jsonSize, toonSize: toonSize)

        XCTAssertGreaterThan(reduction, 30.0, "TOON should save at least 30% on large output")
        XCTAssertLessThan(toonSize, jsonSize, "TOON should be smaller than JSON")
    }

    // MARK: - TOON Error Handling Tests

    func testTOONEncoderAlwaysProducesValidUTF8() throws {
        // This test verifies that TOONEncoder always produces valid UTF-8 data,
        // making the "invalid UTF-8" error path in outputTOON() unreachable in practice.
        let parser = OutputParser()

        // Test with various complex inputs
        let testCases = [
            // Basic error
            "main.swift:15:5: error: use of undeclared identifier 'unknown'",

            // Multiple warnings with special characters
            """
            Parser.swift:20:10: warning: immutable value "result" was never used
            Model.swift:30:15: warning: variable 'foo' wasn't mutated; consider 'let'
            """,

            // Unicode characters in paths and messages
            "Файл.swift:10:5: error: неизвестный идентификатор 'тест'",

            // Emojis in messages
            "test.swift:5:1: warning: 🚨 deprecated function",

            // Very long messages
            String(repeating: "very long error message with lots of text ", count: 100)
        ]

        for input in testCases {
            let result = parser.parse(input: input, printWarnings: true)

            let encoder = TOONEncoder()
            encoder.indent = 2
            encoder.delimiter = .comma

            let toonData = try encoder.encode(result)

            // Verify that the data can always be converted to a valid UTF-8 string
            let toonString = String(data: toonData, encoding: .utf8)
            XCTAssertNotNil(toonString, "TOONEncoder should always produce valid UTF-8 data")

            // Additionally verify the string is not empty
            XCTAssertFalse(toonString!.isEmpty, "TOON output should not be empty")
        }
    }

    // MARK: - Helper Methods

    private func measureJSONSize(_ result: BuildResult) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(result)
        return data.count
    }

    private func measureTOONSize(_ result: BuildResult) throws -> Int {
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let data = try encoder.encode(result)
        return data.count
    }

    private func calculateReduction(jsonSize: Int, toonSize: Int) -> Double {
        return Double(jsonSize - toonSize) / Double(jsonSize) * 100.0
    }
}
