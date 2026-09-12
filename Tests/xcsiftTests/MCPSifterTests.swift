import Foundation
import TestUtils
import XCTest

@testable import xcsift

// MARK: - Fixtures

/// Fixtures for the MCP tests, namespaced so they cannot collide with other suites in this target.
enum MCPFixtures {

    static func resolvedConfig(
        format: FormatType = .json,
        warnings: Bool = false,
        buildInfo: Bool = false
    ) -> ResolvedConfig {
        ResolvedConfig(
            format: format,
            warnings: warnings,
            warningsAsErrors: false,
            quiet: false,
            coverage: false,
            coverageDetails: false,
            coveragePath: nil,
            slowThreshold: nil,
            buildInfo: buildInfo,
            executable: false,
            exitOnFailure: false,
            xcbeautify: false,
            toonDelimiter: .comma,
            toonKeyFolding: .disabled,
            toonFlattenDepth: nil
        )
    }

    /// A mock file system with a stable home directory, so `~` expansion is testable.
    static func fileSystem() -> MockFileSystem {
        let mock = MockFileSystem()
        mock.mockHomeDirectory = URL(fileURLWithPath: "/Users/me")
        return mock
    }

    /// A raw xcodebuild transcript, trimmed to the lines a parser reacts to.
    static let failingBuild = """
        note: Building targets in dependency order
        CompileSwiftSources normal arm64 (in target 'SampleKit' from project 'SampleKit')
        /Users/me/Sample/Sources/SampleKit/SampleKit.swift:6:26: error: cannot convert value of type 'String' to specified type 'Int'
        ** BUILD FAILED **
        """

    static let cleanBuild = """
        note: Building targets in dependency order
        CompileSwiftSources normal arm64 (in target 'SampleKit' from project 'SampleKit')
        ** BUILD SUCCEEDED **
        """

    static let warningBuild = """
        note: Building targets in dependency order
        /Users/me/Sample/Sources/SampleKit/SampleKit.swift:5:9: warning: initialization of immutable value 'unused' was never used
        ** BUILD SUCCEEDED **
        """

    static let failingTestRun = """
        Test Suite 'MyTests.xctest' started at 2026-09-12 16:47:46.000.
        Test Case '-[MyTests testOne]' started.
        /project/Tests/MyTests.swift:12: error: -[MyTests testOne] : XCTAssertEqual failed: ("1") is not equal to ("2")
        Test Case '-[MyTests testOne]' failed (0.010 seconds).
        Test Suite 'MyTests.xctest' failed at 2026-09-12 16:47:47.000.
            Executed 3 tests, with 1 failure (0 unexpected) in 0.030 (0.031) seconds
        ** TEST FAILED **
        """

    /// A source file that merely quotes diagnostic text. A file-reading tool returning this must
    /// never have it replaced by a parse of itself.
    static let sourceFileQuotingDiagnostics =
        (1 ... 8)
        .map { "    static let line\($0) = \"placeholder\"" }
        .joined(separator: "\n")
            + """

            enum XcodebuildSymbols {
                static let errorFormat = ": error: "
                static let warningFormat = ": warning: "
                static let noteFormat = ": note: "
            }
            """

    /// The shape a summarising server returns: rendered prose plus a pointer to the full log.
    static func summary(referencing logPath: String) -> String {
        """

        🔨 Build

        Errors (1):

          ✗ cannot convert value of type 'String' to specified type 'Int'
            Sources/SampleKit/SampleKit.swift:6

        ❌ Build failed. (⏱️ 3.4s)
          └ Files:
             └── \(logPath) — Build Logs
        """
    }

    /// Reads a field out of a sifted JSON payload, so tests assert on values rather than on the
    /// encoder's whitespace.
    static func field(_ key: String, of json: String) -> JSONValue? {
        JSONValue.parse(Data(json.utf8))?[key]
    }
}

// MARK: - Build log references

final class BuildLogReferenceTests: XCTestCase {

