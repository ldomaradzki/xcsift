import XCTest
@testable import xcsift

/// Tests for code coverage functionality
final class CoverageTests: XCTestCase {

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
                FileCoverage(
                    path: "/path/to/file.swift",
                    name: "file.swift",
                    lineCoverage: 75.5,
                    coveredLines: 75,
                    executableLines: 100
                )
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
                FileCoverage(
                    path: "/path/to/file.swift",
                    name: "file.swift",
                    lineCoverage: 75.5,
                    coveredLines: 75,
                    executableLines: 100
                )
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
}
