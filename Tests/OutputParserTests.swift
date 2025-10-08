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
}