    func testFindsAbsolutePathInTree() {
        let text = "  └ Files:\n     └── /tmp/logs/build.log — Build Logs\n"
        XCTAssertEqual(BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"), ["/tmp/logs/build.log"])
    }

    func testExpandsTilde() {
        let text = "     └── ~/Library/Logs/xcode-mcp/logs/build.log — Build Logs"
        XCTAssertEqual(
            BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"),
            ["/Users/me/Library/Logs/xcode-mcp/logs/build.log"]
        )
    }

    /// Shared artefacts are rendered as a base directory with indented children.
    func testJoinsChildPathsToBaseDirectory() {
        let text = """
                 └── ~/Library/Logs/xcode-mcp/workspaces/App-1234/
                     ├── logs/test_sim_2026.log — Build Logs
                     └── result-bundles/test_sim_2026.xcresult — Result Bundle
            """

        XCTAssertEqual(
            BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"),
            ["/Users/me/Library/Logs/xcode-mcp/workspaces/App-1234/logs/test_sim_2026.log"]
        )
    }

    /// A base directory only governs the lines nested under it. A later top-level line must not
    /// have its relative token joined to a directory it has nothing to do with.
    func testBaseDirectoryDoesNotLeakToLaterLines() {
        let text = """
            Files:
              /tmp/workspace-a/
                logs/build.log — Build Logs
            Elsewhere: notes.log
            """

        XCTAssertEqual(
            BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"),
            ["/tmp/workspace-a/logs/build.log"]
        )
    }

    func testStripsANSIColourCodes() {
        let text = "\u{1B}[32m     └── /tmp/logs/build.log\u{1B}[0m — Build Logs"
        XCTAssertEqual(BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"), ["/tmp/logs/build.log"])
    }

    func testDeduplicatesAndPreservesOrder() {
        let text = "/tmp/a.log\n/tmp/b.log\n/tmp/a.log\n"
        XCTAssertEqual(
            BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"),
            ["/tmp/a.log", "/tmp/b.log"]
        )
    }

    func testIgnoresRelativePathsWithoutABaseAndOtherExtensions() {
        let text = "See build.log for details, or /tmp/output.json"
        XCTAssertEqual(BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"), [])
    }

    /// Xcode's own server writes the transcript as `.txt` and reports it inside a JSON payload.
    func testReadsFullLogPathOutOfAJSONResponse() {
        let text =
            #"{"buildResult":"The project built successfully.","elapsedTime":5.11,"errors":[],"#
            + #""fullLogPath":"/var/folders/7m/T/ActionArtifacts/BuildProject-Log-20260912.txt"}"#

        XCTAssertEqual(
            BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"),
            ["/var/folders/7m/T/ActionArtifacts/BuildProject-Log-20260912.txt"]
        )
    }

    /// Several log-shaped values in one payload all come back, so a caller can try each in turn.
    func testReturnsEveryLogPathInAJSONResponse() {
        let text = #"{"fullConsoleLogsPath":"/tmp/console.txt","fullLogPath":"/tmp/build.txt"}"#

        XCTAssertEqual(
            Set(BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me")),
            ["/tmp/console.txt", "/tmp/build.txt"]
        )
    }

    func testTrimsSurroundingPunctuation() {
        let text = "Wrote log to \"/tmp/logs/build.log\"."
        XCTAssertEqual(BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"), ["/tmp/logs/build.log"])
    }
}

// MARK: - Sifting

final class BuildOutputSifterTests: XCTestCase {

    private func makeSifter(
        config: ResolvedConfig = MCPFixtures.resolvedConfig(),
        strategy: BuildOutputSifter.SummaryStrategy = .append,
        minimumRawLines: Int = MCPDefaults.minimumRawLines,
        maximumLogBytes: Int = MCPDefaults.maximumLogBytes,
        fileSystem: MockFileSystem = MCPFixtures.fileSystem()
    ) -> BuildOutputSifter {
        BuildOutputSifter(
            settings: BuildOutputSifter.Settings(
                config: config,
                summaryStrategy: strategy,
                minimumRawLines: minimumRawLines,
                maximumLogBytes: maximumLogBytes
            ),
            fileSystem: fileSystem
        )
    }

    // MARK: Raw transcripts

    func testReplacesRawBuildTranscript() throws {
        let outcome = makeSifter().sift(text: MCPFixtures.failingBuild)
        let replacement = try XCTUnwrap(outcome.replacement)

        XCTAssertEqual(MCPFixtures.field("status", of: replacement)?.stringValue, "failed")
        XCTAssertEqual(MCPFixtures.field("errors", of: replacement)?.arrayValue?.count, 1)
        XCTAssertFalse(replacement.contains("CompileSwiftSources"), "build noise must not survive sifting")
        XCTAssertTrue(outcome.additions.isEmpty, "a raw transcript carries no log path to preserve")
    }

    func testRendersTOONWhenConfigured() throws {
        let sifter = makeSifter(config: MCPFixtures.resolvedConfig(format: .toon))
        let replacement = try XCTUnwrap(sifter.sift(text: MCPFixtures.failingBuild).replacement)

        XCTAssertTrue(replacement.hasPrefix("status: failed"))
    }

    /// A tool that is not build-shaped may be handing back a source file that quotes diagnostic
    /// text. Replacing that with a parse of itself would destroy the file and invent a failed build.
    func testDoesNotInterpretOtherToolsOutputAsABuild() {
        let sifter = makeSifter()

        XCTAssertNil(sifter.sift(text: MCPFixtures.sourceFileQuotingDiagnostics, trust: .unknown).replacement)
        XCTAssertNotNil(
            sifter.sift(text: MCPFixtures.sourceFileQuotingDiagnostics, trust: .buildShaped).replacement,
            "a build tool's output is still sifted on the weaker markers"
        )
    }

    /// A terminal phase marker is unmistakable, so it counts even from an unknown tool.
    func testTerminalMarkerIsTrustedFromAnyTool() throws {
        let outcome = makeSifter().sift(text: MCPFixtures.failingBuild, trust: .unknown)
        XCTAssertNotNil(outcome.replacement)
    }

    func testLeavesShortProseAlone() {
        XCTAssertEqual(makeSifter().sift(text: "Simulator booted successfully."), .unchanged)
        XCTAssertEqual(makeSifter().sift(text: "iPhone 17 Pro (booted)\niPad Pro"), .unchanged)
    }

    /// A one-line tool error is not a transcript: parsing it yields a worse answer than the text.
    func testLeavesAOneLineToolErrorAlone() {
        let text = "xcodebuild: error: The workspace named 'App' does not contain a scheme named 'Foo'."
        XCTAssertEqual(makeSifter().sift(text: text), .unchanged)
    }

    func testMinimumRawLinesDecidesUnmarkedOutput() {
        let body = (1 ... 6).map { "/project/File\($0).swift:\($0): warning: something" }.joined(separator: "\n")

        XCTAssertEqual(makeSifter(minimumRawLines: 99).sift(text: body), .unchanged)
        XCTAssertNotNil(makeSifter(minimumRawLines: 3).sift(text: body).replacement)
    }

    func testUnterminatedOutputWithoutFindingsIsLeftAlone() {
        let truncated = Array(repeating: "CompileSwiftSources normal arm64 (in target 'A' from project 'B')", count: 20)
            .joined(separator: "\n")
        XCTAssertEqual(makeSifter().sift(text: truncated), .unchanged)
    }

    // MARK: Summaries that reference a log

    func testLeavesUpstreamSummaryAloneWhenItReferencesNothing() {
        XCTAssertEqual(makeSifter().sift(text: MCPFixtures.summary(referencing: "(not written)")), .unchanged)
    }

    /// The server already listed this error, so repeating it would only cost tokens.
    func testDoesNotRepeatWhatTheSummaryAlreadySays() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild

        let outcome = makeSifter(fileSystem: fileSystem)
            .sift(text: MCPFixtures.summary(referencing: "/tmp/logs/build.log"))

        XCTAssertFalse(outcome.changesContent)
    }

    func testAppendsDiagnosticsTheSummaryOmits() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild + "\n" + MCPFixtures.warningBuild

        let sifter = makeSifter(config: MCPFixtures.resolvedConfig(warnings: true), fileSystem: fileSystem)
        let outcome = sifter.sift(text: MCPFixtures.summary(referencing: "/tmp/logs/build.log"))

        XCTAssertNil(outcome.replacement)
        XCTAssertEqual(outcome.additions.count, 1)
        XCTAssertTrue(try XCTUnwrap(outcome.additions.first).contains("never used"))
    }

    /// Xcode's own server returns structured errors but never the warnings; that gap is the point.
    func testAppendsWarningsMissingFromAJSONBuildResult() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/BuildProject-Log.txt"] = MCPFixtures.warningBuild

        let response =
            #"{"buildResult":"The project built successfully.","elapsedTime":5.11,"errors":[],"#
            + #""fullLogPath":"/tmp/logs/BuildProject-Log.txt"}"#

        let sifter = makeSifter(config: MCPFixtures.resolvedConfig(warnings: true), fileSystem: fileSystem)
        let addition = try XCTUnwrap(sifter.sift(text: response).additions.first)

        XCTAssertTrue(addition.contains("never used"))
    }

    /// The decision must rest on the diagnostics themselves. A summary that merely contains the
    /// word "Warnings" — a `Warnings (0):` heading, say — still omits the warning in the log.
    func testTheWordWarningInTheSummaryDoesNotSuppressTheAppend() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.warningBuild

        let response = """

            🔨 Build

            Warnings (0):

            ✅ Build succeeded. (⏱️ 3.4s)
              └ Files:
                 └── /tmp/logs/build.log — Build Logs
            """

        let outcome = makeSifter(fileSystem: fileSystem).sift(text: response)
        XCTAssertEqual(outcome.additions.count, 1)
    }

    /// Xcode reports a console log and a build log together, and only one of them holds what the
    /// response left out. The first unhelpful log must not end the search.
    func testKeepsLookingAfterALogThatAddsNothing() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/a.log"] = MCPFixtures.failingBuild
        fileSystem.fileContents["/tmp/b.log"] = MCPFixtures.warningBuild

        let response = """
            Errors (1):
              ✗ cannot convert value of type 'String' to specified type 'Int'
            Files: /tmp/a.log and /tmp/b.log
            """

        let sifter = makeSifter(config: MCPFixtures.resolvedConfig(warnings: true), fileSystem: fileSystem)
        let addition = try XCTUnwrap(sifter.sift(text: response).additions.first)

        XCTAssertTrue(addition.contains("never used"))
    }

