import XCTest

@testable import XCSiftCore

final class SwiftTestingParameterizedTests: XCTestCase {
    func testBundleWithNoSwiftTestingSummaryKeepsParameterizedFailureDetails() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "swift-testing-parameterized-issue", withExtension: "txt")
        )
        let input = try String(contentsOf: url, encoding: .utf8)

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.summary.passedTests, 0)
        XCTAssertEqual(result.failedTests.count, 1)
        let failure = try XCTUnwrap(result.failedTests.first)
        XCTAssertEqual(failure.test, "validatesFixture(_:)")
        XCTAssertEqual(failure.file, "ParameterizedTests.swift")
        XCTAssertEqual(failure.line, 8)
        XCTAssertEqual(failure.message, #"Expectation failed: (fixture → "invalid") == "valid""#)
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
