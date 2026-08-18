import Foundation
import RegexBuilder

/// Incrementally parses xcodebuild or SPM output and returns a structured ``BuildResult``.
///
/// A `StreamingOutputParser` is a single-use parsing session. Feed it complete lines, then call
/// ``finish(coverage:)`` once the source reaches EOF. Use ``OutputParser`` when the complete build
/// output is already in memory.
///
/// ```swift
/// var parser = StreamingOutputParser(printWarnings: true)
/// parser.feed(line)
/// let result = parser.finish()
/// ```
public struct StreamingOutputParser {

    private struct WarningKey: Hashable {
        let file: String?
        let line: Int?
        let message: String
    }

    private struct ParseState {
        var errors: [BuildError] = []
        var warnings: [BuildWarning] = []
        var failedTests: [FailedTest] = []
        var linkerErrors: [LinkerError] = []
        var executables: [Executable] = []
        var seenExecutablePaths: Set<String> = []
        var buildTime: String?
        var swiftTestingTimeAccumulator: Double = 0
        var seenTestNames: Set<String> = []
        var seenWarnings: Set<WarningKey> = []
        var warningCount = 0
        var seenErrors: Set<String> = []
        var seenLinkerErrors: Set<String> = []
        var seenPassedTestNames: Set<String> = []
        var xctestBundleExecutedCount: Int = 0
        var xctestBundleFailedCount: Int = 0
        var xctestBundleDuration: Double = 0
        var xctestFallbackExecutedCount: Int?
        var xctestFallbackFailedCount: Int?
        var xctestFallbackDuration: Double = 0
        var sawBundleLevelXCTestSummary: Bool = false
        var swiftTestingExecutedCount: Int?
        var swiftTestingFailedCount: Int?
        var passedTestsCount: Int = 0
        var parallelTestsTotalCount: Int?
        var lastParallelTestSchedulingIndex: Int?
        var testRunFailed: Bool = false
        var passedTestDurations: [String: Double] = [:]
        var failedTestDurations: [String: Double] = [:]
        var targetPhases: [String: [String]] = [:]
        var targetDurations: [String: String] = [:]
        var targetOrder: [String] = []
        var targetDependencies: [String: [String]] = [:]
    }

    private var state = ParseState()
    private var lineParser = LineParser()
    private var shouldPrintWarnings = false
    private var shouldRetainWarnings = true
    private var shouldTreatWarningsAsErrors = false
    private var shouldPrintCoverageDetails = false
    private var slowThreshold: Double?
    private var shouldPrintBuildInfo = false
    private var shouldPrintExecutables = false
    private var shouldDiscoverTestedTarget = false
    private var finishedResult: BuildResult?

    /// `true` if this session caused an xcbeautify auto-detection hint to be written to stderr.
    public private(set) var didEmitXcbeautifyHint: Bool = false

    /// The tested target discovered while feeding build output, when target discovery is enabled.
    public private(set) var testedTarget: String?

    // Target regex for extractTestedTarget (used externally)
    private nonisolated(unsafe) static let testSuiteRegex = Regex {
        /[Tt]est [Ss]uite '/
        Capture(OneOrMore(.any, .reluctant))
        ".xctest'"
    }

    /// Creates a single-use streaming parse session.
    ///
    /// - Parameters:
    ///   - printWarnings: Include retained warning details when encoding the result.
    ///   - retainWarnings: Keep warning models in the result. Disable for exact count-only parsing.
    ///   - warningsAsErrors: Convert warnings to errors when finishing; this forces retention.
    ///   - printCoverageDetails: Include per-file coverage details when encoding the result.
    ///   - slowThreshold: Report tests slower than this many seconds.
    ///   - printBuildInfo: Accumulate per-target phases, timing, and dependencies.
    ///   - printExecutables: Include discovered executable targets.
    ///   - discoverTestedTarget: Detect the `.xctest` target used for coverage filtering.
    ///   - xcbeautify: Parse xcbeautify/Tuist markers.
    public init(
        printWarnings: Bool = false,
        retainWarnings: Bool = true,
        warningsAsErrors: Bool = false,
        printCoverageDetails: Bool = false,
        slowThreshold: Double? = nil,
        printBuildInfo: Bool = false,
        printExecutables: Bool = false,
        discoverTestedTarget: Bool = false,
        xcbeautify: Bool = false
    ) {
        lineParser = LineParser(
            xcbeautify: xcbeautify,
            parseBuildInfo: printBuildInfo
        )
        shouldPrintWarnings = printWarnings
        shouldRetainWarnings = retainWarnings || printWarnings || warningsAsErrors
        shouldTreatWarningsAsErrors = warningsAsErrors
        shouldPrintCoverageDetails = printCoverageDetails
        self.slowThreshold = slowThreshold
        shouldPrintBuildInfo = printBuildInfo
        shouldPrintExecutables = printExecutables
        shouldDiscoverTestedTarget = discoverTestedTarget
    }

