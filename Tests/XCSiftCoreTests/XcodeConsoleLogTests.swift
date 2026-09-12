import XCTest

import XCSiftCore

/// Xcode's own console transcript — the log an Xcode MCP server hands back — differs from piped
/// `xcodebuild` output in two ways that changed the parser: diagnostics are indented under the task
/// that emitted them, and each XCTest suite completion is repeated (inline, under `Summary:`, and
/// sometimes again) with the identical millisecond timestamp.
///
/// The suite names here end in `.xctest` on purpose: that is the shape Xcode logs, and the only
/// shape whose totals accumulate, so these tests fail if the de-duplication is removed.
final class XcodeConsoleLogTests: XCTestCase {

    func testRepeatedSuiteCompletionCountsOnce() {
        let output = """
            Test Suite 'MyAppTests.xctest' passed at 2026-09-12 16:47:46.179.
                Executed 10 tests, with 0 failures (0 unexpected) in 0.500 (0.502) seconds
              Summary: Test Suite 'MyAppTests.xctest' passed at 2026-09-12 16:47:46.179.
                Executed 10 tests, with 0 failures (0 unexpected) in 0.500 (0.502) seconds
              Test Suite 'MyAppTests.xctest' passed at 2026-09-12 16:47:46.179.
                Executed 10 tests, with 0 failures (0 unexpected) in 0.500 (0.502) seconds
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.passedTests, 10)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertEqual(result.summary.testTime, "0.500s", "the duration double-counts the same way")
    }

    func testRepeatedFailingSuiteCompletionCountsOnce() {
        let output = """
            Test Suite 'MyAppTests.xctest' failed at 2026-09-12 16:48:07.966.
                Executed 23 tests, with 2 failures (0 unexpected) in 0.667 (0.672) seconds
              Summary: Test Suite 'MyAppTests.xctest' failed at 2026-09-12 16:48:07.966.
                Executed 23 tests, with 2 failures (0 unexpected) in 0.667 (0.672) seconds
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.failedTests, 2)
        XCTAssertEqual(result.summary.passedTests, 21)
    }

    /// Two genuine runs of one bundle carry different timestamps, and both count. This is the guard
    /// against the de-duplication over-firing on repeated or multi-destination runs.
    func testDistinctSuiteCompletionsBothCount() {
        let output = """
            Test Suite 'MyAppTests.xctest' passed at 2026-09-12 16:47:46.179.
                Executed 4 tests, with 0 failures (0 unexpected) in 0.500 (0.502) seconds
            Test Suite 'MyAppTests.xctest' passed at 2026-09-12 16:48:07.964.
                Executed 4 tests, with 0 failures (0 unexpected) in 0.500 (0.502) seconds
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.passedTests, 8)
    }

    /// A completion line with no timestamp cannot be recognised as a repeat, so it is always
    /// counted. Stating it here keeps the safety valve deliberate rather than accidental.
    func testCompletionsWithoutATimestampAreAlwaysCounted() {
        let output = """
            Test Suite 'MyAppTests.xctest' passed.
                Executed 4 tests, with 0 failures (0 unexpected) in 0.500 (0.502) seconds
            Test Suite 'MyAppTests.xctest' passed.
                Executed 4 tests, with 0 failures (0 unexpected) in 0.500 (0.502) seconds
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.passedTests, 8)
    }

    /// The same indentation that hides a diagnostic's path also hides a failed test's path.
    func testIndentedTestFailureKeepsACleanFilePath() {
        let output = """
            Test CalculatorApp
                Test Case '-[MyTests testOne]' started.
                        /project/Tests/MyTests.swift:12: error: -[MyTests testOne] : XCTAssertEqual failed: ("1") is not equal to ("2")
                Test Case '-[MyTests testOne]' failed (0.010 seconds).
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.failedTests.first?.file, "/project/Tests/MyTests.swift")
        XCTAssertEqual(result.failedTests.first?.line, 12)
    }

    /// `Double("inf")` parses, and a non-finite duration cannot be encoded — it would turn a whole
    /// build result into an encoding error at the last moment.
    func testNonFiniteDurationIsDropped() throws {
        let output = """
            Test Case '-[MyTests testOne]' started.
            Test Case '-[MyTests testOne]' failed (inf seconds).
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertNil(result.failedTests.first?.duration)
        XCTAssertNoThrow(try JSONEncoder().encode(result))
    }
}
