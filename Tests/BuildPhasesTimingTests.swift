import XCTest
@testable import xcsift

/// Tests for build phases parsing and per-target timing extraction
final class BuildPhasesTimingTests: XCTestCase {

    // MARK: - Build Phases Parsing Tests

    func testParseCompileSwiftSourcesPhase() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
                Compiling 42 swift files
            """

        let result = parser.parse(input: input, printPhases: true)

        XCTAssertEqual(result.phases?.count, 1)
        XCTAssertEqual(result.phases?[0].name, "CompileSwiftSources")
        XCTAssertEqual(result.phases?[0].target, "MyApp")
        XCTAssertEqual(result.phases?[0].files, 42)
    }

    func testParseLinkPhase() {
        let parser = OutputParser()
        let input = """
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyApp')
                cd /path/to/project
            """

        let result = parser.parse(input: input, printPhases: true)

        XCTAssertEqual(result.phases?.count, 1)
        XCTAssertEqual(result.phases?[0].name, "Link")
        XCTAssertEqual(result.phases?[0].target, "MyApp")
    }

    func testParseCopyResourcesPhase() {
        let parser = OutputParser()
        let input = """
            CopySwiftLibs /path/to/MyApp.app (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printPhases: true)

        XCTAssertEqual(result.phases?.count, 1)
        XCTAssertEqual(result.phases?[0].name, "CopySwiftLibs")
        XCTAssertEqual(result.phases?[0].target, "MyApp")
    }

    func testParseRunScriptPhase() {
        let parser = OutputParser()
        let input = """
            PhaseScriptExecution Copy_Pods_Resources /path/to/script (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printPhases: true)

        XCTAssertEqual(result.phases?.count, 1)
        XCTAssertEqual(result.phases?[0].name, "PhaseScriptExecution")
        XCTAssertEqual(result.phases?[0].target, "MyApp")
    }

    func testMultiplePhasesAreCaptured() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
                Compiling 10 swift files
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyApp')
            CopySwiftLibs /path/to/MyApp.app (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printPhases: true)

        XCTAssertEqual(result.phases?.count, 3)
        XCTAssertEqual(result.phases?[0].name, "CompileSwiftSources")
        XCTAssertEqual(result.phases?[1].name, "Link")
        XCTAssertEqual(result.phases?[2].name, "CopySwiftLibs")
    }

    func testPhasesOmittedByDefault() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            """

        // Without printPhases flag, phases should be nil
        let result = parser.parse(input: input, printPhases: false)

        XCTAssertNil(result.phases)
    }

    func testParseCompileSwiftDriverPhase() {
        let parser = OutputParser()
        let input = """
            SwiftDriver\\ Compilation MyApp normal arm64 com.apple.xcode.tools.swift.compiler (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printPhases: true)

        XCTAssertEqual(result.phases?.count, 1)
        XCTAssertEqual(result.phases?[0].name, "SwiftCompilation")
        XCTAssertEqual(result.phases?[0].target, "MyApp")
    }

    func testParseCompileClangPhase() {
        let parser = OutputParser()
        let input = """
            CompileC /path/to/file.o /path/to/file.m normal arm64 (in target 'MyLib' from project 'MyProject')
            """

        let result = parser.parse(input: input, printPhases: true)

        XCTAssertEqual(result.phases?.count, 1)
        XCTAssertEqual(result.phases?[0].name, "CompileC")
        XCTAssertEqual(result.phases?[0].target, "MyLib")
    }

    // MARK: - Target Timing Tests

    func testParseSingleTargetTiming() {
        let parser = OutputParser()
        let input = """
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printTiming: true)

        XCTAssertNotNil(result.timing)
        XCTAssertEqual(result.timing?.total, "45.2s")
        XCTAssertEqual(result.timing?.targets.count, 1)
        XCTAssertEqual(result.timing?.targets[0].name, "MyApp")
        XCTAssertEqual(result.timing?.targets[0].duration, "23.1s")
    }

    func testParseMultipleTargetsTiming() {
        let parser = OutputParser()
        let input = """
            Build target MyFramework of project MyProject with configuration Debug (12.4s)
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printTiming: true)

        XCTAssertNotNil(result.timing)
        XCTAssertEqual(result.timing?.total, "45.2s")
        XCTAssertEqual(result.timing?.targets.count, 2)
        XCTAssertEqual(result.timing?.targets[0].name, "MyFramework")
        XCTAssertEqual(result.timing?.targets[0].duration, "12.4s")
        XCTAssertEqual(result.timing?.targets[1].name, "MyApp")
        XCTAssertEqual(result.timing?.targets[1].duration, "23.1s")
    }

    func testParseSPMTargetTiming() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            [42/42] Linking xcsift
            Build complete! (12.34s)
            """

        let result = parser.parse(input: input, printTiming: true)

        XCTAssertNotNil(result.timing)
        XCTAssertEqual(result.timing?.total, "12.34s")
    }

    func testParseXcodebuildSucceededWithTime() {
        let parser = OutputParser()
        let input = """
            ** BUILD SUCCEEDED ** [32.5s]
            """

        let result = parser.parse(input: input, printTiming: true)

        XCTAssertNotNil(result.timing)
        XCTAssertEqual(result.timing?.total, "32.5s")
    }

    func testParseXcodebuildFailedWithTime() {
        let parser = OutputParser()
        let input = """
            main.swift:15:5: error: use of undeclared identifier 'unknown'
            ** BUILD FAILED ** [15.3s]
            """

        let result = parser.parse(input: input, printTiming: true)

        XCTAssertNotNil(result.timing)
        XCTAssertEqual(result.timing?.total, "15.3s")
        XCTAssertEqual(result.status, "failed")
    }

    func testTimingOmittedByDefault() {
        let parser = OutputParser()
        let input = """
            ** BUILD SUCCEEDED ** [32.5s]
            """

        // Without printTiming flag, timing should be nil
        let result = parser.parse(input: input, printTiming: false)

        XCTAssertNil(result.timing)
    }

    func testSummaryIncludesBuildTime() {
        let parser = OutputParser()
        let input = """
            ** BUILD SUCCEEDED ** [32.5s]
            """

        let result = parser.parse(input: input)

        // build_time in summary should still work even without printTiming
        XCTAssertEqual(result.summary.buildTime, "32.5s")
    }

    // MARK: - JSON Encoding Tests

    func testJSONEncodingWithPhases() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
                Compiling 10 swift files
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyApp')
            ** BUILD SUCCEEDED ** [15.0s]
            """

        let result = parser.parse(input: input, printPhases: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"phases\""))
        XCTAssertTrue(jsonString.contains("\"CompileSwiftSources\""))
        XCTAssertTrue(jsonString.contains("\"Link\""))
    }

    func testJSONEncodingWithTiming() {
        let parser = OutputParser()
        let input = """
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printTiming: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"timing\""))
        XCTAssertTrue(jsonString.contains("\"total\":\"45.2s\""))
        XCTAssertTrue(jsonString.contains("\"targets\""))
        XCTAssertTrue(jsonString.contains("\"MyApp\""))
    }

    func testJSONEncodingOmitsEmptyPhasesAndTiming() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """

        let result = parser.parse(input: input, printPhases: false, printTiming: false)

        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("\"phases\""))
        XCTAssertFalse(jsonString.contains("\"timing\""))
    }

    // MARK: - Alternative xcodebuild formats

    func testParseTargetCompletedFormat() {
        let parser = OutputParser()
        // Another common format from xcodebuild
        let input = """
            Build target 'MyApp' completed. (12.3s)
            """

        let result = parser.parse(input: input, printTiming: true)

        XCTAssertEqual(result.timing?.targets.count, 1)
        XCTAssertEqual(result.timing?.targets[0].name, "MyApp")
        XCTAssertEqual(result.timing?.targets[0].duration, "12.3s")
    }

    func testParseBuildSucceededNoTime() {
        let parser = OutputParser()
        let input = """
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input, printTiming: true)

        // Should handle BUILD SUCCEEDED without timing gracefully
        XCTAssertEqual(result.status, "success")
        XCTAssertNil(result.timing?.total)
    }
}
