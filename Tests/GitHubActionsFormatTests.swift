import XCTest
@testable import xcsift

/// Tests for GitHub Actions format output
///
/// ## CI Auto-Append Behavior
/// On GitHub Actions (GITHUB_ACTIONS=true), xcsift automatically appends
/// GitHub Actions annotations after JSON/TOON output:
/// - `xcsift` (no flags) → JSON + annotations
/// - `xcsift -f toon` → TOON + annotations
/// - `xcsift -f github-actions` → annotations only
///
/// Locally, only the specified format is output (no annotations).
final class GitHubActionsFormatTests: XCTestCase {

    func testGitHubActionsFormatWithColumn() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        """
        let result = parser.parse(input: input)

        let output = result.formatGitHubActions()

        XCTAssertTrue(output.contains("::error file=main.swift,line=15,col=5::use of undeclared identifier 'unknown'"))
        XCTAssertTrue(output.contains("::notice ::"))
    }

    func testGitHubActionsFormatWarningWithColumn() throws {
        let parser = OutputParser()
        let input = """
        Parser.swift:20:10: warning: immutable value 'result' was never used
        """
        let result = parser.parse(input: input, printWarnings: true)

        let output = result.formatGitHubActions()

        XCTAssertTrue(output.contains("::warning file=Parser.swift,line=20,col=10::immutable value 'result' was never used"))
    }

    func testGitHubActionsFormatTestWithTitle() throws {
        let parser = OutputParser()
        let input = """
        /path/to/TestFile.swift:42:9: error: testUserLogin(): XCTAssertEqual failed: ("expected") is not equal to ("actual")
        Test Case '-[MyTests testUserLogin]' failed (0.123 seconds).
        """
        let result = parser.parse(input: input)

        let output = result.formatGitHubActions()

        // Test should have title parameter
        XCTAssertTrue(output.contains("title="))
    }

    func testGitHubActionsFormatWithoutColumn() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15: error: some error without column
        """
        let result = parser.parse(input: input)

        let output = result.formatGitHubActions()

        // Should not have col= when column is not present
        XCTAssertTrue(output.contains("::error file=main.swift,line=15::some error without column"))
        XCTAssertFalse(output.contains("col="))
    }

    func testGitHubActionsFormatSummary() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: error 1
        main.swift:20:10: error: error 2
        Parser.swift:30:15: warning: warning 1
        Build failed
        """
        let result = parser.parse(input: input, printWarnings: true)

        let output = result.formatGitHubActions()

        XCTAssertTrue(output.contains("::notice ::Build failed"))
        XCTAssertTrue(output.contains("2 errors"))
        XCTAssertTrue(output.contains("1 warning"))
    }

    // MARK: - CI Auto-Append Tests

    /// Verifies that formatGitHubActions() produces valid annotations
    /// that can be appended after JSON output on CI.
    func testAnnotationsCanBeAppendedToJSON() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        """
        let result = parser.parse(input: input, printWarnings: true)

        // Get JSON output
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Get annotations output
        let annotations = result.formatGitHubActions()

        // Combined output (simulating CI behavior)
        let combinedOutput = jsonString + "\n" + annotations

        // Verify JSON is valid and complete
        XCTAssertTrue(jsonString.contains("\"status\""))
        XCTAssertTrue(jsonString.contains("\"summary\""))
        XCTAssertTrue(jsonString.contains("\"errors\""))

        // Verify annotations are present after JSON
        XCTAssertTrue(combinedOutput.contains("::error file=main.swift,line=15,col=5::"))
        XCTAssertTrue(combinedOutput.contains("::warning file=Parser.swift,line=20,col=10::"))
        XCTAssertTrue(combinedOutput.contains("::notice ::"))

        // Verify JSON comes before annotations
        let jsonEndIndex = jsonString.count
        let errorIndex = combinedOutput.range(of: "::error")!.lowerBound
        XCTAssertTrue(combinedOutput.distance(from: combinedOutput.startIndex, to: errorIndex) > jsonEndIndex - 10)
    }

    /// Verifies that annotations output is consistent
    /// whether generated for appending or standalone use.
    func testAnnotationsOutputIsConsistent() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: test error
        ** BUILD FAILED **
        """
        let result = parser.parse(input: input)

        let annotations = result.formatGitHubActions()

        // Annotations should start with :: commands
        XCTAssertTrue(annotations.hasPrefix("::error") || annotations.hasPrefix("::warning") || annotations.hasPrefix("::notice"))

        // Should contain error annotation
        XCTAssertTrue(annotations.contains("::error file=main.swift,line=15,col=5::test error"))

        // Should contain summary notice
        XCTAssertTrue(annotations.contains("::notice ::Build failed"))
    }

    /// Verifies that success builds produce minimal annotations.
    func testSuccessBuildAnnotations() throws {
        let parser = OutputParser()
        let input = """
        Building for debugging...
        Build complete!
        ** BUILD SUCCEEDED **
        """
        let result = parser.parse(input: input)

        let annotations = result.formatGitHubActions()

        // Success build should only have summary notice
        XCTAssertFalse(annotations.contains("::error"))
        XCTAssertFalse(annotations.contains("::warning"))
        XCTAssertTrue(annotations.contains("::notice ::Build succeeded"))
    }

    /// Verifies that warnings without errors still produce correct annotations.
    func testWarningsOnlyAnnotations() throws {
        let parser = OutputParser()
        let input = """
        Parser.swift:20:10: warning: immutable value 'result' was never used
        Parser.swift:25:5: warning: variable 'foo' was never mutated
        ** BUILD SUCCEEDED **
        """
        let result = parser.parse(input: input, printWarnings: true)

        let annotations = result.formatGitHubActions()

        // Should have warning annotations
        XCTAssertTrue(annotations.contains("::warning file=Parser.swift,line=20,col=10::"))
        XCTAssertTrue(annotations.contains("::warning file=Parser.swift,line=25,col=5::"))

        // No error annotations
        XCTAssertFalse(annotations.contains("::error"))

        // Summary should show warnings
        XCTAssertTrue(annotations.contains("2 warnings"))
    }
}