    func testAppendsBuildInfoWhenAsked() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.cleanBuild

        let sifter = makeSifter(config: MCPFixtures.resolvedConfig(buildInfo: true), fileSystem: fileSystem)
        let addition = try XCTUnwrap(
            sifter.sift(text: "Build succeeded.\nFiles: /tmp/logs/build.log").additions.first
        )

        XCTAssertNotNil(MCPFixtures.field("build_info", of: addition))
    }

    func testSummaryStrategyReplaceSubstitutesTheSummaryAndKeepsTheLogPath() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild

        let outcome = makeSifter(strategy: .replace, fileSystem: fileSystem)
            .sift(text: MCPFixtures.summary(referencing: "/tmp/logs/build.log"))

        XCTAssertNotNil(outcome.replacement)
        XCTAssertEqual(outcome.additions, ["Build log: /tmp/logs/build.log"])
    }

    func testSummaryStrategyOffLeavesEverythingAlone() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild

        XCTAssertEqual(
            makeSifter(strategy: .off, fileSystem: fileSystem)
                .sift(text: MCPFixtures.summary(referencing: "/tmp/logs/build.log")),
            .unchanged
        )
    }

    func testDoesNotFollowLogsForNonBuildTools() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild

        XCTAssertEqual(
            makeSifter(fileSystem: fileSystem).sift(
                text: MCPFixtures.summary(referencing: "/tmp/logs/build.log"),
                trust: .unknown
            ),
            .unchanged
        )
    }

    /// A clean build has nothing the summary did not already say, so nothing is appended.
    func testCleanLogAddsNothing() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.cleanBuild

        let summary = "\n🔨 Build\n\n✅ Build succeeded. (⏱️ 3.4s)\n  └ Files:\n     └── /tmp/logs/build.log — Build Logs"
        XCTAssertFalse(makeSifter(fileSystem: fileSystem).sift(text: summary).changesContent)
    }

    /// A skipped log is a question the user will ask about, so the reason reaches stderr.
    func testReportsALogItRefusedToParse() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild
        fileSystem.fileAttributes["/tmp/logs/build.log"] = [.size: NSNumber(value: 10_000)]

        let outcome = makeSifter(maximumLogBytes: 1024, fileSystem: fileSystem)
            .sift(text: MCPFixtures.summary(referencing: "/tmp/logs/build.log"))

        XCTAssertFalse(outcome.changesContent)
        XCTAssertTrue(try XCTUnwrap(outcome.notes.first).contains("--max-log-size"))
    }

    func testReportsAnUnreadableLog() throws {
        let outcome = makeSifter().sift(text: MCPFixtures.summary(referencing: "/tmp/logs/missing.log"))

        XCTAssertFalse(outcome.changesContent)
        XCTAssertTrue(try XCTUnwrap(outcome.notes.first).contains("could not be read"))
    }

    func testReportsAFileThatIsNotBuildOutput() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = "just some notes\nnothing to see"

        let outcome = makeSifter(fileSystem: fileSystem)
            .sift(text: MCPFixtures.summary(referencing: "/tmp/logs/build.log"))

        XCTAssertFalse(outcome.changesContent)
        XCTAssertTrue(try XCTUnwrap(outcome.notes.first).contains("does not read like"))
    }

    // MARK: Explicit parsing

    func testParseLogReportsEvenACleanBuild() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.cleanBuild

        let rendered = try makeSifter(fileSystem: fileSystem).parseLog(atPath: "/tmp/logs/build.log").get()
        XCTAssertEqual(MCPFixtures.field("status", of: rendered)?.stringValue, "success")
    }

    func testParseLogRejectsNonBuildText() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/notes.txt"] = "just some notes"

        let outcome = makeSifter(fileSystem: fileSystem).parseLog(atPath: "/tmp/notes.txt")
        XCTAssertEqual(outcome, .failure(.notBuildOutput))
    }

    /// The explicit tool shares the size cap, so an agent cannot make the proxy read a
    /// multi-gigabyte path into memory.
    func testParseLogHonoursTheSizeCap() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild
        fileSystem.fileAttributes["/tmp/logs/build.log"] = [.size: NSNumber(value: 10_000)]

        let outcome = makeSifter(maximumLogBytes: 1024, fileSystem: fileSystem).parseLog(atPath: "/tmp/logs/build.log")
        XCTAssertEqual(outcome, .failure(.tooLarge(bytes: 10_000, cap: 1024)))
    }
}
