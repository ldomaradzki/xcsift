import Foundation
import RegexBuilder

struct BuildResult: Codable {
    let status: String
    let summary: BuildSummary
    let errors: [BuildError]
    let warnings: [BuildWarning]
    let failedTests: [FailedTest]
    let coverage: CodeCoverage?
    let printWarnings: Bool
    let printCoverageDetails: Bool

    enum CodingKeys: String, CodingKey {
        case status, summary, errors, warnings, coverage
        case failedTests = "failed_tests"
    }

    init(status: String, summary: BuildSummary, errors: [BuildError], warnings: [BuildWarning], failedTests: [FailedTest], coverage: CodeCoverage?, printWarnings: Bool, printCoverageDetails: Bool = false) {
        self.status = status
        self.summary = summary
        self.errors = errors
        self.warnings = warnings
        self.failedTests = failedTests
        self.coverage = coverage
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
        coverage = try container.decodeIfPresent(CodeCoverage.self, forKey: .coverage)
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

        // Only output coverage section in details mode
        // In summary-only mode, coverage_percent in summary is sufficient
        if let coverage = coverage, printCoverageDetails {
            try container.encode(coverage, forKey: .coverage)
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

        return parts.joined(separator: ", ")
    }
}

struct BuildSummary: Codable {
    let errors: Int
    let warnings: Int
    let failedTests: Int
    let passedTests: Int?
    let buildTime: String?
    let coveragePercent: Double?

    enum CodingKeys: String, CodingKey {
        case errors
        case warnings
        case failedTests = "failed_tests"
        case passedTests = "passed_tests"
        case buildTime = "build_time"
        case coveragePercent = "coverage_percent"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(errors, forKey: .errors)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(failedTests, forKey: .failedTests)

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

    // Internal only - used for GitHub Actions format, not encoded to JSON/TOON
    var column: Int? = nil

    enum CodingKeys: String, CodingKey {
        case test, message, file, line
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

class OutputParser {
    private var errors: [BuildError] = []
    private var warnings: [BuildWarning] = []
    private var failedTests: [FailedTest] = []
    private var buildTime: String?
    private var seenTestNames: Set<String> = []
    private var executedTestsCount: Int?
    private var summaryFailedTestsCount: Int?
    private var passedTestsCount: Int = 0
    private var seenPassedTestNames: Set<String> = []

    func parse(input: String, printWarnings: Bool = false, warningsAsErrors: Bool = false, coverage: CodeCoverage? = nil, printCoverageDetails: Bool = false) -> BuildResult {
        resetState()
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            parseLine(String(line))
        }

        // If warnings-as-errors is enabled, convert warnings to errors
        var finalErrors = errors
        var finalWarnings = warnings

        if warningsAsErrors && !warnings.isEmpty {
            // Convert warnings to errors
            for warning in warnings {
                finalErrors.append(BuildError(
                    file: warning.file,
                    line: warning.line,
                    message: warning.message
                ))
            }
            finalWarnings = []
        }

        let status = finalErrors.isEmpty && failedTests.isEmpty ? "success" : "failed"

        let summaryFailedCount = summaryFailedTestsCount ?? failedTests.count
        let computedPassedTests: Int? = {
            if let executed = executedTestsCount {
                return max(executed - summaryFailedCount, 0)
            }
            if passedTestsCount > 0 {
                return passedTestsCount
            }
            return nil
        }()

        let summary = BuildSummary(
            errors: finalErrors.count,
            warnings: finalWarnings.count,
            failedTests: failedTests.count,
            passedTests: computedPassedTests,
            buildTime: buildTime,
            coveragePercent: coverage?.lineCoverage
        )

        return BuildResult(
            status: status,
            summary: summary,
            errors: finalErrors,
            warnings: finalWarnings,
            failedTests: failedTests,
            coverage: coverage,
            printWarnings: printWarnings,
            printCoverageDetails: printCoverageDetails
        )
    }

