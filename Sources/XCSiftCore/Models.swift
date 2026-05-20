import Foundation

public struct BuildResult: Codable, Sendable {
    public let status: String
    public let summary: BuildSummary
    public let errors: [BuildError]
    public let warnings: [BuildWarning]
    public let failedTests: [FailedTest]
    public let linkerErrors: [LinkerError]
    public let coverage: CodeCoverage?
    public let slowTests: [SlowTest]
    public let flakyTests: [String]
    public let buildInfo: BuildInfo?
    public let executables: [Executable]
    public let printWarnings: Bool
    public let printCoverageDetails: Bool
    public let printBuildInfo: Bool
    public let printExecutables: Bool

    public enum CodingKeys: String, CodingKey {
        case status, summary, errors, warnings, coverage, executables
        case failedTests = "failed_tests"
        case linkerErrors = "linker_errors"
        case slowTests = "slow_tests"
        case flakyTests = "flaky_tests"
        case buildInfo = "build_info"
    }

    public init(
        status: String,
        summary: BuildSummary,
        errors: [BuildError],
        warnings: [BuildWarning],
        failedTests: [FailedTest],
        linkerErrors: [LinkerError] = [],
        coverage: CodeCoverage?,
        slowTests: [SlowTest] = [],
        flakyTests: [String] = [],
        buildInfo: BuildInfo? = nil,
        executables: [Executable] = [],
        printWarnings: Bool,
        printCoverageDetails: Bool = false,
        printBuildInfo: Bool = false,
        printExecutables: Bool = false
    ) {
        self.status = status
        self.summary = summary
        self.errors = errors
        self.warnings = warnings
        self.failedTests = failedTests
        self.linkerErrors = linkerErrors
        self.coverage = coverage
        self.slowTests = slowTests
        self.flakyTests = flakyTests
        self.buildInfo = buildInfo
        self.executables = executables
        self.printWarnings = printWarnings
        self.printCoverageDetails = printCoverageDetails
        self.printBuildInfo = printBuildInfo
        self.printExecutables = printExecutables
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        summary = try container.decode(BuildSummary.self, forKey: .summary)
        errors = try container.decodeIfPresent([BuildError].self, forKey: .errors) ?? []
        warnings = try container.decodeIfPresent([BuildWarning].self, forKey: .warnings) ?? []
        failedTests = try container.decodeIfPresent([FailedTest].self, forKey: .failedTests) ?? []
        linkerErrors = try container.decodeIfPresent([LinkerError].self, forKey: .linkerErrors) ?? []
        coverage = try container.decodeIfPresent(CodeCoverage.self, forKey: .coverage)
        slowTests = try container.decodeIfPresent([SlowTest].self, forKey: .slowTests) ?? []
        flakyTests = try container.decodeIfPresent([String].self, forKey: .flakyTests) ?? []
        buildInfo = try container.decodeIfPresent(BuildInfo.self, forKey: .buildInfo)
        executables = try container.decodeIfPresent([Executable].self, forKey: .executables) ?? []
        printWarnings = false
        printCoverageDetails = false
        printBuildInfo = false
        printExecutables = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(summary, forKey: .summary)

        if !errors.isEmpty {
            try container.encode(errors, forKey: .errors)
        }

        if printWarnings && !warnings.isEmpty {
            try container.encode(warnings, forKey: .warnings)
        }

        if !failedTests.isEmpty {
            try container.encode(failedTests, forKey: .failedTests)
        }

        if !linkerErrors.isEmpty {
            try container.encode(linkerErrors, forKey: .linkerErrors)
        }

        // Only output coverage section in details mode
        // In summary-only mode, coverage_percent in summary is sufficient
        if let coverage = coverage, printCoverageDetails {
            try container.encode(coverage, forKey: .coverage)
        }

        if !slowTests.isEmpty {
            try container.encode(slowTests, forKey: .slowTests)
        }

        if !flakyTests.isEmpty {
            try container.encode(flakyTests, forKey: .flakyTests)
        }

        // Only output build_info section when printBuildInfo flag is set and there are targets
        if printBuildInfo, let buildInfo = buildInfo, !buildInfo.targets.isEmpty {
            try container.encode(buildInfo, forKey: .buildInfo)
        }

        if printExecutables && !executables.isEmpty {
            try container.encode(executables, forKey: .executables)
        }
    }

