import Foundation
import RegexBuilder

// MARK: - Public API

/// An event emitted by ``LineParser`` when a line of build output is recognized.
public enum ParseEvent: Codable, Sendable {
    // Compile / link
    /// A compiler or tool error was detected.
    case error(BuildError)
    /// A compiler warning was detected.
    case warning(BuildWarning)
    /// A linker error was detected (undefined symbol, duplicate symbol, or missing framework/library).
    case linkerError(LinkerError)

    // Test lifecycle
    /// A test case began execution.
    case testStarted(name: String)
    /// A test case passed.
    case testPassed(name: String, duration: Double?)
    /// A test case failed.
    case testFailed(FailedTest)

    // Test run summaries
    /// An XCTest bundle completed; carries executed/failed totals and duration for that bundle.
    case testSuiteCompleted(suiteName: String, executed: Int, failed: Int, duration: Double)
    /// A Swift Testing run completed; carries aggregate totals across all suites.
    case swiftTestingCompleted(executed: Int, failed: Int, duration: Double)
    /// A parallel test slot was scheduled.
    case parallelTestScheduled(index: Int, total: Int)

    // Build timing / status
    /// The overall build duration string extracted from the build output (e.g. `"1.234 seconds"`).
    case buildTime(String)
    /// The test runner exited with a non-zero status without an explicit per-test failure line.
    case testRunFailed

    // Build info
    /// A build phase was observed for a named target.
    case buildPhase(target: String, phase: String)
    /// A target finished building and reported its duration.
    case targetCompleted(name: String, duration: String)
    /// A dependency edge was parsed from the xcodebuild dependency graph.
    case targetDependency(target: String, dependsOn: String)
    /// A target name appeared as a header in the xcodebuild dependency graph.
    case targetDiscovered(name: String)

    // Executables
    /// An executable app bundle was registered or validated during the build.
    case executable(Executable)
}

/// The outcome of feeding a single line to ``LineParser/feed(_:)``.
public enum LineResult {
    /// The line (or a previously buffered line) produced a ``ParseEvent``.
    case consumed(ParseEvent)
    /// The line is being held pending a look-ahead; no event is available yet.
    case buffering
    /// The line did not match any recognized pattern and was discarded.
    case ignored
}

/// Parses raw xcodebuild/SPM output lines one at a time, emitting structured ``ParseEvent`` values.
///
/// `LineParser` is a streaming state machine. Feed lines via ``feed(_:)`` and call ``flush()``
/// after the last line to drain buffered state (look-ahead windows, in-flight crash detection).
///
/// ```swift
/// let parser = LineParser()
/// for line in output.split(separator: "\n") {
///     if case .consumed(let event) = parser.feed(String(line)) {
///         handle(event)
///     }
/// }
/// for event in parser.flush() { handle(event) }
/// ```
public struct LineParser: Sendable {

    // MARK: - Multi-line linker state
    private var currentLinkerArchitecture: String?
    private var pendingLinkerSymbol: String?
    private var pendingDuplicateSymbol: String?
    private var pendingConflictingFiles: [String] = []

    // MARK: - Crash detection state
    private var lastStartedTestName: String?
    private var pendingSignalCode: Int?
    private var sawTestRunFailed: Bool = false

    // MARK: - Test suite tracking
    private var lastCompletedXCTestSuiteName: String?

    // MARK: - Dependency graph state
    private var currentDependencyTarget: String?

    // MARK: - Look-ahead / look-back state
    private var pendingRecordedIssueLine: String?
    private var lookBackBuffer: [String] = []

    // MARK: - xcbeautify
    private let shouldParseXcbeautify: Bool
    private var xcbeautifyHintEmitted: Bool = false

    /// `true` if the parser wrote an xcbeautify auto-detection hint to stderr during parsing.
    ///
    /// Set when xcbeautify-formatted markers are encountered while `xcbeautify` mode is off.
    /// Useful in tests to assert that the hint was (or was not) emitted.
    public private(set) var didEmitXcbeautifyHint: Bool = false

    /// `true` if a positive terminal success marker was seen
    /// (`** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, `Build complete!`, `Build succeeded in …`).
    public private(set) var sawSuccessMarker: Bool = false

    /// `true` if a terminal failure marker was seen
    /// (`** BUILD FAILED **`, `** TEST FAILED **`, `Build failed after …`).
    public private(set) var sawFailureMarker: Bool = false

    // MARK: - Event queue (events waiting to be delivered one per feed() call)
    private var eventQueue: [ParseEvent] = []

    /// Creates a new `LineParser`.
    ///
    /// - Parameter xcbeautify: Pass `true` when the input was pre-processed by xcbeautify or Tuist.
    ///   Enables parsing of `[x]`/`❌` error markers, `[!]`/`⚠️` warning markers, and `✔`/`✖` test markers.
    public init(xcbeautify: Bool = false) {
        self.shouldParseXcbeautify = xcbeautify
    }

    // MARK: - Public interface

    /// Feeds one line of build output to the parser and returns the result.
    ///
    /// Most callers process each line in a loop:
    /// ```swift
    /// if case .consumed(let event) = parser.feed(line) { ... }
    /// ```
    ///
    /// The method may return `.buffering` when look-ahead is needed (e.g. Swift Testing
    /// `#expect` comments that span two consecutive lines). Call ``flush()`` after the
    /// final line to retrieve any events still in the buffer.
    ///
    /// - Parameter line: A single line of raw build output (no trailing newline required).
    /// - Returns: `.consumed(event)` when a ``ParseEvent`` was produced, `.buffering` when
    ///   the line was held for look-ahead, or `.ignored` when no pattern matched.
    public mutating func feed(_ line: String) -> LineResult {
        if !eventQueue.isEmpty {
            // Drain one queued event; schedule current line for next call.
            let queued = eventQueue.removeFirst()
            enqueueFromLine(line)
            return .consumed(queued)
        }
        if pendingRecordedIssueLine != nil { return flushRecordedIssue(currentLine: line) }
        return normalFeed(line)
    }

    // Called when a queued event is being returned; current line must still be processed.
    private mutating func enqueueFromLine(_ line: String) {
        updateLookBackBuffer(line)
        if line.contains(XcodebuildSymbols.recordedIssue) {
            pendingRecordedIssueLine = line
        } else if let event = processLine(line) {
            eventQueue.append(event)
        }
    }

    // Path B: holding a buffered recordedIssue line — flush it, possibly amending with comment.
    private mutating func flushRecordedIssue(currentLine line: String) -> LineResult {
        let pending = pendingRecordedIssueLine!
        let buffered = processLine(pending)
        pendingRecordedIssueLine = nil

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isCommentContinuation =
            trimmed.hasPrefix(XcodebuildSymbols.swiftTestingDetailsPrefix)
            || trimmed.hasPrefix(XcodebuildSymbols.swiftTestingDetailsPrefixFallback)
        if isCommentContinuation {
            if let event = buffered, case .testFailed(let failed) = event {
                let comment = String(
                    trimmed.drop(while: { $0 != " " }).drop(while: { $0 == " " })
                )
                let amended = FailedTest(
                    test: failed.test,
                    message: comment.isEmpty ? failed.message : failed.message + ": " + comment,
                    file: failed.file,
                    line: failed.line,
                    duration: failed.duration
                )
                return .consumed(.testFailed(amended))
            }
            return buffered.map { .consumed($0) } ?? .ignored
        } else {
            // Current line is unrelated — enqueue its result, emit buffered now.
            if let overflow = processLine(line) { eventQueue.append(overflow) }
            return buffered.map { .consumed($0) } ?? .ignored
        }
    }

