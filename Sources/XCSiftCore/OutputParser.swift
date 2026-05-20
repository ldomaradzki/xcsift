import Foundation
import RegexBuilder

/// Parses a complete xcodebuild or SPM output string and returns a structured ``BuildResult``.
///
/// `OutputParser` drives ``LineParser`` internally, accumulating and deduplicating events across
/// all lines before producing a single ``BuildResult``. Use this when you have the full build
/// output in memory rather than streaming it line-by-line.
///
/// ```swift
/// let result = OutputParser().parse(input: rawOutput, printWarnings: true)
/// let json = try JSONEncoder().encode(result)
/// ```
public class OutputParser {

    private struct ParseState {
        var errors: [BuildError] = []
        var warnings: [BuildWarning] = []
        var failedTests: [FailedTest] = []
        var linkerErrors: [LinkerError] = []
        var executables: [Executable] = []
        var seenExecutablePaths: Set<String> = []
        var buildTime: String?
        var testTimeAccumulator: Double = 0
        var seenTestNames: Set<String> = []
        var seenWarnings: Set<String> = []
        var seenErrors: Set<String> = []
        var seenLinkerErrors: Set<String> = []
        var seenPassedTestNames: Set<String> = []
        var xctestBundleExecutedCount: Int = 0
        var xctestBundleFailedCount: Int = 0
        var xctestFallbackExecutedCount: Int?
        var xctestFallbackFailedCount: Int?
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

    /// `true` if the most recent ``parse(input:printWarnings:warningsAsErrors:coverage:printCoverageDetails:slowThreshold:printBuildInfo:printExecutables:xcbeautify:)`` call caused an xcbeautify auto-detection hint to be written to stderr.
    public private(set) var didEmitXcbeautifyHint: Bool = false

    // Target regex for extractTestedTarget (used externally)
    private nonisolated(unsafe) static let testSuiteRegex = Regex {
        /[Tt]est [Ss]uite '/
        Capture(OneOrMore(.any, .reluctant))
        ".xctest'"
    }

    public init() {}

    /// Parses raw xcodebuild or SPM output and returns a structured ``BuildResult``.
    ///
    /// The method is stateless across calls — each invocation resets internal accumulators —
    /// so a single `OutputParser` instance can be reused for multiple runs.
    ///
    /// - Parameters:
    ///   - input: The complete build output as a single string (typically captured from stderr).
    ///   - printWarnings: When `true`, the returned `BuildResult` includes the full warnings list;
    ///     when `false` (default), only the warning count appears in the summary.
    ///   - warningsAsErrors: When `true`, every warning is converted to an error and the warnings
    ///     list is cleared, mirroring `-Werror` behavior.
    ///   - coverage: Pre-parsed ``CodeCoverage`` data to embed in the result. Pass `nil` (default)
    ///     when coverage is not needed.
    ///   - printCoverageDetails: When `true`, per-file coverage details are included in the result;
    ///     when `false` (default), only the summary percentage is included.
    ///   - slowThreshold: Tests whose duration exceeds this value (in seconds) are reported as slow.
    ///     Pass `nil` (default) to disable slow-test detection.
    ///   - printBuildInfo: When `true`, per-target phases, durations, and dependency graph data are
    ///     included in the result.
    ///   - printExecutables: When `true`, the executables list is populated in the result.
    ///   - xcbeautify: Pass `true` when the input was pre-processed by xcbeautify or Tuist.
    /// - Returns: A ``BuildResult`` representing the parsed build state.
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
        state = ParseState()
        var lineParser = LineParser(xcbeautify: xcbeautify)
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for line in lines {
            if case .consumed(let event) = lineParser.feed(line) {
                handleEvent(event, printBuildInfo: printBuildInfo)
            }
        }
        for event in lineParser.flush() {
            handleEvent(event, printBuildInfo: printBuildInfo)
        }
        didEmitXcbeautifyHint = lineParser.didEmitXcbeautifyHint

        // If warnings-as-errors is enabled, convert warnings to errors
        var finalErrors = state.errors
        var finalWarnings = state.warnings