    func extractTestedTarget(from input: String) -> String? {
        let lines = input.split(separator: "\n")

        for line in lines {
            let lineStr = String(line)

            // Only match lines with .xctest to skip "All tests" and individual test classes
            if lineStr.contains("Test Suite '") && lineStr.contains(".xctest") && lineStr.contains("started") {
                let pattern = Regex {
                    "Test Suite '"
                    Capture {
                        OneOrMore(.any, .reluctant)
                    }
                    ".xctest"
                    "'"
                }

                if let match = lineStr.firstMatch(of: pattern) {
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
        buildTime = nil
        seenTestNames = []
        executedTestsCount = nil
        summaryFailedTestsCount = nil
        passedTestsCount = 0
        seenPassedTestNames = []
    }
    
    private func parseLine(_ line: String) {
        // Quick filters to avoid regex on irrelevant lines
        if line.isEmpty || line.count > 5000 {
            return
        }

        // Fast path checks before expensive regex
        let containsRelevant = line.contains("error:") ||
                               line.contains("warning:") ||
                               line.contains("failed") ||
                               line.contains("passed") ||
                               line.contains("✘") ||
                               line.contains("✓") ||
                               line.contains("❌") ||
                               line.contains("Build succeeded") ||
                               line.contains("Build failed") ||
                               line.contains("Executed")

        if !containsRelevant {
            return
        }

        if let failedTest = parseFailedTest(line) {
            let normalizedTestName = normalizeTestName(failedTest.test)

            // Check if we've already seen this test name or a similar one
            if !hasSeenSimilarTest(normalizedTestName) {
                failedTests.append(failedTest)
                seenTestNames.insert(normalizedTestName)
            } else {
                // If we've seen this test before, check if the new one has more info (file/line)
                if let index = failedTests.firstIndex(where: { normalizeTestName($0.test) == normalizedTestName }) {
                    let existing = failedTests[index]
                    // Update if new test has file info and existing doesn't
                    if failedTest.file != nil && existing.file == nil {
                        failedTests[index] = failedTest
                    }
                }
            }
        } else if let error = parseError(line) {
            errors.append(error)
        } else if let warning = parseWarning(line) {
            warnings.append(warning)
        } else if parsePassedTest(line) {
            return
        } else if let time = parseBuildTime(line) {
            buildTime = time
        }
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
    
    /// Checks if a line looks like JSON output (e.g., from the tool's own output or other JSON sources)
    /// This prevents false positives when parsing build output that contains JSON
    private func isJSONLikeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Check for JSON-like patterns:
        // 1. Lines that start with quotes and contain colon (JSON key-value pairs)
        // 2. Lines containing JSON structure like "key" : "value"
        // 3. Lines with escaped quotes and backslashes typical of JSON
        // 4. Lines that are indented and contain JSON-like structures (common in formatted JSON)
        
        // Pattern: "key" : "value" or "key" : value
        let jsonKeyValuePattern = Regex {
            Optionally(OneOrMore(.whitespace))
            "\""
            OneOrMore(.any, .reluctant)
            "\""
            Optionally(OneOrMore(.whitespace))
            ":"
            Optionally(OneOrMore(.whitespace))
        }
        
        if trimmed.firstMatch(of: jsonKeyValuePattern) != nil {
            return true
        }
        
        // Check for JSON array/object markers at start
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("}") || trimmed.hasPrefix("]") {
            return true
        }
        
        // Check for lines with multiple escaped characters (common in JSON)
        // Pattern like "\\(message)\"" suggests JSON escaping
        if line.contains("\\\"") && line.contains("\"") && line.contains(":") {
            return true
        }
        
        // Check for indented lines that look like JSON (common in formatted JSON output)
        // Lines starting with spaces/tabs followed by quotes are likely JSON
        if line.hasPrefix(" ") || line.hasPrefix("\t") {
            // If it's indented and contains quoted strings with colons, it's likely JSON
            if trimmed.firstMatch(of: jsonKeyValuePattern) != nil {
                return true
            }
            // Check for JSON array/object markers in indented lines
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("}") || trimmed.hasPrefix("[") || trimmed.hasPrefix("]") {
                return true
            }
        }
        
        // Check for lines that contain "error:" but are clearly JSON (e.g., error messages in JSON)
        // Pattern: lines with quotes, colons, and escaped characters that contain "error:"
        if line.contains("error:") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // If line starts with "error:" (even if indented), it's likely a real error, not JSON
            // UNLESS it's clearly JSON structure like "error" : "value"
            if trimmed.hasPrefix("\"") && trimmed.contains("\"") && trimmed.contains(":") {
                // This looks like JSON: "error" : "value" or "errors" : [...]
                return true
            }
            
            // If it's indented and has JSON-like structure (quoted keys), it's probably JSON
            if (line.hasPrefix(" ") || line.hasPrefix("\t")) && trimmed.hasPrefix("\"") {
                return true
            }
            
            // If it has escaped quotes and looks like JSON structure, but NOT if it starts with "error:"
            // (lines starting with "error:" are likely real errors, not JSON)
            if !trimmed.hasPrefix("error:") {
                let hasQuotedStrings = line.contains("\"") && line.contains(":")
                let hasEscapedContent = line.contains("\\") && line.contains("\"")
                // If it has escaped quotes and looks like JSON structure (but not a file path)
                if hasEscapedContent && hasQuotedStrings && !line.contains("file:") && !line.contains(".swift:") && !line.contains(".m:") && !line.contains(".h:") {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func recordPassedTest(named testName: String) {
        let normalizedTestName = normalizeTestName(testName)
        guard seenPassedTestNames.insert(normalizedTestName).inserted else {
            return
        }
        passedTestsCount += 1
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

        // Pattern: file:line:column: error: message
        let fileLineColumnError = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ":"
            Capture(OneOrMore(.digit))
            ":"
            Capture(OneOrMore(.digit))
            ": error: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }

        if let match = line.firstMatch(of: fileLineColumnError) {
            let file = String(match.1)
            let lineNumber = Int(String(match.2))
            let columnNumber = Int(String(match.3))
            let message = String(match.4)
            return BuildError(file: file, line: lineNumber, message: message, column: columnNumber)
        }
        
        // Pattern: file:line: error: message
        let fileLineError = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ":"
            Capture(OneOrMore(.digit))
            ": error: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: fileLineError) {
            let file = String(match.1)
            let lineNumber = Int(String(match.2))
            let message = String(match.3)
            return BuildError(file: file, line: lineNumber, message: message)
        }
        
        // Pattern: file: error: message
        let fileError = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ": error: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: fileError) {
            let file = String(match.1)
            let message = String(match.2)
            return BuildError(file: file, line: nil, message: message)
        }
        
        // Pattern: file:line: Fatal error: message
        let fileFatalError = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ":"
            Capture(OneOrMore(.digit))
            ": Fatal error: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: fileFatalError) {
            let file = String(match.1)
            let lineNumber = Int(String(match.2))
            let message = String(match.3)
            return BuildError(file: file, line: lineNumber, message: message)
        }
        
        // Pattern: file: Fatal error: message
        let fatalError = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ": Fatal error: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: fatalError) {
            let file = String(match.1)
            let message = String(match.2)
            return BuildError(file: file, line: nil, message: message)
        }
        
        // Pattern: ❌ message
        let emojiError = Regex {
            "❌ "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: emojiError) {
            let message = String(match.1)
            return BuildError(file: nil, line: nil, message: message)
        }
        
        // Pattern: error: message
        let simpleError = Regex {
            "error: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: simpleError) {
            let message = String(match.1)
            return BuildError(file: nil, line: nil, message: message)
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

        // Pattern: file:line:column: warning: message
        let fileLineColumnWarning = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ":"
            Capture(OneOrMore(.digit))
            ":"
            Capture(OneOrMore(.digit))
            ": warning: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }

        if let match = line.firstMatch(of: fileLineColumnWarning) {
            let file = String(match.1)
            let lineNumber = Int(String(match.2))
            let columnNumber = Int(String(match.3))
            let message = String(match.4)
            return BuildWarning(file: file, line: lineNumber, message: message, column: columnNumber)
        }

        // Pattern: file:line: warning: message
        let fileLineWarning = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ":"
            Capture(OneOrMore(.digit))
            ": warning: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }

        if let match = line.firstMatch(of: fileLineWarning) {
            let file = String(match.1)
            let lineNumber = Int(String(match.2))
            let message = String(match.3)
            return BuildWarning(file: file, line: lineNumber, message: message)
        }

        // Pattern: file: warning: message
        let fileWarning = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ": warning: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }

        if let match = line.firstMatch(of: fileWarning) {
            let file = String(match.1)
            let message = String(match.2)
            return BuildWarning(file: file, line: nil, message: message)
        }

        // Pattern: warning: message
        let simpleWarning = Regex {
            "warning: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }

        if let match = line.firstMatch(of: simpleWarning) {
            let message = String(match.1)
            return BuildWarning(file: nil, line: nil, message: message)
        }

        return nil
    }

    private func parsePassedTest(_ line: String) -> Bool {
        let testCasePassedPattern = Regex {
            "Test Case '"
            Capture(OneOrMore(.any, .reluctant))
            "' passed ("
            OneOrMore(.any, .reluctant)
            ")"
            Optionally(".")
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: testCasePassedPattern) {
            let testName = String(match.1)
            recordPassedTest(named: testName)
            return true
        }
        
        let swiftTestingPassedPattern = Regex {
            "✓ Test \""
            Capture(OneOrMore(.any, .reluctant))
            "\" passed"
            OneOrMore(.any, .reluctant)
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: swiftTestingPassedPattern) {
            let testName = String(match.1)
            recordPassedTest(named: testName)
            return true
        }
        
        return false
    }
    
    
    private func parseFailedTest(_ line: String) -> FailedTest? {
        // Handle XCUnit test failures specifically first
        if line.contains("XCTAssertEqual failed") || line.contains("XCTAssertTrue failed") || line.contains("XCTAssertFalse failed") {
            // Pattern: file:line: error: -[ClassName testMethod] : XCTAssert... failed: details
            let xctestPattern = Regex {
                Capture(OneOrMore(.any, .reluctant))
                ":"
                Capture(OneOrMore(.digit))
                ": error: -["
                Capture(OneOrMore(.any, .reluctant))
                "] : "
                Capture(OneOrMore(.any, .reluctant))
                Anchor.endOfSubject
            }
            
            if let match = line.firstMatch(of: xctestPattern) {
                let file = String(match.1)
                let lineNumber = Int(String(match.2))
                let testName = String(match.3)
                let message = String(match.4)
                return FailedTest(test: testName, message: message, file: file, line: lineNumber)
            }
            
            // Fallback: extract test name from -[ClassName testMethod] format
            let testNamePattern = Regex {
                "-["
                Capture(OneOrMore(.any, .reluctant))
                "]"
            }
            
            if let match = line.firstMatch(of: testNamePattern) {
                let testName = String(match.1)
                return FailedTest(test: testName, message: line.trimmingCharacters(in: .whitespaces), file: nil, line: nil)
            }
            
            return FailedTest(test: "Test assertion", message: line.trimmingCharacters(in: .whitespaces), file: nil, line: nil)
        }
        
        // Pattern: Test Case 'TestName' failed (time)
        let testCasePattern = Regex {
            "Test Case '"
            Capture(OneOrMore(.any, .reluctant))
            "' failed ("
            Capture(OneOrMore(.any, .reluctant))
            ")"
            Optionally(".")
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: testCasePattern) {
            let test = String(match.1)
            let message = String(match.2)
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }
        
        // Pattern: ✘ Test "name" recorded an issue at file:line:column: message
        let swiftTestingIssuePattern = Regex {
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
        
        if let match = line.firstMatch(of: swiftTestingIssuePattern) {
            let test = String(match.1)
            let file = String(match.2)
            let lineNumber = Int(String(match.3))
            let message = String(match.4)
            return FailedTest(test: test, message: message, file: file, line: lineNumber)
        }
        
        // Pattern: ✘ Test "name" failed after time with N issues.
        let swiftTestingFailedPattern = Regex {
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
        
        if let match = line.firstMatch(of: swiftTestingFailedPattern) {
            let test = String(match.1)
            return FailedTest(test: test, message: "Test failed", file: nil, line: nil)
        }
        
        // Pattern: ❌ testname (message)
        let emojiTestPattern = Regex {
            "❌ "
            Capture(OneOrMore(.any, .reluctant))
            " ("
            Capture(OneOrMore(.any, .reluctant))
            ")"
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: emojiTestPattern) {
            let test = String(match.1)
            let message = String(match.2)
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }
        
        // Pattern: testname (message) failed
        let testFailedPattern = Regex {
            Capture(OneOrMore(.any, .reluctant))
            " ("
            Capture(OneOrMore(.any, .reluctant))
            ") failed"
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: testFailedPattern) {
            let test = String(match.1)
            let message = String(match.2)
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }
        
        // Pattern: generic failed test with colon
        let colonFailedPattern = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ": "
            Capture(OneOrMore(.any, .reluctant))
            " failed:"
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: colonFailedPattern) {
            let test = String(match.1)
            let message = String(match.2)
            return FailedTest(test: test, message: message, file: nil, line: nil)
        }
        
        return nil
    }
    
    private func parseBuildTime(_ line: String) -> String? {
        // Pattern: Build succeeded in time
        let buildSucceededPattern = Regex {
            "Build succeeded in "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: buildSucceededPattern) {
            return String(match.1)
        }
        
        // Pattern: Build failed after time
        let buildFailedPattern = Regex {
            "Build failed after "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: buildFailedPattern) {
            return String(match.1)
        }
        
        // Pattern: Executed N tests, with N failures (N unexpected) in time (seconds) seconds
        let executedTestsPattern = Regex {
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
        
        if let match = line.firstMatch(of: executedTestsPattern) {
            if let total = Int(match.1) {
                executedTestsCount = total
            }
            if let failures = Int(match.2) {
                summaryFailedTestsCount = failures
            }
            return String(match.4)
        }
        
        let executedTestsSimplePattern = Regex {
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
        
        if let match = line.firstMatch(of: executedTestsSimplePattern) {
            if let total = Int(match.1) {
                executedTestsCount = total
            }
            if let failures = Int(match.2) {
                summaryFailedTestsCount = failures
            }
            return String(match.3)
        }

        // Pattern: Test run with N tests in N suites passed after X seconds.
        let swiftTestingPassedPattern = Regex {
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

        if let match = line.firstMatch(of: swiftTestingPassedPattern) {
            if let total = Int(match.1) {
                executedTestsCount = total
                summaryFailedTestsCount = 0  // All tests passed
            }
            return String(match.2)
        }

        return nil
    }

    // MARK: - Code Coverage Parsing

    // MARK: - Coverage Auto-Conversion Helpers

    /// Runs a shell command and returns the output
    private static func runShellCommand(_ command: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            // Read data BEFORE waiting for exit to avoid pipe deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Finds all .profraw files in a directory (recursively)
    private static func findProfrawFiles(in directory: String) -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            return []
        }

        var profrawFiles: [String] = []
        for case let file as String in enumerator {
            if file.hasSuffix(".profraw") {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                profrawFiles.append(fullPath)
            }
        }
        return profrawFiles
    }

    /// Finds the test binary (.xctest bundle) in .build directory
    private static func findTestBinary() -> String? {
        let fileManager = FileManager.default
        let buildDir = ".build"

        guard fileManager.fileExists(atPath: buildDir),
              let enumerator = fileManager.enumerator(atPath: buildDir) else {
            return nil
        }

        for case let file as String in enumerator {
            if file.hasSuffix(".xctest") {
                let xctestPath = (buildDir as NSString).appendingPathComponent(file)
                let macosPath = (xctestPath as NSString).appendingPathComponent("Contents/MacOS")

                guard let macosContents = try? fileManager.contentsOfDirectory(atPath: macosPath) else {
                    continue
                }

                for item in macosContents {
                    let itemPath = (macosPath as NSString).appendingPathComponent(item)
                    var isDirectory: ObjCBool = false

                    if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                       !isDirectory.boolValue,
                       !item.hasSuffix(".dSYM") {
                        return itemPath
                    }
                }
            }
        }
        return nil
    }

    /// Converts .profraw files to JSON coverage data
    private static func convertProfrawToJSON(profrawFiles: [String]) -> CodeCoverage? {
        guard !profrawFiles.isEmpty else {
            return nil
        }

        guard let testBinary = findTestBinary() else {
            return nil
        }

        let tempDir = NSTemporaryDirectory()
        let profdataPath = (tempDir as NSString).appendingPathComponent("xcsift-coverage.profdata")
        let jsonPath = (tempDir as NSString).appendingPathComponent("xcsift-coverage.json")

        let mergeArgs = ["llvm-profdata", "merge", "-sparse"] + profrawFiles + ["-o", profdataPath]
        guard runShellCommand("xcrun", args: mergeArgs) != nil else {
            return nil
        }

        let exportArgs = ["llvm-cov", "export", testBinary, "-instr-profile=\(profdataPath)", "-format=text"]
        guard let jsonOutput = runShellCommand("xcrun", args: exportArgs) else {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }

        guard let jsonData = jsonOutput.data(using: .utf8) else {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }

        do {
            try jsonData.write(to: URL(fileURLWithPath: jsonPath))
            let coverage = parseCoverageJSON(at: jsonPath)
            try? FileManager.default.removeItem(atPath: profdataPath)
            try? FileManager.default.removeItem(atPath: jsonPath)
            return coverage
        } catch {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }
    }

    /// Finds .xcresult bundles (created by xcodebuild)
    private static func findXCResultBundles(in directory: String) -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            return []
        }

        var xcresultPaths: [String] = []
        for case let file as String in enumerator {
            if file.hasSuffix(".xcresult") {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                xcresultPaths.append(fullPath)
            }
        }
        return xcresultPaths
    }

    /// Finds the most recent .xcresult bundle in Xcode DerivedData using shell find
    private static func findLatestXCResultInDerivedData() -> String? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        let derivedDataPath = (homeDir as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard fileManager.fileExists(atPath: derivedDataPath) else {
            return nil
        }

        let findArgs = ["find", derivedDataPath, "-name", "*.xcresult", "-type", "d", "-mtime", "-7"]
        guard let output = runShellCommand("/usr/bin/env", args: findArgs) else {
            return nil
        }

        let paths = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            return nil
        }

        var newestBundle: String?
        var newestDate: Date?

        for path in paths {
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                if newestDate == nil || modDate > newestDate! {
                    newestDate = modDate
                    newestBundle = path
                }
            }
        }

        return newestBundle
    }

    /// Converts .xcresult bundle to JSON coverage data
    private static func convertXCResultToJSON(xcresultPath: String, targetFilter: String? = nil) -> CodeCoverage? {
        let args = ["xccov", "view", "--report", "--json", xcresultPath]
        guard let jsonOutput = runShellCommand("xcrun", args: args) else {
            return nil
        }

        guard let jsonData = jsonOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        return parseXcodebuildFormat(json: json, targetFilter: targetFilter)
    }

    static func parseCoverageFromPath(_ path: String, targetFilter: String? = nil) -> CodeCoverage? {
        let fileManager = FileManager.default
        let coveragePath: String

        // If explicit path provided and exists, use it
        if !path.isEmpty && fileManager.fileExists(atPath: path) {
            coveragePath = path
        } else {
            // Auto-detect: try xcodebuild first (DerivedData), then SPM paths
            if let latestXCResult = findLatestXCResultInDerivedData() {
                return convertXCResultToJSON(xcresultPath: latestXCResult, targetFilter: targetFilter)
            }

            let defaultPaths = [
                ".build/debug/codecov",
                ".build/arm64-apple-macosx/debug/codecov",
                ".build/x86_64-apple-macosx/debug/codecov",
                ".build/arm64-unknown-linux-gnu/debug/codecov",
                ".build/x86_64-unknown-linux-gnu/debug/codecov",
                "DerivedData",
                "."
            ]

            var foundPath: String?
            for defaultPath in defaultPaths {
                if fileManager.fileExists(atPath: defaultPath) {
                    foundPath = defaultPath
                    break
                }
            }

            guard let found = foundPath else {
                return nil
            }
            coveragePath = found
        }

        guard fileManager.fileExists(atPath: coveragePath) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        _ = fileManager.fileExists(atPath: coveragePath, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            guard let files = try? fileManager.contentsOfDirectory(atPath: coveragePath) else {
                return nil
            }

            let jsonFiles = files.filter { $0.hasSuffix(".json") }
            if let firstJsonFile = jsonFiles.first {
                let jsonPath = (coveragePath as NSString).appendingPathComponent(firstJsonFile)
                return parseCoverageJSON(at: jsonPath, targetFilter: targetFilter)
            }

            let profrawFiles = findProfrawFiles(in: coveragePath)
            if !profrawFiles.isEmpty {
                return convertProfrawToJSON(profrawFiles: profrawFiles)
            }

            let xcresultBundles = findXCResultBundles(in: coveragePath)
            if let firstXCResult = xcresultBundles.first {
                return convertXCResultToJSON(xcresultPath: firstXCResult, targetFilter: targetFilter)
            }

            if let latestXCResult = findLatestXCResultInDerivedData() {
                return convertXCResultToJSON(xcresultPath: latestXCResult, targetFilter: targetFilter)
            }

            return nil
        } else {
            if coveragePath.hasSuffix(".xcresult") {
                return convertXCResultToJSON(xcresultPath: coveragePath, targetFilter: targetFilter)
            } else {
                return parseCoverageJSON(at: coveragePath, targetFilter: targetFilter)
            }
        }
    }

    private static func parseCoverageJSON(at path: String, targetFilter: String? = nil) -> CodeCoverage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let coverage = parseXcodebuildFormat(json: json, targetFilter: targetFilter) {
            return coverage
        }

        if let coverage = parseSPMFormat(json: json) {
            return coverage
        }

        return nil
    }

    private static func parseXcodebuildFormat(json: [String: Any], targetFilter: String? = nil) -> CodeCoverage? {
        guard let targets = json["targets"] as? [[String: Any]] else {
            return nil
        }

        var fileCoverages: [FileCoverage] = []
        var totalCovered = 0
        var totalExecutable = 0

        for target in targets {
            // Get target name if available
            let targetName = target["name"] as? String

            // Skip test bundles - we want coverage of tested code, not tests themselves
            if let name = targetName, name.hasSuffix(".xctest") {
                continue
            }

            // Apply target filter if specified
            if let filter = targetFilter, let name = targetName {
                if !name.contains(filter) && !filter.contains(name) {
                    continue
                }
            }

            guard let filesArray = target["files"] as? [[String: Any]] else {
                continue
            }

            for fileData in filesArray {
                guard let filename = fileData["path"] as? String else {
                    continue
                }

                let lineCoverage: Double
                let covered: Int
                let executable: Int

                if let coverage = fileData["lineCoverage"] as? Double {
                    lineCoverage = coverage > 1.0 ? coverage : coverage * 100.0
                    covered = fileData["coveredLines"] as? Int ?? 0
                    executable = fileData["executableLines"] as? Int ?? 0
                } else {
                    continue
                }

                let name = (filename as NSString).lastPathComponent

                fileCoverages.append(FileCoverage(
                    path: filename,
                    name: name,
                    lineCoverage: lineCoverage,
                    coveredLines: covered,
                    executableLines: executable
                ))

                totalCovered += covered
                totalExecutable += executable
            }
        }

        guard !fileCoverages.isEmpty else {
            return nil
        }

        let overallCoverage = totalExecutable > 0 ? (Double(totalCovered) / Double(totalExecutable)) * 100.0 : 0.0

        return CodeCoverage(lineCoverage: overallCoverage, files: fileCoverages)
    }

    private static func parseSPMFormat(json: [String: Any]) -> CodeCoverage? {
        guard let dataArray = json["data"] as? [[String: Any]],
              let firstData = dataArray.first,
              let filesArray = firstData["files"] as? [[String: Any]] else {
            return nil
        }

        var fileCoverages: [FileCoverage] = []
        var totalCovered = 0
        var totalExecutable = 0

        for fileData in filesArray {
            guard let filename = fileData["filename"] as? String,
                  let summary = fileData["summary"] as? [String: Any],
                  let lines = summary["lines"] as? [String: Any],
                  let covered = lines["covered"] as? Int,
                  let count = lines["count"] as? Int else {
                continue
            }

            let coverage = count > 0 ? (Double(covered) / Double(count)) * 100.0 : 0.0
            let name = (filename as NSString).lastPathComponent

            fileCoverages.append(FileCoverage(
                path: filename,
                name: name,
                lineCoverage: coverage,
                coveredLines: covered,
                executableLines: count
            ))

            totalCovered += covered
            totalExecutable += count
        }

        guard !fileCoverages.isEmpty else {
            return nil
        }

        let overallCoverage = totalExecutable > 0 ? (Double(totalCovered) / Double(totalExecutable)) * 100.0 : 0.0

        return CodeCoverage(lineCoverage: overallCoverage, files: fileCoverages)
    }
}
