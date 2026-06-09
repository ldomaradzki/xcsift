import XCTest

@testable import XCSiftCore

final class LineParserTests: XCTestCase {

    // MARK: - Ignored line

    func testIgnoredLine() {
        var parser = LineParser()
        XCTAssertEqual(parser.feed("note: some note message"), .ignored)
    }

    // MARK: - Error

    func testError() {
        var parser = LineParser()
        let result = parser.feed("main.swift:10:5: error: use of undeclared identifier 'foo'")
        guard case .consumed(let event) = result, case .error(let error) = event else {
            return XCTFail("Expected .consumed(.error), got \(result)")
        }
        XCTAssertEqual(error.file, "main.swift")
        XCTAssertEqual(error.line, 10)
        XCTAssertEqual(error.message, "use of undeclared identifier 'foo'")
    }

    // MARK: - Warning

    func testWarning() {
        var parser = LineParser()
        let result = parser.feed("Foo.swift:3:1: warning: unused variable 'x'")
        guard case .consumed(let event) = result, case .warning(let warning) = event else {
            return XCTFail("Expected .consumed(.warning), got \(result)")
        }
        XCTAssertEqual(warning.file, "Foo.swift")
        XCTAssertEqual(warning.line, 3)
        XCTAssertEqual(warning.message, "unused variable 'x'")
    }

    // MARK: - Failed test

    func testFailedTest() {
        var parser = LineParser()
        let result = parser.feed(
            "Test Case '-[MyModule.MyTests testFoo]' failed (0.123 seconds)."
        )
        guard case .consumed(let event) = result, case .testFailed(let failed) = event else {
            return XCTFail("Expected .consumed(.testFailed), got \(result)")
        }
        XCTAssertEqual(failed.test, "-[MyModule.MyTests testFoo]")
    }

    // MARK: - Passed test

    func testPassedTest() {
        var parser = LineParser()
        let result = parser.feed(
            "Test Case '-[MyModule.MyTests testBar]' passed (0.001 seconds)."
        )
        guard case .consumed(let event) = result, case .testPassed(let name, let duration) = event
        else {
            return XCTFail("Expected .consumed(.testPassed), got \(result)")
        }
        XCTAssertEqual(name, "-[MyModule.MyTests testBar]")
        XCTAssertEqual(duration ?? 0, 0.001, accuracy: 0.0001)
    }

    // MARK: - Test started

    func testTestStarted() {
        var parser = LineParser()
        let result = parser.feed("Test Case '-[MyModule.MyTests testBaz]' started.")
        guard case .consumed(let event) = result, case .testStarted(let name) = event else {
            return XCTFail("Expected .consumed(.testStarted), got \(result)")
        }
        XCTAssertEqual(name, "-[MyModule.MyTests testBaz]")
    }

    // MARK: - Linker: undefined symbol (3-line sequence)

    func testLinkerUndefinedSymbol() {
        var parser = LineParser()
        XCTAssertEqual(
            parser.feed("Undefined symbols for architecture arm64:"),
            .ignored
        )
        XCTAssertEqual(
            parser.feed("  \"_MissingSymbol\", referenced from:"),
            .ignored
        )
        let result = parser.feed("      objc-class-ref in SomeFile.o")
        guard case .consumed(let event) = result, case .linkerError(let linkerError) = event else {
            return XCTFail("Expected .consumed(.linkerError), got \(result)")
        }
        XCTAssertEqual(linkerError.symbol, "_MissingSymbol")
        XCTAssertEqual(linkerError.architecture, "arm64")
        XCTAssertEqual(linkerError.referencedFrom, "SomeFile.o")
    }

    // MARK: - Linker: duplicate symbol (multi-line)

    func testLinkerDuplicateSymbol() {
        var parser = LineParser()
        XCTAssertEqual(parser.feed("duplicate symbol '_dupVar' in:"), .ignored)
        XCTAssertEqual(parser.feed("    /path/to/FileA.o"), .ignored)
        XCTAssertEqual(parser.feed("    /path/to/FileB.o"), .ignored)
        let result = parser.feed("ld: 1 duplicate symbol for architecture arm64")
        guard case .consumed(let event) = result, case .linkerError(let linkerError) = event else {
            return XCTFail("Expected .consumed(.linkerError), got \(result)")
        }
        XCTAssertEqual(linkerError.symbol, "_dupVar")
        XCTAssertEqual(linkerError.conflictingFiles.count, 2)
    }