    // Path C: normal processing with look-back enrichment.
    private mutating func normalFeed(_ line: String) -> LineResult {
        if line.contains(XcodebuildSymbols.recordedIssue) {
            pendingRecordedIssueLine = line
            updateLookBackBuffer(line)
            return .buffering
        }

        var event = processLine(line)

        // PhaseScriptExecution look-back: enrich the error message with preceding context.
        if line.contains("Command PhaseScriptExecution failed with a nonzero exit"),
            case .error(let error) = event, error.message == line
        {
            var contextLines: [String] = []
            for contextLine in lookBackBuffer {
                let trimmed = contextLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("Warning:")
                    || trimmed.hasPrefix("Run script build phase")
                {
                    continue
                }
                if trimmed.contains(": warning:") && !trimmed.contains("error:") {
                    continue
                }
                contextLines.append(trimmed)
            }
            if !contextLines.isEmpty {
                let combined = contextLines.joined(separator: " ") + " " + line
                event = .error(BuildError(file: nil, line: nil, message: combined, column: nil))
            }
        }

        updateLookBackBuffer(line)
        return event.map { .consumed($0) } ?? .ignored
    }

    /// Flushes all buffered state and returns any remaining events.
    ///
    /// Call this once after ``feed(_:)`` has been called for every line. The method drains:
    /// - The internal event queue
    /// - Any look-ahead–buffered line that hasn't been emitted yet
    /// - A synthetic `testFailed` crash event when a test was in flight at process exit
    ///
    /// - Returns: Zero or more ``ParseEvent`` values representing buffered output.
    public mutating func flush() -> [ParseEvent] {
        var result: [ParseEvent] = eventQueue
        eventQueue = []
        if let pending = pendingRecordedIssueLine {
            if let event = processLine(pending) { result.append(event) }
            pendingRecordedIssueLine = nil
        }
        // If a test was in-flight when the run ended without a crash-confirmation line,
        // emit a synthetic testFailed so callers don't need to read internal state.
        if sawTestRunFailed, let testName = lastStartedTestName {
            let message =
                pendingSignalCode.map { "Crashed (signal \($0)): last test started before crash" }
                ?? "Test did not complete (possible crash or timeout)"
            result.append(
                .testFailed(
                    FailedTest(
                        test: testName,
                        message: message,
                        file: nil,
                        line: nil
                    )
                )
            )
            lastStartedTestName = nil
        }
        return result
    }

    // MARK: - Look-back buffer

    private mutating func updateLookBackBuffer(_ line: String) {
        lookBackBuffer.append(line)
        if lookBackBuffer.count > 3 {
            lookBackBuffer.removeFirst()
        }
    }

    // MARK: - Core dispatch

    /// Returns at most one ParseEvent for a line. Uses if/else if so only one branch fires.
    private mutating func processLine(_ line: String) -> ParseEvent? {
        if line.isEmpty || line.count > 5000 { return nil }

        // Suite name tracking (state only, no event emitted)
        if let suiteName = parseCompletedXCTestSuiteName(line) {
            lastCompletedXCTestSuiteName = suiteName
        }

        // Linker (multi-line state machine)
        if let event = parseLinkerLine(line) { return event }

        // xcbeautify auto-detection hint
        if !shouldParseXcbeautify && !xcbeautifyHintEmitted {
            if line.hasPrefix(XCBeautifySymbols.asciiError + " ")
                || line.hasPrefix(XCBeautifySymbols.asciiWarning + " ")
                || line.hasPrefix(XCBeautifySymbols.error + " ")
                || line.hasPrefix(XCBeautifySymbols.warning + " ")
            {
                xcbeautifyHintEmitted = true
                didEmitXcbeautifyHint = true
                FileHandle.standardError.write(
                    Data(
                        "hint: Detected xcbeautify-formatted input. Use --xcbeautify flag for proper parsing.\n"
                            .utf8
                    )
                )
            }
        }

        // xcbeautify rewrites the terminal `** … SUCCEEDED **` markers to title-case status lines.
        if shouldParseXcbeautify
            && (line.contains(XCBeautifySymbols.buildSucceeded)
                || line.contains(XCBeautifySymbols.testSucceeded))
        {
            sawSuccessMarker = true
        }

        // xcbeautify parsing
        if shouldParseXcbeautify, let event = parseXcbeautifyLine(line) {
            return event
        }

        // Fast-path filter
        let containsRelevant =
            line.contains(XcodebuildSymbols.errorKeyword)
            || line.contains(XcodebuildSymbols.warningKeyword)
            || line.contains(XcodebuildSymbols.failedKeyword)
            || line.contains(XcodebuildSymbols.passedKeyword)
            || line.contains(XcodebuildSymbols.swiftTestingFail)
            || line.contains(XcodebuildSymbols.swiftTestingPass)
            || line.contains(XcodebuildSymbols.emojiError)
            || line.contains("Build succeeded")
            || line.contains("Build failed")
            || line.contains("Executed")
            || line.contains("] Testing ")
            || line.contains(XcodebuildSymbols.succeededKeyword)
            || line.contains(XcodebuildSymbols.buildFailedKeyword)
            || line.contains(XcodebuildSymbols.testFailed)
            || line.contains(XcodebuildSymbols.buildComplete)
            || line.contains(XcodebuildSymbols.recordedIssue)
            || line.hasPrefix(XcodebuildSymbols.registerWithLaunchServices)
            || line.hasPrefix(XcodebuildSymbols.validate)
            || line.contains(XcodebuildSymbols.fatalErrorKeyword)
            || (line.hasPrefix("/") && line.contains(XcodebuildSymbols.swiftFilePattern))
            || line.contains(XcodebuildSymbols.startedSuffix)
            || line.contains("\" started")
            || line.contains(XcodebuildSymbols.signalCode)
            || line.hasPrefix(XcodebuildSymbols.restartingAfter)
            || line.hasPrefix("Build target ")
            || line.hasPrefix("Build target '")
            || line.contains(XcodebuildSymbols.targetPrefix)
            || line.contains(XcodebuildSymbols.dependencyOnTarget)
            || line.contains(XcodebuildSymbols.spmCompiling)
            || line.contains(XcodebuildSymbols.spmLinking)
            || line.contains("Test run with ")
            || line.hasPrefix("CompileSwiftSources ")
            || line.hasPrefix("CompileC ")
            || line.hasPrefix("Ld ")
            || line.hasPrefix("CopySwiftLibs ")
            || line.hasPrefix("PhaseScriptExecution ")
            || line.hasPrefix("LinkAssetCatalog ")
            || line.hasPrefix("ProcessInfoPlistFile ")
            || (line.contains("SwiftDriver") && line.contains("Compilation"))
            || line.hasPrefix("RegisterWithLaunchServices ")
            || line.hasPrefix("Validate ")

        if !containsRelevant { return nil }

        // Crash detection
        if let event = parseCrashLine(line) { return event }

        // Parallel test scheduling
        if line.contains("] Testing "), let match = line.firstMatch(of: Self.parallelTestSchedulingRegex) {
            if let index = Int(match.1), let total = Int(match.2) {
                return .parallelTestScheduled(index: index, total: total)
            }
        }

        // Executables
        if let exec = parseExecutable(line) { return .executable(exec) }

        // Failed test
        if let failed = parseFailedTest(line) {
            if lastStartedTestName == failed.test { lastStartedTestName = nil }
            return .testFailed(failed)
        }

        // Error
        if let error = parseError(line) {
            // Fatal error + lastStartedTestName → also emit a synthetic testFailed (matches original)
            if line.contains("Fatal error"), let testName = lastStartedTestName {
                lastStartedTestName = nil
                eventQueue.append(
                    .testFailed(
                        FailedTest(
                            test: testName,
                            message: "Crashed (Fatal error): last test started before crash",
                            file: error.file,
                            line: error.line
                        )
                    )
                )
            }
            return .error(error)
        }

        // Warning
        if let warning = parseWarning(line) { return .warning(warning) }
        if let warning = parseRuntimeWarning(line) { return .warning(warning) }

        // Passed test
        if let (name, duration) = parsePassedTest(line) {
            if lastStartedTestName == name { lastStartedTestName = nil }
            return .testPassed(name: name, duration: duration)
        }

        // Build / test time, XCTest summaries, Swift Testing summaries
        if let event = parseBuildAndTestTime(line) { return event }

        // Build phases
        if let (phase, target) = parseBuildPhase(line) { return .buildPhase(target: target, phase: phase) }
        if let (phase, target) = parseSPMPhase(line) { return .buildPhase(target: target, phase: phase) }

        // Target timing
        if let (name, duration) = parseTargetTiming(line) { return .targetCompleted(name: name, duration: duration) }

        // Dependency graph
        if let event = parseDependencyGraph(line) { return event }

        return nil
    }