    /// Feeds one complete line, without its trailing newline, into the current parse.
    ///
    /// Feeding after ``finish(coverage:)`` is a programmer error.
    public mutating func feed(_ line: String) {
        precondition(finishedResult == nil, "Cannot feed a finished StreamingOutputParser")
        if shouldDiscoverTestedTarget, testedTarget == nil,
            LineParser.contains(LineParser.xctestBundleNeedle, in: line)
        {
            testedTarget = Self.extractTestedTarget(fromLine: line)
        }
        if case .consumed(let event) = lineParser.feed(line) {
            handleEvent(event, printBuildInfo: shouldPrintBuildInfo)
        }
        didEmitXcbeautifyHint = lineParser.didEmitXcbeautifyHint
    }

    /// Finishes the current parse and returns its aggregate result.
    ///
    /// Repeated calls return the result produced by the first call.
    public mutating func finish(coverage: CodeCoverage? = nil) -> BuildResult {
        if let finishedResult {
            return finishedResult
        }
        for event in lineParser.flush() {
            handleEvent(event, printBuildInfo: shouldPrintBuildInfo)
        }
        didEmitXcbeautifyHint = lineParser.didEmitXcbeautifyHint
        let sawSuccessMarker = lineParser.sawSuccessMarker
        let sawFailureMarker = lineParser.sawFailureMarker || state.testRunFailed

        // If warnings-as-errors is enabled, convert warnings to errors
        var finalErrors = state.errors
        var finalWarnings = state.warnings

        if shouldTreatWarningsAsErrors && !state.warnings.isEmpty {
            for warning in state.warnings {
                finalErrors.append(
                    BuildError(
                        file: warning.file,
                        line: warning.line,
                        message: warning.message,
                        column: nil
                    )
                )
            }
            finalWarnings = []
        }

        // Aggregate test counts from both XCTest and Swift Testing
        let totalExecuted: Int? = {
            if let parallelTotal = state.parallelTestsTotalCount {
                if let xctest = resolvedXCTestExecutedCount() {
                    return parallelTotal + xctest
                }
                return parallelTotal
            }
            let xctest = resolvedXCTestExecutedCount() ?? 0
            let swiftTesting = state.swiftTestingExecutedCount ?? 0
            if xctest > 0 || swiftTesting > 0 {
                return xctest + swiftTesting
            }
            return nil
        }()

        let totalFailed: Int = {
            let xctestFailed = resolvedXCTestFailedCount() ?? 0
            let swiftTestingFailed = state.swiftTestingFailedCount ?? 0
            let aggregated = xctestFailed + swiftTestingFailed
            return aggregated > 0 ? aggregated : state.failedTests.count
        }()

        let computedPassedTests: Int? = {
            if let executed = totalExecuted {
                return max(executed - totalFailed, 0)
            }
            if state.passedTestsCount > 0 {
                return state.passedTestsCount
            }
            return nil
        }()

        let status: String = {
            let hasActualFailures =
                !finalErrors.isEmpty || !state.failedTests.isEmpty
                || !state.linkerErrors.isEmpty || totalFailed > 0
            if hasActualFailures { return "failed" }

            let hasPassedTests = (computedPassedTests ?? 0) > 0

            // A terminal failure marker means the run failed even when no specific failure was
            // attributed — unless tests actually passed (guards a stray "TEST FAILED" substring).
            if sawFailureMarker {
                return hasPassedTests ? "success" : "failed"
            }

            // Success requires positive evidence: a terminal success marker or passed tests.
            if sawSuccessMarker || hasPassedTests {
                return "success"
            }

            // No failures and no positive terminal marker: the stream ended before reporting an
            // outcome (e.g. xcodebuild Killed: 9). Never report a truncated run as success.
            return "incomplete"
        }()

        let slowTests: [SlowTest] = {
            guard let threshold = self.slowThreshold else { return [] }
            return detectSlowTests(threshold: threshold)
        }()

        let flakyTests = detectFlakyTests()

        let totalTestTime = state.swiftTestingTimeAccumulator + resolvedXCTestDuration()
        let formattedTestTime: String? =
            totalTestTime > 0
            ? String(format: "%.3fs", totalTestTime)
            : nil

        let summary = BuildSummary(
            errors: finalErrors.count,
            warnings: shouldTreatWarningsAsErrors ? 0 : state.warningCount,
            failedTests: totalFailed,
            linkerErrors: state.linkerErrors.count,
            passedTests: computedPassedTests,
            buildTime: state.buildTime,
            testTime: formattedTestTime,
            coveragePercent: coverage?.lineCoverage,
            slowTests: slowTests.isEmpty ? nil : slowTests.count,
            flakyTests: flakyTests.isEmpty ? nil : flakyTests.count,
            executables: shouldPrintExecutables && !state.executables.isEmpty ? state.executables.count : nil
        )

        let buildInfo: BuildInfo? =
            shouldPrintBuildInfo
            ? {
                let targets = state.targetOrder.map { targetName in
                    TargetBuildInfo(
                        name: targetName,
                        duration: state.targetDurations[targetName],
                        phases: state.targetPhases[targetName] ?? [],
                        dependsOn: state.targetDependencies[targetName] ?? []
                    )
                }
                let slowestTargets = computeSlowestTargets(targets: targets, limit: 5)
                return BuildInfo(targets: targets, slowestTargets: slowestTargets)
            }() : nil

        let result = BuildResult(
            status: status,
            summary: summary,
            errors: finalErrors,
            warnings: finalWarnings,
            failedTests: state.failedTests,
            linkerErrors: state.linkerErrors,
            coverage: coverage,
            slowTests: slowTests,
            flakyTests: flakyTests,
            buildInfo: buildInfo,
            executables: state.executables,
            printWarnings: shouldPrintWarnings,
            printCoverageDetails: shouldPrintCoverageDetails,
            printBuildInfo: shouldPrintBuildInfo,
            printExecutables: shouldPrintExecutables
        )
        finishedResult = result
        return result
    }