    // MARK: - Swift Testing look-ahead: buffering

    func testSwiftTestingBuffering() {
        var parser = LineParser()
        let result = parser.feed(
            "✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed"
        )
        XCTAssertEqual(result, .buffering)
    }

    // MARK: - Swift Testing look-ahead: comment appended

    func testSwiftTestingCommentAppended() {
        var parser = LineParser()
        _ = parser.feed(
            "✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed"
        )
        let result = parser.feed("↳ Custom failure reason")
        guard case .consumed(let event) = result, case .testFailed(let failed) = event else {
            return XCTFail("Expected .consumed(.testFailed), got \(result)")
        }
        XCTAssert(
            failed.message.contains("Custom failure reason"),
            "Expected comment in message, got: \(failed.message)"
        )
    }

    // MARK: - Swift Testing look-ahead: no comment, unrelated line

    func testSwiftTestingNoComment() {
        var parser = LineParser()
        // First feed: buffering
        let r1 = parser.feed(
            "✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed"
        )
        XCTAssertEqual(r1, .buffering)

        // Second feed (error line): emits testFailed from buffer
        let r2 = parser.feed("other.swift:5:1: error: something broke")
        guard case .consumed(let e2) = r2, case .testFailed = e2 else {
            return XCTFail("Expected .consumed(.testFailed) from flushed buffer, got \(r2)")
        }

        // Third feed: should return the overflow error event
        let r3 = parser.feed("note: irrelevant")
        guard case .consumed(let e3) = r3, case .error = e3 else {
            return XCTFail("Expected .consumed(.error) from pendingEvent, got \(r3)")
        }
    }

    // MARK: - flush drains pending buffer

    func testFlushDrainsBuffer() {
        var parser = LineParser()
        _ = parser.feed(
            "✘ Test \"myTest()\" recorded an issue at Foo.swift:10:1: Expectation failed"
        )
        let events = parser.flush()
        XCTAssertEqual(events.count, 1)
        guard case .testFailed(let failed) = events[0] else {
            return XCTFail("Expected .testFailed, got \(events[0])")
        }
        XCTAssertFalse(failed.message.contains(":"), "No comment should be in message")
    }

    // MARK: - Build time

    func testBuildTime() {
        var parser = LineParser()
        let result = parser.feed("** BUILD SUCCEEDED ** [12.345 seconds]")
        guard case .consumed(let event) = result, case .buildTime(let buildTime) = event else {
            return XCTFail("Expected .consumed(.buildTime), got \(result)")
        }
        XCTAssertEqual(buildTime, "12.345 seconds")
    }

    // MARK: - Test run failed

    func testTestRunFailed() {
        var parser = LineParser()
        let result = parser.feed("** TEST FAILED **")
        guard case .consumed(let event) = result, case .testRunFailed = event else {
            return XCTFail("Expected .consumed(.testRunFailed), got \(result)")
        }
    }

    // MARK: - Terminal markers

    func testSawSuccessMarker() {
        for marker in ["** BUILD SUCCEEDED **", "** TEST SUCCEEDED **", "Build complete!", "Build succeeded in 1.2s"] {
            var parser = LineParser()
            _ = parser.feed(marker)
            XCTAssertTrue(parser.sawSuccessMarker, "Expected success marker for \(marker)")
            XCTAssertFalse(parser.sawFailureMarker, "Unexpected failure marker for \(marker)")
        }
    }

    func testSawFailureMarker() {
        for marker in ["** BUILD FAILED **", "** TEST FAILED **", "Build failed after 1.2s"] {
            var parser = LineParser()
            _ = parser.feed(marker)
            XCTAssertTrue(parser.sawFailureMarker, "Expected failure marker for \(marker)")
            XCTAssertFalse(parser.sawSuccessMarker, "Unexpected success marker for \(marker)")
        }
    }

    func testNoTerminalMarker() {
        var parser = LineParser()
        _ = parser.feed("CompileSwiftSources normal arm64")
        XCTAssertFalse(parser.sawSuccessMarker)
        XCTAssertFalse(parser.sawFailureMarker)
    }

    // MARK: - Build phase

