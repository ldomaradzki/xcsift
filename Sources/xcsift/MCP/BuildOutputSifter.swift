import Foundation
import XCSiftCore

/// Turns the text an Xcode MCP server returns into xcsift's structured build result.
///
/// Two shapes of upstream output are handled, and both are left alone when nothing useful can be
/// extracted — the proxy never substitutes something worse for a response it does not understand:
///
/// - **Raw `xcodebuild`/SPM output.** Servers that hand the build transcript straight to the agent
///   are the expensive case: the text is replaced by the sifted result.
/// - **An already-summarised response that points at a build log on disk.** The log is parsed and
///   the result is *appended* as an extra content block, so the server's own fields survive.
struct BuildOutputSifter {

    /// What to do with a response that is already summarised but references a build log.
    enum SummaryStrategy: String, Sendable {
        /// Append the sifted result as an extra content block (default).
        case append
        /// Replace the summary with the sifted result.
        case replace
        /// Leave summarised responses untouched.
        case off
    }

    struct Settings: Sendable {
        var config: ResolvedConfig
        var summaryStrategy: SummaryStrategy = .append
        var minimumRawLines: Int = MCPDefaults.minimumRawLines
        var maximumLogBytes: Int = MCPDefaults.maximumLogBytes

        init(
            config: ResolvedConfig,
            summaryStrategy: SummaryStrategy = .append,
            minimumRawLines: Int = MCPDefaults.minimumRawLines,
            maximumLogBytes: Int = MCPDefaults.maximumLogBytes
        ) {
            precondition(minimumRawLines > 0, "minimumRawLines must be greater than zero")
            precondition(maximumLogBytes > 0, "maximumLogBytes must be greater than zero")
            self.config = config
            self.summaryStrategy = summaryStrategy
            self.minimumRawLines = minimumRawLines
            self.maximumLogBytes = maximumLogBytes
        }
    }

    /// What should happen to one text content block.
    ///
    /// Replacement and appending are separate axes rather than alternatives: replacing a summary
    /// still has to carry the log path forward, which is an addition.
    struct Outcome: Equatable {
        /// Text replacing the block, or `nil` to keep the block as the server wrote it.
        var replacement: String?
        /// Blocks appended after the (possibly replaced) block.
        var additions: [String] = []
        /// Diagnostics for stderr, shown under `--verbose`. Never sent to the client.
        var notes: [String] = []

        static let unchanged = Outcome()

        static func replaced(_ text: String, carrying additions: [String] = []) -> Outcome {
            Outcome(replacement: text, additions: additions)
        }

        static func appended(_ text: String) -> Outcome {
            Outcome(additions: [text])
        }

        var changesContent: Bool { replacement != nil || !additions.isEmpty }
    }

    /// Why a referenced log could not be turned into a result.
    enum LogFailure: Error, Equatable {
        case tooLarge(bytes: Int, cap: Int)
        case unreadable(String)
        case notBuildOutput
        case notRenderable(String)

        var description: String {
            switch self {
            case let .tooLarge(bytes, cap):
                return "log is \(bytes) bytes, above the \(cap / (1024 * 1024)) MB --max-log-size cap; not parsed"
            case let .unreadable(reason):
                return "log could not be read: \(reason)"
            case .notBuildOutput:
                return "file does not read like xcodebuild or SPM output"
            case let .notRenderable(reason):
                return "the parsed result could not be encoded: \(reason)"
            }
        }
    }

    private let settings: Settings
    private let fileSystem: FileSystemProtocol

    init(settings: Settings, fileSystem: FileSystemProtocol = FileManager.default) {
        self.settings = settings
        self.fileSystem = fileSystem
    }

    // MARK: - Sifting

