import XCTest

@testable import XCSiftCore

final class StreamingOutputParserTests: XCTestCase {
    func testIncrementalFeedProducesBuildResultAtFinish() {
        var parser = StreamingOutputParser(printWarnings: true)

        parser.feed("App.swift:12:5: warning: value 'name' was never used")
        parser.feed("** BUILD SUCCEEDED **")

        let result = parser.finish()

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].file, "App.swift")
        XCTAssertEqual(result.warnings[0].line, 12)
        XCTAssertEqual(result.warnings[0].message, "value 'name' was never used")
    }

    func testIncrementalFeedDiscoversTestedTargetForCoverage() {
        var parser = StreamingOutputParser(discoverTestedTarget: true)

        parser.feed("Test Suite 'VideoGoTests.xctest' started at 2026-08-06 20:00:00.000.")

        XCTAssertEqual(parser.testedTarget, "VideoGo")
    }

    func testCountOnlyWarningsPreservesExactSummaryWithoutRetainingDetails() {
        var parser = StreamingOutputParser(retainWarnings: false)
        let duplicate = "App.swift:4:2: warning: unused value"

        parser.feed(duplicate)
        parser.feed(duplicate)
        parser.feed("Other.swift:8:1: warning: deprecated API")
        parser.feed("** BUILD SUCCEEDED **")

        let result = parser.finish()

        XCTAssertEqual(result.summary.warnings, 2)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testCountOnlyWarningIdentityHandlesOptionalFieldsNULAndCanonicalUnicode() {
        func warningCount(_ lines: [String]) -> Int {
            var parser = StreamingOutputParser(retainWarnings: false)
            for line in lines { parser.feed(line) }
            return parser.finish().summary.warnings
        }

        XCTAssertEqual(
            warningCount(["warning: same", ": warning: same"]),
            2,
            "nil and empty files must remain distinct"
        )
        XCTAssertEqual(
            warningCount([
                "File.swift: warning: same",
                "File.swift:0: warning: same",
            ]),
            2,
            "nil and zero line numbers must remain distinct"
        )
        XCTAssertEqual(
            warningCount([
                "x:1: warning: u\0l2\0mv",
                "x\0l1\0mu:2: warning: v",
            ]),
            2,
            "embedded NULs must not collide with key separators"
        )
        XCTAssertEqual(
            warningCount([
                "é.swift:1: warning: same",
                "e\u{301}.swift:1: warning: same",
            ]),
            1,
            "canonically equivalent Swift strings must deduplicate"
        )
    }

    func testOmittingBuildInfoKeepsDiagnosticOnBuildPhaseLine() {
        var parser = StreamingOutputParser(printWarnings: true, printBuildInfo: false)

        parser.feed(
            "CompileSwiftSources /tmp/Foo.swift:1:2: warning: diagnostic on phase line "
                + "(in target 'MyApp' from project 'MyProject')"
        )
        parser.feed("** BUILD SUCCEEDED **")

        let result = parser.finish()

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.warnings, 1)
        XCTAssertEqual(
            result.warnings.first?.message,
            "diagnostic on phase line (in target 'MyApp' from project 'MyProject')"
        )
        XCTAssertNil(result.buildInfo)
    }

    func testFinishDrainsBufferedRecordedIssueAtEOF() {
        var parser = StreamingOutputParser()
        parser.feed(
            "✘ Test \"rendersCard()\" recorded an issue at CardTests.swift:42:1: Expectation failed"
        )

        let result = parser.finish()

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.failedTests.first?.test, "rendersCard()")
        XCTAssertEqual(result.failedTests.first?.file, "CardTests.swift")
        XCTAssertEqual(result.failedTests.first?.line, 42)
    }

    func testFinishDrainsQueuedCrashEventAtEOF() {
        var parser = StreamingOutputParser()
        parser.feed("Test Case '-[CardTests testCrash]' started.")
        parser.feed("Card.swift:9:1: Fatal error: unexpected nil")

        let result = parser.finish()

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.failedTests, 1)
        XCTAssertEqual(result.failedTests.first?.test, "-[CardTests testCrash]")
    }

    func testTargetDiscoveryIsDisabledByDefault() {
        var parser = StreamingOutputParser()
        parser.feed("Test Suite 'VideoGoTests.xctest' started at 2026-08-06 20:00:00.000.")

        XCTAssertNil(parser.testedTarget)
    }

    func testFinishIsIdempotent() throws {
        var parser = StreamingOutputParser(warningsAsErrors: true)
        parser.feed("App.swift:4:2: warning: unused value")
        parser.feed("** BUILD SUCCEEDED **")

        let first = parser.finish()
        let second = parser.finish()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        XCTAssertEqual(try encoder.encode(first), try encoder.encode(second))
    }

    func testCompleteInputParserDoesNotLeakStateAcrossCalls() {
        let parser = OutputParser()

        let failed = parser.parse(input: "First.swift:1:1: error: broken\n** BUILD FAILED **")
        let succeeded = parser.parse(input: "** BUILD SUCCEEDED **")

        XCTAssertEqual(failed.status, "failed")
        XCTAssertEqual(failed.summary.errors, 1)
        XCTAssertEqual(succeeded.status, "success")
        XCTAssertEqual(succeeded.summary.errors, 0)
    }
}