    func testBuildPhase() {
        var parser = LineParser()
        let result = parser.feed(
            "CompileSwiftSources /some/path (in target 'MyApp' from project 'MyProject')"
        )
        guard case .consumed(let event) = result, case .buildPhase(let target, let phase) = event
        else {
            return XCTFail("Expected .consumed(.buildPhase), got \(result)")
        }
        XCTAssertEqual(target, "MyApp")
        XCTAssertEqual(phase, "CompileSwiftSources")
    }

    // MARK: - Executable

    func testExecutable() {
        var parser = LineParser()
        let result = parser.feed(
            "RegisterWithLaunchServices /path/to/MyApp.app (in target 'MyApp' from project 'MyProject')"
        )
        guard case .consumed(let event) = result, case .executable(let executable) = event else {
            return XCTFail("Expected .consumed(.executable), got \(result)")
        }
        XCTAssertEqual(executable.name, "MyApp.app")
        XCTAssertEqual(executable.target, "MyApp")
    }

    // MARK: - Crash detection

    func testCrashDetection() {
        var parser = LineParser()
        _ = parser.feed("Test Case '-[MyModule.MyTests testCrashing]' started.")
        _ = parser.feed("Exited with signal code 11")
        let result = parser.feed("Restarting after unexpected exit, crash, or test timeout in")
        guard case .consumed(let event) = result, case .testFailed(let failed) = event else {
            return XCTFail("Expected .consumed(.testFailed) on crash confirmation, got \(result)")
        }
        XCTAssert(failed.message.contains("signal 11"), "Expected signal code in message, got: \(failed.message)")
    }

    // MARK: - flush emits synthetic testFailed for in-flight test on TEST FAILED without crash confirmation

    func testFlushEmitsCrashForInFlightTestOnTestRunFailed() {
        var parser = LineParser()
        _ = parser.feed("Test Case '-[MyModule.MyTests testCrashing]' started.")
        _ = parser.feed("** TEST FAILED **")
        let events = parser.flush()
        let failedEvents = events.compactMap { event -> FailedTest? in
            if case .testFailed(let failed) = event { return failed }
            return nil
        }
        XCTAssertEqual(failedEvents.count, 1)
        XCTAssertEqual(failedEvents[0].test, "-[MyModule.MyTests testCrashing]")
        XCTAssertEqual(failedEvents[0].message, "Test did not complete (possible crash or timeout)")
    }

    // MARK: - No phantom testFailed after last test passes then TEST FAILED fires (issue #52 variant)

    func testNoPhantomFailureAfterPassedLastTest() {
        var parser = LineParser()
        _ = parser.feed("Test Case '-[MyModule.MyTests testLast]' started.")
        _ = parser.feed("Test Case '-[MyModule.MyTests testLast]' passed (0.001 seconds).")
        _ = parser.feed("** TEST FAILED **")
        let events = parser.flush()
        let failed = events.compactMap { event -> FailedTest? in
            if case .testFailed(let f) = event { return f }
            return nil
        }
        XCTAssertTrue(
            failed.isEmpty,
            "Expected no phantom testFailed, got: \(failed.map(\.test))"
        )
    }

    // MARK: - Consecutive recordedIssue lines do not drop the second event

    func testConsecutiveRecordedIssueLines() {
        var parser = LineParser()
        let issue1 = "✘ Test \"testA()\" recorded an issue at Foo.swift:10:1: Expectation failed"
        let issue2 = "✘ Test \"testB()\" recorded an issue at Bar.swift:20:1: Expectation failed"

        let r1 = parser.feed(issue1)
        XCTAssertEqual(r1, .buffering)

        // issue2 is an unrelated line — buffer should flush issue1, queue issue2
        let r2 = parser.feed(issue2)
        guard case .consumed(let e2) = r2, case .testFailed(let t2) = e2 else {
            return XCTFail("Expected .consumed(.testFailed) for issue1, got \(r2)")
        }
        XCTAssert(t2.test.contains("testA"), "Expected testA from flushed buffer, got: \(t2.test)")

        // issue2 is now buffered — feed an unrelated line to flush it
        let r3 = parser.feed("note: unrelated")
        guard case .consumed(let e3) = r3, case .testFailed(let t3) = e3 else {
            return XCTFail("Expected .consumed(.testFailed) for issue2, got \(r3)")
        }
        XCTAssert(t3.test.contains("testB"), "Expected testB from flushed buffer, got: \(t3.test)")
    }