    /// - Parameters:
    ///   - text: One text content block from an upstream tool result.
    ///   - trust: How far the tool's name licenses interpreting its output as a build. A tool that
    ///     is not build-shaped may be returning a source file that merely quotes `: error: `, or a
    ///     path that merely appears in its output, so only an unmistakable transcript is sifted and
    ///     no log is read from disk.
    func sift(text: String, trust: ToolTrust = .buildShaped) -> Outcome {
        if isRawBuildOutput(text, trust: trust) {
            let result = parse(text)
            guard isUsable(result) else { return .unchanged }
            switch render(result) {
            case let .success(rendered):
                return .replaced(rendered)
            case let .failure(reason):
                return Outcome(notes: ["xcsift: \(reason.description)"])
            }
        }

        guard trust == .buildShaped, settings.summaryStrategy != .off else { return .unchanged }

        let home = fileSystem.homeDirectoryForCurrentUser.path
        var notes: [String] = []

        for path in BuildLogReference.logPaths(in: text, homeDirectory: home) {
            switch readBuildOutput(atPath: path) {
            case let .failure(reason):
                notes.append("xcsift: \(path): \(reason.description)")
                continue

            case let .success(contents):
                let result = parse(contents)

                if settings.summaryStrategy == .replace {
                    guard isUsable(result), case let .success(rendered) = render(result) else {
                        continue
                    }
                    // Replacing the summary would otherwise take the log path with it, and that
                    // path is what the agent needs to read the raw output or call the parse tool.
                    return .replaced(rendered, carrying: ["Build log: \(path)"])
                }

                guard adds(result, beyond: text) else {
                    // Another referenced log may still carry something: Xcode reports a console
                    // log and a build log together, and only one of them holds the warnings.
                    notes.append("xcsift: \(path): nothing the response did not already carry")
                    continue
                }
                guard case let .success(rendered) = render(result) else {
                    continue
                }
                return Outcome(additions: [rendered], notes: notes)
            }
        }

        return Outcome(notes: notes)
    }

    /// How much the tool that produced a text block licenses interpreting it as build output.
    enum ToolTrust: Sendable {
        /// The tool's name matches the build-tool pattern: full heuristics, logs may be read.
        case buildShaped
        /// Any other tool: only a terminal phase marker counts, and no log is read.
        case unknown
    }

    /// Parses a log the caller pointed at explicitly, without requiring the result to be
    /// actionable: an agent that asked for the log wants the summary even when the build was clean.
    func parseLog(atPath path: String) -> Result<String, LogFailure> {
        readBuildOutput(atPath: path).flatMap { contents in
            render(parse(contents))
        }
    }

    // MARK: - Parsing

    private func parse(_ text: String) -> BuildResult {
        let config = settings.config
        var parser = StreamingOutputParser(
            printWarnings: config.warnings,
            // Warning models are always retained, whether or not they are rendered: `adds` needs
            // them to tell a warning the server already reported from one it left out.
            retainWarnings: true,
            warningsAsErrors: config.warningsAsErrors,
            printCoverageDetails: config.coverageDetails,
            slowThreshold: config.slowThreshold,
            printBuildInfo: config.buildInfo,
            printExecutables: config.executable,
            discoverTestedTarget: config.coverage,
            xcbeautify: config.xcbeautify
        )

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            parser.feed(String(line))
        }

        var coverage: CodeCoverage?
        if config.coverage {
            coverage = CoverageParser.parseCoverageFromPath(
                config.coveragePath ?? "",
                targetFilter: parser.testedTarget
            )
        }

