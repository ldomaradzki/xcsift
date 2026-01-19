import Foundation
import RegexBuilder

class OutputParser {
    private var errors: [BuildError] = []
    private var warnings: [BuildWarning] = []
    private var failedTests: [FailedTest] = []
    private var linkerErrors: [LinkerError] = []
    private var executables: [Executable] = []
    private var seenExecutablePaths: Set<String> = []
    private var buildTime: String?
    private var testTimeAccumulator: Double = 0
    private var seenTestNames: Set<String> = []
    private var seenWarnings: Set<String> = []
    private var seenErrors: Set<String> = []
    private var seenLinkerErrors: Set<String> = []
    private var xctestExecutedCount: Int?
    private var xctestFailedCount: Int?
    private var swiftTestingExecutedCount: Int?
    private var swiftTestingFailedCount: Int?
    private var passedTestsCount: Int = 0
    private var seenPassedTestNames: Set<String> = []
    private var parallelTestsTotalCount: Int?
    private var testRunFailed: Bool = false

    // Linker error parsing state
    private var currentLinkerArchitecture: String?
    private var pendingLinkerSymbol: String?

    // Duplicate symbol parsing state
    private var pendingDuplicateSymbol: String?
    private var pendingConflictingFiles: [String] = []

    // Test duration tracking for slow/flaky detection
    private var passedTestDurations: [String: Double] = [:]
    private var failedTestDurations: [String: Double] = [:]

    // Build info tracking - phases grouped by target
    private var targetPhases: [String: [String]] = [:]  // target -> [phase names]
    private var targetDurations: [String: String] = [:]  // target -> duration
    private var targetOrder: [String] = []  // Tracks order of target appearance
    private var shouldParseBuildInfo: Bool = false  // Performance: skip phase parsing when not needed

    // Dependency graph tracking
    private var targetDependencies: [String: [String]] = [:]  // target -> [dependencies]
    private var currentDependencyTarget: String?  // For multi-line dependency parsing

    // MARK: - Static Regex Patterns (compiled once)

