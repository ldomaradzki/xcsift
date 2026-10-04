import XCTest

import XCSiftCore

final class SwiftTestingSkippedTests: XCTestCase {
    func testSkippedTestNamesAndReasonsDoNotReportFailures() {
        for name in ["\"requires service\"", "\"requires service\" (aka 'requiresService()')", "requiresService()"] {
            for prefix in ["➜", "􀙟", "\u{200B}\u{200B}➜"] {
                let input = """
                    \(prefix) Test \(name) skipped: "Dependency failed after 0.001 seconds with 1 issue."
                    ✔ Test run with 1 test passed after 0.001 seconds.
                    """

                let result = OutputParser().parse(input: input)

                XCTAssertEqual(result.status, "success", input)
                XCTAssertEqual(result.summary.passedTests, 0, input)
                XCTAssertEqual(result.summary.failedTests, 0, input)
                XCTAssertTrue(result.failedTests.isEmpty, input)
            }
        }
    }

    func testPassedTestNameMentioningSkippedIsNotASkip() {
        let input = """
            ✔ Test "2 tests skipped." (aka 'message()') passed after 0.001 seconds.
            ✔ Test run with 1 test passed after 0.001 seconds.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testVerboseSkippedTestsAreDeduplicatedWithinEachRun() {
        let input = """
            ➜ Test "requires service" skipped.
            ➜ Test "requires service" (aka 'requiresService()') skipped.
            ✔ Test run with 2 tests passed after 0.001 seconds.
            ➜ Test "requires service" (aka 'requiresService()') skipped.
            ✔ Test run with 2 tests passed after 0.001 seconds.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 2)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testSkippedTestsWithoutRunCompletionRemainIncomplete() {
        let input = """
            ◇ Test run started.
            ◇ Test "requires service" (aka 'requiresService()') started.
            ➜ Test "requires service" (aka 'requiresService()') skipped.
            ◇ Test waiting() started.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "incomplete")
        XCTAssertEqual(result.summary.passedTests, 0)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertEqual(result.summary.unreportedTests, 1)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testCompletedSkippedRunDoesNotHideBuildFailures() {
        let completedRun = """
            ➜ Test "requires service" skipped.
            ✔ Test run with 1 test passed after 0.001 seconds.
            """
        for failure in [
            "Command CodeSign failed with a nonzero exit code",
            "App.swift:10:5: error: build failed",
            "** BUILD FAILED **",
            "** TEST FAILED **",
        ] {
            for input in [failure + "\n" + completedRun, completedRun + "\n" + failure] {
                let result = OutputParser().parse(input: input)

                XCTAssertEqual(result.status, "failed", input)
                XCTAssertEqual(result.summary.passedTests, 0, input)
            }
        }
    }

    func testEmptyCompletedSwiftTestingRunSucceeds() {
        let result = OutputParser().parse(input: "✔ Test run with 0 tests passed after 0.001 seconds.")

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testAllSkippedRunWithoutBuildMarkerSucceeds() {
        let input = """
            Test Suite 'Selected tests' passed at 2026-10-04 12:00:00.000.
            Executed 0 tests, with 0 failures in 0.000 seconds
            ◇ Test run started.
            ➜ Test "requires service" skipped.
            ➜ Test unavailable() skipped.
            ✔ Test run with 2 tests in 1 suite passed after 0.001 seconds.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 0)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertNil(result.summary.buildTime)
        XCTAssertNil(result.summary.unreportedTests)
    }

    func testUnquotedFailureMentioningSkippedTestsKeepsItsLocation() {
        let input = """
            ✘ Test foo() recorded an issue at Tests.swift:42:5: "2 tests skipped."
            ✘ Test foo() failed after 0.001 seconds with 1 issue.
            ✘ Test run with 1 test failed after 0.001 seconds with 1 issue.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.passedTests, 0)
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests.first?.test, "foo()")
        XCTAssertEqual(result.failedTests.first?.file, "Tests.swift")
        XCTAssertEqual(result.failedTests.first?.line, 42)
        XCTAssertEqual(result.failedTests.first?.message, "\"2 tests skipped.\"")
        XCTAssertEqual(result.failedTests.first?.duration, 0.001)
    }

    /// Swift 6.3 output for `ParserTests.roundTrip()`, which passed, and `EncoderTests.roundTrip()`,
    /// which failed. Neither line names its suite, so the pass is not evidence of a flaky test.
    func testFunctionNameSharedAcrossSuitesIsNotFlaky() {
        let input = """
            ◇ Test run started.
            ◇ Test roundTrip() started.
            ◇ Test roundTrip() started.
            ✔ Test roundTrip() passed after 0.001 seconds.
            ✘ Test roundTrip() recorded an issue at T.swift:3:48: Expectation failed: 1 == 2
            ✘ Test roundTrip() failed after 0.001 seconds with 1 issue.
            ✘ Test run with 2 tests in 2 suites failed after 0.002 seconds with 1 issue.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertTrue(result.flakyTests.isEmpty)
        XCTAssertNil(result.summary.flakyTests)
        XCTAssertEqual(result.failedTests.first?.file, "T.swift")
        XCTAssertEqual(result.failedTests.first?.line, 3)
    }

    func testVerboseSkippedTestIsNotReportedAsPassed() {
        let input = """
            ➜ Test "requires service" (aka 'requiresService()') skipped.
            ✔ Test "passing test" (aka 'passingTest()') passed after 0.001 seconds.
            ✔ Test run with 2 tests passed after 0.001 seconds.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testObservedOutcomesDoNotSubtractSkippedTestsTwice() {
        let input = """
            ➜ Test "requires service" skipped.
            ➜ Test "requires service" skipped.
            ✔ Test "passing test" passed after 0.001 seconds.
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testAllSkippedWithoutSummaryReportsZeroPassed() {
        let input = """
            ➜ Test "requires service" skipped.
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.passedTests, 0)
        XCTAssertEqual(result.status, "success")
    }

    func testSkippedOutcomeDoesNotLeaveAnUnreportedOrCrashedTest() {
        let input = """
            ✘ Test "failing test" failed after 0.001 seconds with 1 issue.
            ◇ Test "requires service" started.
            ➜ Test "requires service" skipped: "Service failed after startup."
            ✘ Test run with 2 tests failed after 0.001 seconds with 1 issue.
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.passedTests, 0)
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertNil(result.summary.unreportedTests)
        XCTAssertEqual(result.failedTests.map(\.test), ["failing test"])
    }

    func testSkippedTestsAreExcludedFromParallelTotalsAlongsideXCTest() {
        let input = """
            Test Suite 'LegacyTests.xctest' passed at 2026-01-15 12:00:00.001.
            Executed 3 tests, with 0 failures in 0.100 seconds
            [1/2] Testing MyModule.requiresService
            [2/2] Testing MyModule.passingTest
            ➜ Test "requires service" skipped.
            ✔ Test "passing test" passed after 0.001 seconds.
            ✔ Test run with 2 tests passed after 0.001 seconds.
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.passedTests, 4)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testSkippedTestsAreCountedInEachCompletedRun() {
        let input = """
            ➜ Test "requires service" skipped.
            ➜ Test "requires service" skipped.
            ✔ Test run with 3 tests passed after 0.001 seconds.
            ➜ Test "requires service" skipped.
            ✔ Test run with 3 tests passed after 0.001 seconds.
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.passedTests, 4)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testUnquotedSkippedTestIsNotReportedAsPassed() {
        let input = """
            ➜ Test requiresService() skipped: "Service failed after startup."
            ✔ Test run with 1 test passed after 0.001 seconds.
            ** TEST SUCCEEDED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 0)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertTrue(result.failedTests.isEmpty)
    }

    func testSkippedTestsAreNotReportedAsPassedInFailedRun() {
        let input = """
            \u{200B}➜ Suite IntegrationTests skipped: "Requires an external service."
            \u{200B}\u{200B}➜ Test "first integration test" skipped: "Requires an external service."
            \u{200B}\u{200B}➜ Test "second integration test" skipped: "Requires an external service."
            ◇ Test "failing test" started.
            ✘ Test "failing test" failed after 0.001 seconds with 1 issue.
            ◇ Test "passing test" started.
            ✔ Test "passing test" passed after 0.001 seconds.
            ✘ Test run with 4 tests in 2 suites failed after 0.002 seconds with 1 issue.
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.failedTests.map(\.test), ["failing test"])
    }
}