    // MARK: - Regression: OutputParser still produces same results

    func testOutputParserRegression() throws {
        let fixtureURL = Bundle.module.url(forResource: "build", withExtension: "txt")!
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)
        let result = OutputParser().parse(input: input)
        // The fixture is a successful build — basic sanity
        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
    }
}

// MARK: - Equatable conformances for test assertions

extension BuildError: Equatable {
    public static func == (lhs: BuildError, rhs: BuildError) -> Bool {
        lhs.file == rhs.file && lhs.line == rhs.line && lhs.message == rhs.message
            && lhs.column == rhs.column
    }
}

extension BuildWarning: Equatable {
    public static func == (lhs: BuildWarning, rhs: BuildWarning) -> Bool {
        lhs.file == rhs.file && lhs.line == rhs.line && lhs.message == rhs.message
            && lhs.type == rhs.type
    }
}

extension FailedTest: Equatable {
    public static func == (lhs: FailedTest, rhs: FailedTest) -> Bool {
        lhs.test == rhs.test && lhs.message == rhs.message && lhs.file == rhs.file
            && lhs.line == rhs.line && lhs.duration == rhs.duration
    }
}

extension LinkerError: Equatable {
    public static func == (lhs: LinkerError, rhs: LinkerError) -> Bool {
        lhs.symbol == rhs.symbol && lhs.architecture == rhs.architecture
            && lhs.referencedFrom == rhs.referencedFrom && lhs.message == rhs.message
            && lhs.conflictingFiles == rhs.conflictingFiles
    }
}

extension Executable: Equatable {
    public static func == (lhs: Executable, rhs: Executable) -> Bool {
        lhs.path == rhs.path && lhs.name == rhs.name && lhs.target == rhs.target
    }
}

extension ParseEvent: Equatable {
    public static func == (lhs: ParseEvent, rhs: ParseEvent) -> Bool {
        switch (lhs, rhs) {
        case (.error(let lhsVal), .error(let rhsVal)): return lhsVal == rhsVal
        case (.warning(let lhsVal), .warning(let rhsVal)): return lhsVal == rhsVal
        case (.linkerError(let lhsVal), .linkerError(let rhsVal)): return lhsVal == rhsVal
        case (.testStarted(let lhsVal), .testStarted(let rhsVal)): return lhsVal == rhsVal
        case (.testPassed(let an, let ad), .testPassed(let bn, let bd)): return an == bn && ad == bd
        case (.testFailed(let lhsVal), .testFailed(let rhsVal)): return lhsVal == rhsVal
        case (.testSuiteCompleted(let an, let ae, let af, let ad), .testSuiteCompleted(let bn, let be, let bf, let bd)):
            return an == bn && ae == be && af == bf && ad == bd
        case (.swiftTestingCompleted(let ae, let af, let ad), .swiftTestingCompleted(let be, let bf, let bd)):
            return ae == be && af == bf && ad == bd
        case (.parallelTestScheduled(let ai, let at), .parallelTestScheduled(let bi, let bt)):
            return ai == bi && at == bt
        case (.buildTime(let lhsVal), .buildTime(let rhsVal)): return lhsVal == rhsVal
        case (.testRunFailed, .testRunFailed): return true
        case (.buildPhase(let at, let ap), .buildPhase(let bt, let bp)): return at == bt && ap == bp
        case (.targetCompleted(let an, let ad), .targetCompleted(let bn, let bd)): return an == bn && ad == bd
        case (.targetDependency(let at, let ad), .targetDependency(let bt, let bd)): return at == bt && ad == bd
        case (.targetDiscovered(let lhsVal), .targetDiscovered(let rhsVal)): return lhsVal == rhsVal
        case (.executable(let lhsVal), .executable(let rhsVal)): return lhsVal == rhsVal
        default: return false
        }
    }
}

extension LineResult: Equatable {
    public static func == (lhs: LineResult, rhs: LineResult) -> Bool {
        switch (lhs, rhs) {
        case (.buffering, .buffering): return true
        case (.ignored, .ignored): return true
        case (.consumed(let lhsVal), .consumed(let rhsVal)): return lhsVal == rhsVal
        default: return false
        }
    }
}