    // MARK: - GitHub Actions Output

    /// Formats the build result as GitHub Actions workflow commands
    public func formatGitHubActions() -> String {
        var output: [String] = []

        // Format errors as ::error commands
        for error in errors {
            output.append(formatGitHubActionsError(error))
        }

        // Format linker errors as ::error commands
        for linkerError in linkerErrors {
            output.append(formatGitHubActionsLinkerError(linkerError))
        }

        // Format warnings as ::warning commands
        if printWarnings {
            for warning in warnings {
                output.append(formatGitHubActionsWarning(warning))
            }
        }

        // Format failed tests as ::error commands
        for test in failedTests {
            output.append(formatGitHubActionsTest(test))
        }

        // Add summary notice
        let summaryMessage = buildSummaryMessage()
        output.append("::notice ::\(summaryMessage)")

        return output.joined(separator: "\n")
    }

    private func formatGitHubActionsError(_ error: BuildError) -> String {
        let fileComponents = formatFileComponents(file: error.file, line: error.line, column: error.column)
        return "::\("error") \(fileComponents)::\(error.message)"
    }

    private func formatGitHubActionsLinkerError(_ linkerError: LinkerError) -> String {
        if !linkerError.symbol.isEmpty {
            let details =
                "Undefined symbol '\(linkerError.symbol)' for \(linkerError.architecture), referenced from \(linkerError.referencedFrom)"
            return "::error ::\(details)"
        } else {
            return "::error ::\(linkerError.message)"
        }
    }

    private func formatGitHubActionsWarning(_ warning: BuildWarning) -> String {
        let fileComponents = formatFileComponents(file: warning.file, line: warning.line, column: warning.column)
        return "::\("warning") \(fileComponents)::\(warning.message)"
    }

    private func formatGitHubActionsTest(_ test: FailedTest) -> String {
        var fileComponents = formatFileComponents(file: test.file, line: test.line, column: test.column)
        // Add test name as title for better visibility in GitHub Actions
        if !fileComponents.isEmpty {
            fileComponents += ","
        }
        fileComponents += "title=\(test.test)"
        return "::\("error") \(fileComponents)::\(test.message)"
    }

    private func formatFileComponents(file: String?, line: Int?, column: Int?) -> String {
        guard let file = file else {
            return ""
        }

        guard let line = line else {
            return "file=\(file)"
        }

        if let column = column {
            return "file=\(file),line=\(line),col=\(column)"
        }

        return "file=\(file),line=\(line)"
    }

    private func buildSummaryMessage() -> String {
        var parts: [String] = []

        if status == "success" {
            parts.append("Build succeeded")
        } else {
            parts.append("Build failed")
        }

        if summary.errors > 0 {
            parts.append("\(summary.errors) error\(summary.errors == 1 ? "" : "s")")
        }

        if summary.linkerErrors > 0 {
            parts.append("\(summary.linkerErrors) linker error\(summary.linkerErrors == 1 ? "" : "s")")
        }

        if summary.warnings > 0 {
            parts.append("\(summary.warnings) warning\(summary.warnings == 1 ? "" : "s")")
        }

        if summary.failedTests > 0 {
            parts.append("\(summary.failedTests) failed test\(summary.failedTests == 1 ? "" : "s")")
        }

        if let passedTests = summary.passedTests, passedTests > 0 {
            parts.append("\(passedTests) passed test\(passedTests == 1 ? "" : "s")")
        }

        if let buildTime = summary.buildTime {
            parts.append("in \(buildTime)")
        }

        if let coveragePercent = summary.coveragePercent {
            parts.append(String(format: "%.1f%% coverage", coveragePercent))
        }

        if let slowTests = summary.slowTests, slowTests > 0 {
            parts.append("\(slowTests) slow test\(slowTests == 1 ? "" : "s")")
        }

        if let flakyTests = summary.flakyTests, flakyTests > 0 {
            parts.append("\(flakyTests) flaky test\(flakyTests == 1 ? "" : "s")")
        }

        return parts.joined(separator: ", ")
    }
}