    // Error patterns
    nonisolated(unsafe) private static let fileLineColumnErrorRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ":"
        Capture(OneOrMore(.digit))
        ":"
        Capture(OneOrMore(.digit))
        ": error: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let fileLineErrorRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ":"
        Capture(OneOrMore(.digit))
        ": error: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let fileErrorRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ": error: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let fileFatalErrorRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ":"
        Capture(OneOrMore(.digit))
        ": Fatal error: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let fatalErrorRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ": Fatal error: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let emojiErrorRegex = Regex {
        "❌ "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let simpleErrorRegex = Regex {
        "error: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    // Warning patterns
    nonisolated(unsafe) private static let fileLineColumnWarningRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ":"
        Capture(OneOrMore(.digit))
        ":"
        Capture(OneOrMore(.digit))
        ": warning: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let fileLineWarningRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ":"
        Capture(OneOrMore(.digit))
        ": warning: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let fileWarningRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ": warning: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let simpleWarningRegex = Regex {
        "warning: "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    // Test patterns
    nonisolated(unsafe) private static let testCasePassedRegex = Regex {
        "Test Case '"
        Capture(OneOrMore(.any, .reluctant))
        "' passed ("
        OneOrMore(.any, .reluctant)
        ")"
        Optionally(".")
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let swiftTestingPassedRegex = Regex {
        "✓ Test \""
        Capture(OneOrMore(.any, .reluctant))
        "\" passed"
        OneOrMore(.any, .reluctant)
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let xctestFailedRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ":"
        Capture(OneOrMore(.digit))
        ": error: -["
        Capture(OneOrMore(.any, .reluctant))
        "] : "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let testNameBracketRegex = Regex {
        "-["
        Capture(OneOrMore(.any, .reluctant))
        "]"
    }

    nonisolated(unsafe) private static let testCaseFailedRegex = Regex {
        "Test Case '"
        Capture(OneOrMore(.any, .reluctant))
        "' failed ("
        Capture(OneOrMore(.any, .reluctant))
        ")"
        Optionally(".")
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let swiftTestingIssueRegex = Regex {
        "✘ Test \""
        Capture(OneOrMore(.any, .reluctant))
        "\" recorded an issue at "
        Capture(OneOrMore(.any, .reluctant))
        ":"
        Capture(OneOrMore(.digit))
        ":"
        OneOrMore(.digit)
        ": "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let swiftTestingFailedRegex = Regex {
        "✘ Test \""
        Capture(OneOrMore(.any, .reluctant))
        "\" failed after "
        OneOrMore(.any, .reluctant)
        " with "
        OneOrMore(.digit)
        " issue"
        Optionally("s")
        "."
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let emojiTestFailedRegex = Regex {
        "❌ "
        Capture(OneOrMore(.any, .reluctant))
        " ("
        Capture(OneOrMore(.any, .reluctant))
        ")"
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let testFailedRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        " ("
        Capture(OneOrMore(.any, .reluctant))
        ") failed"
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let colonFailedRegex = Regex {
        Capture(OneOrMore(.any, .reluctant))
        ": "
        Capture(OneOrMore(.any, .reluctant))
        " failed:"
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    // Build time patterns
    nonisolated(unsafe) private static let buildSucceededRegex = Regex {
        "Build succeeded in "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let buildFailedRegex = Regex {
        "Build failed after "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let executedTestsRegex = Regex {
        "Executed "
        Capture(OneOrMore(.digit))
        " test"
        Optionally("s")
        ", with "
        Capture(OneOrMore(.digit))
        " failure"
        Optionally("s")
        " ("
        Capture(OneOrMore(.digit))
        " unexpected) in "
        Capture(OneOrMore(.any, .reluctant))
        " ("
        Capture(OneOrMore(.any, .reluctant))
        ") seconds"
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let swiftTestingSummaryRegex = Regex {
        "Test run with "
        Capture(OneOrMore(.digit))
        " test"
        Optionally("s")
        " passed"
    }

    nonisolated(unsafe) private static let executedTestsSimpleRegex = Regex {
        "Executed "
        Capture(OneOrMore(.digit))
        " test"
        Optionally("s")
        ", with "
        Capture(OneOrMore(.digit))
        " failure"
        Optionally("s")
        " in "
        Capture(OneOrMore(.any, .reluctant))
        " seconds"
        Optionally(".")
        Anchor.endOfSubject
    }

    nonisolated(unsafe) private static let swiftTestingPassedFullRegex = Regex {
        "Test run with "
        Capture(OneOrMore(.digit))
        " test"
        Optionally("s")
        " in "
        OneOrMore(.digit)
        " suite"
        Optionally("s")
        " passed after "
        Capture(OneOrMore(.any, .reluctant))
        " seconds"
        Optionally(".")
        Anchor.endOfSubject
    }

    // JSON detection pattern
    nonisolated(unsafe) private static let jsonKeyValueRegex = Regex {
        Optionally(OneOrMore(.whitespace))
        "\""
        OneOrMore(.any, .reluctant)
        "\""
        Optionally(OneOrMore(.whitespace))
        ":"
        Optionally(OneOrMore(.whitespace))
    }

    // Target extraction pattern
    nonisolated(unsafe) private static let testSuiteRegex = Regex {
        "Test Suite '"
        Capture(OneOrMore(.any, .reluctant))
        ".xctest'"
    }

    // Parallel test scheduling pattern: [N/TOTAL] Testing Module.Class/method
    nonisolated(unsafe) private static let parallelTestSchedulingRegex = Regex {
        "["
        Capture(OneOrMore(.digit))
        "/"
        Capture(OneOrMore(.digit))
        "] Testing "
        Capture(OneOrMore(.any, .reluctant))
        Anchor.endOfSubject
    }

    // PhaseScriptExecution failure pattern
    nonisolated(unsafe) private static let phaseScriptExecutionFailedRegex = Regex {
        "Command PhaseScriptExecution failed with a nonzero exit"
        OneOrMore(.any, .reluctant)
        Anchor.endOfSubject
    }

    func parse(
        input: String,
        printWarnings: Bool = false,
        warningsAsErrors: Bool = false,
        coverage: CodeCoverage? = nil,
        printCoverageDetails: Bool = false,
        slowThreshold: Double? = nil,
        printBuildInfo: Bool = false,
        printExecutables: Bool = false
    ) -> BuildResult {
        resetState()
        shouldParseBuildInfo = printBuildInfo
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (index, line) in lines.enumerated() {
            parseLine(line)
            
            // Handle PhaseScriptExecution failures with context from preceding lines
            if line.contains("Command PhaseScriptExecution failed with a nonzero exit") {
                // Look back for relevant context (skip unrelated warnings and metadata)
                var contextLines: [String] = []
                let startIndex = max(0, index - 3)  // Look back a few lines
                for contextIdx in startIndex..<index {
                    let contextLine = lines[contextIdx].trimmingCharacters(in: .whitespaces)
                    
                    // Skip empty lines and build metadata warnings
                    if contextLine.isEmpty || contextLine.hasPrefix("Warning:") || 
                       contextLine.hasPrefix("Run script build phase") {
                        continue
                    }
                    
                    // Skip lines that contain Xcode build phase info that's not error-related
                    if contextLine.contains(": warning:") && !contextLine.contains("error:") {
                        continue
                    }
                    
                    // Include all other lines as they're likely actual error context
                    contextLines.append(contextLine)
                }
                
                // Combine context with failure message, using spaces as separator
                if !contextLines.isEmpty {
                    let combinedMessage = contextLines.joined(separator: " ") + " " + line
                    // Update the last error (which was just added by parseLine) with combined message
                    if !errors.isEmpty && errors.last?.message == line {
                        errors[errors.count - 1] = BuildError(
                            file: nil,
                            line: nil,
                            message: combinedMessage
                        )
                    }
                }
            }
        }

        // If warnings-as-errors is enabled, convert warnings to errors
        var finalErrors = errors
        var finalWarnings = warnings

        if warningsAsErrors && !warnings.isEmpty {
            // Convert warnings to errors
            for warning in warnings {
                finalErrors.append(
                    BuildError(
                        file: warning.file,
                        line: warning.line,
                        message: warning.message
                    )
                )
            }
            finalWarnings = []
        }

        let status =
            finalErrors.isEmpty && failedTests.isEmpty && linkerErrors.isEmpty && !testRunFailed
            ? "success" : "failed"

        // Aggregate test counts from both XCTest and Swift Testing
        let totalExecuted: Int? = {
            // Priority 1: Use parallel test total count if available (Swift Testing parallel mode)
            if let parallelTotal = parallelTestsTotalCount {
                // Add XCTest count if available
                if let xctest = xctestExecutedCount {
                    return parallelTotal + xctest
                }
                return parallelTotal
            }

            // Priority 2: Sum XCTest and Swift Testing counts from summary lines
            let xctest = xctestExecutedCount ?? 0
            let swiftTesting = swiftTestingExecutedCount ?? 0
            if xctest > 0 || swiftTesting > 0 {
                return xctest + swiftTesting
            }
            return nil
        }()

        let totalFailed: Int = {
            let xctestFailed = xctestFailedCount ?? 0
            let swiftTestingFailed = swiftTestingFailedCount ?? 0
            let aggregated = xctestFailed + swiftTestingFailed
            // Fall back to parsed failed tests if no summary counts
            return aggregated > 0 ? aggregated : failedTests.count
        }()

        let computedPassedTests: Int? = {
            // Use aggregated counts from summary lines
            if let executed = totalExecuted {
                return max(executed - totalFailed, 0)
            }
            // Fallback: Use individually counted passed tests
            if passedTestsCount > 0 {
                return passedTestsCount
            }
            return nil
        }()

        // Detect slow tests (if threshold is set)
        let slowTests: [SlowTest] = {
            guard let threshold = slowThreshold else { return [] }
            return detectSlowTests(threshold: threshold)
        }()

        // Detect flaky tests (tests that both passed and failed in the same run)
        let flakyTests = detectFlakyTests()

        // Format accumulated test time (nil if no tests ran)
        let formattedTestTime: String? =
            testTimeAccumulator > 0
            ? String(format: "%.3fs", testTimeAccumulator)
            : nil

        let summary = BuildSummary(
            errors: finalErrors.count,
            warnings: finalWarnings.count,
            failedTests: totalFailed,
            linkerErrors: linkerErrors.count,
            passedTests: computedPassedTests,
            buildTime: buildTime,
            testTime: formattedTestTime,
            coveragePercent: coverage?.lineCoverage,
            slowTests: slowTests.isEmpty ? nil : slowTests.count,
            flakyTests: flakyTests.isEmpty ? nil : flakyTests.count,
            executables: printExecutables && !executables.isEmpty ? executables.count : nil
        )

        // Build info - phases, timing, and dependencies per target (total time is in summary.build_time)
        let buildInfo: BuildInfo? =
            printBuildInfo
            ? {
                // Build targets list with phases, durations, and dependencies, preserving order of appearance
                let targets = targetOrder.map { targetName in
                    TargetBuildInfo(
                        name: targetName,
                        duration: targetDurations[targetName],
                        phases: targetPhases[targetName] ?? [],
                        dependsOn: targetDependencies[targetName] ?? []
                    )
                }

                // Compute top 5 slowest targets (sorted by duration descending)
                let slowestTargets = computeSlowestTargets(targets: targets, limit: 5)

                return BuildInfo(targets: targets, slowestTargets: slowestTargets)
            }() : nil

        return BuildResult(
            status: status,
            summary: summary,
            errors: finalErrors,
            warnings: finalWarnings,
            failedTests: failedTests,
            linkerErrors: linkerErrors,
            coverage: coverage,
            slowTests: slowTests,
            flakyTests: flakyTests,
            buildInfo: buildInfo,
            executables: executables,
            printWarnings: printWarnings,
            printCoverageDetails: printCoverageDetails,
            printBuildInfo: printBuildInfo,
            printExecutables: printExecutables
        )
    }

    // MARK: - Slow/Flaky Test Detection

    /// Detects tests that exceeded the slow threshold
    private func detectSlowTests(threshold: Double) -> [SlowTest] {
        var slow: [SlowTest] = []
        var seenNames: Set<String> = []

        for (name, duration) in passedTestDurations where duration > threshold {
            slow.append(SlowTest(test: name, duration: duration))
            seenNames.insert(name)
        }

        for (name, duration) in failedTestDurations where duration > threshold {
            if !seenNames.contains(name) {
                slow.append(SlowTest(test: name, duration: duration))
            }
        }

        // Sort by duration descending (slowest first)
        return slow.sorted { $0.duration > $1.duration }
    }

    /// Detects flaky tests - tests that both passed and failed in the same run
    private func detectFlakyTests() -> [String] {
        let passedNames = Set(passedTestDurations.keys)
        let failedNames = Set(failedTests.map { normalizeTestName($0.test) })
        return Array(passedNames.intersection(failedNames)).sorted()
    }

    /// Computes the top N slowest targets sorted by duration (descending)
    private func computeSlowestTargets(targets: [TargetBuildInfo], limit: Int) -> [String] {
        // Parse duration string "12.4s" to Double for sorting
        func parseDuration(_ duration: String?) -> Double {
            guard let d = duration, d.hasSuffix("s") else { return 0 }
            return Double(d.dropLast()) ?? 0
        }

        // Filter targets with duration, sort by duration descending, take top N
        let sorted =
            targets
            .filter { $0.duration != nil }
            .sorted { parseDuration($0.duration) > parseDuration($1.duration) }

        return Array(sorted.prefix(limit).map { $0.name })
    }

    func extractTestedTarget(from input: String) -> String? {
        let lines = input.split(separator: "\n")

        for line in lines {
            let lineStr = String(line)

            // Only match lines with .xctest to skip "All tests" and individual test classes
            if lineStr.contains("Test Suite '") && lineStr.contains(".xctest") && lineStr.contains("started") {
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

    private func resetState() {
        errors = []
        warnings = []
        failedTests = []
        linkerErrors = []
        executables = []
        seenExecutablePaths = []
        buildTime = nil
        testTimeAccumulator = 0
        seenTestNames = []
        xctestExecutedCount = nil
        xctestFailedCount = nil
        swiftTestingExecutedCount = nil
        swiftTestingFailedCount = nil
        passedTestsCount = 0
        seenPassedTestNames = []
        currentLinkerArchitecture = nil
        pendingLinkerSymbol = nil
        pendingDuplicateSymbol = nil
        pendingConflictingFiles = []
        parallelTestsTotalCount = nil
        testRunFailed = false
        passedTestDurations = [:]
        failedTestDurations = [:]
        targetPhases = [:]
        targetDurations = [:]
        targetOrder = []
        shouldParseBuildInfo = false
        targetDependencies = [:]
        currentDependencyTarget = nil
    }

    private func parseLine(_ line: String) {
        // Quick filters to avoid regex on irrelevant lines
        if line.isEmpty || line.count > 5000 {
            return
        }

        // Check for linker-related lines first (multi-line parsing)
        if parseLinkerLine(line) {
            return
        }

        // Check for build phases only if build info is requested (performance optimization)
        if shouldParseBuildInfo {
            // Check for dependency graph (xcodebuild outputs this early in build)
            if parseDependencyGraph(line) {
                return
            }

            // Check for xcodebuild phases (these have different keywords from errors/warnings)
            if let (phaseName, targetName) = parseBuildPhase(line) {
                addPhaseToTarget(phaseName, target: targetName)
                return
            }

            // Check for SPM phases (format: [N/M] Compiling/Linking TARGET)
            if let (phaseName, targetName) = parseSPMPhase(line) {
                addPhaseToTarget(phaseName, target: targetName)
                return
            }

            // Check for target timing
            if let (targetName, duration) = parseTargetTiming(line) {
                // Track order if this is the first time we see this target
                if !targetOrder.contains(targetName) {
                    targetOrder.append(targetName)
                }
                targetDurations[targetName] = duration
                return
            }
        }

        // Fast path checks before expensive regex
        let containsRelevant =
            line.contains("error:") || line.contains("warning:") || line.contains("failed") || line.contains("passed")
            || line.contains("✘") || line.contains("✓") || line.contains("❌") || line.contains("Build succeeded")
            || line.contains("Build failed") || line.contains("Executed") || line.contains("] Testing ")
            || line.contains("BUILD SUCCEEDED") || line.contains("BUILD FAILED") || line.contains("TEST FAILED")
            || line.contains("Build complete!") || line.hasPrefix("RegisterWithLaunchServices")
            || line.hasPrefix("Validate") || line.contains("Fatal error")
            || (line.hasPrefix("/") && line.contains(".swift:"))  // runtime warnings

        if !containsRelevant {
            return
        }

        // Parse parallel test scheduling lines: [N/TOTAL] Testing Module.Class/method
        if line.contains("] Testing "), let match = line.firstMatch(of: Self.parallelTestSchedulingRegex) {
            if let _ = Int(match.1), let total = Int(match.2) {
                // Only set on first match (total should be consistent across all lines)
                if parallelTestsTotalCount == nil {
                    parallelTestsTotalCount = total
                }
            }
            return
        }

        // Parse executable registration (deduplicate by path)
        if let executable = parseExecutable(line) {
            if seenExecutablePaths.insert(executable.path).inserted {
                executables.append(executable)
            }
            return
        }

        if let failedTest = parseFailedTest(line) {
            let normalizedTestName = normalizeTestName(failedTest.test)

            // Check if we've already seen this test name or a similar one
            if !hasSeenSimilarTest(normalizedTestName) {
                failedTests.append(failedTest)
                seenTestNames.insert(normalizedTestName)
            } else {
                // If we've seen this test before, check if the new one has more info (file/line or duration)
                if let index = failedTests.firstIndex(where: { normalizeTestName($0.test) == normalizedTestName }) {
                    let existing = failedTests[index]

                    // Merge: prefer new file/line if available, otherwise keep existing
                    let mergedFile = failedTest.file ?? existing.file
                    let mergedLine = failedTest.line ?? existing.line
                    let mergedMessage = failedTest.file != nil ? failedTest.message : existing.message
                    let mergedDuration = failedTest.duration ?? existing.duration

                    // Update if we have new info
                    if mergedFile != existing.file || mergedLine != existing.line || mergedDuration != existing.duration
                    {
                        failedTests[index] = FailedTest(
                            test: existing.test,
                            message: mergedMessage,
                            file: mergedFile,
                            line: mergedLine,
                            duration: mergedDuration
                        )
                    }
                }
            }
        } else if let error = parseError(line) {
            let key = "\(error.file ?? ""):\(error.line ?? 0):\(error.message)"
            if !seenErrors.contains(key) {
                seenErrors.insert(key)
                errors.append(error)
            }
        } else if let warning = parseWarning(line) {
            let key = "\(warning.file ?? ""):\(warning.line ?? 0):\(warning.message)"
            if !seenWarnings.contains(key) {
                seenWarnings.insert(key)
                warnings.append(warning)
            }
        } else if let runtimeWarning = parseRuntimeWarning(line) {
            let key = "\(runtimeWarning.file ?? ""):\(runtimeWarning.line ?? 0):\(runtimeWarning.message)"
            if !seenWarnings.contains(key) {
                seenWarnings.insert(key)
                warnings.append(runtimeWarning)
            }
        } else if parsePassedTest(line) {
            return
        } else {
            parseBuildAndTestTime(line)
        }
    }

    // MARK: - Linker Error Parsing

    /// Parses linker-related lines. Returns true if the line was handled.
    private func parseLinkerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Pattern: "Undefined symbols for architecture arm64:"
        if trimmed.hasPrefix("Undefined symbols for architecture ") {
            let afterPrefix = trimmed.dropFirst("Undefined symbols for architecture ".count)
            if let colonIndex = afterPrefix.firstIndex(of: ":") {
                currentLinkerArchitecture = String(afterPrefix[..<colonIndex])
            }
            return true
        }

        // Pattern: "  \"_symbol\", referenced from:" - symbol name line
        if trimmed.hasPrefix("\"") && trimmed.contains("\", referenced from:") {
            if let endQuote = trimmed.range(of: "\", referenced from:") {
                let symbol = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< endQuote.lowerBound])
                pendingLinkerSymbol = symbol
            }
            return true
        }

        // Pattern: "      objc-class-ref in FileName.o" - reference location line
        if let symbol = pendingLinkerSymbol, let arch = currentLinkerArchitecture,
            trimmed.contains(" in ") && (trimmed.hasSuffix(".o") || trimmed.hasSuffix(".a"))
        {
            // Extract the reference (everything after " in ")
            if let inRange = trimmed.range(of: " in ") {
                let referencedFrom = String(trimmed[inRange.upperBound...])
                appendLinkerErrorIfNew(
                    LinkerError(symbol: symbol, architecture: arch, referencedFrom: referencedFrom)
                )
                pendingLinkerSymbol = nil
            }
            return true
        }

        // Pattern: "ld: framework not found SomeFramework"
        if trimmed.hasPrefix("ld: framework not found ") {
            let framework = String(trimmed.dropFirst("ld: framework not found ".count))
            appendLinkerErrorIfNew(LinkerError(message: "framework not found \(framework)"))
            return true
        }

        // Pattern: "ld: library not found for -lsomelib"
        if trimmed.hasPrefix("ld: library not found for ") {
            let library = String(trimmed.dropFirst("ld: library not found for ".count))
            appendLinkerErrorIfNew(LinkerError(message: "library not found for \(library)"))
            return true
        }

        // Pattern: "duplicate symbol '_symbolName' in:" - start multi-line duplicate symbol parsing
        if trimmed.hasPrefix("duplicate symbol '") || trimmed.hasPrefix("duplicate symbol \"") {
            // Extract symbol name from: duplicate symbol '_symbolName' in:
            let quoteChar: Character = trimmed.hasPrefix("duplicate symbol '") ? "'" : "\""
            let afterPrefix =
                trimmed.hasPrefix("duplicate symbol '")
                ? trimmed.dropFirst("duplicate symbol '".count) : trimmed.dropFirst("duplicate symbol \"".count)
            if let endQuote = afterPrefix.firstIndex(of: quoteChar) {
                pendingDuplicateSymbol = String(afterPrefix[..<endQuote])
                pendingConflictingFiles = []
            }
            return true
        }

        // Pattern: "    /path/to/file.o" - conflicting file path (indented, part of duplicate symbol block)
        if pendingDuplicateSymbol != nil && (trimmed.hasSuffix(".o") || trimmed.hasSuffix(".a"))
            && (line.hasPrefix("    ") || line.hasPrefix("\t"))
        {
            pendingConflictingFiles.append(trimmed)
            return true
        }

        // Pattern: "ld: building for iOS Simulator, but linking in dylib built for iOS"
        if trimmed.hasPrefix("ld: building for ") && trimmed.contains("but linking") {
            appendLinkerErrorIfNew(LinkerError(message: trimmed))
            return true
        }

        // Pattern: "ld: N duplicate symbol(s) for architecture arm64" - finalize duplicate symbol error
        if trimmed.hasPrefix("ld: ") && trimmed.contains("duplicate symbol") {
            // Finalize pending duplicate symbol if any
            if let symbol = pendingDuplicateSymbol {
                // Extract architecture from summary line
                var arch = ""
                if let archRange = trimmed.range(of: "for architecture ") {
                    arch = String(trimmed[archRange.upperBound...])
                }
                appendLinkerErrorIfNew(
                    LinkerError(symbol: symbol, architecture: arch, conflictingFiles: pendingConflictingFiles)
                )
                pendingDuplicateSymbol = nil
                pendingConflictingFiles = []
            }
            return true
        }

        // Pattern: "ld: symbol(s) not found for architecture arm64" - just acknowledge, errors already captured
        if trimmed.hasPrefix("ld: symbol(s) not found for architecture ") {
            // Already have the detailed errors, this is just the summary line
            return true
        }

        return false
    }

    private func normalizeTestName(_ testName: String) -> String {
        // Convert "-[xcsiftTests.OutputParserTests testFirstFailingTest]" to "xcsiftTests.OutputParserTests testFirstFailingTest"
        if testName.hasPrefix("-[") && testName.hasSuffix("]") {
            let withoutBrackets = String(testName.dropFirst(2).dropLast(1))
            return withoutBrackets.replacingOccurrences(of: " ", with: " ")
        }
        return testName
    }

    private func hasSeenSimilarTest(_ normalizedTestName: String) -> Bool {
        return seenTestNames.contains(normalizedTestName)
    }

    private func appendLinkerErrorIfNew(_ error: LinkerError) {
        let key = "\(error.symbol):\(error.message)"
        if !seenLinkerErrors.contains(key) {
            seenLinkerErrors.insert(key)
            linkerErrors.append(error)
        }
    }

    /// Checks if a line looks like JSON output (e.g., from the tool's own output or other JSON sources)
    /// This prevents false positives when parsing build output that contains JSON
    private func isJSONLikeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Check for JSON array/object markers at start
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("}") || trimmed.hasPrefix("]") {
            return true
        }

        // Check for JSON key-value pattern: "key" : value
        // Fast check: starts with quote and contains " :
        if trimmed.hasPrefix("\"") && trimmed.contains("\" :") {
            return true
        }

        // Check for lines with multiple escaped characters (common in JSON)
        // Pattern like "\\(message)\"" suggests JSON escaping
        if line.contains("\\\"") && line.contains("\"") && line.contains(":") {
            return true
        }

        // Check for indented lines that look like JSON (common in formatted JSON output)
        if line.hasPrefix(" ") || line.hasPrefix("\t") {
            // Check for JSON array/object markers in indented lines
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("}") || trimmed.hasPrefix("[") || trimmed.hasPrefix("]") {
                return true
            }
            // If it's indented and starts with quote and contains " :
            if trimmed.hasPrefix("\"") && trimmed.contains("\" :") {
                return true
            }
        }

        // Check for lines that contain "error:" but are clearly JSON (e.g., error messages in JSON)
        if line.contains("error:") {
            // If line starts with quote, it's likely JSON: "error" : "value" or "errors" : [...]
            if trimmed.hasPrefix("\"") && trimmed.contains(":") {
                return true
            }

            // If it's indented and has JSON-like structure (quoted keys), it's probably JSON
            if (line.hasPrefix(" ") || line.hasPrefix("\t")) && trimmed.hasPrefix("\"") {
                return true
            }

            // If it has escaped quotes and looks like JSON structure, but NOT if it starts with "error:"
            if !trimmed.hasPrefix("error:") {
                let hasQuotedStrings = line.contains("\"") && line.contains(":")
                let hasEscapedContent = line.contains("\\") && line.contains("\"")
                // If it has escaped quotes and looks like JSON structure (but not a file path)
                if hasEscapedContent && hasQuotedStrings && !line.contains("file:") && !line.contains(".swift:")
                    && !line.contains(".m:") && !line.contains(".h:")
                {
                    return true
                }
            }
        }

        return false
    }

    private func recordPassedTest(named testName: String, duration: Double? = nil) {
        let normalizedTestName = normalizeTestName(testName)
        guard seenPassedTestNames.insert(normalizedTestName).inserted else {
            return
        }
        passedTestsCount += 1

        // Track duration for slow test detection
        if let dur = duration {
            passedTestDurations[normalizedTestName] = dur
        }
    }

    private func parseError(_ line: String) -> BuildError? {
        // Skip JSON-like lines (e.g., "  \"message\" : \"\\\\(message)\\\"\"")
        if isJSONLikeLine(line) {
            return nil
        }

        // Skip visual error lines (e.g., "    |   `- error: message")
        if line.hasPrefix(" ") && (line.contains("|") || line.contains("`")) {
            return nil
        }

        // Fast path: use string parsing instead of regex for common patterns
        if let errorRange = line.range(of: ": error: ") {
            let beforeError = String(line[..<errorRange.lowerBound])
            let message = String(line[errorRange.upperBound...])

            // Parse file:line:column or file:line or file
            let components = beforeError.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 3, let lineNum = Int(components[components.count - 2]),
                let colNum = Int(components[components.count - 1])
            {
                // file:line:column: error: message
                let file = components[0 ..< (components.count - 2)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message, column: colNum)
            } else if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                // file:line: error: message
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message)
            } else {
                // file: error: message
                return BuildError(file: beforeError, line: nil, message: message)
            }
        }

        // Fast path for Fatal error with message
        if let fatalRange = line.range(of: ": Fatal error: ") {
            let beforeError = String(line[..<fatalRange.lowerBound])
            let message = String(line[fatalRange.upperBound...])

            let components = beforeError.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: message)
            } else {
                return BuildError(file: beforeError, line: nil, message: message)
            }
        }

        // Pattern: file:line: Fatal error (without trailing message)
        if line.hasSuffix(": Fatal error") && !line.contains(" xctest[") {
            let beforeFatal = String(line.dropLast(": Fatal error".count))
            let components = beforeFatal.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildError(file: file, line: lineNum, message: "Fatal error")
            }
        }

        // Pattern: ❌ message
        if line.hasPrefix("❌ ") {
            let message = String(line.dropFirst(2))
            return BuildError(file: nil, line: nil, message: message)
        }

        // Pattern: error: message (simple)
        if line.hasPrefix("error: ") {
            let message = String(line.dropFirst(7))
            return BuildError(file: nil, line: nil, message: message)
        }

        // Pattern: Command PhaseScriptExecution failed with a nonzero exit code
        if line.contains("Command PhaseScriptExecution failed with a nonzero exit") {
            return BuildError(file: nil, line: nil, message: line)
        }

        return nil
    }

    private func parseWarning(_ line: String) -> BuildWarning? {
        // Skip JSON-like lines (e.g., "  \"message\" : \"\\\\(message)\\\"\"")
        if isJSONLikeLine(line) {
            return nil
        }

        // Skip visual warning lines (e.g., "    |   `- warning: message")
        if line.hasPrefix(" ") && (line.contains("|") || line.contains("`")) {
            return nil
        }

        // Fast path: use string parsing instead of regex for common patterns
        if let warningRange = line.range(of: ": warning: ") {
            let beforeWarning = String(line[..<warningRange.lowerBound])
            let message = String(line[warningRange.upperBound...])

            // Parse file:line:column or file:line or file
            let components = beforeWarning.split(separator: ":", omittingEmptySubsequences: false)
            if components.count >= 3, let lineNum = Int(components[components.count - 2]),
                let colNum = Int(components[components.count - 1])
            {
                // file:line:column: warning: message
                let file = components[0 ..< (components.count - 2)].joined(separator: ":")
                return BuildWarning(file: file, line: lineNum, message: message, column: colNum)
            } else if components.count >= 2, let lineNum = Int(components[components.count - 1]) {
                // file:line: warning: message
                let file = components[0 ..< (components.count - 1)].joined(separator: ":")
                return BuildWarning(file: file, line: lineNum, message: message)
            } else {
                // file: warning: message
                return BuildWarning(file: beforeWarning, line: nil, message: message)
            }
        }

        // Pattern: warning: message (simple)
        if line.hasPrefix("warning: ") {
            let message = String(line.dropFirst(9))
            return BuildWarning(file: nil, line: nil, message: message)
        }

        return nil
    }

    // MARK: - Runtime Warning Parsing

    /// Parses runtime warnings in format: /path/to/file.swift:42 Message
    /// These are SwiftUI and custom runtime warnings (e.g., from swift-issue-reporting)
    private func parseRuntimeWarning(_ line: String) -> BuildWarning? {
        // Skip if it's a compile warning/error (has `: warning:` or `: error:`)
        if line.contains(": warning:") || line.contains(": error:") {
            return nil
        }

        // Must be absolute path to .swift file
        guard line.hasPrefix("/"), line.contains(".swift:") else {
            return nil
        }

        // Skip visual lines (e.g., "    |   `- warning: message")
        if line.contains("|") || line.contains("`-") {
            return nil
        }

        // Parse /path/to/file.swift:42 Message
        guard let swiftColonRange = line.range(of: ".swift:") else {
            return nil
        }

        let afterColon = line[swiftColonRange.upperBound...]

        // Find the line number (digits followed by space)
        var lineNumEnd = afterColon.startIndex
        while lineNumEnd < afterColon.endIndex && afterColon[lineNumEnd].isNumber {
            lineNumEnd = afterColon.index(after: lineNumEnd)
        }

        // Must have at least one digit, then space, then message
        guard lineNumEnd > afterColon.startIndex,
            lineNumEnd < afterColon.endIndex,
            afterColon[lineNumEnd] == " "
        else {
            return nil
        }

        let lineNumStr = String(afterColon[..<lineNumEnd])
        guard let lineNum = Int(lineNumStr) else {
            return nil
        }

        // Extract file path (everything before .swift: plus .swift)
        let file = String(line[..<swiftColonRange.lowerBound]) + ".swift"
        let message = String(afterColon[afterColon.index(after: lineNumEnd)...])

        // Don't parse empty messages
        guard !message.isEmpty else {
            return nil
        }

        // Determine type based on message content
        let type = detectRuntimeWarningType(message: message)

        return BuildWarning(file: file, line: lineNum, message: message, type: type)
    }

    /// Detects whether a runtime warning is SwiftUI-specific or generic
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

        for keyword in swiftuiKeywords {
            if message.contains(keyword) {
                return .swiftui
            }
        }

        return .runtime
    }

    private func parsePassedTest(_ line: String) -> Bool {
        // Pattern: Test Case 'TestName' passed (0.123 seconds).
        if line.hasPrefix("Test Case '"), let endQuote = line.range(of: "' passed (") {
            let startIndex = line.index(line.startIndex, offsetBy: 11)  // "Test Case '".count
            let testName = String(line[startIndex ..< endQuote.lowerBound])

            // Extract duration from "(X.XXX seconds)"
            var duration: Double? = nil
            let afterPassed = line[endQuote.upperBound...]
            if let parenEnd = afterPassed.range(of: " seconds") {
                let durationStr = String(afterPassed[..<parenEnd.lowerBound])
                duration = Double(durationStr)
            }

            recordPassedTest(named: testName, duration: duration)
            return true
        }

        // Pattern: ✓ Test "name" passed after 0.123 seconds.
        if line.hasPrefix("✓ Test \""), let endQuote = line.range(of: "\" passed") {
            let startIndex = line.index(line.startIndex, offsetBy: 8)  // "✓ Test \"".count
            let testName = String(line[startIndex ..< endQuote.lowerBound])

            // Extract duration from "passed after X.XXX seconds"
            var duration: Double? = nil
            if let afterRange = line.range(of: " after ", range: endQuote.upperBound ..< line.endIndex) {
                let afterStr = line[afterRange.upperBound...]
                if let secondsRange = afterStr.range(of: " seconds") {
                    let durationStr = String(afterStr[..<secondsRange.lowerBound])
                    duration = Double(durationStr)
                }
            }

            recordPassedTest(named: testName, duration: duration)
            return true
        }

        return false
    }

    private func parseFailedTest(_ line: String) -> FailedTest? {
        // Handle XCUnit test failures specifically first
        if line.contains("XCTAssertEqual failed") || line.contains("XCTAssertTrue failed")
            || line.contains("XCTAssertFalse failed")
        {
            // Pattern: file:line: error: -[ClassName testMethod] : XCTAssert... failed: details
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

            // Fallback: extract test name from -[ClassName testMethod] format
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

        // Pattern: Test Case 'TestName' failed (0.123 seconds).
        if line.hasPrefix("Test Case '"), let endQuote = line.range(of: "' failed (") {
            let startIndex = line.index(line.startIndex, offsetBy: 11)
            let test = String(line[startIndex ..< endQuote.lowerBound])

            // Extract duration from "(X.XXX seconds)"
            var duration: Double? = nil
            let afterFailed = line[endQuote.upperBound...]
            if let secondsRange = afterFailed.range(of: " seconds") {
                let durationStr = String(afterFailed[..<secondsRange.lowerBound])
                duration = Double(durationStr)
            }

            // Track duration for slow test detection
            let normalizedTest = normalizeTestName(test)
            if let dur = duration {
                failedTestDurations[normalizedTest] = dur
            }

            let message = duration.map { String(format: "%.3f seconds", $0) } ?? "failed"
            return FailedTest(test: test, message: message, file: nil, line: nil, duration: duration)
        }

        // Pattern: ✘ Test "name" recorded an issue at file:line:column: message
        if line.hasPrefix("✘ Test \""), let issueAt = line.range(of: "\" recorded an issue at ") {
            let startIndex = line.index(line.startIndex, offsetBy: 8)
            let test = String(line[startIndex ..< issueAt.lowerBound])
            let afterIssue = String(line[issueAt.upperBound...])

            // Parse file:line:column: message
            let parts = afterIssue.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            if parts.count >= 4, let lineNum = Int(parts[1]) {
                let file = String(parts[0])
                let message = String(parts[3]).trimmingCharacters(in: .whitespaces)
                return FailedTest(test: test, message: message, file: file, line: lineNum)
            }
        }

        // Pattern: ✘ Test "name" failed after 0.123 seconds with N issues.
        if line.hasPrefix("✘ Test \""), let failedAfter = line.range(of: "\" failed after ") {
            let startIndex = line.index(line.startIndex, offsetBy: 8)
            let test = String(line[startIndex ..< failedAfter.lowerBound])

            // Extract duration from "failed after X.XXX seconds"
            var duration: Double? = nil
            let afterStr = line[failedAfter.upperBound...]
            if let secondsRange = afterStr.range(of: " seconds") {
                let durationStr = String(afterStr[..<secondsRange.lowerBound])
                duration = Double(durationStr)
            }

            // Track duration for slow test detection
            let normalizedTest = normalizeTestName(test)
            if let dur = duration {
                failedTestDurations[normalizedTest] = dur
            }

            return FailedTest(test: test, message: "Test failed", file: nil, line: nil, duration: duration)
        }

        // Pattern: ❌ testname (message)
        if line.hasPrefix("❌ "), let parenStart = line.range(of: " ("),
            let parenEnd = line.range(of: ")", options: .backwards)
        {
            let startIndex = line.index(line.startIndex, offsetBy: 2)
            let test = String(line[startIndex ..< parenStart.lowerBound])
            let message = String(line[parenStart.upperBound ..< parenEnd.lowerBound])
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }

        // Pattern: testname (message) failed
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

    private func parseBuildAndTestTime(_ line: String) {
        // Pattern: ** BUILD SUCCEEDED ** [45.2s] or ** BUILD FAILED ** [15.3s]
        // xcodebuild format with bracket timing - BUILD time
        if line.contains("** BUILD SUCCEEDED **") || line.contains("** BUILD FAILED **") {
            if let bracketStart = line.range(of: "[", options: .backwards),
                let bracketEnd = line.range(of: "]", options: .backwards),
                bracketStart.lowerBound < bracketEnd.lowerBound
            {
                buildTime = String(line[bracketStart.upperBound ..< bracketEnd.lowerBound])
            }
            return
        }

        // Pattern: ** TEST FAILED **
        if line.contains("** TEST FAILED **") {
            testRunFailed = true
            return
        }

        // Pattern: Build complete! (12.34s) - SPM format - BUILD time
        if line.hasPrefix("Build complete!") {
            if let parenStart = line.range(of: "("),
                let parenEnd = line.range(of: ")"),
                parenStart.lowerBound < parenEnd.lowerBound
            {
                buildTime = String(line[parenStart.upperBound ..< parenEnd.lowerBound])
            }
            return
        }

        // Pattern: Build succeeded in time - BUILD time
        if line.hasPrefix("Build succeeded in ") {
            buildTime = String(line.dropFirst(19))
            return
        }

        // Pattern: Build failed after time - BUILD time
        if line.hasPrefix("Build failed after ") {
            buildTime = String(line.dropFirst(19))
            return
        }

        // Pattern: Executed N tests, with N failures (N unexpected) in time (seconds) seconds
        // This is XCTest output format (may have leading whitespace/tab) - TEST time
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("Executed "), let withRange = trimmedLine.range(of: ", with ") {
            let afterExecuted = trimmedLine[
                trimmedLine.index(trimmedLine.startIndex, offsetBy: 9) ..< withRange.lowerBound
            ]
            let testCountStr = afterExecuted.split(separator: " ").first
            if let testCountStr = testCountStr, let total = Int(testCountStr) {
                xctestExecutedCount = total
            }

            // Extract failures count
            let afterWith = String(trimmedLine[withRange.upperBound...])
            if let failureRange = afterWith.range(of: " failure") {
                let beforeFailure = afterWith[..<failureRange.lowerBound]
                let words = beforeFailure.split(separator: " ")
                if let lastWord = words.last, let failures = Int(lastWord) {
                    xctestFailedCount = failures
                }
            }

            // Extract TEST time and accumulate
            if let inRange = trimmedLine.range(of: " in ", range: withRange.upperBound ..< trimmedLine.endIndex) {
                let afterIn = trimmedLine[inRange.upperBound...]
                if let parenStart = afterIn.range(of: " (") {
                    accumulateTestTime(String(afterIn[..<parenStart.lowerBound]))
                } else if let secondsRange = afterIn.range(of: " seconds", options: .backwards) {
                    accumulateTestTime(String(afterIn[..<secondsRange.lowerBound]))
                }
            }
            return
        }

        // Pattern: ✘ Test run with N test(s) failed, N test(s) passed after X seconds.
        // Swift Testing failure summary format - TEST time
        if let testRunRange = line.range(of: "Test run with "),
            let failedRange = line.range(of: " failed, ", range: testRunRange.upperBound ..< line.endIndex),
            let passedRange = line.range(of: " passed after ", range: failedRange.upperBound ..< line.endIndex)
        {
            let beforeFailed = line[testRunRange.upperBound ..< failedRange.lowerBound]
            let failedCountStr = beforeFailed.split(separator: " ").first
            if let failedCountStr = failedCountStr, let failedCount = Int(failedCountStr) {
                swiftTestingFailedCount = failedCount
            }

            let beforePassed = line[failedRange.upperBound ..< passedRange.lowerBound]
            let passedCountStr = beforePassed.split(separator: " ").first
            if let passedCountStr = passedCountStr, let passedCount = Int(passedCountStr),
                let failedCount = swiftTestingFailedCount
            {
                swiftTestingExecutedCount = passedCount + failedCount
            }

            // Extract TEST time and accumulate
            let afterPassed = line[passedRange.upperBound...]
            if let secondsRange = afterPassed.range(of: " seconds", options: .backwards) {
                accumulateTestTime(String(afterPassed[..<secondsRange.lowerBound]))
            } else {
                accumulateTestTime(String(afterPassed))
            }
            return
        }

        // Pattern: Test run with N tests in N suites passed after X seconds.
        // Swift Testing output format (passed-only case) - TEST time
        if let testRunRange = line.range(of: "Test run with "),
            let passedAfter = line.range(of: " passed after ")
        {
            let afterPrefix = line[testRunRange.upperBound ..< passedAfter.lowerBound]
            let testCountStr = afterPrefix.split(separator: " ").first
            if let testCountStr = testCountStr, let total = Int(testCountStr) {
                swiftTestingExecutedCount = total
                swiftTestingFailedCount = 0

                // Only accumulate test time if there were actual tests
                if total > 0 {
                    let afterPassed = line[passedAfter.upperBound...]
                    if let secondsRange = afterPassed.range(of: " seconds", options: .backwards) {
                        accumulateTestTime(String(afterPassed[..<secondsRange.lowerBound]))
                    } else {
                        accumulateTestTime(String(afterPassed))
                    }
                }
            }
        }
    }

    /// Parses time string and adds to accumulator
    private func accumulateTestTime(_ timeString: String) {
        // Remove any trailing characters like "." and whitespace
        let cleaned = timeString.trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))
        if let time = Double(cleaned) {
            testTimeAccumulator += time
        }
    }

    // MARK: - Build Phase Parsing

    /// Adds a phase to the target, tracking order of appearance and avoiding duplicates
    private func addPhaseToTarget(_ phase: String, target: String) {
        if targetPhases[target] == nil {
            targetPhases[target] = []
            // Only add to order if not already present (may have been added by dependency parsing)
            if !targetOrder.contains(target) {
                targetOrder.append(target)
            }
        }
        if !targetPhases[target]!.contains(phase) {
            targetPhases[target]!.append(phase)
        }
    }

    /// Extract target name from "(in target 'TargetName' from project 'ProjectName')"
    private func extractTarget(from line: String) -> String? {
        if let inTargetRange = line.range(of: "(in target '") {
            let afterTarget = line[inTargetRange.upperBound...]
            if let endQuote = afterTarget.range(of: "'") {
                return String(afterTarget[..<endQuote.lowerBound])
            }
        }
        return nil
    }

    /// Phase prefix patterns mapped to their canonical phase names
    private static let phasePatterns: [(prefix: String, phaseName: String)] = [
        ("CompileSwiftSources ", "CompileSwiftSources"),
        ("CompileC ", "CompileC"),
        ("Ld ", "Link"),
        ("CopySwiftLibs ", "CopySwiftLibs"),
        ("PhaseScriptExecution ", "PhaseScriptExecution"),
        ("LinkAssetCatalog ", "LinkAssetCatalog"),
        ("ProcessInfoPlistFile ", "ProcessInfoPlistFile"),
    ]

    /// Returns (phaseName, targetName) tuple if line contains a build phase
    private func parseBuildPhase(_ line: String) -> (String, String)? {
        // Check standard prefix-based patterns
        for (prefix, phaseName) in Self.phasePatterns {
            if line.hasPrefix(prefix), let target = extractTarget(from: line) {
                return (phaseName, target)
            }
        }

        // Special case: SwiftDriver\ Compilation or SwiftDriver Compilation
        if line.contains("SwiftDriver") && line.contains("Compilation"),
            let target = extractTarget(from: line)
        {
            return ("SwiftCompilation", target)
        }

        return nil
    }

    // MARK: - SPM Phase Parsing

    /// Returns (phaseName, targetName) tuple if line contains SPM build phase
    /// Format: [N/M] Compiling TARGET or [N/M] Linking TARGET
    private func parseSPMPhase(_ line: String) -> (String, String)? {
        // Pattern: [1/5] Compiling xcsift main.swift
        // or [1/5] Compiling plugin GenerateManual
        if line.contains("] Compiling ") {
            // Find the start of target name (after "] Compiling ")
            if let compilingRange = line.range(of: "] Compiling ") {
                let afterCompiling = line[compilingRange.upperBound...]
                // Target name is the first word after "Compiling"
                // For SPM: "[1/5] Compiling xcsift main.swift" -> target is "xcsift"
                // For plugins: "[1/1] Compiling plugin GenerateManual" -> target is "plugin" (skip)
                let parts = afterCompiling.split(separator: " ", maxSplits: 1)
                if let targetName = parts.first {
                    let target = String(targetName)
                    // Skip plugin compilation (not a real target)
                    if target == "plugin" {
                        return nil
                    }
                    return ("Compiling", target)
                }
            }
        }

        // Pattern: [3/5] Linking xcsift
        if line.contains("] Linking ") {
            if let linkingRange = line.range(of: "] Linking ") {
                let afterLinking = line[linkingRange.upperBound...]
                // Target name is everything after "Linking" (may have path)
                let targetName = afterLinking.trimmingCharacters(in: .whitespaces)
                if !targetName.isEmpty {
                    return ("Linking", targetName)
                }
            }
        }

        return nil
    }

    // MARK: - Dependency Graph Parsing

    /// Parses dependency graph lines from xcodebuild output
    /// Format:
    ///     Target 'SimpleMeditation' in project 'SimpleMeditation'
    ///         ➜ Explicit dependency on target 'PostHog' in project 'PostHog'
    ///     Target 'phlibwebp' in project 'PostHog' (no dependencies)
    private func parseDependencyGraph(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Pattern: "Target 'TargetName' in project 'ProjectName'"
        if trimmed.hasPrefix("Target '") && trimmed.contains("' in project '") {
            // Extract target name
            let afterTarget = trimmed.dropFirst("Target '".count)
            if let endQuote = afterTarget.range(of: "'") {
                let targetName = String(afterTarget[..<endQuote.lowerBound])
                currentDependencyTarget = targetName

                // Track target order (only add if not already present)
                if !targetOrder.contains(targetName) {
                    targetOrder.append(targetName)
                }

                // Check for "(no dependencies)" suffix
                if trimmed.hasSuffix("(no dependencies)") {
                    targetDependencies[targetName] = []
                }
                return true
            }
        }

        // Pattern: "➜ Explicit dependency on target 'DependencyName' in project 'ProjectName'"
        if trimmed.contains("dependency on target '"), let currentTarget = currentDependencyTarget {
            if let startQuote = trimmed.range(of: "dependency on target '") {
                let afterStartQuote = trimmed[startQuote.upperBound...]
                if let endQuote = afterStartQuote.range(of: "'") {
                    let dependencyName = String(afterStartQuote[..<endQuote.lowerBound])

                    // Add dependency to current target
                    if targetDependencies[currentTarget] == nil {
                        targetDependencies[currentTarget] = []
                    }
                    if !targetDependencies[currentTarget]!.contains(dependencyName) {
                        targetDependencies[currentTarget]!.append(dependencyName)
                    }
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Target Timing Parsing

    /// Returns (targetName, duration) tuple if line contains target timing
    private func parseTargetTiming(_ line: String) -> (String, String)? {
        // Pattern: Build target MyApp of project MyProject with configuration Debug (23.1s)
        if line.hasPrefix("Build target ") && line.contains(" of project ") {
            // Extract target name
            let afterBuildTarget = line.dropFirst("Build target ".count)
            if let ofProjectRange = afterBuildTarget.range(of: " of project ") {
                let targetName = String(afterBuildTarget[..<ofProjectRange.lowerBound])

                // Extract duration from parentheses at the end
                if let parenStart = line.range(of: "(", options: .backwards),
                    let parenEnd = line.range(of: ")", options: .backwards),
                    parenStart.lowerBound < parenEnd.lowerBound
                {
                    let duration = String(line[parenStart.upperBound ..< parenEnd.lowerBound])
                    return (targetName, duration)
                }
            }
        }

        // Pattern: Build target 'MyApp' completed. (12.3s)
        if line.hasPrefix("Build target '") && line.contains("' completed") {
            let afterPrefix = line.dropFirst("Build target '".count)
            if let endQuote = afterPrefix.range(of: "'") {
                let targetName = String(afterPrefix[..<endQuote.lowerBound])

                // Extract duration from parentheses at the end
                if let parenStart = line.range(of: "(", options: .backwards),
                    let parenEnd = line.range(of: ")", options: .backwards),
                    parenStart.lowerBound < parenEnd.lowerBound
                {
                    let duration = String(line[parenStart.upperBound ..< parenEnd.lowerBound])
                    return (targetName, duration)
                }
            }
        }

        return nil
    }

    // MARK: - Executable Parsing

    private func parseExecutable(_ line: String) -> Executable? {
        // Pattern 1: RegisterWithLaunchServices /path/to/Executable.app (in target 'TargetName' from project 'ProjectName')
        // Pattern 2: Validate /path/to/Executable.app (in target 'TargetName' from project 'ProjectName')
        let prefixes = ["RegisterWithLaunchServices ", "Validate "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else {
            return nil
        }
        let afterPrefix = line.dropFirst(prefix.count)

        // Find the path (between prefix and " (in target")
        guard let targetRange = afterPrefix.range(of: " (in target '") else {
            return nil
        }

        let path = String(afterPrefix[..<targetRange.lowerBound])

        // Only capture .app bundles (not other validated artifacts)
        if !path.hasSuffix(".app") {
            return nil
        }

        // Extract the name from the path (last component, e.g., "ClaudeSettings.app")
        let name = (path as NSString).lastPathComponent

        // Extract the target name
        let afterTarget = afterPrefix[targetRange.upperBound...]
        guard let targetEnd = afterTarget.range(of: "' from project") else {
            return nil
        }

        let target = String(afterTarget[..<targetEnd.lowerBound])

        return Executable(path: path, name: name, target: target)
    }
}
