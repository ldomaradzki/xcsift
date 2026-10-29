import Foundation
import XCTest
import XCSiftCore

// MARK: - xcbeautify Error Parsing Tests

final class XcbeautifyErrorTests: XCTestCase {

    func testAsciiErrorParsed() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/ContentView.swift:93:35: 'wheel' is unavailable in macOS
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "/path/to/ContentView.swift")
        XCTAssertEqual(result.errors[0].line, 93)
        XCTAssertEqual(result.errors[0].message, "'wheel' is unavailable in macOS")
    }

    func testEmojiErrorParsed() {
        let parser = OutputParser()
        let input = """
            ❌ /path/to/ContentView.swift:93:35: 'wheel' is unavailable in macOS
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors[0].file, "/path/to/ContentView.swift")
        XCTAssertEqual(result.errors[0].line, 93)
        XCTAssertEqual(result.errors[0].message, "'wheel' is unavailable in macOS")
    }

    func testAsciiErrorWithoutColumnParsed() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/File.swift:93: some error message
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors[0].file, "/path/to/File.swift")
        XCTAssertEqual(result.errors[0].line, 93)
        XCTAssertEqual(result.errors[0].message, "some error message")
    }

    func testAsciiErrorGenericMessage() {
        let parser = OutputParser()
        let input = """
            [x] some error without file path
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors[0].message, "some error without file path")
    }

    func testMultipleAsciiErrors() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/ContentView.swift:93:35: 'wheel' is unavailable in macOS
            [x] /path/to/OtherView.swift:10:20: 'navigationDestination' is unavailable in watchOS
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.errors, 2)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertEqual(result.errors[0].file, "/path/to/ContentView.swift")
        XCTAssertEqual(result.errors[1].file, "/path/to/OtherView.swift")
    }

    func testErrorDeduplication() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/File.swift:10:5: duplicate error
            [x] /path/to/File.swift:10:5: duplicate error
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.count, 1)
    }

    func testAsciiErrorIgnoredWithoutFlag() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/ContentView.swift:93:35: 'wheel' is unavailable in macOS
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input, xcbeautify: false)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.errors.count, 0)
    }
}

// MARK: - xcbeautify Warning Parsing Tests

final class XcbeautifyWarningTests: XCTestCase {

    func testAsciiWarningParsed() {
        let parser = OutputParser()
        let input = """
            [!] /path/to/Parser.swift:20:10: variable 'unused' was never used
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].file, "/path/to/Parser.swift")
        XCTAssertEqual(result.warnings[0].line, 20)
        XCTAssertEqual(result.warnings[0].message, "variable 'unused' was never used")
    }

    func testEmojiWarningParsed() {
        let parser = OutputParser()
        let input = """
            ⚠️ /path/to/Parser.swift:20:10: variable 'unused' was never used
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings[0].file, "/path/to/Parser.swift")
        XCTAssertEqual(result.warnings[0].line, 20)
        XCTAssertEqual(result.warnings[0].message, "variable 'unused' was never used")
    }

    // xcbeautify's terminal renderer writes a compile warning with two spaces after the marker
    // (issue #101).
    func testCompileWarningWithTwoSpacesHasNoLeadingSpaceInFile() {
        let parser = OutputParser()
        let input = """
            [!]  /repo/Sources/Foo/Foo.swift:10:5: variable 'x' was never used
            ⚠️  /repo/Sources/Foo/Foo.swift:11:5: variable 'y' was never used
            Build Succeeded
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.warnings.map(\.file), ["/repo/Sources/Foo/Foo.swift", "/repo/Sources/Foo/Foo.swift"])
        XCTAssertEqual(result.warnings.map(\.line), [10, 11])
        XCTAssertEqual(result.warnings.first?.message, "variable 'x' was never used")
    }

    func testCompileWarningWithTwoSpacesKeepsPathWhenPromotedToError() {
        let parser = OutputParser()
        let input = """
            [!]  /repo/Sources/Foo/Foo.swift:10:5: variable 'x' was never used
            Build Succeeded
            """

        let result = parser.parse(input: input, warningsAsErrors: true, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errors.map(\.file), ["/repo/Sources/Foo/Foo.swift"])
    }

    func testWarningIgnoredWithoutFlag() {
        let parser = OutputParser()
        let input = """
            [!] /path/to/Parser.swift:20:10: variable 'unused' was never used
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: false)

        XCTAssertEqual(result.summary.warnings, 0)
    }

    func testMixedErrorsAndWarnings() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/File.swift:10:5: error message
            [!] /path/to/File.swift:20:10: warning message
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.errors[0].message, "error message")
        XCTAssertEqual(result.warnings[0].message, "warning message")
    }
}

