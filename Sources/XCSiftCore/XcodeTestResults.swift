import Foundation

/// Reads the test enumeration Xcode's MCP server answers a test run with.
///
/// The server states every test it ran, one block each, and the whole thing runs to tens of
/// kilobytes for a run whose interesting part is three failures:
///
/// ```text
/// ================================================================================
/// TEST RESULTS SUMMARY
/// ================================================================================
/// Generated: 2026-09-12T11:48:08Z
/// Total Results: 72
/// ================================================================================
///
/// --------------------------------------------------------------------------------
/// TEST_RESULT_INDEX: 1/72
/// TEST_TARGET: CalculatorAppFeatureTests
/// TEST_IDENTIFIER: CalculatorBasicTests/testInitialState()
/// TEST_DISPLAY_NAME: Calculator initializes with correct default values
/// TEST_STATE: Passed
/// TEST_FILE_PATH: Tests/CalculatorServiceTests.swift
/// TEST_LINE_NUMBER: 8
/// TEST_TAGS: (none)
///
/// TEST_ISSUE_COUNT: 0
/// ```
///
/// This enumeration is the authority on a run — it is what the test bundles reported, not what a
/// console transcript managed to print — so a result parsed from it is exact, where one counted
/// from Xcode's console log is as complete as that log happened to be.
public enum XcodeTestResults {

    /// Whether `text` is one of these enumerations. Cheap enough to ask of any text block.
    public static func looksLikeTestResults(_ text: String) -> Bool {
        text.contains(Marker.header) && text.contains(Marker.index)
    }

    /// Parses the enumeration into a result, or returns `nil` when the text is not one, or is one
    /// the parser cannot account for in full.
    ///
    /// Completeness is the condition, not a nicety: a caller substitutes this result for the text
    /// it came from, and a block the parser skipped is a test that would silently disappear. When
    /// the count it declares and the blocks it carries disagree, the text is left to the caller.
    public static func parse(_ text: String) -> BuildResult? {
        guard looksLikeTestResults(text) else { return nil }

        var declaredTotal: Int?
        var blocks: [[String]] = []
        var current: [String]?

        for line in TextLines.split(text) {
            if let total = value(of: Marker.totalResults, in: line), blocks.isEmpty, current == nil {
                declaredTotal = Int(total)
                continue
            }
            if value(of: Marker.index, in: line) != nil {
                if let current { blocks.append(current) }
                current = [line]
                continue
            }
            current?.append(line)
        }
        if let current { blocks.append(current) }

        guard let declaredTotal, declaredTotal == blocks.count else { return nil }

        var passed = 0
        var failed: [FailedTest] = []
        var others = 0

        for block in blocks {
            switch state(of: block) {
            case Marker.passed:
                passed += 1
            case Marker.failed:
                failed.append(failure(from: block))
            default:
                // Skipped, or a state this parser has not met. Counted in neither column, and
                // `Total Results` keeps it visible: passed + failed need not reach the total.
                others += 1
            }
        }

        guard passed + failed.count + others == blocks.count else { return nil }

        return BuildResult(
            status: failed.isEmpty ? "success" : "failed",
            summary: BuildSummary(
                errors: 0,
                warnings: 0,
                failedTests: failed.count,
                linkerErrors: 0,
                passedTests: passed,
                buildTime: nil,
                coveragePercent: nil
            ),
            errors: [],
            warnings: [],
            failedTests: failed,
            coverage: nil,
            printWarnings: false
        )
    }

    // MARK: - Blocks

    private static func failure(from block: [String]) -> FailedTest {
        let identifier = field(Marker.identifier, in: block) ?? field(Marker.displayName, in: block) ?? "Unknown test"
        let target = field(Marker.target, in: block)
        let name = target.map { "\($0)/\(identifier)" } ?? identifier

        let issues = issueLines(in: block)
        let parsed = issues.first.flatMap(parseIssue)

        return FailedTest(
            test: name,
            message: parsed?.message ?? issues.first ?? "Test failed",
            file: parsed?.file ?? available(field(Marker.filePath, in: block)),
            line: parsed?.line ?? available(field(Marker.lineNumber, in: block)).flatMap(Int.init)
        )
    }

    /// `    Tests/MyTests.swift:286 MyTests/test(): XCTAssertTrue failed - …`
    private static func parseIssue(_ issue: String) -> (file: String?, line: Int?, message: String)? {
        let trimmed = issue.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(of: " ") else { return nil }

        let location = trimmed[..<firstSpace]
        let rest = trimmed[trimmed.index(after: firstSpace)...]

        // `<identifier>: <message>` — the identifier is already the test's name, so only the
        // message is carried over.
        let message = rest.range(of: ": ").map { String(rest[$0.upperBound...]) } ?? String(rest)

        guard let colon = location.lastIndex(of: ":"), let line = Int(location[location.index(after: colon)...])
        else {
            return (nil, nil, message)
        }
        return (String(location[..<colon]), line, message)
    }

    private static func issueLines(in block: [String]) -> [String] {
        guard let start = block.firstIndex(where: { $0.hasPrefix(Marker.issues) }) else { return [] }
        return block[block.index(after: start)...]
            .prefix { $0.hasPrefix(" ") || $0.hasPrefix("\t") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func state(of block: [String]) -> String {
        field(Marker.state, in: block) ?? ""
    }

    private static func field(_ marker: String, in block: [String]) -> String? {
        for line in block {
            if let value = value(of: marker, in: line) { return value }
        }
        return nil
    }

    private static func value(of marker: String, in line: String) -> String? {
        guard line.hasPrefix(marker) else { return nil }
        return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }

    /// The server writes `(not available)` where it has no value.
    private static func available(_ value: String?) -> String? {
        guard let value, value != Marker.notAvailable, !value.isEmpty else { return nil }
        return value
    }

    private enum Marker {
        static let header = "TEST RESULTS SUMMARY"
        static let index = "TEST_RESULT_INDEX:"
        static let totalResults = "Total Results:"
        static let target = "TEST_TARGET:"
        static let identifier = "TEST_IDENTIFIER:"
        static let displayName = "TEST_DISPLAY_NAME:"
        static let state = "TEST_STATE:"
        static let filePath = "TEST_FILE_PATH:"
        static let lineNumber = "TEST_LINE_NUMBER:"
        static let issues = "TEST_ISSUES:"
        static let notAvailable = "(not available)"
        static let passed = "Passed"
        static let failed = "Failed"
    }
}
