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
            #"1 argument fixture → "bad: value at noon""#,
            #"2 arguments input → "invalid", expected → "valid""#,
        ]

        for symbol in ["✘", "􀢄"] {
            for (printedName, expectedName) in names {
                for argument in arguments {
                    let input = """
                          \(symbol) Test \(printedName) recorded an issue with \(argument) at /project/My Tests/Fixtures.swift:12:5: Expectation failed: fixture.isValid at runtime
                        """

                    let result = OutputParser().parse(input: input)

                    XCTAssertEqual(result.status, "failed", input)
                    XCTAssertEqual(result.summary.failedTests, 1, input)
                    XCTAssertEqual(result.failedTests.count, 1, input)
                    let failure = try XCTUnwrap(result.failedTests.first)
                    XCTAssertEqual(failure.test, expectedName, input)
                    XCTAssertEqual(failure.file, "/project/My Tests/Fixtures.swift", input)
                    XCTAssertEqual(failure.line, 12, input)
                    XCTAssertEqual(failure.message, "Expectation failed: fixture.isValid at runtime", input)
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
                XCTAssertEqual(failure.message, "Expectation failed: Fixture must be valid", input)
                XCTAssertEqual(failure.duration, 0.002, input)
            }
        }
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
