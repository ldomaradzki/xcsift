import XCTest
@testable import xcsift

final class OutputParserTests: XCTestCase {
    
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
    
    func testDeprecatedFunction() {
        let parser = OutputParser()
        let _ = parser.deprecatedFunction()
        parser.functionWithUnusedVariable()
    }
    
    func testFirstFailingTest() {
        XCTAssertEqual("expected", "actual", "This test should fail - values don't match")
    }
    
    func testSecondFailingTest() {
        XCTAssertTrue(false, "This test should fail - asserting false")
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
        XCTAssertEqual(result.summary.buildTime, "5.017")
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

        // Load the real-world build.txt fixture
        let fixtureURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("build.txt")

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
        XCTAssertEqual(result.summary.buildTime, "0.031")
    }

    func testRealWorldSwiftTestingOutput() throws {
        let parser = OutputParser()

        // Load the real-world Swift Testing output fixture
        let fixtureURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("swift-testing-output.txt")

        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        // This is real Swift Testing output with 23 passed tests
        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.failedTests, 0)
        XCTAssertEqual(result.summary.passedTests, 23)
        XCTAssertEqual(result.summary.buildTime, "0.031")
    }
    
    func testJSONLikeLinesAreFiltered() {
        let parser = OutputParser()
        // This simulates the case where JSON output contains "error:" but shouldn't be parsed as an error
        let input = """
        {
          "errors" : [
            {
              "message" : "\\(message)\""
            },
            {
              "message" : "\\(message)\""
            },
            {
              "message" : "\\(message)\""
            }
          ],
          "status" : "failed",
          "summary" : {
            "warnings" : 96,
            "failed_tests" : 0,
            "errors" : 3
          }
        }
        """
        
        let result = parser.parse(input: input)
        
        // Should not parse JSON lines as errors - this should be a successful parse with no errors
        // (since there are no actual build errors, just JSON structure)
        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.errors.count, 0)
    }
    
    func testJSONLikeLinesWithActualErrors() {
        let parser = OutputParser()
        // Mix of JSON-like lines and actual errors - should only parse the real errors
        let input = """
        {
          "errors" : [
            {
              "message" : "\\(message)\""
            }
          ]
        }
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        """
        
        let result = parser.parse(input: input)
        
        // Should parse the real error but ignore JSON lines
        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors[0].file, "main.swift")
        XCTAssertEqual(result.errors[0].line, 15)
        XCTAssertEqual(result.errors[0].message, "use of undeclared identifier 'unknown'")
    }
}