    // MARK: - Event handling (accumulation + dedup)

    private mutating func handleEvent(_ event: ParseEvent, printBuildInfo: Bool) {
        switch event {
        case .error(let e):
            let key = "\(e.file ?? ""):\(e.line ?? 0):\(e.message)"
            guard state.seenErrors.insert(key).inserted else { return }
            state.errors.append(e)

        case .warning(let w):
            let key = WarningKey(file: w.file, line: w.line, message: w.message)
            guard state.seenWarnings.insert(key).inserted else { return }
            state.warningCount += 1
            if shouldRetainWarnings {
                state.warnings.append(w)
            }

        case .linkerError(let e):
            let key = "\(e.symbol):\(e.message)"
            guard state.seenLinkerErrors.insert(key).inserted else { return }
            state.linkerErrors.append(e)

        case .testStarted:
            break  // crash detection is handled inside LineParser

        case .testPassed(let name, let duration):
            let normalized = normalizeTestName(name)
            guard state.seenPassedTestNames.insert(normalized).inserted else { return }
            state.passedTestsCount += 1
            if let d = duration { state.passedTestDurations[normalized] = d }

        case .testFailed(let t):
            let normalized = normalizeTestName(t.test)
            if !state.seenTestNames.contains(normalized) {
                state.failedTests.append(t)
                state.seenTestNames.insert(normalized)
                if let d = t.duration { state.failedTestDurations[normalized] = d }
            } else {
                // Merge: update with more info if available
                if let index = state.failedTests.firstIndex(where: {
                    normalizeTestName($0.test) == normalized
                }) {
                    let existing = state.failedTests[index]
                    let mergedFile = t.file ?? existing.file
                    let mergedLine = t.line ?? existing.line
                    let mergedMessage = t.file != nil ? t.message : existing.message
                    let mergedDuration = t.duration ?? existing.duration
                    if mergedFile != existing.file || mergedLine != existing.line
                        || mergedDuration != existing.duration
                    {
                        state.failedTests[index] = FailedTest(
                            test: existing.test,
                            message: mergedMessage,
                            file: mergedFile,
                            line: mergedLine,
                            duration: mergedDuration
                        )
                    }
                }
            }

        case .testSuiteCompleted(let suiteName, let executed, let failed, let duration):
            // "Selected tests"/"All tests" wrap the bundles, so they repeat totals instead of adding to them
            if suiteName.hasSuffix(".xctest") {
                state.xctestBundleExecutedCount += executed
                state.xctestBundleFailedCount += failed
                state.xctestBundleDuration += duration
                state.sawBundleLevelXCTestSummary = true
            } else {
                state.xctestFallbackExecutedCount = executed
                state.xctestFallbackFailedCount = failed
                state.xctestFallbackDuration = duration
            }

        case .swiftTestingCompleted(let executed, let failed, let duration):
            state.swiftTestingExecutedCount = (state.swiftTestingExecutedCount ?? 0) + executed
            state.swiftTestingFailedCount = (state.swiftTestingFailedCount ?? 0) + failed
            state.swiftTestingTimeAccumulator += duration

        case .parallelTestScheduled(let index, let total):
            if let previousIndex = state.lastParallelTestSchedulingIndex {
                if index <= previousIndex {
                    state.parallelTestsTotalCount = (state.parallelTestsTotalCount ?? 0) + total
                }
            } else {
                state.parallelTestsTotalCount = (state.parallelTestsTotalCount ?? 0) + total
            }
            state.lastParallelTestSchedulingIndex = index

        case .buildTime(let t):
            state.buildTime = t

        case .testRunFailed:
            state.testRunFailed = true

        case .buildPhase(let target, let phase):
            guard printBuildInfo else { return }
            if state.targetPhases[target] == nil {
                state.targetPhases[target] = []
                if !state.targetOrder.contains(target) { state.targetOrder.append(target) }
            }
            if !state.targetPhases[target]!.contains(phase) {
                state.targetPhases[target]!.append(phase)
            }

        case .targetCompleted(let name, let duration):
            guard printBuildInfo else { return }
            if !state.targetOrder.contains(name) { state.targetOrder.append(name) }
            state.targetDurations[name] = duration

        case .targetDependency(let target, let dependsOn):
            guard printBuildInfo else { return }
            if !state.targetOrder.contains(target) { state.targetOrder.append(target) }
            if state.targetDependencies[target] == nil { state.targetDependencies[target] = [] }
            if !state.targetDependencies[target]!.contains(dependsOn) {
                state.targetDependencies[target]!.append(dependsOn)
            }

        case .targetDiscovered(let name):
            guard printBuildInfo else { return }
            if !state.targetOrder.contains(name) { state.targetOrder.append(name) }
            // Ensure an entry exists in targetDependencies (may be updated by .targetDependency)
            if state.targetDependencies[name] == nil { state.targetDependencies[name] = [] }

        case .executable(let e):
            guard state.seenExecutablePaths.insert(e.path).inserted else { return }
            state.executables.append(e)
        }
    }

