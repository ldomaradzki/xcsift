import Foundation
import RegexBuilder

struct BuildResult: Codable {
    let status: String
    let summary: BuildSummary
    let errors: [BuildError]
    let failedTests: [FailedTest]
    
    enum CodingKeys: String, CodingKey {
        case status, summary, errors
        case failedTests = "failed_tests"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(summary, forKey: .summary)
        
        if !errors.isEmpty {
            try container.encode(errors, forKey: .errors)
        }
        
        if !failedTests.isEmpty {
            try container.encode(failedTests, forKey: .failedTests)
        }
    }
}

struct BuildSummary: Codable {
    let errors: Int
    let failedTests: Int
    let passedTests: Int?
    let buildTime: String?
    
    enum CodingKeys: String, CodingKey {
        case errors
        case failedTests = "failed_tests"
        case passedTests = "passed_tests"
        case buildTime = "build_time"
    }
}

struct BuildError: Codable {
    let file: String?
    let line: Int?
    let message: String
}


struct FailedTest: Codable {
    let test: String
    let message: String
    let file: String?
    let line: Int?
}

class OutputParser {
    private var errors: [BuildError] = []
    private var failedTests: [FailedTest] = []
    private var buildTime: String?
    private var seenTestNames: Set<String> = []
    private var executedTestsCount: Int?
    private var summaryFailedTestsCount: Int?
    private var passedTestsCount: Int = 0
    private var seenPassedTestNames: Set<String> = []
    
    @available(*, deprecated, message: "This function will be removed in a future version")
    func deprecatedFunction() -> String {
        return "This function is deprecated"
    }
    
    func functionWithUnusedVariable() {
        let unusedVariable = "This variable is never used and will cause a warning"
    }
    
    func parse(input: String) -> BuildResult {
        resetState()
        let lines = input.components(separatedBy: .newlines)
        
        for i in 0..<lines.count {
            parseLine(lines[i])
        }
        
        let status = errors.isEmpty && failedTests.isEmpty ? "success" : "failed"
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
            errors: errors.count,
            failedTests: failedTests.count,
            passedTests: computedPassedTests,
            buildTime: buildTime
        )
        
        return BuildResult(
            status: status,
            summary: summary,
            errors: errors,
            failedTests: failedTests
        )
    }
    
    private func resetState() {
        errors = []
        failedTests = []
        buildTime = nil
        seenTestNames = []
        executedTestsCount = nil
        summaryFailedTestsCount = nil
        passedTestsCount = 0
        seenPassedTestNames = []
    }
    
    private func parseLine(_ line: String) {
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
    
    private func recordPassedTest(named testName: String) {
        let normalizedTestName = normalizeTestName(testName)
        guard seenPassedTestNames.insert(normalizedTestName).inserted else {
            return
        }
        passedTestsCount += 1
    }
    
    private func parseError(_ line: String) -> BuildError? {
        // Pattern: file:line:column: error: message
        let fileLineColumnError = Regex {
            Capture(OneOrMore(.any, .reluctant))
            ":"
            Capture(OneOrMore(.digit))
            ":"
            OneOrMore(.digit)
            ": error: "
            Capture(OneOrMore(.any, .reluctant))
            Anchor.endOfSubject
        }
        
        if let match = line.firstMatch(of: fileLineColumnError) {
            let file = String(match.1)
            let lineNumber = Int(String(match.2))
            let message = String(match.3)
            return BuildError(file: file, line: lineNumber, message: message)
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
        
        return nil
    }
}
