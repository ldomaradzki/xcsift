import XCTest

@testable import XCSiftCore

final class TrackingLineParserTests: XCTestCase {

    // MARK: - Immediate consume

    func testImmediateConsume() {
        var parser = TrackingLineParser()
        let (lineRange, result) = parser.feed("main.swift:10:5: error: use of undeclared identifier 'foo'")
        guard case .consumed(let event) = result, case .error = event else {
            return XCTFail("Expected .consumed(.error), got \(result)")
        }
        XCTAssertEqual(lineRange, 1 ... 1)
    }

    // MARK: - Ignored line does not consume a slot

    func testIgnoredLineDoesNotAffectNumbering() {
        var parser = TrackingLineParser()
        let (r1Range, r1) = parser.feed("note: some note message")
        XCTAssertEqual(r1, .ignored)
        XCTAssertNil(r1Range)

        let (r2Range, r2) = parser.feed("main.swift:10:5: error: use of undeclared identifier 'foo'")
        guard case .consumed(let event) = r2, case .error = event else {
            return XCTFail("Expected .consumed(.error), got \(r2)")
        }
        XCTAssertEqual(r2Range, 2 ... 2)
    }

    // MARK: - Buffering then consumed: event attributed to the buffered line

    func testBufferingThenConsumedAttributedToBufferedLine() {
        var parser = TrackingLineParser()

        // Line 1: recorded-issue → buffering
        let (r1Range, r1) = parser.feed("✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed")
        XCTAssertEqual(r1, .buffering)
        XCTAssertEqual(r1Range, 1 ... 1)

        // Line 2: unrelated error → emits testFailed from the line-1 buffer
        let (r2Range, r2) = parser.feed("other.swift:5:1: error: something broke")
        guard case .consumed(let e2) = r2, case .testFailed = e2 else {
            return XCTFail("Expected .consumed(.testFailed) from flushed buffer, got \(r2)")
        }
        XCTAssertEqual(r2Range, 1 ... 1, "testFailed should be attributed to line 1, not line 2")

        // Line 3: anything that drains the overflow error from line 2
        let (r3Range, r3) = parser.feed("note: irrelevant")
        guard case .consumed(let e3) = r3, case .error = e3 else {
            return XCTFail("Expected .consumed(.error) from overflow, got \(r3)")
        }
        XCTAssertEqual(r3Range, 2 ... 2, "overflow error should be attributed to line 2, not extended by line 3")
    }

    // MARK: - Comment-continuation: range extends to include the comment line

    func testCommentContinuationExtendsRangeToIncludeCommentLine() {
        var parser = TrackingLineParser()

        // Line 1: recorded-issue → buffering
        _ = parser.feed("✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed")

        // Line 2: comment continuation → merges into line 1's event; range grows to 1...2
        let (r2Range, r2) = parser.feed("↳ Custom failure reason")
        guard case .consumed(let e2) = r2, case .testFailed = e2 else {
            return XCTFail("Expected .consumed(.testFailed), got \(r2)")
        }
        XCTAssertEqual(
            r2Range,
            1 ... 2,
            "merged testFailed should span lines 1 and 2, since line 2's text is in the message"
        )

        // Line 3: next event should be attributed to line 3 alone (no orphaned slot)
        let (r3Range, r3) = parser.feed("main.swift:7:1: error: bad")
        guard case .consumed(let e3) = r3, case .error = e3 else {
            return XCTFail("Expected .consumed(.error), got \(r3)")
        }
        XCTAssertEqual(r3Range, 3 ... 3, "error on line 3 should not be bumped to line 2 by an orphaned slot")
    }

    // MARK: - flush attributes events to their buffered lines