public struct BuildSummary: Codable, Sendable {
    public let errors: Int
    public let warnings: Int
    public let failedTests: Int
    public let linkerErrors: Int
    public let passedTests: Int?
    public let buildTime: String?
    public let testTime: String?
    public let coveragePercent: Double?
    public let slowTests: Int?
    public let flakyTests: Int?
    public let executables: Int?

    public enum CodingKeys: String, CodingKey {
        case errors
        case warnings
        case failedTests = "failed_tests"
        case linkerErrors = "linker_errors"
        case passedTests = "passed_tests"
        case buildTime = "build_time"
        case testTime = "test_time"
        case coveragePercent = "coverage_percent"
        case slowTests = "slow_tests"
        case flakyTests = "flaky_tests"
        case executables
    }

    public init(
        errors: Int,
        warnings: Int,
        failedTests: Int,
        linkerErrors: Int = 0,
        passedTests: Int?,
        buildTime: String?,
        testTime: String? = nil,
        coveragePercent: Double?,
        slowTests: Int? = nil,
        flakyTests: Int? = nil,
        executables: Int? = nil
    ) {
        self.errors = errors
        self.warnings = warnings
        self.failedTests = failedTests
        self.linkerErrors = linkerErrors
        self.passedTests = passedTests
        self.buildTime = buildTime
        self.testTime = testTime
        self.coveragePercent = coveragePercent
        self.slowTests = slowTests
        self.flakyTests = flakyTests
        self.executables = executables
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errors, forKey: .errors)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(failedTests, forKey: .failedTests)
        try container.encode(linkerErrors, forKey: .linkerErrors)

        // Only encode optional fields if they have values
        if let passedTests = passedTests {
            try container.encode(passedTests, forKey: .passedTests)
        }
        if let buildTime = buildTime {
            try container.encode(buildTime, forKey: .buildTime)
        }
        if let testTime = testTime {
            try container.encode(testTime, forKey: .testTime)
        }
        if let coveragePercent = coveragePercent {
            try container.encode(coveragePercent, forKey: .coveragePercent)
        }
        if let slowTests = slowTests, slowTests > 0 {
            try container.encode(slowTests, forKey: .slowTests)
        }
        if let flakyTests = flakyTests, flakyTests > 0 {
            try container.encode(flakyTests, forKey: .flakyTests)
        }
        if let executables = executables {
            try container.encode(executables, forKey: .executables)
        }
    }
}

public struct BuildError: Codable, Sendable {
    public let file: String?
    public let line: Int?
    public let message: String

    // Internal only - used for GitHub Actions format, not encoded to JSON/TOON
    public var column: Int? = nil

    public enum CodingKeys: String, CodingKey {
        case file, line, message
    }

    public init(file: String?, line: Int?, message: String, column: Int?) {
        self.file = file
        self.line = line
        self.message = message
        self.column = column
    }
}

public enum WarningType: String, Codable, Sendable {
    case compile
    case runtime
    case swiftui
}

public struct BuildWarning: Codable, Sendable {
    public let file: String?
    public let line: Int?
    public let message: String
    public let type: WarningType

    // Internal only - used for GitHub Actions format, not encoded to JSON/TOON
    public var column: Int? = nil

    public enum CodingKeys: String, CodingKey {
        case file, line, message, type
    }

    public init(file: String?, line: Int?, message: String, type: WarningType = .compile, column: Int? = nil) {
        self.file = file
        self.line = line
        self.message = message
        self.type = type
        self.column = column
    }
}

public struct FailedTest: Codable, Sendable {
    public let test: String
    public let message: String
    public let file: String?
    public let line: Int?
    public let duration: Double?

    // Internal only - used for GitHub Actions format, not encoded to JSON/TOON
    public var column: Int? = nil

    public enum CodingKeys: String, CodingKey {
        case test, message, file, line, duration
    }

    public init(test: String, message: String, file: String?, line: Int?, duration: Double? = nil) {
        self.test = test
        self.message = message
        self.file = file
        self.line = line
        self.duration = duration
        self.column = nil
    }
}

