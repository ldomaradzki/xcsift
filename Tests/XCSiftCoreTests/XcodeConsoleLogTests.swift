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

    // MARK: - Two frameworks in one run

    /// Xcode runs XCTest bundles and Swift Testing in the same session, and its console transcript
    /// is the only record of the latter: an XCTest bundle counts Swift Testing's tests as zero.
    /// Counting the bundle alone reported this 72-test run as 23.
    func testCountsSwiftTestingAlongsideAnXCTestBundle() {
        let output = """
            Test Suite 'MyAppTests.xctest' started at 2026-09-12 16:48:07.293.
              ✔ Test "Addition works" passed after 0.010 seconds.
              ✔ Test "Subtraction works" passed after 0.011 seconds.
            Test Suite 'MyAppTests.xctest' passed at 2026-09-12 16:48:07.966.
                Executed 3 tests, with 0 failures (0 unexpected) in 0.667 (0.672) seconds
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.passedTests, 5, "3 from the bundle, 2 from Swift Testing")
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    /// Xcode's console writes the heavy check (U+2714), not the light one, and indents the line
    /// under the task that emitted it — so neither a prefix nor the terminal's glyph matches.
    func testReadsSwiftTestingLinesWhateverTheGlyphAndIndentation() {
        let output = """
            Test CalculatorApp
                    ✔ Test "Indented and heavy" passed after 0.010 seconds.
              ✓ Test "Light check" passed after 0.010 seconds.
            ** TEST SUCCEEDED **
            """

        XCTAssertEqual(OutputParser().parse(input: output).summary.passedTests, 2)
    }

    /// A parameterised test reports its cases on one line, and Xcode counts each case as a test.
    func testParameterisedSwiftTestingTestCountsItsCases() {
        let output = """
              ✔ Test "Addition operation" with 4 test cases passed after 0.012 seconds.
              ✔ Test "Plain test" passed after 0.010 seconds.
            ** TEST SUCCEEDED **
            """

        XCTAssertEqual(OutputParser().parse(input: output).summary.passedTests, 5)
    }

    /// The transcript repeats whole blocks under `Summary:`, and a failing Swift Testing test is
    /// reported twice on its own (the issue, then the outcome). Each test counts once.
    func testSwiftTestingOutcomesCountOncePerTest() {
        let output = """
              ✔ Test "Addition works" passed after 0.010 seconds.
              ✘ Test "Intentional failure" recorded an issue at Tests.swift:37:9: Expectation failed
              ✘ Test "Intentional failure" failed after 0.011 seconds with 1 issue.
              Summary: ✔ Test "Addition works" passed after 0.010 seconds.
              ✔ Test "Addition works" passed after 0.010 seconds.
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.failedTests.count, 1)
    }

    /// The per-case lines of a parameterised test would double its count, and `Test run with …`
    /// is the run summary rather than a test.
    func testDoesNotCountCaseLinesOrTheRunSummaryAsTests() {
        let output = """
              ◇ Test "Addition operation" started.
              ◇ Test case passing 3 arguments a → 5.0, b → 3.0, expected → 8.0 to "Addition operation" started.
              ✔ Test "Addition operation" with 4 test cases passed after 0.012 seconds.
              ✔ Test run with 4 tests in 1 suite passed after 0.020 seconds.
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.passedTests, 4, "the run summary states the total; it is not added to it")
        XCTAssertNil(result.summary.unreportedTests)
    }

    /// A run summary is authoritative: it states what the per-test lines could only be counted up
    /// to, including the tests the transcript never got round to printing.
    func testARunSummaryOutranksTheCountedLines() {
        let output = """
              ✔ Test "Only one printed" passed after 0.010 seconds.
              ✔ Test run with 30 tests in 6 suites passed after 0.500 seconds.
            ** TEST SUCCEEDED **
            """

        XCTAssertEqual(OutputParser().parse(input: output).summary.passedTests, 30)
    }

    /// Xcode's console transcript drops lines under load: a test can start and never be reported.
    /// Saying how many is the difference between a count that is wrong and one that is qualified.
    func testReportsTestsThatStartedAndWereNeverReported() {
        let output = """
              ◇ Test "Reported" started.
              ◇ Test "Never reported" started.
              ◇ Test "Also never reported" started.
              ✔ Test "Reported" passed after 0.010 seconds.
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.unreportedTests, 2)
    }

    /// Xcode restates a failure as `<file>:test failure:<message>`, without naming the test. That
    /// is the same failure again, not a second one — and it used to be counted as `Test assertion`.
    func testARestatedFailureIsNotASecondFailure() {
        let output = """
            /project/Tests/MyTests.swift:52: error: -[MyTests testOne] : XCTAssertEqual failed: ("0") is not equal to ("999")
            /project/Tests/MyTests.swift:test failure:XCTAssertEqual failed: ("0") is not equal to ("999")
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests.first?.test, "MyTests testOne")
        XCTAssertEqual(result.summary.failedTests, 1)
    }

    /// Order is not guaranteed, and the named rendering says strictly more, so it takes over.
    func testTheNamedRenderingReplacesARestatementThatCameFirst() {
        let output = """
            /project/Tests/MyTests.swift:test failure:XCTAssertEqual failed: ("0") is not equal to ("999")
            /project/Tests/MyTests.swift:52: error: -[MyTests testOne] : XCTAssertEqual failed: ("0") is not equal to ("999")
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests.first?.line, 52)
    }

    /// A summary must never count fewer failures than the list it ships.
    func testTheSummaryNeverCountsFewerFailuresThanItLists() {
        let output = """
              ✘ Test "Swift Testing failure" recorded an issue at Tests.swift:9:5: Expectation failed
            Test Suite 'MyAppTests.xctest' failed at 2026-09-12 16:48:07.966.
                Executed 4 tests, with 1 failure (0 unexpected) in 0.667 (0.672) seconds
            /project/Tests/MyTests.swift:52: error: -[MyTests testOne] : XCTAssertEqual failed: nope
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: output)

        XCTAssertEqual(result.failedTests.count, 2)
        XCTAssertEqual(result.summary.failedTests, 2)
    }

    // MARK: - The whole transcript

    /// Xcode's own console log for a 72-test run: an XCTest bundle of 23 and a Swift Testing
    /// target of 49, with every block repeated under `Summary:`.
    ///
    /// Xcode's result bundle is the authority on that run — 72 tests, 69 passed, 3 failed — and the
    /// transcript cannot reach it: it prints `started` for 34 Swift Testing tests and an outcome
    /// for only 29, losing 11 test cases. What it can do is count everything it was shown (58
    /// passed, all 3 failures) and say how many tests it never saw the end of, which is what makes
    /// the difference from 69 explainable rather than silent. It used to report 21 and 2.
    func testRealXcodeConsoleTranscript() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "xcode-console-test-run", withExtension: "txt"))
        let result = OutputParser().parse(input: try String(contentsOf: url, encoding: .utf8))

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.failedTests, 3)
        XCTAssertEqual(result.failedTests.count, 3)
        XCTAssertEqual(result.summary.passedTests, 58)
        XCTAssertEqual(result.summary.unreportedTests, 5)
        XCTAssertEqual(
            result.failedTests.map(\.test).sorted(),
            [
                "CalculatorAppTests.CalculatorAppTests testCalculatorServiceFailure",
                "CalculatorAppTests.IntentionalFailureTests test",
                "This test should fail to verify error reporting",
            ]
        )
    }
}