        if warningsAsErrors && !state.warnings.isEmpty {
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
            let hasActualFailures = !finalErrors.isEmpty || !state.failedTests.isEmpty || !state.linkerErrors.isEmpty
            let hasPassedTests = (computedPassedTests ?? 0) > 0

            switch (hasActualFailures, state.testRunFailed, hasPassedTests) {
            case (true, _, _):
                return "failed"
            case (false, true, true):
                return "success"
            case (false, true, false):
                return "failed"
            case (false, false, _):
                return "success"
            }
        }()

        let slowTests: [SlowTest] = {
            guard let threshold = slowThreshold else { return [] }
            return detectSlowTests(threshold: threshold)
        }()

        let flakyTests = detectFlakyTests()

        let formattedTestTime: String? =
            state.testTimeAccumulator > 0
            ? String(format: "%.3fs", state.testTimeAccumulator)
            : nil

        let summary = BuildSummary(
            errors: finalErrors.count,
            warnings: finalWarnings.count,
            failedTests: totalFailed,
            linkerErrors: state.linkerErrors.count,
            passedTests: computedPassedTests,
            buildTime: state.buildTime,
            testTime: formattedTestTime,
            coveragePercent: coverage?.lineCoverage,
            slowTests: slowTests.isEmpty ? nil : slowTests.count,
            flakyTests: flakyTests.isEmpty ? nil : flakyTests.count,
            executables: printExecutables && !state.executables.isEmpty ? state.executables.count : nil
        )

        let buildInfo: BuildInfo? =
            printBuildInfo
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

        return BuildResult(
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
            printWarnings: printWarnings,
            printCoverageDetails: printCoverageDetails,
            printBuildInfo: printBuildInfo,
            printExecutables: printExecutables
        )
    }

    // MARK: - Event handling (accumulation + dedup)

    private func handleEvent(_ event: ParseEvent, printBuildInfo: Bool) {
        switch event {
        case .error(let e):
            let key = "\(e.file ?? ""):\(e.line ?? 0):\(e.message)"
            guard state.seenErrors.insert(key).inserted else { return }
            state.errors.append(e)

        case .warning(let w):
            let key = "\(w.file ?? ""):\(w.line ?? 0):\(w.message)"
            guard state.seenWarnings.insert(key).inserted else { return }
            state.warnings.append(w)

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
            if suiteName.hasSuffix(".xctest") || suiteName == XcodebuildSymbols.selectedTestsSuite {
                state.xctestBundleExecutedCount += executed
                state.xctestBundleFailedCount += failed
                state.sawBundleLevelXCTestSummary = true
            } else {
                state.xctestFallbackExecutedCount = executed
                state.xctestFallbackFailedCount = failed
            }
            state.testTimeAccumulator += duration

        case .swiftTestingCompleted(let executed, let failed, let duration):
            state.swiftTestingExecutedCount = (state.swiftTestingExecutedCount ?? 0) + executed
            state.swiftTestingFailedCount = (state.swiftTestingFailedCount ?? 0) + failed
            state.testTimeAccumulator += duration

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

    /// Extracts the name of the tested target from xcodebuild output.
    ///
    /// Scans for a `Test Suite '*.xctest' started` line and derives the target name by stripping
    /// the `.xctest` suffix and an optional `Tests` suffix (e.g. `MyAppTests.xctest` → `MyApp`).
    ///
    /// This is used internally by ``CoverageParser`` to filter coverage data to the relevant target.
    ///
    /// - Parameter input: Raw xcodebuild or SPM output.
    /// - Returns: The inferred target name, or `nil` if no `.xctest` suite line was found.
    public func extractTestedTarget(from input: String) -> String? {
        let lines = input.split(separator: "\n")
        for line in lines {
            let lineStr = String(line)
            let hasTestSuite =
                lineStr.contains("Test Suite '") || lineStr.contains("Test suite '")
            if hasTestSuite, lineStr.contains(".xctest"), lineStr.contains("started") {
                if let match = lineStr.firstMatch(of: Self.testSuiteRegex) {
                    var targetName = String(match.1)
                    if targetName.hasSuffix("Tests") {
                        targetName = String(targetName.dropLast(5))
                    }
                    return targetName
                }
            }
        }
        return nil
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
}