        return parser.finish(coverage: coverage)
    }

    /// An encoding failure must never become the payload: the server's own text is worth more than
    /// the encoder's error message.
    private func render(_ result: BuildResult) -> Result<String, LogFailure> {
        do {
            return .success(try ResultRenderer.render(result, config: settings.config))
        } catch {
            return .failure(.notRenderable(String(describing: error)))
        }
    }

    private func readBuildOutput(atPath path: String) -> Result<String, LogFailure> {
        if let size = (try? fileSystem.attributesOfItem(atPath: path))?[.size] as? NSNumber,
            size.intValue > settings.maximumLogBytes
        {
            return .failure(.tooLarge(bytes: size.intValue, cap: settings.maximumLogBytes))
        }

        let contents: String
        do {
            contents = try fileSystem.contentsOfFile(atPath: path)
        } catch {
            // A compressed `.xcactivitylog` lands here too: it exists and is readable, but is not
            // the UTF-8 text the parser needs.
            return .failure(.unreadable(error.localizedDescription))
        }

        guard isRawBuildOutput(contents, trust: .buildShaped) else { return .failure(.notBuildOutput) }
        return .success(contents)
    }

    // MARK: - Classification

    /// A parsed result is worth substituting for the original text when the parser reached a
    /// verdict or found something concrete. An `incomplete` status with no findings means the text
    /// only looked like build output, so the original is kept.
    private func isUsable(_ result: BuildResult) -> Bool {
        result.status != "incomplete" || hasFindings(result)
    }

    private func hasFindings(_ result: BuildResult) -> Bool {
        !result.errors.isEmpty
            || !result.linkerErrors.isEmpty
            || !result.failedTests.isEmpty
            || result.summary.warnings > 0
    }

    /// Appending is only worth its tokens when the log carries at least one diagnostic the response
    /// does not. The gap in Xcode's own responses — structured errors, no warnings, as observed on
    /// Xcode 27 — is the case that motivated this, but nothing here assumes it stays true.
    ///
    /// This is a gate, not a filter: when it opens, the whole sifted result is appended, so a
    /// response missing one warning gets the complete result, known errors included.
    private func adds(_ result: BuildResult, beyond text: String) -> Bool {
        if settings.config.buildInfo, result.buildInfo != nil { return true }
        if result.warnings.contains(where: { !alreadySaid($0.message, in: text) }) { return true }
        if result.errors.contains(where: { !alreadySaid($0.message, in: text) }) { return true }
        if result.linkerErrors.contains(where: { !mentions($0.symbol, in: text) }) { return true }

        // A response that already enumerates per-test results is the authority on the run. xcsift
        // aggregates an Xcode console transcript across bundles less accurately than the server
        // that ran the tests, so its test numbers are not offered against one.
        guard !enumeratesTestResults(text) else { return false }

        return result.failedTests.contains {
            !mentions($0.test, in: text) && !mentions($0.message, in: text)
        }
    }

    /// Detects a JSON response carrying an array of per-test results.
    private func enumeratesTestResults(_ text: String) -> Bool {
        guard let json = JSONValue.parse(Data(text.utf8)), let object = json.objectValue else {
            return false
        }

        let stateKeys: Set<String> = ["state", "status", "result", "outcome"]
        for (_, value) in object {
            guard let elements = value.arrayValue, let first = elements.first?.objectValue else {
                continue
            }
            if !stateKeys.isDisjoint(with: first.keys) { return true }
        }
        return false
    }

    /// Whether the server's own text already carries this diagnostic.
    ///
    /// Two differences are normalised away, both observed against Xcode's server: it capitalises
    /// the compiler's message (`Cannot convert …` against the log's `cannot convert …`), and xcsift
    /// attributes a diagnostic to its target (`… (in target 'A' from project 'B')`) where the
    /// server states the bare message.
    private func alreadySaid(_ message: String, in text: String) -> Bool {
        if mentions(message, in: text) { return true }
        guard let attribution = message.range(of: " (in target '") else { return false }
        return mentions(String(message[..<attribution.lowerBound]), in: text)
    }

    private func mentions(_ word: String, in text: String) -> Bool {
        !word.isEmpty && text.range(of: word, options: .caseInsensitive) != nil
    }

    /// Recognises verbose `xcodebuild`/SPM transcripts.
    ///
    /// A terminal phase marker (`** BUILD FAILED **`) is conclusive on its own — a text that quotes
    /// one is quoting a transcript — and it is the *only* thing accepted from a tool that is not
    /// build-shaped. Everything weaker is a guess, and a guess is how a source file that quotes
    /// `: error: ` would get replaced by a parse of itself.
    private func isRawBuildOutput(_ text: String, trust: ToolTrust = .buildShaped) -> Bool {
        var lineCount = 0
        var sawConclusiveMarker = false
        var corroboratingMarkers = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineCount += 1

            if isTerminalPhaseMarker(line) { return true }
            guard trust == .buildShaped else { continue }

            if Self.conclusiveMarkers.contains(where: { line.contains($0) }) {
                sawConclusiveMarker = true
            }
            if Self.corroboratingMarkers.contains(where: { line.contains($0) }) {
                corroboratingMarkers += 1
            }
        }

        guard trust == .buildShaped else { return false }
        if sawConclusiveMarker, lineCount >= Self.minimumConclusiveLines { return true }
        return lineCount >= settings.minimumRawLines && corroboratingMarkers >= 2
    }

    /// `** BUILD SUCCEEDED **`, `** TEST FAILED **`, `** ARCHIVE SUCCEEDED **`, …
    private func isTerminalPhaseMarker(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("** ") else { return false }
        return trimmed.contains(" SUCCEEDED **") || trimmed.contains(" FAILED **")
    }

    private static let minimumConclusiveLines = 3

    private static let conclusiveMarkers = [
        "Build complete!",
        "note: Building targets in dependency order",
        "◇ Test run started",
        "Test Suite '",
    ]

    private static let corroboratingMarkers = [
        ": error: ",
        ": warning: ",
        "xcodebuild: error:",
        "Test Case '",
        "] Compiling ",
        "] Linking ",
        "CompileSwiftSources ",
        "SwiftDriver\\ Compilation",
        "PhaseScriptExecution ",
        "ProcessInfoPlistFile ",
        "CodeSign ",
        "Undefined symbols for architecture ",
    ]
}

/// Defaults shared by the `mcp` command's flags and the types they configure, so a documented
/// default lives in exactly one place.
enum MCPDefaults {
    static let upstream = ["xcrun", "mcpbridge"]
    static let minimumRawLines = 12
    static let maximumLogMegabytes = 64
    static let maximumLogBytes = maximumLogMegabytes * 1024 * 1024
    static let buildToolPattern = "(?i)(build|test|run|archive|clean|compile|package)"
}
