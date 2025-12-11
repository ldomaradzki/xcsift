import Foundation

struct BuildResult: Codable {
    let status: String
    let summary: BuildSummary
    let errors: [BuildError]
    let warnings: [BuildWarning]
    let failedTests: [FailedTest]
    let linkerErrors: [LinkerError]
    let coverage: CodeCoverage?
    let slowTests: [SlowTest]
    let flakyTests: [String]
    let printWarnings: Bool
    let printCoverageDetails: Bool

    enum CodingKeys: String, CodingKey {
        case status, summary, errors, warnings, coverage
        case failedTests = "failed_tests"
        case linkerErrors = "linker_errors"
        case slowTests = "slow_tests"
        case flakyTests = "flaky_tests"
    }

    init(
        status: String,
        summary: BuildSummary,
        errors: [BuildError],
        warnings: [BuildWarning],
        failedTests: [FailedTest],
        linkerErrors: [LinkerError] = [],
        coverage: CodeCoverage?,
        slowTests: [SlowTest] = [],
        flakyTests: [String] = [],
        printWarnings: Bool,
        printCoverageDetails: Bool = false
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
        self.printWarnings = printWarnings
        self.printCoverageDetails = printCoverageDetails
    }

    init(from decoder: Decoder) throws {
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
        printWarnings = false
        printCoverageDetails = false
    }

    func encode(to encoder: Encoder) throws {
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
    }

    // MARK: - GitHub Actions Output

    /// Formats the build result as GitHub Actions workflow commands
    func formatGitHubActions() -> String {
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

struct BuildSummary: Codable {
    let errors: Int
    let warnings: Int
    let failedTests: Int
    let linkerErrors: Int
    let passedTests: Int?
    let buildTime: String?
    let coveragePercent: Double?
    let slowTests: Int?
    let flakyTests: Int?

    enum CodingKeys: String, CodingKey {
        case errors
        case warnings
        case failedTests = "failed_tests"
        case linkerErrors = "linker_errors"
        case passedTests = "passed_tests"
        case buildTime = "build_time"
        case coveragePercent = "coverage_percent"
        case slowTests = "slow_tests"
        case flakyTests = "flaky_tests"
    }

    init(
        errors: Int,
        warnings: Int,
        failedTests: Int,
        linkerErrors: Int = 0,
        passedTests: Int?,
        buildTime: String?,
        coveragePercent: Double?,
        slowTests: Int? = nil,
        flakyTests: Int? = nil
    ) {
        self.errors = errors
        self.warnings = warnings
        self.failedTests = failedTests
        self.linkerErrors = linkerErrors
        self.passedTests = passedTests
        self.buildTime = buildTime
        self.coveragePercent = coveragePercent
        self.slowTests = slowTests
        self.flakyTests = flakyTests
    }

    func encode(to encoder: Encoder) throws {
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
        if let coveragePercent = coveragePercent {
            try container.encode(coveragePercent, forKey: .coveragePercent)
        }
        if let slowTests = slowTests, slowTests > 0 {
            try container.encode(slowTests, forKey: .slowTests)
        }
        if let flakyTests = flakyTests, flakyTests > 0 {
            try container.encode(flakyTests, forKey: .flakyTests)
        }
    }
}

struct BuildError: Codable {
    let file: String?
    let line: Int?
    let message: String

    // Internal only - used for GitHub Actions format, not encoded to JSON/TOON
    var column: Int? = nil

    enum CodingKeys: String, CodingKey {
        case file, line, message
    }
}

struct BuildWarning: Codable {
    let file: String?
    let line: Int?
    let message: String

    // Internal only - used for GitHub Actions format, not encoded to JSON/TOON
    var column: Int? = nil

    enum CodingKeys: String, CodingKey {
        case file, line, message
    }
}

struct FailedTest: Codable {
    let test: String
    let message: String
    let file: String?
    let line: Int?
    let duration: Double?

    // Internal only - used for GitHub Actions format, not encoded to JSON/TOON
    var column: Int? = nil

    enum CodingKeys: String, CodingKey {
        case test, message, file, line, duration
    }

    init(test: String, message: String, file: String?, line: Int?, duration: Double? = nil) {
        self.test = test
        self.message = message
        self.file = file
        self.line = line
        self.duration = duration
        self.column = nil
    }
}

struct CodeCoverage: Codable {
    let lineCoverage: Double
    let files: [FileCoverage]

    enum CodingKeys: String, CodingKey {
        case lineCoverage = "line_coverage"
        case files
    }
}

struct FileCoverage: Codable {
    let path: String
    let name: String
    let lineCoverage: Double
    let coveredLines: Int
    let executableLines: Int

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case lineCoverage = "line_coverage"
        case coveredLines = "covered_lines"
        case executableLines = "executable_lines"
    }
}

struct LinkerError: Codable {
    let symbol: String
    let architecture: String
    let referencedFrom: String
    let message: String
    let conflictingFiles: [String]

    enum CodingKeys: String, CodingKey {
        case symbol
        case architecture
        case referencedFrom = "referenced_from"
        case message
        case conflictingFiles = "conflicting_files"
    }

    init(symbol: String, architecture: String, referencedFrom: String, message: String = "") {
        self.symbol = symbol
        self.architecture = architecture
        self.referencedFrom = referencedFrom
        self.message = message
        self.conflictingFiles = []
    }

    init(message: String) {
        self.symbol = ""
        self.architecture = ""
        self.referencedFrom = ""
        self.message = message
        self.conflictingFiles = []
    }

    init(symbol: String, architecture: String, conflictingFiles: [String]) {
        self.symbol = symbol
        self.architecture = architecture
        self.referencedFrom = ""
        self.message = ""
        self.conflictingFiles = conflictingFiles
    }
}

struct SlowTest: Codable {
    let test: String
    let duration: Double
}
