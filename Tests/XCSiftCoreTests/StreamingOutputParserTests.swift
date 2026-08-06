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