// MARK: - xcbeautify GitHub Actions Renderer Tests

/// xcbeautify's GitHub Actions renderer, which Tuist selects when `GITHUB_ACTIONS` is set, writes
/// diagnostics as workflow commands (issue #103).
final class XcbeautifyGitHubActionsTests: XCTestCase {

    func testWorkflowWarningParsed() throws {
        let parser = OutputParser()
        let input = """
            [Foo] Compiling Foo.swift
            ::warning file=/repo/Sources/Foo/Foo.swift,line=10,col=5::variable 'x' was never used; consider replacing with '_' or removing it
            Build Succeeded
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.warnings, 1)
        let warning = try XCTUnwrap(result.warnings.first)
        XCTAssertEqual(warning.file, "/repo/Sources/Foo/Foo.swift")
        XCTAssertEqual(warning.line, 10)
        XCTAssertEqual(warning.message, "variable 'x' was never used; consider replacing with '_' or removing it")
    }

    func testWorkflowWarningPromotedByWarningsAsErrors() {
        let parser = OutputParser()
        let input = """
            ::warning file=/repo/Sources/Foo/Foo.swift,line=10,col=5::variable 'x' was never used
            Build Succeeded
            """

        let result = parser.parse(input: input, warningsAsErrors: true, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.map(\.file), ["/repo/Sources/Foo/Foo.swift"])
    }

    func testWorkflowErrorParsed() throws {
        let parser = OutputParser()
        let input = """
            [Foo] Compiling Foo.swift
            ::error file=/repo/Sources/Foo/Foo.swift,line=12,col=9::cannot find 'bar' in scope
            Build Failed
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        let error = try XCTUnwrap(result.errors.first)
        XCTAssertEqual(error.file, "/repo/Sources/Foo/Foo.swift")
        XCTAssertEqual(error.line, 12)
        XCTAssertEqual(error.column, 9)
        XCTAssertEqual(error.message, "cannot find 'bar' in scope")
    }

