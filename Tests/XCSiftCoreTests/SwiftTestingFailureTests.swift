import XCTest

@testable import XCSiftCore

final class SwiftTestingFailureTests: XCTestCase {
    func testFailedSwiftTestingOutputKeepsFailureDetailsWithAndWithoutSummary() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "swift-testing-failed-output", withExtension: "txt")
        )
        let output = try String(contentsOf: url, encoding: .utf8)
        let withoutSummary = output.split(separator: "\n")
            .filter { !$0.contains("Test run with ") }.joined(separator: "\n")
        let expectedFailures = [
            ("expectationFailure()", 15, "Expectation failed: actual == 2: Values should match"),
            ("requirementFailure()", 20, "Expectation failed: value: A value is required"),
            ("thrownError()", 23, "Caught error: .invalid"),
            ("explicitIssue()", 28, "Issue recorded: An explicit failure"),
            ("missingExpectedError()", 32, "Expectation failed: an error was expected but none was thrown"),
            ("unexpectedError()", 36, "Expectation failed: an error was thrown when none was expected"),
            ("parameterizedFailure(value:)", 41, #"Expectation failed: value == "valid": The argument must be valid"#),
            ("Multiple arguments", 46, "Expectation failed: actual == expected"),
            ("multipleIssues()", 51, "Issue recorded: A second issue in the same test"),
            ("missingKnownIssue()", 55, "Known issue was not recorded: This failure no longer occurs"),
        ]

        for input in [output, withoutSummary] {
            let result = OutputParser().parse(input: input)

            XCTAssertEqual(result.status, "failed")
            XCTAssertEqual(result.summary.errors, 0)
            XCTAssertEqual(result.summary.failedTests, expectedFailures.count)
            XCTAssertEqual(result.summary.passedTests, 0)
            XCTAssertEqual(result.failedTests.count, expectedFailures.count)
            for (name, line, message) in expectedFailures {
                let failure = try XCTUnwrap(result.failedTests.first { $0.test == name })
                XCTAssertEqual(failure.file, "SwiftTestingFailedOutputTestFixtures.swift", name)
                XCTAssertEqual(failure.line, line, name)
                XCTAssertTrue(failure.message.hasPrefix(message), name)
                XCTAssertNotNil(failure.duration, name)
            }
        }
    }

    func testArgumentCountsNamesAndPlatformSymbols() throws {
        let names = [
            ("validatesFixture(_:)", "validatesFixture(_:)"),
            (#""Fixture validation""#, "Fixture validation"),
            ("validatesFixture(_:) (aka 'Fixture validation')", "validatesFixture(_:)"),
        ]
        let arguments = [
            ("1 argument", #"fixture → "bad: value at noon""#),
            ("2 arguments", #"input → "invalid", expected → "valid""#),
        ]

        for symbol in ["✘", "􀢄"] {
            for (printedName, expectedName) in names {
                for (count, argument) in arguments {
                    let input = """
                          \(symbol) Test \(printedName) recorded an issue with \(count) \(argument) at /project/My Tests/Fixtures.swift:12:5: Expectation failed: fixture.isValid at runtime
                        """

                    let result = OutputParser().parse(input: input)

                    XCTAssertEqual(result.status, "failed", input)
                    XCTAssertEqual(result.summary.failedTests, 1, input)
                    XCTAssertEqual(result.failedTests.count, 1, input)
                    let failure = try XCTUnwrap(result.failedTests.first)
                    XCTAssertEqual(failure.test, expectedName, input)
                    XCTAssertEqual(failure.file, "/project/My Tests/Fixtures.swift", input)
                    XCTAssertEqual(failure.line, 12, input)
                    XCTAssertEqual(
                        failure.message,
                        "Expectation failed: fixture.isValid at runtime [arguments: \(argument)]",
                        input
                    )
                }
            }
        }
    }

    func testIssueAndParameterizedCompletionMergeWithCommentAndDuration() throws {
        for name in ["validatesFixture(_:)", #""Fixture validation""#] {
            for newline in ["\n", "\r\n"] {
                let input = [
                    "✘ Test \(name) recorded an issue with 1 argument fixture → \"invalid\" at Fixtures.swift:12:5: Expectation failed",
                    "↳ Fixture must be valid",
                    "✘ Test \(name) with 2 test cases failed after 0.002 seconds with 1 issue.",
                    "** TEST FAILED **",
                ].joined(separator: newline)

                let result = OutputParser().parse(input: input)

                XCTAssertEqual(result.status, "failed", input)
                XCTAssertEqual(result.summary.failedTests, 1, input)
                XCTAssertEqual(result.failedTests.count, 1, input)
                let failure = try XCTUnwrap(result.failedTests.first)
                XCTAssertEqual(failure.file, "Fixtures.swift", input)
                XCTAssertEqual(failure.line, 12, input)
                XCTAssertEqual(
                    failure.message,
                    #"Expectation failed: Fixture must be valid [arguments: fixture → "invalid"]"#,
                    input
                )
                XCTAssertEqual(failure.duration, 0.002, input)
            }
        }
    }

    func testLocationQuotedInMessageDoesNotReplaceIssueLocation() throws {
        let message = "Caught error: parse failed at config.yml:3:14: unexpected token"
        for (issue, expected) in [
            ("recorded an issue", message),
            ("recorded an issue with 1 argument n → 1", message + " [arguments: n → 1]"),
        ] {
            let input = "✘ Test throwsLocated(n:) \(issue) at ParamTests.swift:20:6: \(message)"

            let result = OutputParser().parse(input: input)

            let failure = try XCTUnwrap(result.failedTests.first, input)
            XCTAssertEqual(failure.test, "throwsLocated(n:)", input)
            XCTAssertEqual(failure.file, "ParamTests.swift", input)
            XCTAssertEqual(failure.line, 20, input)
            XCTAssertEqual(failure.message, expected, input)
        }
    }

    func testFailingCasesAtOnePlaceListTheirArguments() throws {
        let input = """
            ✘ Test single(value:) recorded an issue with 1 argument value → "invalid" at ParamTests.swift:8:9: Expectation failed: isValid(value)
            ↳ must be valid
            ✘ Test single(value:) recorded an issue with 1 argument value → "bad: value" at ParamTests.swift:8:9: Expectation failed: isValid(value)
            ↳ must be valid
            ✘ Test single(value:) with 3 test cases failed after 0.003 seconds with 2 issues.
            """

        let result = OutputParser().parse(input: input)

        let failure = try XCTUnwrap(result.failedTests.first)
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(failure.line, 8)
        XCTAssertEqual(
            failure.message,
            #"Expectation failed: isValid(value): must be valid [arguments: value → "invalid"; value → "bad: value"]"#
        )
        XCTAssertEqual(failure.duration, 0.003)
    }

    func testFailingCaseElsewhereReplacesTheArguments() throws {
        let input = """
            ✘ Test pair(a:b:) recorded an issue with 2 arguments a → 1, b → 2 at ParamTests.swift:13:9: Expectation failed: a == b
            ✘ Test pair(a:b:) recorded an issue with 2 arguments a → 3, b → 0 at ParamTests.swift:14:9: Expectation failed: b > 0
            ✘ Test pair(a:b:) with 2 test cases failed after 0.001 seconds with 2 issues.
            """

        let result = OutputParser().parse(input: input)

        let failure = try XCTUnwrap(result.failedTests.first)
        XCTAssertEqual(failure.line, 14)
        XCTAssertEqual(failure.message, "Expectation failed: b > 0 [arguments: a → 3, b → 0]")
    }

    func testExpressionExpansionStaysOutOfTheMessage() throws {
        let input = """
            ✘ Test plain() recorded an issue at ParamTests.swift:17:9: Expectation failed: 1 == 2
            ↳ 1 == 2 → false
            ✘ Test plain() failed after 0.001 seconds with 1 issue.
            ✘ Test commented() recorded an issue at ParamTests.swift:21:9: Expectation failed: a == b
            ↳ a must equal b
            ↳ a == b → false
            ✘ Test commented() failed after 0.001 seconds with 1 issue.
            ✘ Test recorded() recorded an issue at ParamTests.swift:25:21: Issue recorded
            ↳ state → ready did not happen
            ✘ Test recorded() failed after 0.001 seconds with 1 issue.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(
            result.failedTests.map(\.message),
            [
                "Expectation failed: 1 == 2",
                "Expectation failed: a == b: a must equal b",
                // An issue that is not an expectation has no expansion, so its detail is a comment.
                "Issue recorded: state → ready did not happen",
            ]
        )
    }

    func testFailedRunSummaryCountsFailedTestsNotIssues() {
        let input = """
            ✘ Test twoIssues() recorded an issue at ParamTests.swift:30:9: Expectation failed: a
            ✘ Test twoIssues() recorded an issue at ParamTests.swift:31:9: Expectation failed: b
            ✘ Test twoIssues() failed after 0.001 seconds with 2 issues.
            ✘ Test single(value:) recorded an issue with 1 argument value → "x" at ParamTests.swift:8:9: Expectation failed: v
            ✘ Test single(value:) recorded an issue with 1 argument value → "y" at ParamTests.swift:8:9: Expectation failed: v
            ✘ Test single(value:) with 3 test cases failed after 0.001 seconds with 2 issues.
            ✔ Test passes() passed after 0.001 seconds.
            ✘ Test run with 3 tests in 1 suite failed after 0.002 seconds with 4 issues.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.failedTests, 2)
        XCTAssertEqual(result.summary.passedTests, 1)
    }

    func testParameterizedCaseLinesLeaveNoPhantomCrash() {
        // xcodebuild prints the case lines, then `** TEST FAILED **` for a run with any failure.
        // Each case line after the first starts with a zero-width space, as Xcode writes them.
        let input = """
            ◇ Test plain() started.
            ✘ Test plain() recorded an issue at ParamTests.swift:17:9: Expectation failed: 1 == 2
            ✘ Test plain() failed after 0.001 seconds with 1 issue.
            ◇ Test allPass(n:) started.
            ◇ Test case passing 1 argument n → 1 to allPass(n:) started.
            \u{200B}◇ Test case passing 1 argument n → 2 to allPass(n:) started.
            \u{200B}✔ Test allPass(n:) with 2 test cases passed after 0.001 seconds.
            ✘ Test run with 2 tests in 1 suite failed after 0.002 seconds with 1 issue.
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.failedTests.map(\.test), ["plain()"])
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.summary.passedTests, 1)
    }

    func testKnownParameterizedIssueIsNotAFailure() {
        let input = """
            ✔ Test validatesFixture(_:) recorded a known issue with 1 argument fixture → "invalid" at Fixtures.swift:12:5: Expectation failed
            ✔ Test validatesFixture(_:) with 1 test case passed after 0.002 seconds with 1 known issue.
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertTrue(result.failedTests.isEmpty)
    }
}
