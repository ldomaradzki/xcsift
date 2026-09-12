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
            parse: parseConfig(warnings: warnings, buildInfo: buildInfo),
            render: renderConfig(format: format),
            quiet: false,
            exitOnFailure: false
        )
    }

    static func parseConfig(warnings: Bool = false, buildInfo: Bool = false) -> ParseConfig {
        ParseConfig(
            warnings: warnings,
            warningsAsErrors: false,
            coverage: false,
            coverageDetails: false,
            coveragePath: nil,
            slowThreshold: nil,
            buildInfo: buildInfo,
            executable: false,
            xcbeautify: false
        )
    }

    static func renderConfig(format: FormatType = .json) -> RenderConfig {
        RenderConfig(format: format, toonDelimiter: .comma, toonKeyFolding: .disabled, toonFlattenDepth: nil)
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

    /// A summary that quotes the transcript's terminal marker before pointing at the log. Xcode's
    /// own `BuildProject` answers this shape, and the marker must not make it look like the
    /// transcript itself.
    static func summaryQuotingTerminalMarker(referencing logPath: String) -> String {
        """
        Build failed with 2 errors.

        ** BUILD FAILED **

          └ Files:
             └── \(logPath) — Build Logs
        """
    }

    /// Xcode's own test enumeration, trimmed to three tests. One block per test is what makes the
    /// real thing tens of kilobytes.
    static let testResultsEnumeration = """
        ================================================================================
        TEST RESULTS SUMMARY
        ================================================================================
        Generated: 2026-09-12T11:48:08Z
        Total Results: 3
        ================================================================================

        --------------------------------------------------------------------------------
        TEST_RESULT_INDEX: 1/3
        TEST_TARGET: MyAppTests
        TEST_IDENTIFIER: MyTests/testOne()
        TEST_DISPLAY_NAME: testOne()
        TEST_STATE: Passed
        TEST_FILE_PATH: (not available)
        TEST_LINE_NUMBER: (not available)
        TEST_TAGS: (none)

        TEST_ISSUE_COUNT: 0

        --------------------------------------------------------------------------------
        TEST_RESULT_INDEX: 2/3
        TEST_TARGET: MyAppTests
        TEST_IDENTIFIER: MyTests/testTwo()
        TEST_DISPLAY_NAME: testTwo()
        TEST_STATE: Passed
        TEST_FILE_PATH: (not available)
        TEST_LINE_NUMBER: (not available)
        TEST_TAGS: (none)

        TEST_ISSUE_COUNT: 0

        --------------------------------------------------------------------------------
        TEST_RESULT_INDEX: 3/3
        TEST_TARGET: MyAppTests
        TEST_IDENTIFIER: MyTests/testThree()
        TEST_DISPLAY_NAME: testThree()
        TEST_STATE: Failed
        TEST_FILE_PATH: App/Tests/MyTests.swift
        TEST_LINE_NUMBER: 12
        TEST_TAGS: (none)

        TEST_ISSUE_COUNT: 1

        TEST_ISSUES:
            App/Tests/MyTests.swift:13 MyTests/testThree(): XCTAssertEqual failed: ("1") is not equal to ("2")

        ================================================================================
        END OF TEST RESULTS SUMMARY
        ================================================================================
        """

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

    /// A tree written with CRLF endings yields the same paths: `split(separator: "\n")` matches
    /// nothing in one, because Swift reads `\r\n` as a single `Character`.
    func testFindsPathsInACRLFTree() {
        let text = "  └ Files:\r\n     └── /tmp/logs/build.log\r\n"
        XCTAssertEqual(BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"), ["/tmp/logs/build.log"])
    }

    func testJoinsChildPathsToBaseDirectoryAcrossCRLF() {
        let text = "  └── /tmp/workspace-a/\r\n      ├── logs/build.log — Build Logs\r\n"
        XCTAssertEqual(
            BuildLogReference.logPaths(in: text, homeDirectory: "/Users/me"),
            ["/tmp/workspace-a/logs/build.log"]
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
                parse: config.parse,
                render: config.render,
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
    // MARK: A summary that quotes the terminal marker

    /// The marker says "this text is about a build", not "this text *is* the build". A summary
    /// that quotes one still points at the log holding what it left out, and replacing the whole
    /// block with a parse of the quoted fragment would lose the server's fields and that path.
    func testSummaryQuotingATerminalMarkerKeepsItsTextAndGainsTheLog() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild

        let outcome = makeSifter(fileSystem: fileSystem)
            .sift(text: MCPFixtures.summaryQuotingTerminalMarker(referencing: "/tmp/logs/build.log"))

        XCTAssertNil(outcome.replacement, "the server's own summary must survive")
        let appended = try XCTUnwrap(outcome.additions.first)
        XCTAssertEqual(MCPFixtures.field("errors", of: appended)?.arrayValue?.count, 1)
    }

    func testOnSummaryOffProtectsASummaryQuotingATerminalMarker() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild

        XCTAssertEqual(
            makeSifter(strategy: .off, fileSystem: fileSystem)
                .sift(text: MCPFixtures.summaryQuotingTerminalMarker(referencing: "/tmp/logs/build.log")),
            .unchanged
        )
    }

    func testSummaryQuotingATerminalMarkerIsReplacedWithTheLogPathKept() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.failingBuild

        let outcome = makeSifter(strategy: .replace, fileSystem: fileSystem)
            .sift(text: MCPFixtures.summaryQuotingTerminalMarker(referencing: "/tmp/logs/build.log"))

        XCTAssertEqual(MCPFixtures.field("errors", of: try XCTUnwrap(outcome.replacement))?.arrayValue?.count, 1)
        XCTAssertEqual(outcome.additions, ["Build log: /tmp/logs/build.log"])
    }

    /// Preferring a referenced log must not cost the text that names it: when no referenced path
    /// holds a usable log, the block was build output after all and is sifted as such — keeping
    /// the path, which the replacement would otherwise take with it.
    func testFallsBackToSiftingWhenAReferencedLogIsUnusable() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/notes.txt"] = "shopping list"
        let text = """
            ** BUILD FAILED **
            /project/Sources/A.swift:1:1: error: cannot find 'boom' in scope
            See /tmp/notes.txt
            """

        let outcome = makeSifter(fileSystem: fileSystem).sift(text: text)

        XCTAssertEqual(MCPFixtures.field("status", of: try XCTUnwrap(outcome.replacement))?.stringValue, "failed")
        XCTAssertEqual(outcome.additions, ["Build log: /tmp/notes.txt"], "the path must survive the replacement")
        XCTAssertTrue(try XCTUnwrap(outcome.notes.first).contains("does not read like"))
    }

    // MARK: Line endings

    /// `String.split(separator: "\n")` never matches CRLF, because Swift reads `\r\n` as one
    /// `Character`. A log written that way parsed as a single line — that is, as nothing.
    func testParsesALogWithCRLFLineEndings() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] =
            MCPFixtures.failingBuild.replacingOccurrences(of: "\n", with: "\r\n")

        let outcome = makeSifter(fileSystem: fileSystem)
            .sift(text: MCPFixtures.summary(referencing: "/tmp/logs/build.log"))

        XCTAssertEqual(
            MCPFixtures.field("summary", of: try XCTUnwrap(outcome.additions.first))?["errors"]?.intValue,
            1
        )
    }

    func testReplacesARawTranscriptWithCRLFLineEndings() throws {
        let crlf = MCPFixtures.failingBuild.replacingOccurrences(of: "\n", with: "\r\n")
        let replacement = try XCTUnwrap(makeSifter().sift(text: crlf).replacement)

        XCTAssertEqual(MCPFixtures.field("errors", of: replacement)?.arrayValue?.count, 1)
    }

    // MARK: The size cap

    /// The cap is settled on the bytes that were read, so a size the file system reported for some
    /// other file — a symlink's own, or a stale one — cannot walk a log past it.
    func testCapIsEnforcedOnWhatWasActuallyRead() {
        let fileSystem = MCPFixtures.fileSystem()
        let log = String(repeating: "x", count: 4096) + "\n" + MCPFixtures.failingBuild
        fileSystem.fileContents["/tmp/logs/build.log"] = log
        fileSystem.fileAttributes["/tmp/logs/build.log"] = [.size: NSNumber(value: 12)]

        let outcome = makeSifter(maximumLogBytes: 1024, fileSystem: fileSystem)
            .parseLog(atPath: "/tmp/logs/build.log")

        XCTAssertEqual(outcome, .failure(.tooLarge(bytes: log.utf8.count, cap: 1024)))
    }

    /// `attributesOfItem` reports on the link, not its destination, so a symlink used to be a way
    /// around `--max-log-size`. Run against the real file system: the mock cannot hold a link.
    func testSymlinkDoesNotEvadeTheSizeCap() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcsift-symlink-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = directory.appendingPathComponent("build.log")
        let link = directory.appendingPathComponent("link.log")
        try (String(repeating: "x", count: 4096) + "\n" + MCPFixtures.failingBuild)
            .write(to: log, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: log)

        let sifter = BuildOutputSifter(
            settings: BuildOutputSifter.Settings(
                parse: MCPFixtures.parseConfig(),
                render: MCPFixtures.renderConfig(),
                maximumLogBytes: 1024
            )
        )

        guard case let .failure(reason) = sifter.parseLog(atPath: link.path) else {
            return XCTFail("a symlink to an oversized log must be refused like the log itself")
        }
        XCTAssertTrue(reason.description.contains("--max-log-size"), reason.description)
    }
    // MARK: Xcode's test enumeration

    /// The enumeration is the authority on a run, and the run's whole story is its failures. This
    /// is where the proxy's tokens are: the real thing runs to tens of kilobytes of passing tests.
    func testReplacesXcodesTestEnumeration() throws {
        let outcome = makeSifter().sift(text: MCPFixtures.testResultsEnumeration)
        let replacement = try XCTUnwrap(outcome.replacement)

        XCTAssertEqual(MCPFixtures.field("status", of: replacement)?.stringValue, "failed")
        XCTAssertEqual(MCPFixtures.field("summary", of: replacement)?["passed_tests"]?.intValue, 2)
        XCTAssertEqual(MCPFixtures.field("failed_tests", of: replacement)?.arrayValue?.count, 1)
        XCTAssertLessThan(replacement.utf8.count, MCPFixtures.testResultsEnumeration.utf8.count / 2)
    }

    /// The format names itself, so a tool the pattern does not recognise does not hide it. Nothing
    /// is read from disk to tell: the text is the evidence.
    func testReplacesTheEnumerationWhateverToolReturnedIt() {
        XCTAssertNotNil(makeSifter().sift(text: MCPFixtures.testResultsEnumeration, trust: .unknown).replacement)
    }

    /// A summary that points at the enumeration on disk gets it parsed like any other artefact.
    func testParsesAReferencedTestEnumeration() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/results.txt"] = MCPFixtures.testResultsEnumeration

        let outcome = makeSifter(fileSystem: fileSystem)
            .parseLog(atPath: "/tmp/logs/results.txt")

        guard case let .success(rendered) = outcome else { return XCTFail("expected a parse, got \(outcome)") }
        XCTAssertEqual(MCPFixtures.field("summary", of: rendered)?["failed_tests"]?.intValue, 1)
    }
}
