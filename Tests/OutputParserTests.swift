import XCTest
import TOONEncoder
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

        let fixtureURL = Bundle.module.url(forResource: "swift-testing-output", withExtension: "txt")!
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
        XCTAssertEqual(result.status, "success") // No actual errors, just warnings
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.warnings, 1) // Should parse the warning
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

    func testCodeCoverageDataStructures() {
        // Test that coverage data structures can be created and encoded
        let fileCoverage = FileCoverage(
            path: "/path/to/file.swift",
            name: "file.swift",
            lineCoverage: 85.5,
            coveredLines: 50,
            executableLines: 58
        )

        let coverage = CodeCoverage(
            lineCoverage: 75.0,
            files: [fileCoverage]
        )

        XCTAssertEqual(coverage.lineCoverage, 75.0)
        XCTAssertEqual(coverage.files.count, 1)
        XCTAssertEqual(coverage.files[0].name, "file.swift")
        XCTAssertEqual(coverage.files[0].lineCoverage, 85.5)
    }

    func testBuildResultWithCoverage() {
        let fileCoverage = FileCoverage(
            path: "/path/to/file.swift",
            name: "file.swift",
            lineCoverage: 85.5,
            coveredLines: 50,
            executableLines: 58
        )

        let coverage = CodeCoverage(
            lineCoverage: 75.0,
            files: [fileCoverage]
        )

        let parser = OutputParser()
        let input = """
        Building for debugging...
        Build complete!
        """

        let result = parser.parse(input: input, coverage: coverage, printCoverageDetails: true)

        XCTAssertEqual(result.status, "success")
        XCTAssertNotNil(result.coverage)
        XCTAssertEqual(result.coverage?.lineCoverage, 75.0)
        XCTAssertEqual(result.summary.coveragePercent, 75.0)

        // Encode to JSON and verify coverage is included in details mode
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("coverage"))
        XCTAssertTrue(jsonString.contains("line_coverage"))
        XCTAssertTrue(jsonString.contains("coverage_percent"))
    }

    func testBuildResultWithoutCoverage() {
        let parser = OutputParser()
        let input = """
        Building for debugging...
        Build complete!
        """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertNil(result.coverage)
        XCTAssertNil(result.summary.coveragePercent)

        // Encode to JSON and verify coverage is not included
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("\"coverage\""))
    }

    func testParseCoverageFromNonExistentPath() {
        let coverage = OutputParser.parseCoverageFromPath("/nonexistent/path")
        _ = coverage
    }

    func testCoverageJSONEncoding() {
        let fileCoverage = FileCoverage(
            path: "/Users/test/project/Sources/main.swift",
            name: "main.swift",
            lineCoverage: 92.5,
            coveredLines: 37,
            executableLines: 40
        )

        let coverage = CodeCoverage(
            lineCoverage: 85.0,
            files: [fileCoverage]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try! encoder.encode(coverage)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Verify JSON structure
        XCTAssertTrue(jsonString.contains("\"line_coverage\""))
        XCTAssertTrue(jsonString.contains("85"))
        XCTAssertTrue(jsonString.contains("\"files\""))
        XCTAssertTrue(jsonString.contains("main.swift"))
        XCTAssertTrue(jsonString.contains("\"covered_lines\""))
        XCTAssertTrue(jsonString.contains("\"executable_lines\""))
    }

    func testParseXcodebuildCoverageFormat() throws {
        // Create a temporary xcodebuild-format coverage file
        let xcodebuildJSON = """
        {
          "targets": [{
            "name": "MyTarget",
            "files": [
              {
                "path": "/path/to/main.swift",
                "lineCoverage": 0.90,
                "coveredLines": 45,
                "executableLines": 50
              },
              {
                "path": "/path/to/helper.swift",
                "lineCoverage": 0.80,
                "coveredLines": 40,
                "executableLines": 50
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("xcodebuild-coverage.json")
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Parse the xcodebuild format
        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.files.count, 2)

        // Check overall coverage: (45+40)/(50+50) = 85/100 = 85%
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 85.0, accuracy: 0.1)

        // Check individual files
        let mainFile = coverage?.files.first(where: { $0.name == "main.swift" })
        XCTAssertNotNil(mainFile)
        XCTAssertEqual(mainFile?.lineCoverage ?? 0, 90.0, accuracy: 0.1)
        XCTAssertEqual(mainFile?.coveredLines ?? 0, 45)
        XCTAssertEqual(mainFile?.executableLines, 50)
    }

    func testParseSPMCoverageFormat() throws {
        // Create a temporary SPM-format coverage file
        let spmJSON = """
        {
          "data": [{
            "files": [
              {
                "filename": "/path/to/main.swift",
                "summary": {
                  "lines": {
                    "covered": 45,
                    "count": 50
                  }
                }
              },
              {
                "filename": "/path/to/helper.swift",
                "summary": {
                  "lines": {
                    "covered": 40,
                    "count": 50
                  }
                }
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("spm-coverage.json")
        try spmJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Parse the SPM format
        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.files.count, 2)

        // Check overall coverage: (45+40)/(50+50) = 85/100 = 85%
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 85.0, accuracy: 0.1)

        // Check individual files
        let mainFile = coverage?.files.first(where: { $0.name == "main.swift" })
        XCTAssertNotNil(mainFile)
        XCTAssertEqual(mainFile?.lineCoverage ?? 0, 90.0, accuracy: 0.1)
        XCTAssertEqual(mainFile?.coveredLines ?? 0, 45)
        XCTAssertEqual(mainFile?.executableLines, 50)
    }

    func testXcodebuildCoverageWithPercentageFormat() throws {
        // Test xcodebuild format with percentage (85.0) instead of decimal (0.85)
        let xcodebuildJSON = """
        {
          "targets": [{
            "files": [
              {
                "path": "/path/to/main.swift",
                "lineCoverage": 90.0,
                "coveredLines": 45,
                "executableLines": 50
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("xcodebuild-percent.json")
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 90.0, accuracy: 0.1)
    }

    func testParseEmptyPathTriggersAutoDetection() {
        let coverage = OutputParser.parseCoverageFromPath("")
        _ = coverage
    }

    func testParseExplicitPathThatExists() throws {
        let spmJSON = """
        {
          "data": [{
            "files": [
              {
                "filename": "/path/to/test.swift",
                "summary": {
                  "lines": {
                    "covered": 10,
                    "count": 20
                  }
                }
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("explicit-coverage.json")
        try spmJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 50.0, accuracy: 0.1)
    }

    func testParseXCResultPathDirectly() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let xcresultPath = tempDir.appendingPathComponent("test.xcresult")

        try FileManager.default.createDirectory(at: xcresultPath, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: xcresultPath)
        }

        let coverage = OutputParser.parseCoverageFromPath(xcresultPath.path)
        _ = coverage
    }

    func testMultipleFilesInCoverageCalculation() throws {
        let spmJSON = """
        {
          "data": [{
            "files": [
              {
                "filename": "/path/to/file1.swift",
                "summary": {
                  "lines": {
                    "covered": 80,
                    "count": 100
                  }
                }
              },
              {
                "filename": "/path/to/file2.swift",
                "summary": {
                  "lines": {
                    "covered": 40,
                    "count": 100
                  }
                }
              },
              {
                "filename": "/path/to/file3.swift",
                "summary": {
                  "lines": {
                    "covered": 60,
                    "count": 100
                  }
                }
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("multi-file-coverage.json")
        try spmJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.files.count, 3)

        // Overall: (80+40+60)/(100+100+100) = 180/300 = 60%
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 60.0, accuracy: 0.1)
    }

    func testInvalidJSONReturnsNil() throws {
        let invalidJSON = """
        {
          "invalid": "format"
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("invalid-coverage.json")
        try invalidJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNil(coverage)
    }

    func testEmptyFilesArrayReturnsNil() throws {
        let emptyJSON = """
        {
          "data": [{
            "files": []
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("empty-coverage.json")
        try emptyJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNil(coverage)
    }

    func testXcodebuildFormatWithDecimalCoverage() throws {
        let xcodebuildJSON = """
        {
          "targets": [{
            "files": [
              {
                "path": "/path/to/main.swift",
                "lineCoverage": 0.85,
                "coveredLines": 85,
                "executableLines": 100
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("xcodebuild-decimal.json")
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 85.0, accuracy: 0.1)
    }

    func testZeroCoverageHandling() throws {
        let spmJSON = """
        {
          "data": [{
            "files": [
              {
                "filename": "/path/to/uncovered.swift",
                "summary": {
                  "lines": {
                    "covered": 0,
                    "count": 50
                  }
                }
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("zero-coverage.json")
        try spmJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.lineCoverage ?? -1, 0.0, accuracy: 0.01)
        XCTAssertEqual(coverage?.files.first?.lineCoverage ?? -1, 0.0, accuracy: 0.01)
    }

    func testFullCoverageHandling() throws {
        let spmJSON = """
        {
          "data": [{
            "files": [
              {
                "filename": "/path/to/perfect.swift",
                "summary": {
                  "lines": {
                    "covered": 100,
                    "count": 100
                  }
                }
              }
            ]
          }]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("full-coverage.json")
        try spmJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path)

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 100.0, accuracy: 0.01)
        XCTAssertEqual(coverage?.files.first?.lineCoverage ?? 0, 100.0, accuracy: 0.01)
    }

    func testExtractTestedTarget() {
        let parser = OutputParser()
        let input = """
        Test Suite 'MyAppTests.xctest' started at 2025-01-05 10:30:00.000
        Test Suite 'LoginTests' started at 2025-01-05 10:30:00.100
        """

        let target = parser.extractTestedTarget(from: input)

        XCTAssertNotNil(target)
        XCTAssertEqual(target, "MyApp")
    }

    func testExtractTestedTargetSkipsAllTests() {
        let parser = OutputParser()
        let input = """
        Test Suite 'All tests' started at 2025-01-05 10:30:00.000
        Test Suite 'SampleAppTests.xctest' started at 2025-01-05 10:30:00.100
        """

        let target = parser.extractTestedTarget(from: input)

        XCTAssertNotNil(target)
        XCTAssertEqual(target, "SampleApp")
    }

    func testExtractTestedTargetNotFound() {
        let parser = OutputParser()
        let input = """
        Building for debugging...
        Build complete!
        """

        let target = parser.extractTestedTarget(from: input)

        XCTAssertNil(target)
    }

    func testCoverageTargetFiltering() throws {
        let xcodebuildJSON = """
        {
          "targets": [
            {
              "name": "MyApp.app",
              "files": [
                {
                  "path": "/path/to/MyFile.swift",
                  "lineCoverage": 0.85,
                  "coveredLines": 85,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "OtherApp.app",
              "files": [
                {
                  "path": "/path/to/OtherFile.swift",
                  "lineCoverage": 0.50,
                  "coveredLines": 50,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("filtered-coverage.json")
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path, targetFilter: "MyApp")

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.files.count, 1)
        XCTAssertEqual(coverage?.files.first?.name, "MyFile.swift")
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 85.0, accuracy: 0.01)
    }

    func testCoverageExcludesTestBundles() throws {
        let xcodebuildJSON = """
        {
          "targets": [
            {
              "name": "MyModule.framework",
              "files": [
                {
                  "path": "/path/to/MyFile.swift",
                  "lineCoverage": 0.50,
                  "coveredLines": 50,
                  "executableLines": 100
                }
              ]
            },
            {
              "name": "MyModuleTests.xctest",
              "files": [
                {
                  "path": "/path/to/MyModuleTests.swift",
                  "lineCoverage": 1.0,
                  "coveredLines": 100,
                  "executableLines": 100
                }
              ]
            }
          ]
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("exclude-tests-coverage.json")
        try xcodebuildJSON.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let coverage = OutputParser.parseCoverageFromPath(testFile.path, targetFilter: "MyModule")

        XCTAssertNotNil(coverage)
        XCTAssertEqual(coverage?.files.count, 1)
        XCTAssertEqual(coverage?.files.first?.name, "MyFile.swift")
        XCTAssertEqual(coverage?.lineCoverage ?? 0, 50.0, accuracy: 0.01)
    }

    func testCoverageSummaryOnlyMode() throws {
        let parser = OutputParser()
        let input = "Build complete!"
        let coverage = CodeCoverage(
            lineCoverage: 75.5,
            files: [
                FileCoverage(path: "/path/to/file.swift", name: "file.swift", lineCoverage: 75.5, coveredLines: 75, executableLines: 100)
            ]
        )

        let result = parser.parse(input: input, printWarnings: false, coverage: coverage, printCoverageDetails: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"coverage_percent\""))
        XCTAssertFalse(jsonString.contains("\"line_coverage\""))
        XCTAssertFalse(jsonString.contains("\"files\""))
        XCTAssertTrue(jsonString.contains("75.5"))
    }

    func testCoverageDetailsMode() throws {
        let parser = OutputParser()
        let input = "Build complete!"
        let coverage = CodeCoverage(
            lineCoverage: 75.5,
            files: [
                FileCoverage(path: "/path/to/file.swift", name: "file.swift", lineCoverage: 75.5, coveredLines: 75, executableLines: 100)
            ]
        )

        let result = parser.parse(input: input, printWarnings: false, coverage: coverage, printCoverageDetails: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"line_coverage\""))
        XCTAssertTrue(jsonString.contains("\"files\""))
        XCTAssertTrue(jsonString.contains("\"path\""))
        XCTAssertTrue(jsonString.contains("file.swift"))
    }

    // MARK: - TOON Format Tests

    func testTOONEncoderBasic() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        """
        let result = parser.parse(input: input)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("errors[1]{"))
        XCTAssertTrue(toonString!.contains("main.swift"))
    }

    func testTOONEncoderWithWarnings() throws {
        let parser = OutputParser()
        let input = """
        Parser.swift:20:10: warning: immutable value 'result' was never used
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: success"))
        XCTAssertTrue(toonString!.contains("warnings: 2"))
        XCTAssertTrue(toonString!.contains("warnings[2]{"))
        XCTAssertTrue(toonString!.contains("Parser.swift"))
    }

    func testTOONEncoderWithErrorsAndWarnings() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        ** BUILD FAILED **
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("errors: 1"))
        XCTAssertTrue(toonString!.contains("warnings: 1"))
        XCTAssertTrue(toonString!.contains("errors[1]{file,line,message}"))
        XCTAssertTrue(toonString!.contains("warnings[1]{file,line,message}"))
    }

    func testTOONEncoderWithCoverage() throws {
        let parser = OutputParser()
        let input = "Build complete!"
        let coverage = CodeCoverage(
            lineCoverage: 85.5,
            files: [
                FileCoverage(path: "/path/to/file.swift", name: "file.swift", lineCoverage: 85.5, coveredLines: 85, executableLines: 100)
            ]
        )
        let result = parser.parse(input: input, printWarnings: false, coverage: coverage, printCoverageDetails: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("coverage_percent: 85.5"))
        XCTAssertTrue(toonString!.contains("line_coverage: 85.5"))
        XCTAssertTrue(toonString!.contains("files[1]{"))
        XCTAssertTrue(toonString!.contains("file.swift"))
    }

    func testTOONTokenEfficiency() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        Model.swift:30:15: warning: initialization of immutable value 'bar' was never used
        ** BUILD FAILED **
        """
        let result = parser.parse(input: input, printWarnings: true)

        // JSON encoding
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        let jsonData = try jsonEncoder.encode(result)
        let jsonSize = jsonData.count

        // TOON encoding
        let toonEncoder = TOONEncoder()
        toonEncoder.indent = 2
        toonEncoder.delimiter = .comma
        let toonData = try toonEncoder.encode(result)
        let toonSize = toonData.count

        // TOON should be significantly smaller (30-60% reduction)
        let reduction = Double(jsonSize - toonSize) / Double(jsonSize) * 100.0
        XCTAssertGreaterThan(reduction, 20.0, "TOON should save at least 20% tokens")
        XCTAssertLessThan(toonSize, jsonSize, "TOON output should be smaller than JSON")
    }

    func testTOONEncoderWithFailedTests() throws {
        let parser = OutputParser()
        let input = """
        Test Case 'LoginTests.testInvalidCredentials' failed (0.045 seconds).
        XCTAssertEqual failed: Expected valid login
        """
        let result = parser.parse(input: input)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: failed"))
        XCTAssertTrue(toonString!.contains("failed_tests: 2"))
        XCTAssertTrue(toonString!.contains("failed_tests[2]{"))
        XCTAssertTrue(toonString!.contains("LoginTests.testInvalidCredentials"))
    }

    func testTOONEncoderSuccessfulBuild() throws {
        let parser = OutputParser()
        let input = """
        Building for debugging...
        Build complete!
        """
        let result = parser.parse(input: input)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("status: success"))
        XCTAssertTrue(toonString!.contains("errors: 0"))
        XCTAssertTrue(toonString!.contains("warnings: 0"))
        XCTAssertTrue(toonString!.contains("failed_tests: 0"))
    }

    func testTOONCoverageOnlyPrintsCoveragePercentInSummary() throws {
        let parser = OutputParser()
        let input = "Build complete!"
        let coverage = CodeCoverage(
            lineCoverage: 75.5,
            files: [
                FileCoverage(path: "/path/to/file.swift", name: "file.swift", lineCoverage: 75.5, coveredLines: 75, executableLines: 100)
            ]
        )
        let result = parser.parse(input: input, printWarnings: false, coverage: coverage, printCoverageDetails: false)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("coverage_percent: 75.5"))
        // Should NOT contain detailed coverage section in summary-only mode
        XCTAssertFalse(toonString!.contains("line_coverage:"))
        XCTAssertFalse(toonString!.contains("files["))
    }

    // MARK: - TOON Configuration Tests

    func testTOONWithTabDelimiter() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .tab
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("\t"), "Should use tab delimiter")
        XCTAssertFalse(toonString!.contains(",15,"), "Should not use comma for values")
    }

    func testTOONWithPipeDelimiter() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .pipe
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("|"), "Should use pipe delimiter")
        XCTAssertFalse(toonString!.contains(",15,"), "Should not use comma for values")
    }

    func testTOONWithHashLengthMarker() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: unused variable
        """
        let result = parser.parse(input: input, printWarnings: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        encoder.lengthMarker = .hash
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)

        XCTAssertNotNil(toonString)
        XCTAssertTrue(toonString!.contains("[#"), "Should use hash length marker")
        XCTAssertTrue(toonString!.contains("[#1]{"), "Should show [#1]{ for array of 1 element")
    }

    // MARK: - Benchmark Tests

    func testBenchmarkSmallOutput() throws {
        let parser = OutputParser()
        let input = "main.swift:15:5: error: use of undeclared identifier 'unknown'"
        let result = parser.parse(input: input)

        let jsonSize = try measureJSONSize(result)
        let toonSize = try measureTOONSize(result)
        let reduction = calculateReduction(jsonSize: jsonSize, toonSize: toonSize)

        XCTAssertGreaterThan(reduction, 10.0, "TOON should save at least 10% on small output")
        XCTAssertLessThan(toonSize, jsonSize, "TOON should be smaller than JSON")
    }

    func testBenchmarkMediumOutput() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        Parser.swift:20:10: warning: immutable value 'result' was never used
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        Model.swift:30:15: warning: initialization of immutable value 'bar' was never used
        View.swift:40:8: warning: 'oldFunction()' is deprecated
        Controller.swift:50:12: warning: missing documentation
        Test Case 'LoginTests.testInvalidCredentials' failed (0.045 seconds).
        Test Case 'UITests.testButtonTap' failed (0.032 seconds).
        """
        let result = parser.parse(input: input, printWarnings: true)

        let jsonSize = try measureJSONSize(result)
        let toonSize = try measureTOONSize(result)
        let reduction = calculateReduction(jsonSize: jsonSize, toonSize: toonSize)

        XCTAssertGreaterThan(reduction, 25.0, "TOON should save at least 25% on medium output")
        XCTAssertLessThan(toonSize, jsonSize, "TOON should be smaller than JSON")
    }

    func testBenchmarkLargeOutputWithCoverage() throws {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        main.swift:20:5: error: cannot find 'invalidFunc' in scope
        main.swift:25:5: error: type 'String' has no member 'invalidProperty'
        Parser.swift:20:10: warning: unused variable 'result'
        Parser.swift:25:10: warning: variable 'foo' was never mutated
        Model.swift:30:15: warning: 'bar' was never used
        View.swift:40:8: warning: 'oldFunction()' is deprecated
        Controller.swift:50:12: warning: missing documentation
        Service.swift:60:5: warning: unused import 'Foundation'
        Helper.swift:70:10: warning: variable 'temp' was never mutated
        Test Case 'LoginTests.test1' failed (0.045 seconds).
        Test Case 'LoginTests.test2' failed (0.032 seconds).
        Test Case 'UITests.test1' failed (0.050 seconds).
        """

        let coverage = CodeCoverage(
            lineCoverage: 75.5,
            files: [
                FileCoverage(path: "/path/to/file1.swift", name: "file1.swift", lineCoverage: 85.0, coveredLines: 85, executableLines: 100),
                FileCoverage(path: "/path/to/file2.swift", name: "file2.swift", lineCoverage: 70.0, coveredLines: 70, executableLines: 100),
                FileCoverage(path: "/path/to/file3.swift", name: "file3.swift", lineCoverage: 90.0, coveredLines: 90, executableLines: 100)
            ]
        )

        let result = parser.parse(input: input, printWarnings: true, coverage: coverage, printCoverageDetails: true)

        let jsonSize = try measureJSONSize(result)
        let toonSize = try measureTOONSize(result)
        let reduction = calculateReduction(jsonSize: jsonSize, toonSize: toonSize)

        XCTAssertGreaterThan(reduction, 30.0, "TOON should save at least 30% on large output")
        XCTAssertLessThan(toonSize, jsonSize, "TOON should be smaller than JSON")
    }

    // MARK: - TOON Error Handling Tests

    func testTOONEncoderAlwaysProducesValidUTF8() throws {
        // This test verifies that TOONEncoder always produces valid UTF-8 data,
        // making the "invalid UTF-8" error path in outputTOON() unreachable in practice.
        let parser = OutputParser()

        // Test with various complex inputs
        let testCases = [
            // Basic error
            "main.swift:15:5: error: use of undeclared identifier 'unknown'",

            // Multiple warnings with special characters
            """
            Parser.swift:20:10: warning: immutable value "result" was never used
            Model.swift:30:15: warning: variable 'foo' wasn't mutated; consider 'let'
            """,

            // Unicode characters in paths and messages
            "Файл.swift:10:5: error: неизвестный идентификатор 'тест'",

            // Emojis in messages
            "test.swift:5:1: warning: 🚨 deprecated function",

            // Very long messages
            String(repeating: "very long error message with lots of text ", count: 100)
        ]

        for input in testCases {
            let result = parser.parse(input: input, printWarnings: true)

            let encoder = TOONEncoder()
            encoder.indent = 2
            encoder.delimiter = .comma

            let toonData = try encoder.encode(result)

            // Verify that the data can always be converted to a valid UTF-8 string
            let toonString = String(data: toonData, encoding: .utf8)
            XCTAssertNotNil(toonString, "TOONEncoder should always produce valid UTF-8 data")

            // Additionally verify the string is not empty
            XCTAssertFalse(toonString!.isEmpty, "TOON output should not be empty")
        }
    }

    // MARK: - Helper Methods

    private func measureJSONSize(_ result: BuildResult) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(result)
        return data.count
    }

    private func measureTOONSize(_ result: BuildResult) throws -> Int {
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = .comma
        let data = try encoder.encode(result)
        return data.count
    }

    private func calculateReduction(jsonSize: Int, toonSize: Int) -> Double {
        return Double(jsonSize - toonSize) / Double(jsonSize) * 100.0
    }
}
