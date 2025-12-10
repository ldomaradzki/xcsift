import XCTest
import ToonFormat
@testable import xcsift

/// Tests for JSON/TOON encoding and optional fields handling
final class EncodingTests: XCTestCase {

    // MARK: - JSON Optional Fields Tests

    func testJSONOmitsNilOptionalFields() throws {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """
        let result = parser.parse(input: input)

        // Verify that optional fields are nil
        XCTAssertNil(result.summary.passedTests)
        XCTAssertNil(result.summary.buildTime)
        XCTAssertNil(result.summary.coveragePercent)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Verify that nil optional fields are NOT present in JSON output
        XCTAssertFalse(jsonString.contains("\"passed_tests\""), "JSON should not contain passed_tests when nil")
        XCTAssertFalse(jsonString.contains("\"build_time\""), "JSON should not contain build_time when nil")
        XCTAssertFalse(jsonString.contains("\"coverage_percent\""), "JSON should not contain coverage_percent when nil")

        // Verify required fields are present
        XCTAssertTrue(jsonString.contains("\"errors\""))
        XCTAssertTrue(jsonString.contains("\"warnings\""))
        XCTAssertTrue(jsonString.contains("\"failed_tests\""))
    }

    func testJSONIncludesNonNilOptionalFields() throws {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testExample' passed (0.001 seconds).
            Executed 5 tests, with 0 failures (0 unexpected) in 5.017 (5.020) seconds
            """

        let coverage = CodeCoverage(
            lineCoverage: 85.5,
            files: [
                FileCoverage(
                    path: "/path/to/file.swift",
                    name: "file.swift",
                    lineCoverage: 85.5,
                    coveredLines: 85,
                    executableLines: 100
                )
            ]
        )
        let result = parser.parse(input: input, coverage: coverage, printCoverageDetails: false)

        // Verify that optional fields have values
        XCTAssertNotNil(result.summary.passedTests)
        XCTAssertNotNil(result.summary.buildTime)
        XCTAssertNotNil(result.summary.coveragePercent)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Verify that non-nil optional fields ARE present in JSON output
        XCTAssertTrue(jsonString.contains("\"passed_tests\""), "JSON should contain passed_tests when not nil")
        XCTAssertTrue(jsonString.contains("\"build_time\""), "JSON should contain build_time when not nil")
        XCTAssertTrue(jsonString.contains("\"coverage_percent\""), "JSON should contain coverage_percent when not nil")
    }

    // MARK: - TOON Optional Fields Tests

    func testTOONOmitsNilOptionalFields() throws {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """
        let result = parser.parse(input: input)

        // Verify that optional fields are nil
        XCTAssertNil(result.summary.passedTests)
        XCTAssertNil(result.summary.buildTime)
        XCTAssertNil(result.summary.coveragePercent)

        // Encode to TOON
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)!

        // Verify that nil optional fields are NOT present in TOON output
        XCTAssertFalse(toonString.contains("passed_tests:"), "TOON should not contain passed_tests when nil")
        XCTAssertFalse(toonString.contains("build_time:"), "TOON should not contain build_time when nil")
        XCTAssertFalse(toonString.contains("coverage_percent:"), "TOON should not contain coverage_percent when nil")

        // Verify required fields are present
        XCTAssertTrue(toonString.contains("errors:"))
        XCTAssertTrue(toonString.contains("warnings:"))
        XCTAssertTrue(toonString.contains("failed_tests:"))
    }

    func testTOONIncludesNonNilOptionalFields() throws {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testExample' passed (0.001 seconds).
            Executed 5 tests, with 0 failures (0 unexpected) in 5.017 (5.020) seconds
            """

        let coverage = CodeCoverage(
            lineCoverage: 85.5,
            files: [
                FileCoverage(
                    path: "/path/to/file.swift",
                    name: "file.swift",
                    lineCoverage: 85.5,
                    coveredLines: 85,
                    executableLines: 100
                )
            ]
        )
        let result = parser.parse(input: input, coverage: coverage, printCoverageDetails: false)

        // Verify that optional fields have values
        XCTAssertNotNil(result.summary.passedTests)
        XCTAssertNotNil(result.summary.buildTime)
        XCTAssertNotNil(result.summary.coveragePercent)

        // Encode to TOON
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)!

        // Verify that non-nil optional fields ARE present in TOON output
        XCTAssertTrue(toonString.contains("passed_tests:"), "TOON should contain passed_tests when not nil")
        XCTAssertTrue(toonString.contains("build_time:"), "TOON should contain build_time when not nil")
        XCTAssertTrue(toonString.contains("coverage_percent:"), "TOON should contain coverage_percent when not nil")
    }
}
