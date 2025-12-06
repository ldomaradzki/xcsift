import TOONEncoder
import XCTest

@testable import xcsift

/// Tests for unified build info (phases + timing) extraction
final class BuildInfoTests: XCTestCase {

    // MARK: - Build Phases Parsing Tests

    func testParseCompileSwiftSourcesPhase() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets[0].name, "MyApp")
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("CompileSwiftSources") ?? false)
    }

    func testParseLinkPhase() {
        let parser = OutputParser()
        let input = """
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets[0].name, "MyApp")
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("Link") ?? false)
    }

    func testParseCopyResourcesPhase() {
        let parser = OutputParser()
        let input = """
            CopySwiftLibs /path/to/MyApp.app (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("CopySwiftLibs") ?? false)
    }

    func testParseRunScriptPhase() {
        let parser = OutputParser()
        let input = """
            PhaseScriptExecution Copy_Pods_Resources /path/to/script (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("PhaseScriptExecution") ?? false)
    }

    func testMultiplePhasesForSameTarget() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyApp')
            CopySwiftLibs /path/to/MyApp.app (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets[0].name, "MyApp")
        XCTAssertEqual(result.buildInfo?.targets[0].phases.count, 3)
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("CompileSwiftSources") ?? false)
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("Link") ?? false)
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("CopySwiftLibs") ?? false)
    }

    func testMultipleTargets() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyFramework' from project 'MyProject')
            Ld /path/to/MyFramework.framework/MyFramework normal (in target 'MyFramework' from project 'MyProject')
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyProject')
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyProject')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 2)
        // Targets preserve order of appearance in build output
        let targetNames = result.buildInfo?.targets.map { $0.name } ?? []
        XCTAssertTrue(targetNames.contains("MyApp"))
        XCTAssertTrue(targetNames.contains("MyFramework"))
    }

    func testBuildInfoOmittedByDefault() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            """

        // Without printBuildInfo flag, buildInfo should be nil
        let result = parser.parse(input: input, printBuildInfo: false)

        XCTAssertNil(result.buildInfo)
    }

    func testParseCompileSwiftDriverPhase() {
        let parser = OutputParser()
        let input = """
            SwiftDriver\\ Compilation MyApp normal arm64 com.apple.xcode.tools.swift.compiler (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("SwiftCompilation") ?? false)
    }

    func testParseCompileClangPhase() {
        let parser = OutputParser()
        let input = """
            CompileC /path/to/file.o /path/to/file.m normal arm64 (in target 'MyLib' from project 'MyProject')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets[0].name, "MyLib")
        XCTAssertTrue(result.buildInfo?.targets[0].phases.contains("CompileC") ?? false)
    }

    // MARK: - Target Timing Tests

    func testParseSingleTargetTiming() {
        let parser = OutputParser()
        let input = """
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Total build time is in summary, not build_info (no duplication)
        XCTAssertEqual(result.summary.buildTime, "45.2s")
        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets[0].name, "MyApp")
        XCTAssertEqual(result.buildInfo?.targets[0].duration, "23.1s")
    }

    func testParseMultipleTargetsTiming() {
        let parser = OutputParser()
        let input = """
            Build target MyFramework of project MyProject with configuration Debug (12.4s)
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Total build time is in summary
        XCTAssertEqual(result.summary.buildTime, "45.2s")
        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 2)
        // Find targets by name
        let appTarget = result.buildInfo?.targets.first { $0.name == "MyApp" }
        let frameworkTarget = result.buildInfo?.targets.first { $0.name == "MyFramework" }
        XCTAssertEqual(appTarget?.duration, "23.1s")
        XCTAssertEqual(frameworkTarget?.duration, "12.4s")
    }

    func testParseSPMTotalTiming() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            [42/42] Linking xcsift
            Build complete! (12.34s)
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Total build time is in summary
        XCTAssertEqual(result.summary.buildTime, "12.34s")
        // Now SPM phases are parsed, so we get the target with Linking phase
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets.first?.name, "xcsift")
        XCTAssertTrue(result.buildInfo?.targets.first?.phases.contains("Linking") == true)
    }

    func testParseXcodebuildSucceededWithTime() {
        let parser = OutputParser()
        let input = """
            ** BUILD SUCCEEDED ** [32.5s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Total build time is in summary
        XCTAssertEqual(result.summary.buildTime, "32.5s")
        // No target info, so build_info has empty targets
        XCTAssertEqual(result.buildInfo?.targets.count ?? 0, 0)
    }

    func testParseXcodebuildFailedWithTime() {
        let parser = OutputParser()
        let input = """
            main.swift:15:5: error: use of undeclared identifier 'unknown'
            ** BUILD FAILED ** [15.3s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Total build time is in summary
        XCTAssertEqual(result.summary.buildTime, "15.3s")
        XCTAssertEqual(result.status, "failed")
    }

    func testSummaryIncludesBuildTime() {
        let parser = OutputParser()
        let input = """
            ** BUILD SUCCEEDED ** [32.5s]
            """

        let result = parser.parse(input: input)

        // build_time in summary should still work even without printBuildInfo
        XCTAssertEqual(result.summary.buildTime, "32.5s")
    }

    // MARK: - Combined Phases + Timing Tests

    func testCombinedPhasesAndTiming() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyProject')
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyProject')
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Total build time is in summary
        XCTAssertEqual(result.summary.buildTime, "45.2s")
        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)

        let target = result.buildInfo?.targets[0]
        XCTAssertEqual(target?.name, "MyApp")
        XCTAssertEqual(target?.duration, "23.1s")
        XCTAssertEqual(target?.phases.count, 2)
        XCTAssertTrue(target?.phases.contains("CompileSwiftSources") ?? false)
        XCTAssertTrue(target?.phases.contains("Link") ?? false)
    }

    func testMultipleTargetsWithPhasesAndTiming() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyFramework' from project 'MyProject')
            Ld /path/to/MyFramework.framework normal (in target 'MyFramework' from project 'MyProject')
            Build target MyFramework of project MyProject with configuration Debug (12.4s)
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyProject')
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyProject')
            CopySwiftLibs /path/to/MyApp.app (in target 'MyApp' from project 'MyProject')
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Total build time is in summary
        XCTAssertEqual(result.summary.buildTime, "45.2s")
        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 2)

        // Find targets by name
        let appTarget = result.buildInfo?.targets.first { $0.name == "MyApp" }
        let frameworkTarget = result.buildInfo?.targets.first { $0.name == "MyFramework" }

        XCTAssertEqual(appTarget?.duration, "23.1s")
        XCTAssertEqual(appTarget?.phases.count, 3)
        XCTAssertTrue(appTarget?.phases.contains("CopySwiftLibs") ?? false)

        XCTAssertEqual(frameworkTarget?.duration, "12.4s")
        XCTAssertEqual(frameworkTarget?.phases.count, 2)
    }

    // MARK: - JSON Encoding Tests

    func testJSONEncodingWithBuildInfo() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            Ld /path/to/MyApp.app/MyApp normal (in target 'MyApp' from project 'MyApp')
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // build_info contains per-target info, total time is in summary
        XCTAssertTrue(jsonString.contains("\"build_info\""))
        XCTAssertTrue(jsonString.contains("\"build_time\":\"45.2s\""))  // In summary, not build_info
        XCTAssertTrue(jsonString.contains("\"targets\""))
        XCTAssertTrue(jsonString.contains("\"MyApp\""))
        XCTAssertTrue(jsonString.contains("\"duration\":\"23.1s\""))
        XCTAssertTrue(jsonString.contains("\"phases\""))
        // No "total" field in build_info (it's in summary.build_time)
        XCTAssertFalse(jsonString.contains("\"total\""))
    }

    func testJSONEncodingOmitsBuildInfoByDefault() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            ** BUILD SUCCEEDED ** [32.5s]
            """

        let result = parser.parse(input: input, printBuildInfo: false)

        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("\"build_info\""))
        // But summary should still have build_time
        XCTAssertTrue(jsonString.contains("\"build_time\":\"32.5s\""))
    }

    // MARK: - Alternative xcodebuild formats

    func testParseTargetCompletedFormat() {
        let parser = OutputParser()
        let input = """
            Build target 'MyApp' completed. (12.3s)
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets[0].name, "MyApp")
        XCTAssertEqual(result.buildInfo?.targets[0].duration, "12.3s")
    }

    func testParseBuildSucceededNoTime() {
        let parser = OutputParser()
        let input = """
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        // Should handle BUILD SUCCEEDED without timing gracefully
        XCTAssertEqual(result.status, "success")
        XCTAssertNil(result.summary.buildTime)
    }

    // MARK: - Empty Fields Are Not Encoded

    func testEmptyFieldsNotEncodedInJSON() {
        let parser = OutputParser()
        // Only phases, no timing
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // build_info should be present with targets
        XCTAssertTrue(jsonString.contains("\"build_info\""))
        XCTAssertTrue(jsonString.contains("\"targets\""))
        // Duration should NOT be present since no timing info
        XCTAssertFalse(jsonString.contains("\"duration\""))
        // build_time should NOT be present since no time info
        XCTAssertFalse(jsonString.contains("\"build_time\""))
    }

    func testEmptyTargetsOmitsBuildInfo() {
        let parser = OutputParser()
        // No phases, no targets - just a simple build success
        let input = """
            ** BUILD SUCCEEDED ** [32.5s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // build_info should NOT be present when targets are empty
        XCTAssertFalse(jsonString.contains("\"build_info\""))
        // But build_time should still be in summary
        XCTAssertTrue(jsonString.contains("\"build_time\":\"32.5s\""))
    }

    func testTargetWithoutPhasesDoesNotEncodePhasesField() {
        let parser = OutputParser()
        // Only timing, no phases
        let input = """
            Build target MyApp of project MyProject with configuration Debug (23.1s)
            ** BUILD SUCCEEDED ** [45.2s]
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // build_info should be present
        XCTAssertTrue(jsonString.contains("\"build_info\""))
        XCTAssertTrue(jsonString.contains("\"duration\":\"23.1s\""))
        // phases should NOT be present since no phases info
        XCTAssertFalse(jsonString.contains("\"phases\""))
    }

    // MARK: - Duplicate Phase Prevention

    func testDuplicatePhasesAreNotAdded() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyApp')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        // Should only have 1 CompileSwiftSources, not 3
        XCTAssertEqual(result.buildInfo?.targets[0].phases.count, 1)
        XCTAssertEqual(result.buildInfo?.targets[0].phases[0], "CompileSwiftSources")
    }

    // MARK: - SPM Phase Parsing

    func testParseSPMCompilingPhase() {
        let parser = OutputParser()
        let input = """
            [1/5] Compiling xcsift main.swift
            [2/5] Compiling xcsift Parser.swift
            [3/5] Linking xcsift
            Build complete! (2.81s)
            """
        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets.first?.name, "xcsift")
        XCTAssertTrue(result.buildInfo?.targets.first?.phases.contains("Compiling") == true)
        XCTAssertTrue(result.buildInfo?.targets.first?.phases.contains("Linking") == true)
    }

    func testParseSPMMultipleTargets() {
        let parser = OutputParser()
        let input = """
            [1/10] Compiling ArgumentParser Option.swift
            [2/10] Compiling ArgumentParser Parser.swift
            [3/10] Compiling xcsift main.swift
            [4/10] Linking xcsift
            Build complete! (5.2s)
            """
        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 2)
        // Order should be preserved
        XCTAssertEqual(result.buildInfo?.targets[0].name, "ArgumentParser")
        XCTAssertEqual(result.buildInfo?.targets[1].name, "xcsift")
    }

    func testSPMPluginCompilationIsSkipped() {
        let parser = OutputParser()
        let input = """
            [1/1] Compiling plugin GenerateManual
            [2/2] Compiling plugin GenerateDoccReference
            Building for debugging...
            [3/5] Compiling xcsift main.swift
            Build complete! (2.81s)
            """
        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        // Should only have xcsift, not "plugin"
        XCTAssertEqual(result.buildInfo?.targets.count, 1)
        XCTAssertEqual(result.buildInfo?.targets.first?.name, "xcsift")
    }

    // MARK: - Target Order Preservation

    func testTargetOrderPreserved() {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'ZTarget' from project 'MyProject')
            CompileSwiftSources normal arm64 (in target 'ATarget' from project 'MyProject')
            CompileSwiftSources normal arm64 (in target 'MTarget' from project 'MyProject')
            """

        let result = parser.parse(input: input, printBuildInfo: true)

        XCTAssertNotNil(result.buildInfo)
        XCTAssertEqual(result.buildInfo?.targets.count, 3)
        // Order should be by appearance, not alphabetical
        XCTAssertEqual(result.buildInfo?.targets[0].name, "ZTarget")
        XCTAssertEqual(result.buildInfo?.targets[1].name, "ATarget")
        XCTAssertEqual(result.buildInfo?.targets[2].name, "MTarget")
    }

    // MARK: - TOON Format with Build Info

    func testTOONEncodingWithBuildInfo() throws {
        let parser = OutputParser()
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyProject')
            Ld /path/to/binary normal (in target 'MyApp' from project 'MyProject')
            Build target MyApp of project MyProject with configuration Debug (12.5s)
            ** BUILD SUCCEEDED ** [15.3s]
            """
        let result = parser.parse(input: input, printBuildInfo: true)

        let encoder = TOONEncoder()
        encoder.indent = 2
        let toonData = try encoder.encode(result)
        let toonString = String(data: toonData, encoding: .utf8)!

        XCTAssertTrue(toonString.contains("build_info:"))
        XCTAssertTrue(toonString.contains("targets"))
        XCTAssertTrue(toonString.contains("MyApp"))
        XCTAssertTrue(toonString.contains("12.5s"))
        XCTAssertTrue(toonString.contains("CompileSwiftSources"))
        XCTAssertTrue(toonString.contains("Link"))
    }
}