public struct CodeCoverage: Codable, Sendable {
    public let lineCoverage: Double
    public let files: [FileCoverage]

    public init(lineCoverage: Double, files: [FileCoverage]) {
        self.lineCoverage = lineCoverage
        self.files = files
    }

    public enum CodingKeys: String, CodingKey {
        case lineCoverage = "line_coverage"
        case files
    }
}

public struct FileCoverage: Codable, Sendable {
    public let path: String
    public let name: String
    public let lineCoverage: Double
    public let coveredLines: Int
    public let executableLines: Int

    public init(path: String, name: String, lineCoverage: Double, coveredLines: Int, executableLines: Int) {
        self.path = path
        self.name = name
        self.lineCoverage = lineCoverage
        self.coveredLines = coveredLines
        self.executableLines = executableLines
    }

    public enum CodingKeys: String, CodingKey {
        case path
        case name
        case lineCoverage = "line_coverage"
        case coveredLines = "covered_lines"
        case executableLines = "executable_lines"
    }
}

public struct LinkerError: Codable, Sendable {
    public let symbol: String
    public let architecture: String
    public let referencedFrom: String
    public let message: String
    public let conflictingFiles: [String]

    public enum CodingKeys: String, CodingKey {
        case symbol
        case architecture
        case referencedFrom = "referenced_from"
        case message
        case conflictingFiles = "conflicting_files"
    }

    public init(symbol: String, architecture: String, referencedFrom: String, message: String = "") {
        self.symbol = symbol
        self.architecture = architecture
        self.referencedFrom = referencedFrom
        self.message = message
        self.conflictingFiles = []
    }

    public init(message: String) {
        self.symbol = ""
        self.architecture = ""
        self.referencedFrom = ""
        self.message = message
        self.conflictingFiles = []
    }

    public init(symbol: String, architecture: String, conflictingFiles: [String]) {
        self.symbol = symbol
        self.architecture = architecture
        self.referencedFrom = ""
        self.message = ""
        self.conflictingFiles = conflictingFiles
    }
}

public struct SlowTest: Codable, Sendable {
    public let test: String
    public let duration: Double
}

// MARK: - Build Info (Phases + Timing per target)
// Note: Total build time is already in BuildSummary.buildTime, so not duplicated here

public struct BuildInfo: Codable, Sendable {
    public let targets: [TargetBuildInfo]
    public let slowestTargets: [String]

    public enum CodingKeys: String, CodingKey {
        case targets
        case slowestTargets = "slowest_targets"
    }

    public init(targets: [TargetBuildInfo] = [], slowestTargets: [String] = []) {
        self.targets = targets
        self.slowestTargets = slowestTargets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decodeIfPresent([TargetBuildInfo].self, forKey: .targets) ?? []
        slowestTargets = try container.decodeIfPresent([String].self, forKey: .slowestTargets) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !targets.isEmpty {
            try container.encode(targets, forKey: .targets)
        }
        if !slowestTargets.isEmpty {
            try container.encode(slowestTargets, forKey: .slowestTargets)
        }
    }
}

public struct TargetBuildInfo: Codable, Sendable {
    public let name: String
    public let duration: String?
    public let phases: [String]
    public let dependsOn: [String]

    public enum CodingKeys: String, CodingKey {
        case name, duration, phases
        case dependsOn = "depends_on"
    }

    public init(name: String, duration: String? = nil, phases: [String] = [], dependsOn: [String] = []) {
        self.name = name
        self.duration = duration
        self.phases = phases
        self.dependsOn = dependsOn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        duration = try container.decodeIfPresent(String.self, forKey: .duration)
        phases = try container.decodeIfPresent([String].self, forKey: .phases) ?? []
        dependsOn = try container.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let duration = duration {
            try container.encode(duration, forKey: .duration)
        }
        if !phases.isEmpty {
            try container.encode(phases, forKey: .phases)
        }
        if !dependsOn.isEmpty {
            try container.encode(dependsOn, forKey: .dependsOn)
        }
    }
}

public struct Executable: Codable, Sendable {
    public let path: String
    public let name: String
    public let target: String
}