    func testWorkflowCommandsWithoutLocation() {
        let parser = OutputParser()
        let input = """
            ::warning ::Run script build phase 'Lint' will be run during every build
            ::error ::Testing failed
            ::error::documented form without a space
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.warnings.map(\.file), [nil])
        XCTAssertEqual(result.warnings.map(\.message), ["Run script build phase 'Lint' will be run during every build"])
        XCTAssertEqual(result.errors.map(\.message), ["Testing failed", "documented form without a space"])
        XCTAssertEqual(result.errors.map(\.file), [nil, nil])
    }

    func testWorkflowLocationWithoutColumnOrLine() {
        let parser = OutputParser()
        let input = """
            ::error file=/repo/Foo.swift,line=7::no column
            ::error file=/repo/Bar.swift::no line
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.errors.map(\.file), ["/repo/Foo.swift", "/repo/Bar.swift"])
        XCTAssertEqual(result.errors.map(\.line), [7, nil])
        XCTAssertEqual(result.errors.map(\.column), [nil, nil])
    }

    // xcbeautify does not escape the path, so a comma stays part of it.
    func testWorkflowPathWithComma() throws {
        let parser = OutputParser()
        let input = """
            ::error file=/repo/A,B/Foo.swift,line=3,col=1::message
            """

        let result = parser.parse(input: input, xcbeautify: true)

        let error = try XCTUnwrap(result.errors.first)
        XCTAssertEqual(error.file, "/repo/A,B/Foo.swift")
        XCTAssertEqual(error.line, 3)
        XCTAssertEqual(error.column, 1)
    }

    // Lines as Tuist 4.214 printed them with `GITHUB_ACTIONS` set.
    func testFailingXCTestIsAFailedTest() throws {
        let parser = OutputParser()
        let input = """
            ::error file=/repo/Tests/PTests/T.swift,line=30::    testRealFailure, XCTAssertTrue failed - really broken
            ::error file=/repo/Tests/PTests/T.swift,line=40::    testXCTFail, failed - boom
            Executed 2 tests, with 2 failures (0 unexpected) in 0.004 (0.005) seconds
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.failedTests.map(\.test), ["testRealFailure", "testXCTFail"])
        XCTAssertEqual(result.failedTests.map(\.message), ["XCTAssertTrue failed - really broken", "failed - boom"])
        XCTAssertEqual(result.failedTests.map(\.file), ["/repo/Tests/PTests/T.swift", "/repo/Tests/PTests/T.swift"])
        XCTAssertEqual(result.failedTests.map(\.line), [30, 40])
    }

    func testFailingSwiftTestingAndParallelTestsAreFailedTests() {
        let parser = OutputParser()
        let input = """
            ::error ::fails() (0.001 seconds) 1 issue(s)
            ::error ::    testB on 'iPhone 17' (0.200 seconds)
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.failedTests.map(\.test), ["fails()", "testB"])
        XCTAssertEqual(result.failedTests.map(\.duration), [0.001, 0.2])
    }

    // Only an indented message or an issue count marks a test. A compiler message keeps its commas.
    func testOtherErrorsStayErrors() {
        let parser = OutputParser()
        let input = """
            ::error file=/repo/Foo.swift,line=3,col=5::unavailable, use bar
            ::error ::    Restarting after unexpected exit, crash, or test timeout in FooTests.testBar()
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertTrue(result.failedTests.isEmpty)
        XCTAssertEqual(
            result.errors.map(\.message),
            ["unavailable, use bar", "Restarting after unexpected exit, crash, or test timeout in FooTests.testBar()"]
        )
    }

    func testOtherWorkflowCommandsIgnored() {
        let parser = OutputParser()
        let input = """
            ::notice ::Skipped FooTests.testSkipped
            ::group::Build
            ::endgroup::
            ::errors are not a command
            Build Succeeded
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.warnings, 0)
    }

    func testWorkflowCommandsIgnoredWithoutFlag() {
        let parser = OutputParser()
        let input = """
            ::warning file=/repo/Foo.swift,line=10,col=5::variable 'x' was never used
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: false)

        XCTAssertEqual(result.summary.warnings, 0)
        XCTAssertTrue(parser.didEmitXcbeautifyHint)
    }
}

// MARK: - xcbeautify Test Status Parsing Tests

final class XcbeautifyTestStatusTests: XCTestCase {

    func testPassedTestParsed() {
        let parser = OutputParser()
        let input = """
            ✔ ContentViewTests.testExample passed (0.123 seconds)
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.passedTests, 1)
    }

    func testFailedTestParsed() {
        let parser = OutputParser()
        let input = """
            ✖ ContentViewTests.testExample failed (0.456 seconds)
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests[0].test, "ContentViewTests.testExample")
        XCTAssertEqual(result.failedTests[0].duration, 0.456)
        XCTAssertEqual(result.failedTests[0].message, "Test failed")
    }

    func testTestMarkersIgnoredWithoutFlag() {
        let parser = OutputParser()
        let input = """
            ✔ ContentViewTests.testExample passed (0.123 seconds)
            ✖ ContentViewTests.testFailure failed (0.456 seconds)
            """

        let result = parser.parse(input: input, xcbeautify: false)

        // Without xcbeautify flag, ✔ should not be counted as xcbeautify-style test
        XCTAssertNil(result.summary.passedTests)
    }

    // The terminal renderer indents its test results and writes no `passed`/`failed`. Lines as
    // Tuist 4.214 printed them.
    func testIndentedXCTestResults() {
        let parser = OutputParser()
        let input = """
            Test Suite 'T' started at 2026-10-29 08:24:15.281.
                ✔ testPass (0.001 seconds)
                ✖ testRealFailure, XCTAssertTrue failed - really broken
                ✖ testXCTFail, failed - boom
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.failedTests.map(\.test), ["testRealFailure", "testXCTFail"])
        XCTAssertEqual(result.failedTests.map(\.message), ["XCTAssertTrue failed - really broken", "failed - boom"])
    }

    // The indented `[!]` is the issue's location, which the Swift Testing parser reads. It is not a
    // warning.
    func testIndentedSwiftTestingResults() throws {
        let parser = OutputParser()
        let input = """
            Suite ST started
                ✔ passes() (0.001 seconds)
                [!]  Test fails() recorded an issue at ST.swift:6:26: Expectation failed: answer() == 41
                ✖ fails() (0.001 seconds) 1 issue(s)
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.summary.warnings, 0)
        XCTAssertEqual(result.failedTests.count, 1)
        let failure = try XCTUnwrap(result.failedTests.first)
        XCTAssertEqual(failure.test, "fails()")
        XCTAssertEqual(failure.file, "ST.swift")
        XCTAssertEqual(failure.line, 6)
        XCTAssertEqual(failure.duration, 0.001)
    }

    func testParallelTestResults() {
        let parser = OutputParser()
        let input = """
                ✔ [FooTests] testA on 'iPhone 17' (0.100 seconds)
                ✖ [FooTests] testB on 'iPhone 17' (0.200 seconds)
                ✔ [FooTests] testC (0.300 seconds)
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.passedTests, 2)
        XCTAssertEqual(result.failedTests.map(\.test), ["FooTests.testB"])
        XCTAssertEqual(result.failedTests.map(\.duration), [0.2])
    }

    func testUITestFailureKeepsItsLocation() throws {
        let parser = OutputParser()
        let input = """
                ✖ /repo/UITests/LoginUITests.swift:12, Failed to tap "Login" Button
            """

        let result = parser.parse(input: input, xcbeautify: true)

        let failure = try XCTUnwrap(result.failedTests.first)
        XCTAssertEqual(failure.file, "/repo/UITests/LoginUITests.swift")
        XCTAssertEqual(failure.line, 12)
        XCTAssertEqual(failure.message, "Failed to tap \"Login\" Button")
    }

    // Tuist ends a command with `✔ Success` or `✖ Error`, and neither is a test. A raw Swift Testing
    // line is the Swift Testing parser's, not a test called `Test run with 1 test`.
    func testOtherMarkedLinesAreNotTests() {
        let parser = OutputParser()
        let input = """
            ✔ Test run with 1 test passed after 0.001 seconds.
            ✔ Success
            ✖ Error
                ✖ Restarting after unexpected exit, crash, or test timeout in FooTests.testBar()
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertTrue(result.failedTests.isEmpty)
        XCTAssertEqual(result.summary.passedTests, 1)
    }
}

// MARK: - xcbeautify Test Counts

/// XCTest's `Executed …` totals do not include Swift Testing, and xcbeautify writes a Swift Testing
/// result without the word `Test`. Those results have to reach the Swift Testing counts.
final class XcbeautifyTestCountTests: XCTestCase {

    // A Tuist 4.214 run of both frameworks, terminal renderer. XCTest: 4 passed, 5 failed,
    // 1 skipped. Swift Testing: 1 passed, 1 failed.
    func testBothFrameworksTerminalRenderer() {
        let parser = OutputParser()
        let input = """
            Test Suite 'All tests' started at 2026-10-29 08:24:15.280.
            Test Suite 'PTests.xctest' started at 2026-10-29 08:24:15.281.
            Test Suite 'T' started at 2026-10-29 08:24:15.281.
                ✔ testAssertTrueExpected (0.772 seconds)
                ✔ testEqualExpected (0.001 seconds)
                ✔ testFailExpected (0.001 seconds)
                ✔ testPass (0.001 seconds)
                ✖ testRealFailure, XCTAssertTrue failed - really broken
                ✖ testStrictNoFailure, Expected failure 'should fail but does not' but none recorded
            Executed 6 tests, with 2 failures (1 unexpected) in 0.776 (0.778) seconds
            Test Suite 'U' started at 2026-10-29 08:24:16.059.
                ⊘ testSkipped (0.001 seconds)
                ✖ testThrows, failed: caught error: "Oops()"
                ✖ testUnwrap, XCTUnwrap failed: expected non-nil value of type "Int"
                ✖ testXCTFail, failed - boom
            Executed 4 tests, with 1 test skipped and 3 failures (1 unexpected) in 0.004 (0.005) seconds
            Test Suite 'PTests.xctest' failed at 2026-10-29 08:24:16.064.
            Executed 10 tests, with 1 test skipped and 5 failures (2 unexpected) in 0.780 (0.783) seconds
            Test Suite 'All tests' failed at 2026-10-29 08:24:16.064.
            Executed 10 tests, with 1 test skipped and 5 failures (2 unexpected) in 0.780 (0.784) seconds
            Test run started.
            Suite ST started
                ✔ passes() (0.001 seconds)
                [!]  Test fails() recorded an issue at ST.swift:6:26: Expectation failed: answer() == 41
                ✖ fails() (0.001 seconds) 1 issue(s)
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.passedTests, 5)
        XCTAssertEqual(result.summary.failedTests, 6)
        XCTAssertEqual(result.failedTests.filter { $0.test == "fails()" }.count, 1)
    }

    // The same run with the GitHub Actions renderer. No line here reaches the Swift Testing parser.
    func testBothFrameworksGitHubActionsRenderer() {
        let parser = OutputParser()
        let input = """
            Test Suite 'PTests.xctest' started at 2026-10-29 08:24:41.108.
                ✔ testPass (0.000 seconds)
            ::error file=/repo/Tests/PTests/T.swift,line=30::    testRealFailure, XCTAssertTrue failed - really broken
            Test Suite 'PTests.xctest' failed at 2026-10-29 08:24:41.851.
            Executed 2 tests, with 1 failure (1 unexpected) in 0.739 (0.743) seconds
            Test run started.
            Suite ST started
            ::error ::fails() (0.001 seconds) 1 issue(s)
                ✔ passes() (0.001 seconds)
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.passedTests, 2)
        XCTAssertEqual(result.summary.failedTests, 2)
    }

    // Each case of a parameterised test counts, and a display name loses its quotes so that the
    // failure and its issue are one entry.
    func testSwiftTestingOnly() throws {
        let parser = OutputParser()
        let input = """
            Test run started.
            Suite ST started
                ✔ a() (0.001 seconds)
                ✔ "Display name" (0.001 seconds)
                ✔ cases(n:) with 4 test cases (0.002 seconds)
                [!]  Test "Broken" recorded an issue at ST.swift:6:26: Expectation failed: x
                ✖ "Broken" (0.001 seconds) 1 issue(s)
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.summary.passedTests, 6)
        XCTAssertEqual(result.summary.failedTests, 1)
        let failure = try XCTUnwrap(result.failedTests.first)
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(failure.test, "Broken")
        XCTAssertEqual(failure.file, "ST.swift")
        XCTAssertEqual(failure.line, 6)
    }
}

