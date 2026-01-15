import XCTest
@testable import xcsift

/// Tests for basic parsing functionality: errors, warnings, tests, and build output
final class ParsingTests: XCTestCase {

    func testParseError() {
        let parser = OutputParser()
        let input = """
            main.swift:15:5: error: use of undeclared identifier 'unknown'
            unknown = 5
            ^
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "main.swift")
        XCTAssertEqual(result.errors[0].line, 15)
        XCTAssertEqual(result.errors[0].message, "use of undeclared identifier 'unknown'")
    }

    func testParseSuccessfulBuild() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertNil(result.summary.passedTests)
    }

    func testFailingTest() {
        let parser = OutputParser()
        let input = """
            Test Case 'LoginTests.testInvalidCredentials' failed (0.045 seconds).
            XCTAssertEqual failed: Expected valid login
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.failedTests, 2)
        XCTAssertEqual(result.failedTests.count, 2)
        XCTAssertNil(result.summary.passedTests)
        XCTAssertEqual(result.failedTests[0].test, "LoginTests.testInvalidCredentials")
        XCTAssertEqual(result.failedTests[1].test, "Test assertion")
    }

    func testMultipleErrors() {
        let parser = OutputParser()
        let input = """
            UserService.swift:45:12: error: cannot find 'invalidFunction' in scope
            NetworkManager.swift:23:5: error: use of undeclared identifier 'unknownVariable'
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 2)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertNil(result.summary.passedTests)
    }

    func testInvalidAssertion() {
        let line = "XCTAssertTrue failed - Connection should be established"
        let parser = OutputParser()
        let result = parser.parse(input: line)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertNil(result.summary.passedTests)
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests[0].test, "Test assertion")
        XCTAssertEqual(result.failedTests[0].message, line.trimmingCharacters(in: .whitespaces))
    }

    func testWrongFileReference() {
        let parser = OutputParser()
        let input = """
            NonexistentFile.swift:999:1: error: file not found
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertNil(result.summary.passedTests)
        XCTAssertEqual(result.errors[0].file, "NonexistentFile.swift")
        XCTAssertEqual(result.errors[0].line, 999)
        XCTAssertEqual(result.errors[0].message, "file not found")
    }

    func testBuildTimeExtraction() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build failed after 5.7 seconds
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.buildTime, "5.7 seconds")
        XCTAssertNil(result.summary.passedTests)
    }

    func testParseCompileError() {
        let parser = OutputParser()
        let input = """
            UserManager.swift:42:10: error: cannot find 'undefinedVariable' in scope
            print(undefinedVariable)
            ^
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertNil(result.summary.passedTests)
        XCTAssertEqual(result.errors[0].file, "UserManager.swift")
        XCTAssertEqual(result.errors[0].line, 42)
        XCTAssertEqual(result.errors[0].message, "cannot find 'undefinedVariable' in scope")
    }

    func testPassedTestCountFromExecutedSummary() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testExample' passed (0.001 seconds).
            Executed 5 tests, with 0 failures (0 unexpected) in 5.017 (5.020) seconds
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.passedTests, 5)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertEqual(result.summary.testTime, "5.017s")
    }

    func testPassedTestCountFromPassLineOnly() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testExample' passed (0.001 seconds).
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.passedTests, 1)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    /// Tests that XCTest and Swift Testing counts are aggregated correctly
    /// Regression test for issue where only Swift Testing count was reported
    func testCombinedXCTestAndSwiftTestingCounts() {
        let parser = OutputParser()
        // Simulates output from `swift test` with both XCTest and Swift Testing tests
        let input = """
            Test Suite 'All tests' started at 2024-01-01 12:00:00.000.
            Test Suite 'MyPackageTests.xctest' started at 2024-01-01 12:00:00.001.
            Test Suite 'MyXCTests' started at 2024-01-01 12:00:00.002.
            Test Case '-[MyPackageTests.MyXCTests testExample1]' started.
            Test Case '-[MyPackageTests.MyXCTests testExample1]' passed (0.001 seconds).
            Test Case '-[MyPackageTests.MyXCTests testExample2]' started.
            Test Case '-[MyPackageTests.MyXCTests testExample2]' passed (0.001 seconds).
            Test Suite 'MyXCTests' passed at 2024-01-01 12:00:00.003.
            Test Suite 'MyPackageTests.xctest' passed at 2024-01-01 12:00:00.004.
            Test Suite 'All tests' passed at 2024-01-01 12:00:00.005.
            Executed 1624 tests, with 0 failures (0 unexpected) in 2.728 (2.768) seconds
            􀟈  Test run started.
            ✓ Test "SwiftTest1" passed after 0.001 seconds.
            ✓ Test "SwiftTest2" passed after 0.001 seconds.
            ✓ Test "SwiftTest3" passed after 0.001 seconds.
            􁁛  Test run with 82 tests in 7 suites passed after 0.166 seconds.
            """

        let result = parser.parse(input: input)

        // Should aggregate both XCTest (1624) and Swift Testing (82) counts
        XCTAssertEqual(result.summary.passedTests, 1624 + 82)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertEqual(result.status, "success")
    }

    /// Tests combined counts when both XCTest and Swift Testing have failures
    func testCombinedXCTestAndSwiftTestingWithFailures() {
        let parser = OutputParser()
        let input = """
            Executed 100 tests, with 2 failures (2 unexpected) in 1.5 (1.6) seconds
            ✘ Test run with 3 tests failed, 7 tests passed after 0.5 seconds.
            """

        let result = parser.parse(input: input)

        // XCTest: 100 total, 2 failed = 98 passed
        // Swift Testing: 3 failed + 7 passed = 10 total
        // Combined: 100 + 10 = 110 total, 2 + 3 = 5 failed, 110 - 5 = 105 passed
        XCTAssertEqual(result.summary.passedTests, 105)
        XCTAssertEqual(result.summary.failedTests, 5)
    }

    /// Tests combined counts with Swift Testing parallel output + XCTest
    /// Parallel output uses [N/M] Testing format which sets parallelTestsTotalCount
    func testCombinedParallelSwiftTestingAndXCTest() {
        let parser = OutputParser()
        let input = """
            Executed 50 tests, with 0 failures (0 unexpected) in 1.0 (1.1) seconds
            [1/20] Testing MyModule.TestClass/testMethod1
            [2/20] Testing MyModule.TestClass/testMethod2
            [20/20] Testing MyModule.TestClass/testMethod20
            ✓ Test "testMethod1" passed after 0.001 seconds.
            􁁛  Test run with 20 tests in 3 suites passed after 0.5 seconds.
            """

        let result = parser.parse(input: input)

        // XCTest: 50 tests from summary line
        // Swift Testing: 20 tests from parallel count (not summary, which would also be 20)
        // Combined: 50 + 20 = 70 passed, 0 failed
        XCTAssertEqual(result.summary.passedTests, 70)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    /// Tests that test_time is accumulated correctly when both XCTest and Swift Testing are present
    /// Regression test for fix where test times are summed across multiple test bundles
    func testCombinedTestTimeAccumulation() {
        let parser = OutputParser()
        let input = """
            Executed 100 tests, with 0 failures (0 unexpected) in 2.500 (2.600) seconds
            􁁛  Test run with 50 tests in 5 suites passed after 1.500 seconds.
            """

        let result = parser.parse(input: input)

        // XCTest: 2.500 seconds + Swift Testing: 1.500 seconds = 4.000 seconds total
        XCTAssertEqual(result.summary.testTime, "4.000s")
        // Also verify counts are correct
        XCTAssertEqual(result.summary.passedTests, 150)
    }

    func testSwiftCompilerVisualErrorLinesAreFiltered() {
        let parser = OutputParser()
        // Swift compiler outputs each error twice:
        // 1. Main error line with file:line:column
        // 2. Visual caret line with pipe and backtick
        // We should only capture the first one
        let input = """
            /Users/test/project/Tests/TestFile.swift:16:34: error: missing argument for parameter 'fragments' in call
             14 |             kind: "class",
             15 |             language: "swift",
             16 |             structuredContent: []
                |                                  `- error: missing argument for parameter 'fragments' in call
             17 |         )
             18 |
            """

        let result = parser.parse(input: input)

        // Should only have 1 error (not 2), and it should have file/line info
        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "/Users/test/project/Tests/TestFile.swift")
        XCTAssertEqual(result.errors[0].line, 16)
        XCTAssertEqual(result.errors[0].message, "missing argument for parameter 'fragments' in call")
    }

    func testLargeRealWorldBuildOutput() throws {
        let parser = OutputParser()

        let fixtureURL = Bundle.module.url(forResource: "build", withExtension: "txt")!
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        // This is a large successful build output (2.6MB, 8000+ lines)
        // Test that it parses without hanging and completes in reasonable time
        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testParseWarning() {
        let parser = OutputParser()
        let input = """
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].file, "AppDelegate.swift")
        XCTAssertEqual(result.warnings[0].line, 67)
        XCTAssertEqual(result.warnings[0].message, "unused variable 'config'")
    }

    func testParseMultipleWarnings() {
        let parser = OutputParser()
        let input = """
            UserService.swift:45:12: warning: variable 'temp' was never used
            NetworkManager.swift:23:5: warning: initialization of immutable value 'data' was never used
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.warnings, 3)
        XCTAssertEqual(result.warnings.count, 3)
    }

    func testParseErrorsAndWarnings() {
        let parser = OutputParser()
        let input = """
            UserService.swift:45:12: error: cannot find 'invalidFunction' in scope
            NetworkManager.swift:23:5: warning: variable 'temp' was never used
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.warnings, 2)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.warnings.count, 2)
    }

    // MARK: - Deduplication Tests

    func testParseDuplicateWarnings() {
        let parser = OutputParser()
        let input = """
            /path/to/File.swift:10:5: warning: unused variable 'x'
            /path/to/File.swift:10:5: warning: unused variable 'x'
            /path/to/File.swift:10:5: warning: unused variable 'x'
            /path/to/Other.swift:20:1: warning: different warning
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.warnings, 2)  // Only 2 unique warnings
        XCTAssertEqual(result.warnings.count, 2)
    }

    // MARK: - Runtime Warning Tests

    func testParseSwiftUIEnvironmentWarning() {
        let parser = OutputParser()
        let input =
            "/Users/test/Project/Sources/View.swift:42 Accessing Environment<Bool>'s value outside of being installed on a View. This will always read the default value and will not update."

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].file, "/Users/test/Project/Sources/View.swift")
        XCTAssertEqual(result.warnings[0].line, 42)
        XCTAssertEqual(result.warnings[0].type, .swiftui)
        XCTAssertTrue(result.warnings[0].message.contains("Accessing Environment"))
    }

    func testParseSwiftUIPublishingChangesWarning() {
        let parser = OutputParser()
        let input =
            "/path/to/ViewModel.swift:100 Publishing changes from background threads is not allowed; make sure to publish values from the main thread."

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings[0].type, .swiftui)
        XCTAssertTrue(result.warnings[0].message.contains("Publishing changes from background"))
    }

    func testParseSwiftUIModifyingStateWarning() {
        let parser = OutputParser()
        let input = "/path/to/View.swift:50 Modifying state during view update, this will cause undefined behavior."

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings[0].type, .swiftui)
    }

    func testParseSwiftUIStateObjectWrappedValueWarning() {
        let parser = OutputParser()
        let input =
            "/path/to/View.swift:30 StateObject's wrappedValue should only be accessed after the property has been installed on a View."

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings[0].type, .swiftui)
        XCTAssertTrue(result.warnings[0].message.contains("StateObject's wrappedValue"))
    }

    func testParseCustomRuntimeWarning() {
        let parser = OutputParser()
        let input = "/path/to/Custom.swift:25 Custom warning from swift-issue-reporting library"

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings[0].file, "/path/to/Custom.swift")
        XCTAssertEqual(result.warnings[0].line, 25)
        XCTAssertEqual(result.warnings[0].type, .runtime)
        XCTAssertEqual(result.warnings[0].message, "Custom warning from swift-issue-reporting library")
    }

    func testCompileWarningHasCompileType() {
        let parser = OutputParser()
        let input = "/path/to/File.swift:10:5: warning: unused variable 'x'"

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings[0].type, .compile)
    }

    func testMixedCompileAndRuntimeWarnings() {
        let parser = OutputParser()
        let input = """
            /path/to/File.swift:10:5: warning: unused variable 'x'
            /path/to/View.swift:42 Accessing Environment<Bool>'s value outside of being installed on a View.
            /path/to/Custom.swift:25 Custom runtime warning message
            """

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 3)
        XCTAssertEqual(result.warnings.count, 3)

        // Check types
        let compileWarnings = result.warnings.filter { $0.type == .compile }
        let swiftuiWarnings = result.warnings.filter { $0.type == .swiftui }
        let runtimeWarnings = result.warnings.filter { $0.type == .runtime }

        XCTAssertEqual(compileWarnings.count, 1)
        XCTAssertEqual(swiftuiWarnings.count, 1)
        XCTAssertEqual(runtimeWarnings.count, 1)
    }

    func testRuntimeWarningDeduplication() {
        let parser = OutputParser()
        let input = """
            /path/to/View.swift:42 Accessing Environment<Bool>'s value outside of being installed on a View.
            /path/to/View.swift:42 Accessing Environment<Bool>'s value outside of being installed on a View.
            /path/to/Other.swift:10 Different runtime warning
            """

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 2)  // Only 2 unique warnings
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testRuntimeWarningNotParsedForCompileWarningFormat() {
        let parser = OutputParser()
        // This has `: warning:` so should be parsed as compile warning, not runtime
        let input = "/path/to/File.swift:10: warning: some warning message"

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].type, .compile)
    }

    func testRuntimeWarningJSONEncoding() throws {
        let parser = OutputParser()
        let input = "/path/to/View.swift:42 Accessing Environment<Bool>'s value outside of being installed on a View."

        let result = parser.parse(input: input, printWarnings: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(result)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"type\":\"swiftui\""))
    }

    func testParseDuplicateErrors() {
        let parser = OutputParser()
        let input = """
            /path/to/File.swift:10:5: error: use of undeclared identifier
            /path/to/File.swift:10:5: error: use of undeclared identifier
            /path/to/Other.swift:20:1: error: different error
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 2)  // Only 2 unique errors
        XCTAssertEqual(result.errors.count, 2)
    }

    func testParseDuplicateLinkerErrors() {
        let parser = OutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  ViewController.o in main.o
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  ViewController.o in main.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.linkerErrors, 1)  // Only 1 unique linker error
        XCTAssertEqual(result.linkerErrors.count, 1)
    }

    func testPrintWarningsFlagFalse() {
        let parser = OutputParser()
        let input = """
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input, printWarnings: false)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.printWarnings, false)

        // Encode to JSON and verify warnings are not included
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("\"warnings\":["))
        XCTAssertTrue(jsonString.contains("\"warnings\":1"))  // Summary should still show count
    }

    func testPrintWarningsFlagTrue() {
        let parser = OutputParser()
        let input = """
            AppDelegate.swift:67:8: warning: unused variable 'config'
            """

        let result = parser.parse(input: input, printWarnings: true)

        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.printWarnings, true)

        // Encode to JSON and verify warnings are included
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"warnings\":["))
        XCTAssertTrue(jsonString.contains("unused variable"))
    }

    func testSwiftTestingSummaryPassed() {
        let parser = OutputParser()
        let input = """
            ✓ Test "LocaleUrlTag handles deep paths correctly in default locale" passed after 0.022 seconds.
            ✓ Test "LocaleUrlTag generates correct URLs in non-default locale (en)" passed after 0.022 seconds.
            ✓ Test "LocaleUrlTag handles deep paths correctly in non-default locale" passed after 0.023 seconds.
            Test run with 23 tests in 5 suites passed after 0.031 seconds.
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 23)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertEqual(result.summary.testTime, "0.031s")
    }

    func testRealWorldSwiftTestingOutput() throws {
        let parser = OutputParser()

        let fixtureURL = Bundle.module.url(forResource: "swift-testing-output", withExtension: "txt")!
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        // This is real Swift Testing output with 23 passed tests
        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertEqual(result.summary.passedTests, 23)
        XCTAssertEqual(result.summary.testTime, "0.031s")
    }

    func testJSONLikeLinesAreFiltered() {
        let parser = OutputParser()
        // This simulates the actual problematic case: Swift compiler warning/note lines
        // with string interpolation patterns that were incorrectly parsed as errors
        let input = """
            /Path/To/File.swift:79:41: warning: string interpolation produces a debug description for an optional value; did you mean to make this explicit?

                return "Encryption error: \\(message)"

                                            ^~~~~~~

            /Path/To/File.swift:79:41: note: use 'String(describing:)' to silence this warning

                return "Encryption error: \\(message)"

                                            ^~~~~~~

                                            String(describing:  )

            /Path/To/File.swift:79:41: note: provide a default value to avoid this warning

                return "Encryption error: \\(message)"

                                            ^~~~~~~

                                                    ?? <#default value#>
            """

        let result = parser.parse(input: input)

        // Should parse the warning correctly, but NOT parse the note lines as errors
        // The note lines contain \\(message) pattern which shouldn't be treated as error messages
        XCTAssertEqual(result.status, "success")  // No actual errors, just warnings
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.warnings, 1)  // Should parse the warning
        XCTAssertEqual(result.errors.count, 0)
    }

    func testJSONLikeLinesWithActualErrors() {
        let parser = OutputParser()
        // Mix of compiler note lines (with interpolation patterns) and actual errors
        // Should only parse the real errors, not the note lines
        let input = """
            /Path/To/File.swift:79:41: note: use 'String(describing:)' to silence this warning
                return "Encryption error: \\(message)"
                                            ^~~~~~~
            main.swift:15:5: error: use of undeclared identifier 'unknown'
            """

        let result = parser.parse(input: input)

        // Should parse the real error but ignore note lines with interpolation patterns
        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "main.swift")
        XCTAssertEqual(result.errors[0].line, 15)
        XCTAssertEqual(result.errors[0].message, "use of undeclared identifier 'unknown'")
    }

    // MARK: - Swift Test Parallel Tests

    func testSwiftTestParallelAllPassed() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete! (5.00s)
            [1/20] Testing ModuleA.TestClassA/testMethod1
            [2/20] Testing ModuleA.TestClassA/testMethod2
            [3/20] Testing ModuleA.TestClassA/testMethod3
            [4/20] Testing ModuleA.TestClassB/testMethod1
            [5/20] Testing ModuleA.TestClassB/testMethod2
            [6/20] Testing ModuleB.TestClassC/testMethod1
            [7/20] Testing ModuleB.TestClassC/testMethod2
            [8/20] Testing ModuleB.TestClassC/testMethod3
            [9/20] Testing ModuleB.TestClassD/testMethod1
            [10/20] Testing ModuleB.TestClassD/testMethod2
            [11/20] Testing ModuleC.TestClassE/testMethod1
            [12/20] Testing ModuleC.TestClassE/testMethod2
            [13/20] Testing ModuleC.TestClassE/testMethod3
            [14/20] Testing ModuleC.TestClassE/testMethod4
            [15/20] Testing ModuleC.TestClassF/testMethod1
            [16/20] Testing ModuleC.TestClassF/testMethod2
            [17/20] Testing ModuleD.TestClassG/testMethod1
            [18/20] Testing ModuleD.TestClassG/testMethod2
            [19/20] Testing ModuleD.TestClassG/testMethod3
            [20/20] Testing ModuleD.TestClassH/testMethod1
            ◇ Test run started.
            ↳ Testing Library Version: 6.0.3
            ◇ Suite "TestClassG" started.
            ✔ Test "testMethod1" passed after 0.005 seconds.
            ✔ Test "testMethod2" passed after 0.004 seconds.
            ✔ Test "testMethod3" passed after 0.003 seconds.
            ✔ Suite "TestClassG" passed after 0.010 seconds.
            ✔ Test run with 4 tests passed after 0.015 seconds.
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 20)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testSwiftTestParallelWithFailure() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete! (5.00s)
            [1/10] Testing ModuleA.TestClassA/testMethod1
            [2/10] Testing ModuleA.TestClassA/testMethod2
            [3/10] Testing ModuleA.TestClassA/testMethod3
            [4/10] Testing ModuleA.TestClassB/testMethod1
            [5/10] Testing ModuleA.TestClassB/testMethod2
            [6/10] Testing ModuleB.TestClassC/testMethod1
            [7/10] Testing ModuleB.TestClassC/testMethod2
            [8/10] Testing ModuleB.TestClassC/testMethod3
            [9/10] Testing ModuleB.TestClassD/testMethod1
            [10/10] Testing ModuleB.TestClassD/testMethod2
            ◇ Test run started.
            ↳ Testing Library Version: 6.0.3
            ◇ Suite "TestClassD" started.
            ✔ Test "testMethod1" passed after 0.005 seconds.
            ✘ Test "testMethod2" failed after 0.010 seconds.
            ✘ Test run with 1 test failed, 1 test passed after 0.020 seconds.
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.passedTests, 9)
        XCTAssertEqual(result.summary.testTime, "0.020s")
    }

    func testSwiftTestParallelLargeCount() {
        let parser = OutputParser()
        // Simulate a large test run with 1306 tests
        var input = "Building for debugging...\nBuild complete! (5.00s)\n"
        for i in 1 ... 1306 {
            input += "[\(i)/1306] Testing Module.TestClass/testMethod\(i)\n"
        }
        input += "◇ Test run started.\n"
        input += "✔ Test run with 82 tests passed after 0.170 seconds.\n"

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 1306)
        XCTAssertEqual(result.summary.failedTests, 0)
    }

    func testSwiftTestParallelPrioritizesSchedulingCount() {
        let parser = OutputParser()
        // When both [N/TOTAL] and "Test run with X tests passed" are present,
        // the [N/TOTAL] count should take priority
        let input = """
            [1/100] Testing Module.TestClass/testMethod1
            [100/100] Testing Module.TestClass/testMethod100
            ◇ Test run started.
            ✔ Test run with 5 tests passed after 0.015 seconds.
            """

        let result = parser.parse(input: input)

        // Should use 100 from [N/TOTAL], not 5 from summary
        XCTAssertEqual(result.summary.passedTests, 100)
    }

    func testSwiftTestingFailureSummaryParsing() {
        let parser = OutputParser()
        let input = """
            ◇ Test run started.
            ✘ Test "testMethod" failed after 0.010 seconds.
            ✘ Test run with 3 tests failed, 7 tests passed after 0.050 seconds.
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        // Without [N/TOTAL] lines, should use summary: 3 failed + 7 passed = 10 total
        // passed = 10 - 3 = 7
        XCTAssertEqual(result.summary.passedTests, 7)
        XCTAssertEqual(result.summary.testTime, "0.050s")
    }

    // MARK: - Test Duration Parsing

    func testParseDurationFromXCTestPassed() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testExample' passed (0.123 seconds).
            Test Case 'SampleTests.testSlowTest' passed (2.567 seconds).
            """

        let result = parser.parse(input: input, slowThreshold: 1.0)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 2)
        XCTAssertEqual(result.slowTests.count, 1)
        XCTAssertTrue(result.slowTests.contains { $0.test == "SampleTests.testSlowTest" })
        XCTAssertFalse(result.slowTests.contains { $0.test == "SampleTests.testExample" })
        XCTAssertEqual(result.slowTests[0].duration, 2.567)
    }

    func testParseDurationFromXCTestFailed() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testSlowFailing' failed (3.456 seconds).
            """

        let result = parser.parse(input: input, slowThreshold: 1.0)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests[0].duration, 3.456)
        XCTAssertEqual(result.slowTests.count, 1)
        XCTAssertTrue(result.slowTests.contains { $0.test == "SampleTests.testSlowFailing" })
        XCTAssertEqual(result.slowTests[0].duration, 3.456)
    }

    func testParseDurationFromSwiftTestingPassed() {
        let parser = OutputParser()
        let input = """
            ✓ Test "testQuickOperation" passed after 0.022 seconds.
            ✓ Test "testSlowNetworkCall" passed after 5.123 seconds.
            """

        let result = parser.parse(input: input, slowThreshold: 1.0)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.passedTests, 2)
        XCTAssertEqual(result.slowTests.count, 1)
        XCTAssertTrue(result.slowTests.contains { $0.test == "testSlowNetworkCall" })
        XCTAssertEqual(result.slowTests[0].duration, 5.123)
    }

    func testParseDurationFromSwiftTestingFailed() {
        let parser = OutputParser()
        let input = """
            ✘ Test "testSlowFailure" failed after 2.345 seconds with 1 issue.
            """

        let result = parser.parse(input: input, slowThreshold: 1.0)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests[0].duration, 2.345)
        XCTAssertEqual(result.slowTests.count, 1)
    }

    func testSlowThresholdNotSet() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testSlowTest' passed (10.0 seconds).
            """

        // No slowThreshold set - should not detect slow tests
        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertTrue(result.slowTests.isEmpty)
        XCTAssertNil(result.summary.slowTests)
    }

    func testSlowThresholdCustomValue() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testFast' passed (0.4 seconds).
            Test Case 'SampleTests.testMedium' passed (0.6 seconds).
            Test Case 'SampleTests.testSlow' passed (1.2 seconds).
            """

        let result = parser.parse(input: input, slowThreshold: 0.5)

        XCTAssertEqual(result.slowTests.count, 2)
        XCTAssertTrue(result.slowTests.contains { $0.test == "SampleTests.testMedium" })
        XCTAssertTrue(result.slowTests.contains { $0.test == "SampleTests.testSlow" })
        XCTAssertFalse(result.slowTests.contains { $0.test == "SampleTests.testFast" })
    }

    // MARK: - Flaky Test Detection

    func testFlakyTestDetection() {
        let parser = OutputParser()
        // Simulate a test that both passed and failed in the same run (flaky)
        let input = """
            Test Case 'SampleTests.testFlakyTest' passed (0.1 seconds).
            Test Case 'SampleTests.testFlakyTest' failed (0.2 seconds).
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.flakyTests.count, 1)
        XCTAssertTrue(result.flakyTests.contains("SampleTests.testFlakyTest"))
        XCTAssertEqual(result.summary.flakyTests, 1)
    }

    func testNoFlakyTestsWhenAllPass() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testA' passed (0.1 seconds).
            Test Case 'SampleTests.testB' passed (0.2 seconds).
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertTrue(result.flakyTests.isEmpty)
        XCTAssertNil(result.summary.flakyTests)
    }

    func testNoFlakyTestsWhenDifferentTestsFail() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testA' passed (0.1 seconds).
            Test Case 'SampleTests.testB' failed (0.2 seconds).
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertTrue(result.flakyTests.isEmpty)
        XCTAssertNil(result.summary.flakyTests)
    }

    func testDurationInFailedTestStruct() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testWithDuration' failed (1.234 seconds).
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.failedTests.count, 1)
        XCTAssertEqual(result.failedTests[0].test, "SampleTests.testWithDuration")
        XCTAssertEqual(result.failedTests[0].duration, 1.234)
    }

    func testSlowAndFlakyTestsCombined() {
        let parser = OutputParser()
        let input = """
            Test Case 'SampleTests.testFast' passed (0.1 seconds).
            Test Case 'SampleTests.testSlow' passed (5.0 seconds).
            Test Case 'SampleTests.testFlakyAndSlow' passed (3.0 seconds).
            Test Case 'SampleTests.testFlakyAndSlow' failed (2.5 seconds).
            """

        let result = parser.parse(input: input, slowThreshold: 1.0)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.slowTests.count, 2)
        XCTAssertTrue(result.slowTests.contains { $0.test == "SampleTests.testSlow" })
        XCTAssertTrue(result.slowTests.contains { $0.test == "SampleTests.testFlakyAndSlow" })
        XCTAssertEqual(result.flakyTests.count, 1)
        XCTAssertTrue(result.flakyTests.contains("SampleTests.testFlakyAndSlow"))
        XCTAssertEqual(result.summary.slowTests, 2)
        XCTAssertEqual(result.summary.flakyTests, 1)
    }

    // MARK: - Executable Parsing Tests

    func testParseExecutable() {
        let parser = OutputParser()
        let input = """
            RegisterWithLaunchServices /Users/gustavoambrozio/Library/Developer/Xcode/DerivedData/ClaudeSettings-adehczsnoaxfyihgllrkwplhsetn/Build/Products/Debug/ClaudeSettings.app (in target 'ClaudeSettings' from project 'ClaudeSettings')
            """

        let result = parser.parse(input: input, printExecutables: true)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.executables.count, 1)
        XCTAssertEqual(
            result.executables[0].path,
            "/Users/gustavoambrozio/Library/Developer/Xcode/DerivedData/ClaudeSettings-adehczsnoaxfyihgllrkwplhsetn/Build/Products/Debug/ClaudeSettings.app"
        )
        XCTAssertEqual(result.executables[0].name, "ClaudeSettings.app")
        XCTAssertEqual(result.executables[0].target, "ClaudeSettings")
        XCTAssertEqual(result.summary.executables, 1)
    }

    func testParseMultipleExecutables() {
        let parser = OutputParser()
        let input = """
            RegisterWithLaunchServices /path/to/App1.app (in target 'App1' from project 'MyProject')
            Building for debugging...
            RegisterWithLaunchServices /path/to/App2.app (in target 'App2' from project 'MyProject')
            """

        let result = parser.parse(input: input, printExecutables: true)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.executables.count, 2)
        XCTAssertEqual(result.executables[0].name, "App1.app")
        XCTAssertEqual(result.executables[0].target, "App1")
        XCTAssertEqual(result.executables[1].name, "App2.app")
        XCTAssertEqual(result.executables[1].target, "App2")
        XCTAssertEqual(result.summary.executables, 2)
    }

    func testExecutablesNotIncludedWhenFlagFalse() {
        let parser = OutputParser()
        let input = """
            RegisterWithLaunchServices /path/to/App.app (in target 'App' from project 'MyProject')
            """

        let result = parser.parse(input: input, printExecutables: false)

        // Executables are still parsed but not included in output
        XCTAssertEqual(result.executables.count, 1)
        XCTAssertEqual(result.printExecutables, false)
        XCTAssertNil(result.summary.executables)

        // Encode to JSON and verify executables are not included
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("\"executables\":["))
    }

    func testExecutablesIncludedInJSONWhenFlagTrue() {
        let parser = OutputParser()
        let input = """
            RegisterWithLaunchServices /path/to/App.app (in target 'App' from project 'MyProject')
            """

        let result = parser.parse(input: input, printExecutables: true)

        XCTAssertEqual(result.executables.count, 1)
        XCTAssertEqual(result.printExecutables, true)

        // Encode to JSON and verify executables are included
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"executables\":["))
        XCTAssertTrue(jsonString.contains("App.app"))
    }

    func testNoExecutablesInOutput() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """

        let result = parser.parse(input: input, printExecutables: true)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.executables.count, 0)
        XCTAssertNil(result.summary.executables)
    }

    func testExecutableDeduplicationByPath() {
        let parser = OutputParser()
        // Same app registered multiple times (can happen in incremental builds)
        let input = """
            RegisterWithLaunchServices /Users/dev/DerivedData/MyApp/Build/Products/Debug/MyApp.app (in target 'MyApp' from project 'MyApp')
            RegisterWithLaunchServices /Users/dev/DerivedData/MyApp/Build/Products/Debug/MyApp.app (in target 'MyApp' from project 'MyApp')
            RegisterWithLaunchServices /Users/dev/DerivedData/MyApp/Build/Products/Debug/MyApp.app (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printExecutables: true)

        XCTAssertEqual(result.executables.count, 1, "Duplicate executables should be deduplicated by path")
        XCTAssertEqual(result.executables[0].name, "MyApp.app")
        XCTAssertEqual(result.summary.executables, 1)
    }

    // MARK: - TEST FAILED Parsing Tests

    func testParseTestFailed() {
        let parser = OutputParser()
        let input = """
            Test Suite 'All tests' started at 2026-01-15 12:23:33.095.
            Test Suite 'TestProjectTests.xctest' started at 2026-01-15 12:23:33.097.
            Test Suite 'TestProjectTests' started at 2026-01-15 12:23:33.097.
            Test Case '-[TestProjectTests.TestProjectTests testExample]' started.
            TestProjectTests/TestProjectTests.swift:5: Fatal error
            Restarting after unexpected exit, crash, or test timeout
            Test Suite 'Selected tests' started at 2026-01-15 12:23:54.815.
            Test Suite 'TestProjectTests' passed at 2026-01-15 12:23:54.816.
            ** TEST FAILED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
    }

    func testParseTestFailedWithNoIndividualFailures() {
        let parser = OutputParser()
        let input = """
            Building for testing...
            Build complete!
            Testing started
            ** TEST FAILED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.failedTests.count, 0)
    }

    func testParseTestSucceeded() {
        let parser = OutputParser()
        let input = """
            Test Suite 'All tests' started at 2026-01-15 12:23:33.095.
            Test Case 'MyTests.testExample' passed (0.001 seconds).
            Executed 1 test, with 0 failures in 0.001 seconds
            ** TEST SUCCEEDED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
    }

    // MARK: - Fatal Error Parsing Tests

    func testParseFatalErrorWithoutMessage() {
        let parser = OutputParser()
        let input = "TestProjectTests/TestProjectTests.swift:5: Fatal error"

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "TestProjectTests/TestProjectTests.swift")
        XCTAssertEqual(result.errors[0].line, 5)
        XCTAssertEqual(result.errors[0].message, "Fatal error")
    }

    func testParseFatalErrorWithAbsolutePath() {
        let parser = OutputParser()
        let input = "/Users/dev/Project/Tests/MyTests.swift:42: Fatal error"

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "/Users/dev/Project/Tests/MyTests.swift")
        XCTAssertEqual(result.errors[0].line, 42)
        XCTAssertEqual(result.errors[0].message, "Fatal error")
    }

    func testParseFatalErrorSkipsXctestLogLine() {
        let parser = OutputParser()
        let input =
            "2026-01-15 12:23:33.104297+0500 xctest[84150:24837354] TestProjectTests/TestProjectTests.swift:5: Fatal error"

        let result = parser.parse(input: input)

        XCTAssertEqual(result.errors.count, 0)
    }

    func testParseFatalErrorInTestCrash() {
        let parser = OutputParser()
        let input = """
            Test Case '-[TestProjectTests.TestProjectTests testExample]' started.
            TestProjectTests/TestProjectTests.swift:5: Fatal error
            Restarting after unexpected exit, crash, or test timeout
            ** TEST FAILED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "TestProjectTests/TestProjectTests.swift")
        XCTAssertEqual(result.errors[0].line, 5)
        XCTAssertEqual(result.errors[0].message, "Fatal error")
    }
}