    // MARK: - Slow/Flaky Test Detection

    private func detectSlowTests(threshold: Double) -> [SlowTest] {
        var slow: [SlowTest] = []
        var seenNames: Set<String> = []

        for (name, duration) in state.passedTestDurations where duration > threshold {
            slow.append(SlowTest(test: name, duration: duration))
            seenNames.insert(name)
        }
        for (name, duration) in state.failedTestDurations where duration > threshold {
            if !seenNames.contains(name) {
                slow.append(SlowTest(test: name, duration: duration))
            }
        }
        return slow.sorted { $0.duration > $1.duration }
    }

    private func detectFlakyTests() -> [String] {
        let passedNames = Set(state.passedTestDurations.keys)
        let failedNames = Set(state.failedTests.map { normalizeTestName($0.test) })
        return Array(passedNames.intersection(failedNames)).sorted()
    }

    private func computeSlowestTargets(targets: [TargetBuildInfo], limit: Int) -> [String] {
        func parseDuration(_ duration: String?) -> Double {
            guard let d = duration, d.hasSuffix("s") else { return 0 }
            return Double(d.dropLast()) ?? 0
        }
        let sorted =
            targets
            .filter { $0.duration != nil }
            .sorted { parseDuration($0.duration) > parseDuration($1.duration) }
        return Array(sorted.prefix(limit).map { $0.name })
    }

