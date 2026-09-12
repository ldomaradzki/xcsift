import XCTest

import XCSiftCore

/// Xcode's MCP server answers a test run with an enumeration of every test it ran. It is the
/// authority on that run — unlike its console transcript, which prints what it manages to — and it
/// is also where the proxy's tokens go: one block per passing test.
final class XcodeTestResultsTests: XCTestCase {

    private func summary(_ blocks: String, total: Int) -> String {
        """
        ================================================================================
        TEST RESULTS SUMMARY
        ================================================================================
        Generated: 2026-09-12T11:48:08Z
        Total Results: \(total)
        ================================================================================

        \(blocks)

        ================================================================================
        END OF TEST RESULTS SUMMARY
        ================================================================================
        """
    }

    private func block(
        index: Int,
        of total: Int,
        target: String = "MyAppTests",
        identifier: String,
        state: String,
        file: String = "(not available)",
        line: String = "(not available)",
        issues: String = ""
    ) -> String {
        """
        --------------------------------------------------------------------------------
        TEST_RESULT_INDEX: \(index)/\(total)
        TEST_TARGET: \(target)
        TEST_IDENTIFIER: \(identifier)
        TEST_DISPLAY_NAME: \(identifier)
        TEST_STATE: \(state)
        TEST_FILE_PATH: \(file)
        TEST_LINE_NUMBER: \(line)
        TEST_TAGS: (none)

        TEST_ISSUE_COUNT: \(issues.isEmpty ? 0 : 1)
        \(issues.isEmpty ? "" : "\nTEST_ISSUES:\n    \(issues)")
        """
    }

    func testCountsEveryStateItWasGiven() throws {
        let text = summary(
            [
                block(index: 1, of: 3, identifier: "MyTests/testOne()", state: "Passed"),
                block(index: 2, of: 3, identifier: "MyTests/testTwo()", state: "Passed"),
                block(index: 3, of: 3, identifier: "MyTests/testThree()", state: "Skipped"),
            ].joined(separator: "\n"),
            total: 3
        )

        let result = try XCTUnwrap(XcodeTestResults.parse(text))

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 2)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testCarriesAFailureWithItsLocationAndMessage() throws {
        let text = summary(
            block(
                index: 1,
                of: 1,
                identifier: "IntentionalFailureTests/test()",
                state: "Failed",
                file: "App/Tests/MyTests.swift",
                line: "285",
                issues: "App/Tests/MyTests.swift:286 IntentionalFailureTests/test(): XCTAssertTrue failed - on purpose"
            ),
            total: 1
        )

        let result = try XCTUnwrap(XcodeTestResults.parse(text))
        let failure = try XCTUnwrap(result.failedTests.first)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(failure.test, "MyAppTests/IntentionalFailureTests/test()")
        XCTAssertEqual(failure.file, "App/Tests/MyTests.swift")
        XCTAssertEqual(failure.line, 286, "the issue's own line is more precise than the test's")
        XCTAssertEqual(failure.message, "XCTAssertTrue failed - on purpose")
    }

    /// The caller substitutes this result for the text, so a block the parser skipped would be a
    /// test that silently disappeared. A count that disagrees with the blocks refuses to parse.
    func testRefusesAnEnumerationItCannotAccountForInFull() {
        let text = summary(
            block(index: 1, of: 9, identifier: "MyTests/testOne()", state: "Passed"),
            total: 9
        )

        XCTAssertNil(XcodeTestResults.parse(text))
    }

    func testIgnoresTextThatIsNotAnEnumeration() {
        XCTAssertNil(XcodeTestResults.parse("** TEST SUCCEEDED **"))
        XCTAssertNil(XcodeTestResults.parse("TEST RESULTS SUMMARY"))
        XCTAssertFalse(XcodeTestResults.looksLikeTestResults("Executed 3 tests, with 0 failures"))
    }

    /// Xcode's answer for the same run its console transcript could only account for in part.
    func testRealEnumerationFromXcode() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "xcode-test-results-summary", withExtension: "txt"))
        let result = try XCTUnwrap(XcodeTestResults.parse(try String(contentsOf: url, encoding: .utf8)))

        XCTAssertEqual(result.summary.passedTests, 69)
        XCTAssertEqual(result.summary.failedTests, 3)
        XCTAssertEqual(result.failedTests.count, 3)
        XCTAssertEqual(
            result.failedTests.map(\.test).sorted(),
            [
                "CalculatorAppFeatureTests/CalculatorBasicTests/testIntentionalFailure()",
                "CalculatorAppTests/CalculatorAppTests/testCalculatorServiceFailure()",
                "CalculatorAppTests/IntentionalFailureTests/test()",
            ]
        )
    }
}
