import Foundation
import XCTest

@testable import xcsift

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