    fileprivate static func extractTestedTarget(fromLine line: String) -> String? {
        let hasTestSuite = line.contains("Test Suite '") || line.contains("Test suite '")
        guard hasTestSuite, line.contains(".xctest"), line.contains("started"),
            let match = line.firstMatch(of: Self.testSuiteRegex)
        else {
            return nil
        }

        var targetName = String(match.1)
        if targetName.hasSuffix("Tests") {
            targetName = String(targetName.dropLast(5))
        }
        return targetName
    }

    private func normalizeTestName(_ testName: String) -> String {
        if testName.hasPrefix("-[") && testName.hasSuffix("]") {
            return String(testName.dropFirst(2).dropLast(1))
        }
        return testName
    }

    private func resolvedXCTestExecutedCount() -> Int? {
        state.sawBundleLevelXCTestSummary ? state.xctestBundleExecutedCount : state.xctestFallbackExecutedCount
    }

    private func resolvedXCTestFailedCount() -> Int? {
        state.sawBundleLevelXCTestSummary ? state.xctestBundleFailedCount : state.xctestFallbackFailedCount
    }

    private func resolvedXCTestDuration() -> Double {
        state.sawBundleLevelXCTestSummary ? state.xctestBundleDuration : state.xctestFallbackDuration
    }
}

/// Parses a complete xcodebuild or SPM output string into a structured ``BuildResult``.
///
/// Each call creates an isolated ``StreamingOutputParser`` session, so one `OutputParser` can be
/// reused across multiple complete inputs without carrying state between runs.
public class OutputParser {
    /// `true` if the most recent ``parse(input:printWarnings:warningsAsErrors:coverage:printCoverageDetails:slowThreshold:printBuildInfo:printExecutables:xcbeautify:)``
    /// call emitted an xcbeautify auto-detection hint.
    public private(set) var didEmitXcbeautifyHint = false

    public init() {}

    /// Splits on the newline byte. `String.split(separator: "\n")` never matches a CRLF line
    /// ending, because Swift treats `\r\n` as one `Character`.
    private static func lines(of input: String) -> [String] {
        input.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    /// Parses raw xcodebuild or SPM output and returns a structured ``BuildResult``.
    ///
    /// Each invocation uses a fresh streaming session, so an `OutputParser` instance can be reused
    /// across multiple complete inputs without carrying state between runs.
    ///
    /// - Parameters:
    ///   - input: The complete build output as a single string.
    ///   - printWarnings: Include full warning details instead of summary count only.
    ///   - warningsAsErrors: Convert warnings to errors in the final result.
    ///   - coverage: Pre-parsed coverage data to embed in the result.
    ///   - printCoverageDetails: Include per-file coverage details.
    ///   - slowThreshold: Report tests slower than this many seconds.
    ///   - printBuildInfo: Include per-target phases, timing, and dependencies.
    ///   - printExecutables: Include discovered executable targets.
    ///   - xcbeautify: Parse xcbeautify/Tuist markers.
    public func parse(
        input: String,
        printWarnings: Bool = false,
        warningsAsErrors: Bool = false,
        coverage: CodeCoverage? = nil,
        printCoverageDetails: Bool = false,
        slowThreshold: Double? = nil,
        printBuildInfo: Bool = false,
        printExecutables: Bool = false,
        xcbeautify: Bool = false
    ) -> BuildResult {
        var parser = StreamingOutputParser(
            printWarnings: printWarnings,
            warningsAsErrors: warningsAsErrors,
            printCoverageDetails: printCoverageDetails,
            slowThreshold: slowThreshold,
            printBuildInfo: printBuildInfo,
            printExecutables: printExecutables,
            xcbeautify: xcbeautify
        )

        for line in Self.lines(of: input) {
            parser.feed(line)
        }

        let result = parser.finish(coverage: coverage)
        didEmitXcbeautifyHint = parser.didEmitXcbeautifyHint
        return result
    }

    /// Extracts the tested target name used to filter xcodebuild coverage data.
    ///
    /// A `.xctest` suite name such as `MyAppTests.xctest` resolves to `MyApp`.
    public func extractTestedTarget(from input: String) -> String? {
        for line in Self.lines(of: input) {
            if let testedTarget = StreamingOutputParser.extractTestedTarget(fromLine: line) {
                return testedTarget
            }
        }
        return nil
    }
}