    func testFlushAttributedToBufferedLine() {
        var parser = TrackingLineParser()
        _ = parser.feed("✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed")
        let events = parser.flush()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].lineRange, 1 ... 1)
        guard case .testFailed = events[0].1 else {
            return XCTFail("Expected .testFailed, got \(events[0].1)")
        }
    }

    // MARK: - flush on empty state

    func testFlushOnEmptyStateReturnsEmpty() {
        var parser = TrackingLineParser()
        XCTAssertTrue(parser.flush().isEmpty)
    }

    // MARK: - Multi-line linker: intermediate lines are ignored

    func testMultiLineLinkerAttributedToFinalLine() {
        var parser = TrackingLineParser()
        let (r1Range, r1) = parser.feed("Undefined symbols for architecture arm64:")
        XCTAssertEqual(r1, .ignored)
        XCTAssertNil(r1Range)

        let (r2Range, r2) = parser.feed("  \"_MissingSymbol\", referenced from:")
        XCTAssertEqual(r2, .ignored)
        XCTAssertNil(r2Range)

        let (r3Range, r3) = parser.feed("      objc-class-ref in SomeFile.o")
        guard case .consumed(let e3) = r3, case .linkerError = e3 else {
            return XCTFail("Expected .consumed(.linkerError), got \(r3)")
        }
        XCTAssertEqual(r3Range, 3 ... 3)
    }

    // MARK: - Multiple consecutive consumed events

    func testConsecutiveConsumedEventsGetSequentialLineNumbers() {
        var parser = TrackingLineParser()
        let lines = [
            "main.swift:1:1: error: error one",
            "main.swift:2:1: error: error two",
            "main.swift:3:1: warning: warning three",
        ]
        for (index, line) in lines.enumerated() {
            let (lineRange, result) = parser.feed(line)
            guard case .consumed = result else {
                return XCTFail("Expected .consumed for line \(index + 1), got \(result)")
            }
            XCTAssertEqual(lineRange, (index + 1) ... (index + 1))
        }
    }

    // MARK: - Forwarded properties

    func testForwardedSuccessMarker() {
        var parser = TrackingLineParser()
        _ = parser.feed("** BUILD SUCCEEDED **")
        XCTAssertTrue(parser.sawSuccessMarker)
        XCTAssertFalse(parser.sawFailureMarker)
    }

    func testForwardedFailureMarker() {
        var parser = TrackingLineParser()
        _ = parser.feed("** BUILD FAILED **")
        XCTAssertTrue(parser.sawFailureMarker)
        XCTAssertFalse(parser.sawSuccessMarker)
    }

    // MARK: - Line counter increments on every feed regardless of result

    func testLineCounterIncrementsOnEveryFeed() {
        var parser = TrackingLineParser()
        // Feed 3 ignored lines then an error; error should be line 4
        _ = parser.feed("note: a")
        _ = parser.feed("note: b")
        _ = parser.feed("note: c")
        let (lineRange, result) = parser.feed("main.swift:1:1: error: something")
        guard case .consumed = result else { return XCTFail("Expected .consumed") }
        XCTAssertEqual(lineRange, 4 ... 4)
    }

    // MARK: - Consecutive recorded-issue lines (no comment continuation) attribute independently

    func testConsecutiveRecordedIssuesAttributeIndependently() {
        var parser = TrackingLineParser()

        // Line 1: recorded-issue → buffering
        let (r1Range, r1) = parser.feed("✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed")
        XCTAssertEqual(r1, .buffering)
        XCTAssertEqual(r1Range, 1 ... 1)

        // Line 2: another recorded-issue → flushes line 1's event, buffers itself
        let (r2Range, r2) = parser.feed(
            "✘ Test \"myTest()\" recorded an issue at Foo.swift:11:1: Expectation failed"
        )
        guard case .consumed(let e2) = r2, case .testFailed = e2 else {
            return XCTFail("Expected .consumed(.testFailed) flushed from line 1, got \(r2)")
        }
        XCTAssertEqual(r2Range, 1 ... 1, "line 1's event must not absorb line 2 just because line 2 also buffers")

        // Line 3: unrelated line drains line 2's buffered event
        let (r3Range, r3) = parser.feed("note: irrelevant")
        guard case .consumed(let e3) = r3, case .testFailed = e3 else {
            return XCTFail("Expected .consumed(.testFailed) flushed from line 2, got \(r3)")
        }
        XCTAssertEqual(r3Range, 2 ... 2, "line 2's event must be attributed to line 2 alone, not extended by line 3")
    }

    // MARK: - Unparseable recorded-issue line: buffered slot resolves via .ignored, not .consumed

    func testUnparseableRecordedIssueThenOverflowAttributesToOverflowLine() {
        var parser = TrackingLineParser()

        // Line 1: contains the recordedIssue marker but not the strict " recorded an issue at "
        // pattern parseFailedTest requires, so it buffers but will never produce an event.
        let (r1Range, r1) = parser.feed(
            "✘ Test \"myTest()\" recorded an issue: something went wrong"
        )
        XCTAssertEqual(r1, .buffering)
        XCTAssertEqual(r1Range, 1 ... 1)

        // Line 2: unrelated error. The buffered line-1 slot resolves with no event (.ignored
        // overall), but line 2's own error is queued internally as overflow.
        let (r2Range, r2) = parser.feed("main.swift:5:1: error: something broke")
        XCTAssertEqual(r2, .ignored)
        XCTAssertNil(r2Range, "line 1's dead slot must not be reported as a delivered event")

        // Line 3: drains the queue, delivering line 2's overflow error.
        let (r3Range, r3) = parser.feed("note: irrelevant")
        guard case .consumed(let e3) = r3, case .error = e3 else {
            return XCTFail("Expected .consumed(.error) from overflow, got \(r3)")
        }
        XCTAssertEqual(
            r3Range,
            2 ... 2,
            "overflow error should be attributed to line 2, not the dead line-1 slot"
        )
    }

    func testUnparseableRecordedIssueThenCommentContinuationDropsDeadRange() {
        var parser = TrackingLineParser()

        // Line 1: unparseable recorded-issue line, same as above.
        let (r1Range, r1) = parser.feed(
            "✘ Test \"myTest()\" recorded an issue: something went wrong"
        )
        XCTAssertEqual(r1, .buffering)
        XCTAssertEqual(r1Range, 1 ... 1)

        // Line 2: looks like a comment continuation, but there is no buffered event to merge
        // into, so nothing is emitted and no overflow is queued either.
        let (r2Range, r2) = parser.feed("↳ Custom failure reason")
        XCTAssertEqual(r2, .ignored)
        XCTAssertNil(r2Range)

        // Line 3: an unrelated error must be attributed to itself, not to the dead line-1 slot.
        let (r3Range, r3) = parser.feed("main.swift:7:1: error: bad")
        guard case .consumed(let e3) = r3, case .error = e3 else {
            return XCTFail("Expected .consumed(.error), got \(r3)")
        }
        XCTAssertEqual(r3Range, 3 ... 3, "error on line 3 should not be bumped to the dead line-1 slot")
    }
}