    // MARK: - Static Regex Patterns

    private nonisolated(unsafe) static let parallelTestSchedulingRegex = Regex {
        "["
        Capture(OneOrMore(.digit))
        "/"
        Capture(OneOrMore(.digit))
        "] Testing "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    // os_log/NSLog runtime line: `YYYY-MM-DD HH:MM:SS… Process[pid:tid]…`
    private nonisolated(unsafe) static let osLogLineRegex = Regex {
        Anchor.startOfSubject
        Repeat(count: 4) { One(.digit) }
        "-"
        Repeat(count: 2) { One(.digit) }
        "-"
        Repeat(count: 2) { One(.digit) }
        " "
        Repeat(count: 2) { One(.digit) }
        ":"
        Repeat(count: 2) { One(.digit) }
        ":"
        Repeat(count: 2) { One(.digit) }
        OneOrMore(.any, .reluctant)
        "["
        OneOrMore(.digit)
        ":"
        OneOrMore(.digit)
        "]"
    }

    /// App runtime logging (e.g. `2026-… App[pid:tid] [error] CoreData: error: …` or bare
    /// `CoreData: error: …`) embeds `: error:`/`: warning:` substrings but is not a compiler
    /// diagnostic. Skip so runtime noise never inflates error/warning counts.
    private func isRuntimeLogNoise(_ line: String) -> Bool {
        if line.hasPrefix(XcodebuildSymbols.coreDataLogPrefix) { return true }
        return line.firstMatch(of: Self.osLogLineRegex) != nil
    }

    // MARK: - Linker Parsing

    private mutating func parseLinkerLine(_ line: String) -> ParseEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix(XcodebuildSymbols.undefinedSymbols) {
            let afterPrefix = trimmed.dropFirst(XcodebuildSymbols.undefinedSymbols.count)
            if let colonIndex = afterPrefix.firstIndex(of: ":") {
                currentLinkerArchitecture = String(afterPrefix[..<colonIndex])
            }
            return nil
        }

        if trimmed.hasPrefix("\"") && trimmed.contains(XcodebuildSymbols.referencedFrom) {
            if let endQuote = trimmed.range(of: XcodebuildSymbols.referencedFrom) {
                let symbol = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< endQuote.lowerBound])
                pendingLinkerSymbol = symbol
            }
            return nil
        }

        if let symbol = pendingLinkerSymbol, let arch = currentLinkerArchitecture,
            trimmed.contains(" in ") && (trimmed.hasSuffix(".o") || trimmed.hasSuffix(".a"))
        {
            if let inRange = trimmed.range(of: " in ") {
                let referencedFrom = String(trimmed[inRange.upperBound...])
                pendingLinkerSymbol = nil
                return .linkerError(
                    LinkerError(symbol: symbol, architecture: arch, referencedFrom: referencedFrom)
                )
            }
            return nil
        }

        if trimmed.hasPrefix(XcodebuildSymbols.frameworkNotFound) {
            let framework = String(trimmed.dropFirst(XcodebuildSymbols.frameworkNotFound.count))
            return .linkerError(LinkerError(message: "framework not found \(framework)"))
        }

        if trimmed.hasPrefix(XcodebuildSymbols.libraryNotFound) {
            let library = String(trimmed.dropFirst(XcodebuildSymbols.libraryNotFound.count))
            return .linkerError(LinkerError(message: "library not found for \(library)"))
        }

        if trimmed.hasPrefix(XcodebuildSymbols.duplicateSymbolSingle)
            || trimmed.hasPrefix(XcodebuildSymbols.duplicateSymbolDouble)
        {
            let quoteChar: Character =
                trimmed.hasPrefix(XcodebuildSymbols.duplicateSymbolSingle) ? "'" : "\""
            let afterPrefix =
                trimmed.hasPrefix(XcodebuildSymbols.duplicateSymbolSingle)
                ? trimmed.dropFirst(XcodebuildSymbols.duplicateSymbolSingle.count)
                : trimmed.dropFirst(XcodebuildSymbols.duplicateSymbolDouble.count)
            if let endQuote = afterPrefix.firstIndex(of: quoteChar) {
                pendingDuplicateSymbol = String(afterPrefix[..<endQuote])
                pendingConflictingFiles = []
            }
            return nil
        }

        if pendingDuplicateSymbol != nil && (trimmed.hasSuffix(".o") || trimmed.hasSuffix(".a"))
            && (line.hasPrefix("    ") || line.hasPrefix("\t"))
        {
            pendingConflictingFiles.append(trimmed)
            return nil
        }

        if trimmed.hasPrefix("ld: building for ") && trimmed.contains("but linking") {
            return .linkerError(LinkerError(message: trimmed))
        }

        if trimmed.hasPrefix("ld: ") && trimmed.contains("duplicate symbol") {
            if let symbol = pendingDuplicateSymbol {
                var arch = ""
                if let archRange = trimmed.range(of: "for architecture ") {
                    arch = String(trimmed[archRange.upperBound...])
                }
                let files = pendingConflictingFiles
                pendingDuplicateSymbol = nil
                pendingConflictingFiles = []
                return .linkerError(
                    LinkerError(symbol: symbol, architecture: arch, conflictingFiles: files)
                )
            }
            return nil
        }

        if trimmed.hasPrefix("ld: symbol(s) not found for architecture ") {
            return nil
        }

        return nil
    }

    // MARK: - Crash Detection

    private mutating func parseCrashLine(_ line: String) -> ParseEvent? {
        // Track "Test Case '...' started." for crash association
        if let name = parseStartedTestName(line) {
            lastStartedTestName = name
            return .testStarted(name: name)
        }

        // Signal code: "Exited with [unexpected] signal code N"
        if line.contains(XcodebuildSymbols.signalCode) {
            if let lastSpace = line.lastIndex(of: " ") {
                let codeStr = String(line[line.index(after: lastSpace)...])
                pendingSignalCode = Int(codeStr)
            }
            return nil
        }

        // Crash confirmation
        if line.hasPrefix(XcodebuildSymbols.restartingAfter) {
            defer {
                lastStartedTestName = nil
                pendingSignalCode = nil
            }
            if let testName = lastStartedTestName {
                let message: String
                if let code = pendingSignalCode {
                    message = "Crashed (signal \(code)): last test started before crash"
                } else {
                    message = "Crashed: last test started before crash"
                }
                return .testFailed(FailedTest(test: testName, message: message, file: nil, line: nil))
            }
            return nil
        }

        return nil
    }

    private func parseStartedTestName(_ line: String) -> String? {
        if (line.hasPrefix(XcodebuildSymbols.testCasePrefix)
            || line.hasPrefix(XcodebuildSymbols.testCaseLowerPrefix))
            && line.contains(XcodebuildSymbols.startedSuffix)
        {
            let prefixLength = XcodebuildSymbols.testCasePrefix.count
            let startIndex = line.index(line.startIndex, offsetBy: prefixLength)
            if let endQuote = line.range(
                of: XcodebuildSymbols.startedSuffix,
                range: startIndex ..< line.endIndex
            ) {
                return String(line[startIndex ..< endQuote.lowerBound])
            }
        }

        if line.hasPrefix("◇ Test ") {
            let afterPrefix = line.index(line.startIndex, offsetBy: "◇ Test ".count)
            if let result = extractSwiftTestingName(from: line, after: afterPrefix) {
                let afterName = line[result.endIndex...]
                if afterName.hasPrefix(" started") {
                    return result.name
                }
            }
        }
        return nil
    }

    // MARK: - XCTest suite name tracking

    private func parseCompletedXCTestSuiteName(_ line: String) -> String? {
        guard
            line.contains(XcodebuildSymbols.testSuitePassedMarker)
                || line.contains(XcodebuildSymbols.testSuiteFailedMarker)
        else { return nil }

        for prefix in [XcodebuildSymbols.testSuitePrefix, XcodebuildSymbols.testSuiteLowerPrefix] {
            guard let prefixRange = line.range(of: prefix) else { continue }
            let suiteStart = prefixRange.upperBound
            if let suiteEnd = line[suiteStart...].firstIndex(of: "'") {
                return String(line[suiteStart ..< suiteEnd])
            }
        }
        return nil
    }

    // MARK: - xcbeautify

    private func parseXcbeautifyLine(_ line: String) -> ParseEvent? {
        let errorPrefix = XCBeautifySymbols.asciiError + " "
        let emojiErrorPrefix = XCBeautifySymbols.error + " "
        if line.hasPrefix(errorPrefix) {
            return .error(parseXcbeautifyDiagnosticAsError(String(line.dropFirst(errorPrefix.count))))
        }
        if line.hasPrefix(emojiErrorPrefix) {
            return .error(
                parseXcbeautifyDiagnosticAsError(String(line.dropFirst(emojiErrorPrefix.count)))
            )
        }

        let warningPrefix = XCBeautifySymbols.asciiWarning + " "
        let emojiWarningPrefix = XCBeautifySymbols.warning + " "
        if line.hasPrefix(warningPrefix) {
            return .warning(
                parseXcbeautifyDiagnosticAsWarning(String(line.dropFirst(warningPrefix.count)))
            )
        }
        if line.hasPrefix(emojiWarningPrefix) {
            return .warning(
                parseXcbeautifyDiagnosticAsWarning(String(line.dropFirst(emojiWarningPrefix.count)))
            )
        }

        let passPrefix = XCBeautifySymbols.pass + " "
        if line.hasPrefix(passPrefix) {
            return parseXcbeautifyTestResult(
                String(line.dropFirst(passPrefix.count)),
                passed: true
            )
        }

        let failPrefix = XCBeautifySymbols.fail + " "
        if line.hasPrefix(failPrefix) {
            return parseXcbeautifyTestResult(
                String(line.dropFirst(failPrefix.count)),
                passed: false
            )
        }

        return nil
    }

    private func parseXcbeautifyDiagnostic(_ content: String) -> (
        file: String?, line: Int?, column: Int?, message: String
    ) {
        let components = content.split(
            separator: ":",
            maxSplits: .max,
            omittingEmptySubsequences: false
        )

        if components.count >= 4 {
            for i in stride(from: components.count - 2, through: 1, by: -1) {
                let trimmedCol = components[i].trimmingCharacters(in: .whitespaces)
                let trimmedLine = components[i - 1].trimmingCharacters(in: .whitespaces)
                if let colNum = Int(trimmedCol), let lineNum = Int(trimmedLine) {
                    let file = components[0 ..< (i - 1)].joined(separator: ":")
                    if !file.isEmpty && (file.contains("/") || file.contains(".")) {
                        let message = components[(i + 1)...].joined(separator: ":").trimmingCharacters(
                            in: .whitespaces
                        )
                        return (file: file, line: lineNum, column: colNum, message: message)
                    }
                }
            }
        }

        if components.count >= 3 {
            for i in stride(from: components.count - 1, through: 1, by: -1) {
                let trimmedLine = components[i - 1].trimmingCharacters(in: .whitespaces)
                if let lineNum = Int(trimmedLine) {
                    let file = components[0 ..< (i - 1)].joined(separator: ":")
                    if !file.isEmpty && (file.contains("/") || file.contains(".")) {
                        let message = components[i...].joined(separator: ":").trimmingCharacters(
                            in: .whitespaces
                        )
                        return (file: file, line: lineNum, column: nil, message: message)
                    }
                }
            }
        }

        return (file: nil, line: nil, column: nil, message: content)
    }

    private func parseXcbeautifyDiagnosticAsError(_ content: String) -> BuildError {
        let (file, line, column, message) = parseXcbeautifyDiagnostic(content)
        return BuildError(file: file, line: line, message: message, column: column)
    }

    private func parseXcbeautifyDiagnosticAsWarning(_ content: String) -> BuildWarning {
        let (file, line, _, message) = parseXcbeautifyDiagnostic(content)
        return BuildWarning(file: file, line: line, message: message)
    }

    private func parseXcbeautifyTestResult(_ content: String, passed: Bool) -> ParseEvent? {
        let keyword = passed ? " passed" : " failed"
        guard let keywordRange = content.range(of: keyword) else { return nil }
        let testName = String(content[content.startIndex ..< keywordRange.lowerBound])
        if testName.isEmpty { return nil }

        var duration: Double?
        let afterKeyword = String(content[keywordRange.upperBound...])
        if let openParen = afterKeyword.firstIndex(of: "("),
            let closeParen = afterKeyword.firstIndex(of: ")")
        {
            let durationStr =
                afterKeyword[afterKeyword.index(after: openParen) ..< closeParen]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " seconds", with: "")
            duration = Double(durationStr)
        }

        if passed {
            return .testPassed(name: testName, duration: duration)
        } else {
            return .testFailed(
                FailedTest(test: testName, message: "Test failed", file: nil, line: nil, duration: duration)
            )
        }
    }

    // MARK: - Error / Warning Parsing

    private func isJSONLikeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("}")
            || trimmed.hasPrefix("]")
        {
            return true
        }
        if trimmed.hasPrefix("\"") && trimmed.contains("\" :") { return true }
        if line.contains("\\\"") && line.contains("\"") && line.contains(":") { return true }
        if line.hasPrefix(" ") || line.hasPrefix("\t") {
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("}") || trimmed.hasPrefix("[")
                || trimmed.hasPrefix("]")
            {
                return true
            }
            if trimmed.hasPrefix("\"") && trimmed.contains("\" :") { return true }
        }
        if line.contains("error:") {
            if trimmed.hasPrefix("\"") && trimmed.contains(":") { return true }
            if (line.hasPrefix(" ") || line.hasPrefix("\t")) && trimmed.hasPrefix("\"") { return true }
            if !trimmed.hasPrefix("error:") {
                let hasQuotedStrings = line.contains("\"") && line.contains(":")
                let hasEscapedContent = line.contains("\\") && line.contains("\"")
                if hasEscapedContent && hasQuotedStrings && !line.contains("file:")
                    && !line.contains(".swift:") && !line.contains(".m:") && !line.contains(".h:")
                {
                    return true
                }
            }
        }
        return false
    }

    private func parseError(_ line: String) -> BuildError? {
        if isJSONLikeLine(line) { return nil }
        if isRuntimeLogNoise(line) { return nil }
        if line.hasPrefix(" "), line.contains("|") || line.contains("`") { return nil }

        if let errorRange = line.range(of: XcodebuildSymbols.errorFormat) {
            let beforeError = String(line[..<errorRange.lowerBound])
            let message = String(line[errorRange.upperBound...])
            let components = beforeError.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 3, let lineNum = Int(components[components.count - 2]),
                let colNum = Int(components[components.count - 1])
            {
                let file = components[0 ..< (components.count - 2)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message, column: colNum)
            } else if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message, column: nil)
            } else {
                return BuildError(file: beforeError, line: nil, message: message, column: nil)
            }
        }

        if let fatalRange = line.range(of: XcodebuildSymbols.fatalErrorFormat) {
            let beforeError = String(line[..<fatalRange.lowerBound])
            let message = String(line[fatalRange.upperBound...])
            let components = beforeError.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message, column: nil)
            } else {
                return BuildError(file: beforeError, line: nil, message: message, column: nil)
            }
        }

        if line.hasSuffix(XcodebuildSymbols.fatalErrorSuffix), !line.contains(" xctest[") {
            let beforeFatal = String(line.dropLast(XcodebuildSymbols.fatalErrorSuffix.count))
            let components = beforeFatal.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: "Fatal error", column: nil)
            }
        }

        if line.hasPrefix(XcodebuildSymbols.emojiError + " ") {
            return BuildError(file: nil, line: nil, message: String(line.dropFirst(2)), column: nil)
        }

        if line.hasPrefix("error: ") {
            return BuildError(file: nil, line: nil, message: String(line.dropFirst(7)), column: nil)
        }

        if line.contains("Command PhaseScriptExecution failed with a nonzero exit") {
            return BuildError(file: nil, line: nil, message: line, column: nil)
        }

        return nil
    }

    private func parseWarning(_ line: String) -> BuildWarning? {
        if isJSONLikeLine(line) { return nil }
        if isRuntimeLogNoise(line) { return nil }
        if line.hasPrefix(" "), line.contains("|") || line.contains("`") { return nil }

        if let warningRange = line.range(of: XcodebuildSymbols.warningFormat) {
            let beforeWarning = String(line[..<warningRange.lowerBound])
            let message = String(line[warningRange.upperBound...])
            let components = beforeWarning.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 3, let lineNum = Int(components[components.count - 2]),
                let colNum = Int(components[components.count - 1])
            {
                let file = components[0 ..< (components.count - 2)].joined(separator: ":")
                return BuildWarning(file: file, line: lineNum, message: message, column: colNum)
            } else if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildWarning(file: file, line: lineNum, message: message)
            } else {
                return BuildWarning(file: beforeWarning, line: nil, message: message)
            }
        }

        if line.hasPrefix("warning: ") {
            return BuildWarning(file: nil, line: nil, message: String(line.dropFirst(9)))
        }

        return nil
    }

    private func parseRuntimeWarning(_ line: String) -> BuildWarning? {
        if line.contains(": warning:") || line.contains(": error:") { return nil }
        guard line.hasPrefix("/"), line.contains(XcodebuildSymbols.swiftFilePattern) else { return nil }
        if line.contains("|") || line.contains("`-") { return nil }

        guard let swiftColonRange = line.range(of: ".swift:") else { return nil }
        let afterColon = line[swiftColonRange.upperBound...]

        var lineNumEnd = afterColon.startIndex
        while lineNumEnd < afterColon.endIndex, afterColon[lineNumEnd].isNumber {
            lineNumEnd = afterColon.index(after: lineNumEnd)
        }

        guard lineNumEnd > afterColon.startIndex, lineNumEnd < afterColon.endIndex,
            afterColon[lineNumEnd] == " "
        else { return nil }

        guard let lineNum = Int(String(afterColon[..<lineNumEnd])) else { return nil }

        let file = String(line[..<swiftColonRange.lowerBound]) + ".swift"
        let message = String(afterColon[afterColon.index(after: lineNumEnd)...])
        guard !message.isEmpty else { return nil }

        return BuildWarning(
            file: file,
            line: lineNum,
            message: message,
            type: detectRuntimeWarningType(message: message)
        )
    }

    private func detectRuntimeWarningType(message: String) -> WarningType {
        let swiftuiKeywords = [
            "Accessing Environment",
            "Accessing StateObject",
            "StateObject's wrappedValue",
            "Publishing changes from background",
            "Publishing changes from within view",
            "Modifying state during view update",
            "will always read the default value",
        ]
        return swiftuiKeywords.contains(where: { message.contains($0) }) ? .swiftui : .runtime
    }

    // MARK: - Test Parsing

    private func parsePassedTest(_ line: String) -> (name: String, duration: Double?)? {
        let isStandardPassed =
            line.hasPrefix(XcodebuildSymbols.testCasePrefix)
            && line.contains(XcodebuildSymbols.testPassedSuffix)
        let isParallelPassed =
            line.hasPrefix(XcodebuildSymbols.testCaseLowerPrefix)
            && line.contains(XcodebuildSymbols.testPassedOnSuffix)

        if isStandardPassed || isParallelPassed {
            let prefixLength = XcodebuildSymbols.testCasePrefix.count
            let startIndex = line.index(line.startIndex, offsetBy: prefixLength)
            let passedPattern =
                isParallelPassed
                ? XcodebuildSymbols.testPassedOnSuffix : XcodebuildSymbols.testPassedSuffix
            guard let endQuote = line.range(of: passedPattern) else { return nil }
            let testName = String(line[startIndex ..< endQuote.lowerBound])

            var duration: Double?
            if let lastParen = line.range(of: "(", options: .backwards),
                let secondsEnd = line.range(of: XcodebuildSymbols.secondsKeyword, options: .backwards)
            {
                duration = Double(String(line[lastParen.upperBound ..< secondsEnd.lowerBound]))
            }
            return (testName, duration)
        }

        if line.hasPrefix("✓ Test \""), let endQuote = line.range(of: "\" passed") {
            let startIndex = line.index(line.startIndex, offsetBy: 8)
            let testName = String(line[startIndex ..< endQuote.lowerBound])
            var duration: Double?
            if let afterRange = line.range(of: " after ", range: endQuote.upperBound ..< line.endIndex) {
                let afterStr = line[afterRange.upperBound...]
                if let secondsRange = afterStr.range(of: " seconds") {
                    duration = Double(String(afterStr[..<secondsRange.lowerBound]))
                }
            }
            return (testName, duration)
        }

        return nil
    }

    private func parseFailedTest(_ line: String) -> FailedTest? {
        if line.contains("XCTAssertEqual failed") || line.contains("XCTAssertTrue failed")
            || line.contains("XCTAssertFalse failed")
        {
            if let errorRange = line.range(of: ": error: -["),
                let bracketEnd = line.range(of: "] : ", range: errorRange.upperBound ..< line.endIndex)
            {
                let beforeError = String(line[..<errorRange.lowerBound])
                let testName = String(line[errorRange.upperBound ..< bracketEnd.lowerBound])
                let message = String(line[bracketEnd.upperBound...])
                let components = beforeError.split(separator: ":", omittingEmptySubsequences: false)
                if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                    let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                    return FailedTest(test: testName, message: message, file: file, line: lineNum)
                }
            }
            if let bracketStart = line.range(of: "-["),
                let bracketEnd = line.range(of: "]", range: bracketStart.upperBound ..< line.endIndex)
            {
                let testName = String(line[bracketStart.upperBound ..< bracketEnd.lowerBound])
                return FailedTest(
                    test: testName,
                    message: line.trimmingCharacters(in: .whitespaces),
                    file: nil,
                    line: nil
                )
            }
            return FailedTest(
                test: "Test assertion",
                message: line.trimmingCharacters(in: .whitespaces),
                file: nil,
                line: nil
            )
        }

        let isStandardFailed =
            line.hasPrefix(XcodebuildSymbols.testCasePrefix)
            && line.contains(XcodebuildSymbols.testFailedSuffix)
        let isParallelFailed =
            line.hasPrefix(XcodebuildSymbols.testCaseLowerPrefix)
            && line.contains(XcodebuildSymbols.testFailedOnSuffix)

        if isStandardFailed || isParallelFailed {
            let prefixLength = XcodebuildSymbols.testCasePrefix.count
            let startIndex = line.index(line.startIndex, offsetBy: prefixLength)
            let failedPattern =
                isParallelFailed
                ? XcodebuildSymbols.testFailedOnSuffix : XcodebuildSymbols.testFailedSuffix
            guard let endQuote = line.range(of: failedPattern) else { return nil }
            let test = String(line[startIndex ..< endQuote.lowerBound])

            var duration: Double?
            if let lastParen = line.range(of: "(", options: .backwards),
                let secondsEnd = line.range(of: XcodebuildSymbols.secondsKeyword, options: .backwards)
            {
                duration = Double(String(line[lastParen.upperBound ..< secondsEnd.lowerBound]))
            }

            let message = duration.map { String(format: "%.3f seconds", $0) } ?? "failed"
            return FailedTest(test: test, message: message, file: nil, line: nil, duration: duration)
        }

        if let testStart = line.range(of: "Test ") {
            let afterTestStr = line[testStart.upperBound...]
            if !afterTestStr.hasPrefix("run with ") && !afterTestStr.hasPrefix("Case ") {
                if let (testName, nameEnd) = extractSwiftTestingName(
                    from: line,
                    after: testStart.upperBound
                ) {
                    let afterName = line[nameEnd...]

                    if let issueAt = afterName.range(of: " recorded an issue at ") {
                        let afterIssue = String(line[issueAt.upperBound...])
                        let parts = afterIssue.split(
                            separator: ":",
                            maxSplits: 3,
                            omittingEmptySubsequences: false
                        )
                        if parts.count >= 4, let lineNum = Int(parts[1]) {
                            let file = String(parts[0])
                            let message = String(parts[3]).trimmingCharacters(in: .whitespaces)
                            return FailedTest(test: testName, message: message, file: file, line: lineNum)
                        }
                    }

                    if let failedAfter = afterName.range(of: " failed after ") {
                        var duration: Double?
                        let afterFailed = line[failedAfter.upperBound...]
                        if let secondsRange = afterFailed.range(of: " seconds") {
                            duration = Double(String(afterFailed[..<secondsRange.lowerBound]))
                        }
                        return FailedTest(
                            test: testName,
                            message: "Test failed",
                            file: nil,
                            line: nil,
                            duration: duration
                        )
                    }
                }
            }
        }

        if line.hasPrefix("❌ "), let parenStart = line.range(of: " ("),
            let parenEnd = line.range(of: ")", options: .backwards)
        {
            let startIndex = line.index(line.startIndex, offsetBy: 2)
            let test = String(line[startIndex ..< parenStart.lowerBound])
            let message = String(line[parenStart.upperBound ..< parenEnd.lowerBound])
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }

        if line.hasSuffix(") failed") || line.hasSuffix(") failed."),
            let parenStart = line.range(of: " ("),
            let parenEnd = line.range(of: ") failed", options: .backwards)
        {
            let test = String(line[..<parenStart.lowerBound])
            let message = String(line[parenStart.upperBound ..< parenEnd.lowerBound])
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }

        return nil
    }

    // MARK: - Swift Testing name extraction

    private func extractSwiftTestingName(
        from line: String,
        after startIndex: String.Index
    ) -> (name: String, endIndex: String.Index)? {
        let afterTest = line[startIndex...]

        if afterTest.hasPrefix("\"") {
            let nameStart = line.index(after: startIndex)
            if let quoteEnd = line[nameStart...].firstIndex(of: "\"") {
                return (String(line[nameStart ..< quoteEnd]), line.index(after: quoteEnd))
            }
        }

        let endMarkers = [" recorded", " failed", " passed", " started"]
        for marker in endMarkers {
            if let markerRange = afterTest.range(of: marker) {
                let name = String(line[startIndex ..< markerRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                return (name, markerRange.lowerBound)
            }
        }

        return nil
    }

    // MARK: - Build / Test Time

    private func bracketedTime(_ line: String) -> ParseEvent? {
        if let bracketStart = line.range(of: "[", options: .backwards),
            let bracketEnd = line.range(of: "]", options: .backwards),
            bracketStart.lowerBound < bracketEnd.lowerBound
        {
            return .buildTime(String(line[bracketStart.upperBound ..< bracketEnd.lowerBound]))
        }
        return nil
    }

    private mutating func parseBuildAndTestTime(_ line: String) -> ParseEvent? {
        if line.contains(XcodebuildSymbols.buildSucceeded)
            || line.contains(XcodebuildSymbols.testSucceeded)
            || line.contains(XcodebuildSymbols.testExecuteSucceeded)
        {
            sawSuccessMarker = true
            return bracketedTime(line)
        }

        if line.contains(XcodebuildSymbols.buildFailed) {
            sawFailureMarker = true
            return bracketedTime(line)
        }

        if line.contains(XcodebuildSymbols.testFailed) {
            sawTestRunFailed = true
            sawFailureMarker = true
            return .testRunFailed
        }

        if line.hasPrefix(XcodebuildSymbols.buildComplete) {
            sawSuccessMarker = true
            if let parenStart = line.range(of: "("),
                let parenEnd = line.range(of: ")"),
                parenStart.lowerBound < parenEnd.lowerBound
            {
                return .buildTime(String(line[parenStart.upperBound ..< parenEnd.lowerBound]))
            }
            return nil
        }

        if line.hasPrefix(XcodebuildSymbols.buildSucceededInPrefix) {
            sawSuccessMarker = true
            return .buildTime(String(line.dropFirst(XcodebuildSymbols.buildSucceededInPrefix.count)))
        }

        if line.hasPrefix(XcodebuildSymbols.buildFailedAfterPrefix) {
            sawFailureMarker = true
            return .buildTime(String(line.dropFirst(XcodebuildSymbols.buildFailedAfterPrefix.count)))
        }

        // XCTest "Executed N tests" summary
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("Executed "), let withRange = trimmedLine.range(of: ", with ") {
            var executedCount: Int?
            let afterExecuted = trimmedLine[
                trimmedLine.index(trimmedLine.startIndex, offsetBy: 9) ..< withRange.lowerBound
            ]
            if let countStr = afterExecuted.split(separator: " ").first,
                let total = Int(countStr)
            {
                executedCount = total
            }

            var failureCount: Int = 0
            let afterWith = String(trimmedLine[withRange.upperBound...])
            if let failureRange = afterWith.range(of: " failure") {
                let beforeFailure = afterWith[..<failureRange.lowerBound]
                if let lastWord = beforeFailure.split(separator: " ").last,
                    let failures = Int(lastWord)
                {
                    failureCount = failures
                }
            }

            var duration: Double = 0
            if let inRange = trimmedLine.range(
                of: " in ",
                range: withRange.upperBound ..< trimmedLine.endIndex
            ) {
                let afterIn = trimmedLine[inRange.upperBound...]
                let durationStr: String
                if let parenStart = afterIn.range(of: " (") {
                    durationStr = String(afterIn[..<parenStart.lowerBound])
                } else if let secondsRange = afterIn.range(of: " seconds", options: .backwards) {
                    durationStr = String(afterIn[..<secondsRange.lowerBound])
                } else {
                    durationStr = String(afterIn)
                }
                duration = Double(durationStr.trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))) ?? 0
            }

            let suiteName = lastCompletedXCTestSuiteName ?? ""
            lastCompletedXCTestSuiteName = nil

            if let executed = executedCount {
                return .testSuiteCompleted(
                    suiteName: suiteName,
                    executed: executed,
                    failed: failureCount,
                    duration: duration
                )
            }
            return nil
        }

        // Swift Testing failure summary: "Test run with N test(s) failed, N test(s) passed after X seconds."
        if let testRunRange = line.range(of: "Test run with "),
            let failedRange = line.range(of: " failed, ", range: testRunRange.upperBound ..< line.endIndex),
            let passedRange = line.range(of: " passed after ", range: failedRange.upperBound ..< line.endIndex)
        {
            let beforeFailed = line[testRunRange.upperBound ..< failedRange.lowerBound]
            let failedCount = Int(beforeFailed.split(separator: " ").first ?? "") ?? 0

            let beforePassed = line[failedRange.upperBound ..< passedRange.lowerBound]
            let passedCount = Int(beforePassed.split(separator: " ").first ?? "") ?? 0

            let afterPassed = line[passedRange.upperBound...]
            let durationStr: String
            if let secondsRange = afterPassed.range(of: " seconds", options: .backwards) {
                durationStr = String(afterPassed[..<secondsRange.lowerBound])
            } else {
                durationStr = String(afterPassed)
            }
            let duration = Double(durationStr.trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))) ?? 0

            return .swiftTestingCompleted(
                executed: passedCount + failedCount,
                failed: failedCount,
                duration: duration
            )
        }

        // Swift Testing failure summary: "Test run with N test(s) in M suite(s) failed after X seconds with Y issue(s)."
        if let testRunRange = line.range(of: "Test run with "),
            let failedAfterRange = line.range(
                of: " failed after ",
                range: testRunRange.upperBound ..< line.endIndex
            )
        {
            let beforeFailed = line[testRunRange.upperBound ..< failedAfterRange.lowerBound]
            let totalCount = Int(beforeFailed.split(separator: " ").first ?? "") ?? 0

            let afterFailed = line[failedAfterRange.upperBound...]
            var duration: Double = 0
            var issueCount: Int = 0

            if let secondsRange = afterFailed.range(of: " seconds", options: .backwards) {
                duration =
                    Double(
                        String(afterFailed[..<secondsRange.lowerBound]).trimmingCharacters(
                            in: CharacterSet(charactersIn: ". \t")
                        )
                    ) ?? 0
                let afterSeconds = afterFailed[secondsRange.upperBound...]
                if let withRange = afterSeconds.range(of: " with "),
                    let issueRange = afterSeconds.range(
                        of: " issue",
                        range: withRange.upperBound ..< afterSeconds.endIndex
                    )
                {
                    issueCount =
                        Int(
                            afterSeconds[withRange.upperBound ..< issueRange.lowerBound]
                                .trimmingCharacters(in: .whitespaces)
                        ) ?? 0
                }
            } else {
                duration =
                    Double(String(afterFailed).trimmingCharacters(in: CharacterSet(charactersIn: ". \t")))
                    ?? 0
            }

            let clampedIssueCount = min(issueCount, totalCount)
            return .swiftTestingCompleted(executed: totalCount, failed: clampedIssueCount, duration: duration)
        }

        // Swift Testing passed summary: "Test run with N tests in N suites passed after X seconds."
        if let testRunRange = line.range(of: "Test run with "),
            let passedAfter = line.range(of: " passed after ")
        {
            let afterPrefix = line[testRunRange.upperBound ..< passedAfter.lowerBound]
            if let totalCountStr = afterPrefix.split(separator: " ").first,
                let total = Int(totalCountStr)
            {
                var duration: Double = 0
                if total > 0 {
                    let afterPassed = line[passedAfter.upperBound...]
                    let durationStr: String
                    if let secondsRange = afterPassed.range(of: " seconds", options: .backwards) {
                        durationStr = String(afterPassed[..<secondsRange.lowerBound])
                    } else {
                        durationStr = String(afterPassed)
                    }
                    duration =
                        Double(durationStr.trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))) ?? 0
                }
                return .swiftTestingCompleted(executed: total, failed: 0, duration: duration)
            }
        }

        return nil
    }

    // MARK: - Build Phase Parsing

    private static let phasePatterns: [(prefix: String, phaseName: String)] = [
        ("CompileSwiftSources ", "CompileSwiftSources"),
        ("CompileC ", "CompileC"),
        ("Ld ", "Link"),
        ("CopySwiftLibs ", "CopySwiftLibs"),
        ("PhaseScriptExecution ", "PhaseScriptExecution"),
        ("LinkAssetCatalog ", "LinkAssetCatalog"),
        ("ProcessInfoPlistFile ", "ProcessInfoPlistFile"),
    ]

    private func extractTarget(from line: String) -> String? {
        if let inTargetRange = line.range(of: XcodebuildSymbols.inTarget) {
            let afterTarget = line[inTargetRange.upperBound...]
            if let endQuote = afterTarget.range(of: "'") {
                return String(afterTarget[..<endQuote.lowerBound])
            }
        }
        return nil
    }

    private func parseBuildPhase(_ line: String) -> (phaseName: String, target: String)? {
        for (prefix, phaseName) in Self.phasePatterns {
            if line.hasPrefix(prefix), let target = extractTarget(from: line) {
                return (phaseName, target)
            }
        }
        if line.contains("SwiftDriver"), line.contains("Compilation"),
            let target = extractTarget(from: line)
        {
            return ("SwiftCompilation", target)
        }
        return nil
    }

    private func parseSPMPhase(_ line: String) -> (phaseName: String, target: String)? {
        if line.contains(XcodebuildSymbols.spmCompiling),
            let compilingRange = line.range(of: XcodebuildSymbols.spmCompiling)
        {
            let afterCompiling = line[compilingRange.upperBound...]
            let parts = afterCompiling.split(separator: " ", maxSplits: 1)
            if let targetName = parts.first {
                let target = String(targetName)
                if target == "plugin" { return nil }
                return ("Compiling", target)
            }
        }
        if line.contains(XcodebuildSymbols.spmLinking),
            let linkingRange = line.range(of: XcodebuildSymbols.spmLinking)
        {
            let afterLinking = line[linkingRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if !afterLinking.isEmpty { return ("Linking", afterLinking) }
        }
        return nil
    }

    // MARK: - Target Timing

    private func parseTargetTiming(_ line: String) -> (name: String, duration: String)? {
        if line.hasPrefix("Build target "), line.contains(" of project ") {
            let afterBuildTarget = line.dropFirst("Build target ".count)
            if let ofProjectRange = afterBuildTarget.range(of: " of project ") {
                let targetName = String(afterBuildTarget[..<ofProjectRange.lowerBound])
                if let parenStart = line.range(of: "(", options: .backwards),
                    let parenEnd = line.range(of: ")", options: .backwards),
                    parenStart.lowerBound < parenEnd.lowerBound
                {
                    return (targetName, String(line[parenStart.upperBound ..< parenEnd.lowerBound]))
                }
            }
        }
        if line.hasPrefix("Build target '"), line.contains("' completed") {
            let afterPrefix = line.dropFirst("Build target '".count)
            if let endQuote = afterPrefix.range(of: "'") {
                let targetName = String(afterPrefix[..<endQuote.lowerBound])
                if let parenStart = line.range(of: "(", options: .backwards),
                    let parenEnd = line.range(of: ")", options: .backwards),
                    parenStart.lowerBound < parenEnd.lowerBound
                {
                    return (targetName, String(line[parenStart.upperBound ..< parenEnd.lowerBound]))
                }
            }
        }
        return nil
    }

    // MARK: - Dependency Graph

    private mutating func parseDependencyGraph(_ line: String) -> ParseEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix(XcodebuildSymbols.targetPrefix) && trimmed.contains("' in project '") {
            let afterTarget = trimmed.dropFirst(XcodebuildSymbols.targetPrefix.count)
            if let endQuote = afterTarget.range(of: "'") {
                let targetName = String(afterTarget[..<endQuote.lowerBound])
                currentDependencyTarget = targetName
                return .targetDiscovered(name: targetName)
            }
            return nil
        }

        if trimmed.contains(XcodebuildSymbols.dependencyOnTarget),
            let currentTarget = currentDependencyTarget,
            let startQuote = trimmed.range(of: XcodebuildSymbols.dependencyOnTarget)
        {
            let afterStartQuote = trimmed[startQuote.upperBound...]
            if let endQuote = afterStartQuote.range(of: "'") {
                let dependencyName = String(afterStartQuote[..<endQuote.lowerBound])
                return .targetDependency(target: currentTarget, dependsOn: dependencyName)
            }
        }

        return nil
    }

    // MARK: - Executable Parsing

    private func parseExecutable(_ line: String) -> Executable? {
        let prefixes = [
            XcodebuildSymbols.registerWithLaunchServices + " ",
            XcodebuildSymbols.validate + " ",
        ]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        let afterPrefix = line.dropFirst(prefix.count)

        guard let targetRange = afterPrefix.range(of: " " + XcodebuildSymbols.inTarget) else {
            return nil
        }
        let path = String(afterPrefix[..<targetRange.lowerBound])
        if !path.hasSuffix(XcodebuildSymbols.appBundleExt) { return nil }

        let name = (path as NSString).lastPathComponent
        let afterTarget = afterPrefix[targetRange.upperBound...]
        guard let targetEnd = afterTarget.range(of: "' from project") else { return nil }
        let target = String(afterTarget[..<targetEnd.lowerBound])

        return Executable(path: path, name: name, target: target)
    }
}
