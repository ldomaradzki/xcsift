import XCTest

import XCSiftCore

final class SwiftTestingSkippedTests: XCTestCase {
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