// MARK: - xcbeautify Auto-detection Hint Tests

final class XcbeautifyAutoDetectTests: XCTestCase {

    func testAutoDetectHintShown() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/File.swift:10:5: error
            """

        let result = parser.parse(input: input, xcbeautify: false)

        // Errors should NOT be parsed without flag
        XCTAssertEqual(result.summary.errors, 0)
        // But hint should have been emitted (we verify via xcbeautifyHintEmitted)
        XCTAssertTrue(parser.didEmitXcbeautifyHint)
    }

    func testAutoDetectHintNotShownWithFlag() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/File.swift:10:5: error
            """

        _ = parser.parse(input: input, xcbeautify: true)

        // Hint should NOT be emitted when flag is active (parsing works directly)
        XCTAssertFalse(parser.didEmitXcbeautifyHint)
    }

    func testAutoDetectHintShownOnce() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/File.swift:10:5: error one
            [x] /path/to/File.swift:20:5: error two
            [!] /path/to/File.swift:30:5: warning
            """

        _ = parser.parse(input: input, xcbeautify: false)

        // Hint emitted only once regardless of how many markers found
        XCTAssertTrue(parser.didEmitXcbeautifyHint)
    }

    func testAutoDetectNotTriggeredOnCleanInput() {
        let parser = OutputParser()
        let input = """
            /path/to/file.swift:10:5: error: use of undeclared identifier 'unknown'
            """

        _ = parser.parse(input: input, xcbeautify: false)

        XCTAssertFalse(parser.didEmitXcbeautifyHint)
    }

    func testAutoDetectHintShownForEmojiError() {
        let parser = OutputParser()
        let input = """
            ❌ /path/to/File.swift:10:5: error message
            """

        _ = parser.parse(input: input, xcbeautify: false)

        XCTAssertTrue(parser.didEmitXcbeautifyHint)
    }

    func testAutoDetectHintShownForEmojiWarning() {
        let parser = OutputParser()
        let input = """
            ⚠️ /path/to/File.swift:20:10: variable 'unused' was never used
            """

        _ = parser.parse(input: input, xcbeautify: false)

        XCTAssertTrue(parser.didEmitXcbeautifyHint)
    }

    func testAutoDetectHintRequiresAnExactMarkerAtTheStart() {
        let parser = OutputParser()
        let input = """
             [x] leading whitespace
            [xy] near miss
            ⚡️ emoji near miss
            """

        _ = parser.parse(input: input, xcbeautify: false)

        XCTAssertFalse(parser.didEmitXcbeautifyHint)
    }
}

// MARK: - xcbeautify Diagnostic Parsing Tests

final class XcbeautifyDiagnosticTests: XCTestCase {

    func testMessageWithColonsAndNumbers() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/File.swift:10:5: expected 2: got 3
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "/path/to/File.swift")
        XCTAssertEqual(result.errors[0].line, 10)
        XCTAssertEqual(result.errors[0].column, 5)
        XCTAssertEqual(result.errors[0].message, "expected 2: got 3")
    }

    func testMessageWithTypeContainingColon() {
        let parser = OutputParser()
        let input = """
            [x] /path/to/View.swift:42:8: Type 'Foo: Bar' is unavailable
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "/path/to/View.swift")
        XCTAssertEqual(result.errors[0].line, 42)
        XCTAssertEqual(result.errors[0].column, 8)
        XCTAssertEqual(result.errors[0].message, "Type 'Foo: Bar' is unavailable")
    }

    func testPlainMessageWithoutFilePath() {
        let parser = OutputParser()
        let input = """
            [x] Something went wrong: error 42
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.errors.count, 1)
        XCTAssertNil(result.errors[0].file)
        XCTAssertNil(result.errors[0].line)
        XCTAssertEqual(result.errors[0].message, "Something went wrong: error 42")
    }
}

// MARK: - xcbeautify Integration Tests

final class XcbeautifyIntegrationTests: XCTestCase {

    func testFullBuildOutput() {
        let parser = OutputParser()
        let input = """
            [TestApp] Compiling ContentView.swift
            [x] /path/to/ContentView.swift:93:35: 'wheel' is unavailable in macOS
            [!] /path/to/Parser.swift:20:10: variable 'unused' was never used
            [TestApp] Compiling TestAppApp.swift
            ✔ TestAppTests.testExample passed (0.050 seconds)
            ✖ TestAppTests.testFailure failed (0.100 seconds)
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: true)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.errors[0].file, "/path/to/ContentView.swift")
        XCTAssertEqual(result.warnings[0].file, "/path/to/Parser.swift")
        XCTAssertEqual(result.failedTests[0].test, "TestAppTests.testFailure")
    }

    func testBuildOnlySuccessMarker() {
        // xcbeautify rewrites ** BUILD SUCCEEDED ** to "Build Succeeded"; a build with no tests
        // must still report success (not incomplete) on this terminal marker.
        let parser = OutputParser()
        let input = """
            [TestApp] Compiling ContentView.swift
            Build Succeeded
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.status, "success")
    }

    func testArchiveAndExportSuccessMarkers() {
        // xcbeautify rewrites every ** <PHASE> SUCCEEDED ** to "<Phase> Succeeded".
        for marker in ["Archive Succeeded", "Export Succeeded", "Test Execute Succeeded"] {
            let parser = OutputParser()
            let result = parser.parse(input: marker, xcbeautify: true)
            XCTAssertEqual(result.status, "success", marker)
        }
    }

    func testScriptOutputContainingSucceededIsNotATerminalMarker() {
        // A run-script line is not a phase marker. A killed build must stay incomplete.
        let parser = OutputParser()
        let input = """
            Compiling MyApp
            [Upload] Upload Succeeded
            Killed: 9
            """

        let result = parser.parse(input: input, xcbeautify: true)

        XCTAssertEqual(result.status, "incomplete")
    }

    func testEveryXcbeautifyPhaseSuccessMarker() {
        // xcbeautify title-cases the phase word of `** <PHASE> SUCCEEDED **`. Verified against
        // xcbeautify 3.2.1 for the whole xcodebuild action set.
        for marker in [
            "Build Succeeded", "Build For Testing Succeeded", "Test Succeeded",
            "Test Execute Succeeded", "Test Without Building Succeeded", "Analyze Succeeded",
            "Analyze For Testing Succeeded", "Archive Succeeded", "Export Succeeded",
            "Clean Succeeded", "Install Succeeded", "Installsrc Succeeded",
            "Installhdrs Succeeded", "Installloc Succeeded", "Docbuild Succeeded",
        ] {
            let parser = OutputParser()
            let result = parser.parse(input: marker, xcbeautify: true)
            XCTAssertEqual(result.status, "success", marker)
        }
    }

    func testColoredSuccessMarker() {
        // Terminal renderer wraps the marker in ANSI codes.
        let parser = OutputParser()
        let result = parser.parse(input: "\u{1B}[32;1mArchive Succeeded\u{1B}[0m", xcbeautify: true)

        XCTAssertEqual(result.status, "success")
    }

    func testDefaultModeUnaffected() {
        let parser = OutputParser()
        let input = """
            /path/to/file.swift:10:5: error: use of undeclared identifier 'unknown'
            /path/to/file.swift:20:10: warning: variable 'unused' was never used
            """

        let result = parser.parse(input: input, printWarnings: true, xcbeautify: false)

        // Standard xcodebuild parsing should work as usual
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.errors[0].file, "/path/to/file.swift")
    }
}
