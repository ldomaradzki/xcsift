import XCTest

import XCSiftCore

/// Tests for build commands that fail without an error of their own.
///
/// Xcode reports any build command that exits non-zero as
/// `Command <Name> failed with a nonzero exit code`. A compiler has printed `error:` lines by then,
/// but CodeSign, a validation step or a compiler that crashed may not have — that line, and the
/// tool output just above it, is then the only record of why the build failed.
final class FailedCommandTests: XCTestCase {
    private let appex =
        "/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/App/"
        + "InstallationBuildProductsLocation/Applications/App.app/PlugIns/Stickers.appex"

    private let codeSignFailed = "Command CodeSign failed with a nonzero exit code"

    /// A real archive log's shape: no `error:` line anywhere.
    private var codeSignArchiveFailure: String {
        """
        CodeSign \(appex) (in target 'Stickers' from project 'App')
            cd /src/App

            Signing Identity:     "Apple Development: Example Developer (TEAMID1234)"

            /usr/bin/codesign --force --sign ABCDEF --timestamp\\=none --generate-entitlement-der \(appex)
        \(appex): errSecInternalComponent
        Command CodeSign failed with a nonzero exit code

        ** ARCHIVE FAILED **


        The following build commands failed:
        \tCodeSign \(appex) (in target 'Stickers' from project 'App')
        \tArchiving workspace App with scheme App
        (2 failures)
        """
    }

    private func codeSignTask(_ product: String) -> String {
        """
        CodeSign \(product) (in target 'App' from project 'App')
            cd /src/App
            /usr/bin/codesign --force --sign ABCDEF \(product)
        \(product): errSecInternalComponent
        Command CodeSign failed with a nonzero exit code
        """
    }

    // MARK: - The reason

    func testCodeSignFailureIsReportedWithTheToolsOwnReason() {
        let result = OutputParser().parse(input: codeSignArchiveFailure)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errors.map(\.message), ["\(appex): errSecInternalComponent \(codeSignFailed)"])
        XCTAssertNil(result.errors.first?.file)
    }

    /// The invocation Xcode echoes under the task header is indented deeper than the failure line;
    /// it is not the tool's output and stops the search for it.
    func testTheEchoedInvocationIsNotPartOfTheReason() {
        let input = """
            ValidateEmbeddedBinary /p/App.app/PlugIns/Widget.appex (in target 'App' from project 'App')
                cd /src/App
                /Applications/Xcode.app/Contents/Developer/usr/bin/embeddedBinaryValidationUtility /p/Widget.appex
            Command ValidateEmbeddedBinary failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["Command ValidateEmbeddedBinary failed with a nonzero exit code"])
    }

    /// The task header belongs to the task, not to what its tool printed.
    func testTheTaskHeaderIsNotPartOfTheReason() {
        let input = """
            CodeSign /p/App.app (in target 'App' from project 'App')
            /p/App.app: errSecInternalComponent
            Command CodeSign failed with a nonzero exit code
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["/p/App.app: errSecInternalComponent \(codeSignFailed)"])
    }

    /// The reason is at most the three lines before the failure; blank lines take no slot.
    func testTheReasonIsAtMostThreeLines() {
        let input = """
            one
            two

            three

            four
            Command CodeSign failed with a nonzero exit code
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["two three four \(codeSignFailed)"])
    }

    /// A compiler that crashed printed a backtrace, not an `error:` line. Its frames say nothing
    /// about why, so the failure is reported on its own rather than as three hex addresses.
    func testACrashedCompilerIsReportedWithoutItsBacktrace() {
        let input = """
            Stack dump:
            0.\tProgram arguments: /usr/bin/swift-frontend -frontend -c /src/App/Model.swift
            Stack dump without symbol names (ensure you have llvm-symbolizer in your PATH):
            0  swift-frontend           0x0000000104c8e3e8 llvm::sys::PrintStackTrace(llvm::raw_ostream&, int) + 56
            1  swift-frontend           0x0000000104c8c63c llvm::sys::RunSignalHandlers() + 112
            2  libsystem_platform.dylib 0x000000018f2a2de4 _sigtramp + 56
            Command SwiftCompile failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["Command SwiftCompile failed with a nonzero exit code"])
    }

    /// A compiler warning directly above the failure is reported as a warning, not as its reason.
    func testACompilerWarningIsNotTakenForTheReason() {
        let input = """
            /src/App/Model.swift:3:9: warning: variable 'x' was never mutated
            Command SwiftCompile failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input, printWarnings: true)

        XCTAssertEqual(result.errors.map(\.message), ["Command SwiftCompile failed with a nonzero exit code"])
        XCTAssertEqual(result.summary.warnings, 1)
    }

    /// xcodebuild's own log lines and an earlier phase's terminal marker are not the tool's output.
    func testXcodebuildsOwnLinesAreNotTheReason() {
        let input = """
            ** BUILD SUCCEEDED **
            /p/App.app: errSecInternalComponent
            2026-09-29 10:00:00.000 xcodebuild[123:456] Writing error result bundle to /tmp/R.xcresult
            Command CodeSign failed with a nonzero exit code
            ** ARCHIVE FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["/p/App.app: errSecInternalComponent \(codeSignFailed)"])
    }

    /// `OutputParser` hands every line to the parser, however long; one too long to parse is not
    /// glued whole into the message.
    func testAnOverlongLineIsNotTheReason() {
        let input = String(repeating: "x", count: LineParser.maximumLineBytes + 1) + "\n" + codeSignFailed

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), [codeSignFailed])
    }

    /// Xcode's console transcript indents a task under a heading; the reason is read the same
    /// way at the failure line's own depth. This shape is modelled, not taken from a real log.
    func testAnIndentedTaskKeepsTheReasonAndDropsTheInvocation() {
        let input = """
              CodeSign /p/App.app (in target 'App' from project 'App')
                  /usr/bin/codesign --force --sign ABCDEF /p/App.app
              /p/App.app: errSecInternalComponent
              Command CodeSign failed with a nonzero exit code
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["/p/App.app: errSecInternalComponent \(codeSignFailed)"])
    }

    func testCRLFInputGivesTheSameMessage() {
        let input = codeSignArchiveFailure.replacingOccurrences(of: "\n", with: "\r\n")

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errors.map(\.message), ["\(appex): errSecInternalComponent \(codeSignFailed)"])
    }

    // MARK: - Which failures are reported

    /// A compiler that failed has said why already; its `Command SwiftCompile failed` line would
    /// only restate it.
    func testAFailedCompilerCommandIsNotRestated() {
        let input = """
            SwiftCompile normal arm64 /src/App/Model.swift (in target 'App' from project 'App')
                cd /src/App
            /src/App/Model.swift:3:9: error: cannot find 'undefined' in scope
            Command SwiftCompile failed with a nonzero exit code
            ** BUILD FAILED **

            The following build commands failed:
            \tSwiftCompile normal arm64 /src/App/Model.swift (in target 'App' from project 'App')
            (1 failure)
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["cannot find 'undefined' in scope"])
    }

    /// The linker's own errors explain `Command Ld failed`.
    func testAFailedLinkIsExplainedByItsLinkerErrors() {
        let input = """
            Ld /p/App.app/App normal (in target 'App' from project 'App')
            Undefined symbols for architecture arm64:
              "_OBJC_CLASS_$_SomeClass", referenced from:
                  objc-class-ref in ViewController.o
            ld: symbol(s) not found for architecture arm64
            Command Ld failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.linkerErrors, 1)
    }

    /// An error explains its own task only: a signing failure in the next task is reported too,
    /// rather than after the compile error is fixed.
    func testAnErrorInOneTaskDoesNotHideAFailureInAnother() {
        let input = """
            SwiftCompile normal arm64 /src/App/Model.swift (in target 'App' from project 'App')
            /src/App/Model.swift:3:9: error: cannot find 'undefined' in scope
            Command SwiftCompile failed with a nonzero exit code

            \(codeSignTask("/p/App.app/PlugIns/Widget.appex"))

            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(
            result.errors.map(\.message),
            [
                "cannot find 'undefined' in scope",
                "/p/App.app/PlugIns/Widget.appex: errSecInternalComponent \(codeSignFailed)",
            ]
        )
    }

    /// A failed script phase ends its task like any other failure.
    func testAScriptPhaseFailureDoesNotHideAFailureInAnother() {
        let input = """
            /src/Lint/run.sh: line 3: swiftlint: command not found
            Command PhaseScriptExecution failed with a nonzero exit code

            \(codeSignTask("/p/App.app/PlugIns/Widget.appex"))
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 2)
    }

    /// Two tasks failing alike are two failures, even when neither printed anything.
    func testTwoTasksFailingAlikeAreTwoFailures() {
        let input = """
            ValidateEmbeddedBinary /p/A.appex (in target 'App' from project 'App')
                cd /src/App
            Command ValidateEmbeddedBinary failed with a nonzero exit code
            ValidateEmbeddedBinary /p/B.appex (in target 'App' from project 'App')
                cd /src/App
            Command ValidateEmbeddedBinary failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 2)
    }

    /// Script phase failures are reported as errors in their own right, next to other errors.
    func testScriptPhaseFailureIsAnErrorInItsOwnRight() {
        let input = """
            /src/App/Model.swift:3:9: error: cannot find 'undefined' in scope
            The path lib/main.dart does not exist
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 2)
    }

    /// `--Werror` turns warnings into errors; it must not hide the failure they did not cause.
    func testWarningsAsErrorsKeepsTheFailedCommand() {
        let input = """
            /src/App/Model.swift:3:9: warning: variable 'x' was never mutated
            /p/App.app: errSecInternalComponent
            Command CodeSign failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input, warningsAsErrors: true)

        XCTAssertEqual(result.summary.errors, 2)
        XCTAssertTrue(result.errors.contains { $0.message.contains(codeSignFailed) })
    }

    // MARK: - `Testing failed:` restatements

    /// `xcodebuild test` restates the failure that stopped it under `Testing failed:`.
    func testATestingFailedRestatementIsNotASecondFailure() {
        let input = """
            \(codeSignTask("/p/AppTests.xctest"))

            Testing failed:
            \tCommand CodeSign failed with a nonzero exit code
            \tTesting cancelled because the build failed.

            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), ["/p/AppTests.xctest: errSecInternalComponent \(codeSignFailed)"])
    }

    func testTwoRestatedFailuresStayTwo() {
        let input = """
            \(codeSignTask("/p/A.appex"))
            \(codeSignTask("/p/B.appex"))

            Testing failed:
            \tCommand CodeSign failed with a nonzero exit code
            \tCommand CodeSign failed with a nonzero exit code
            \tTesting cancelled because the build failed.

            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(
            result.errors.map(\.message),
            [
                "/p/A.appex: errSecInternalComponent \(codeSignFailed)",
                "/p/B.appex: errSecInternalComponent \(codeSignFailed)",
            ]
        )
    }

    /// A script phase failure is restated the same way, and is one error too.
    func testARestatedScriptPhaseFailureIsNotASecondError() {
        let input = """
            The path lib/main.dart does not exist
            Command PhaseScriptExecution failed with a nonzero exit code

            Testing failed:
            \tCommand PhaseScriptExecution failed with a nonzero exit code
            \tTesting cancelled because the build failed.

            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 1)
    }

    /// When the summary is all the log has, it is the only record of the failure.
    func testARestatementIsReportedWhenItIsTheOnlyRecord() {
        let input = """
            Testing failed:
            \tCommand CodeSign failed with a nonzero exit code
            \tTesting cancelled because the build failed.

            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.errors.map(\.message), [codeSignFailed])
    }

    // MARK: - Success markers

    /// A success marker vouches for the failures before it: a nested tool whose failure a script
    /// tolerated did not fail the build.
    func testASuccessMarkerVouchesForAnEarlierFailure() {
        let input = """
            Command CodeSign failed with a nonzero exit code
            ** BUILD SUCCEEDED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
    }

    /// `xcodebuild clean test`: the clean succeeded, the build that followed did not.
    func testAnEarlierPhasesSuccessDoesNotVouchForALaterFailure() {
        let input = """
            ** CLEAN SUCCEEDED **

            \(codeSignTask("/p/AppTests.xctest"))

            Testing failed:
            \tCommand CodeSign failed with a nonzero exit code
            \tTesting cancelled because the build failed.

            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.errors.map(\.message), ["/p/AppTests.xctest: errSecInternalComponent \(codeSignFailed)"])
    }

    /// A log cut off after the failure is failed, not incomplete — whatever succeeded before it.
    func testAFailedCommandFailsATruncatedLog() {
        for prefix in ["", "** CLEAN SUCCEEDED **\n"] {
            let input = prefix + codeSignTask("/p/App.app")

            let result = OutputParser().parse(input: input)

            XCTAssertEqual(result.status, "failed", "after \(prefix.debugDescription)")
            XCTAssertEqual(result.summary.errors, 1, "after \(prefix.debugDescription)")
        }
    }

    /// Passed tests outrank `** TEST FAILED **` (issue #52), because that marker is unreliable. A
    /// command that failed is not.
    func testAFailedCommandOutranksPassedTests() {
        let input = """
            Test Case '-[AppTests.A testExample]' passed (0.001 seconds).
            Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
            Command ExtractAppIntentsMetadata failed with a nonzero exit code
            ** TEST FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(
            result.errors.map(\.message),
            ["Command ExtractAppIntentsMetadata failed with a nonzero exit code"]
        )
    }

    // MARK: - The shape of the line

    /// Xcode names a command by its rule, which can be several words.
    func testAMultiWordRuleNameIsAFailedCommand() {
        let input = """
            Command SwiftDriver Compilation Requirements failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(
            result.errors.map(\.message),
            ["Command SwiftDriver Compilation Requirements failed with a nonzero exit code"]
        )
    }

    /// Lines that start like the failure but are something else stay out.
    func testOnlyTheExactShapeIsAFailedCommand() {
        let input = """
            Command failed: npm install exited 1 failed with a nonzero exit code
            Command line invocation failed with a nonzero exit code
            Command  failed with a nonzero exit code
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "incomplete")
        XCTAssertEqual(result.summary.errors, 0)
    }

    // MARK: - LineParser

    private func events(_ lines: [String]) -> [ParseEvent] {
        var parser = LineParser()
        var events: [ParseEvent] = []
        for line in lines {
            if case .consumed(let event) = parser.feed(line) { events.append(event) }
        }
        return events + parser.flush()
    }

    private func failedCommands(in events: [ParseEvent]) -> [String] {
        events.compactMap { event in
            guard case .commandFailed(let failure) = event else { return nil }
            return failure.message
        }
    }

    /// The event itself says the task reported no error: a consumer of `LineParser` needs no
    /// look-ahead to know it is news.
    func testLineParserEmitsTheEventOnlyForAFailureItsTaskDidNotExplain() {
        let events = events([
            "/src/App/Model.swift:3:9: error: cannot find 'undefined' in scope",
            "Command SwiftCompile failed with a nonzero exit code",
            "CodeSign /p/App.app (in target 'App' from project 'App')",
            "    /usr/bin/codesign --force --sign ABCDEF /p/App.app",
            "/p/App.app: errSecInternalComponent",
            codeSignFailed,
        ])

        XCTAssertEqual(failedCommands(in: events), ["/p/App.app: errSecInternalComponent \(codeSignFailed)"])
    }

    /// A failure line fed while an earlier event is still queued is read against the lines before
    /// it, not against itself.
    func testAFailureDeliveredFromTheQueueHasItsReason() {
        var parser = LineParser()
        _ = parser.feed("/p/App.app: errSecInternalComponent")
        _ = parser.feed("✘ Test \"example()\" recorded an issue at AppTests.swift:10:1: Expectation failed")
        // Flushes the recorded issue and queues this line's warning behind it.
        _ = parser.feed("/src/App/Model.swift:3:9: warning: variable 'x' was never mutated")

        // The queued warning comes out now; the failure line is processed and queued in turn.
        guard case .consumed(.warning) = parser.feed(codeSignFailed) else {
            return XCTFail("Expected the queued warning to be delivered with the failure line")
        }

        XCTAssertEqual(failedCommands(in: parser.flush()), ["/p/App.app: errSecInternalComponent \(codeSignFailed)"])
    }

    /// An error with no failure line of its own — the build system's, say — does not explain the
    /// next task's failure: that task's header starts it afresh.
    func testATaskHeaderStartsANewTask() {
        let events = events([
            "error: Multiple commands produce '/p/App.app/Info.plist'",
            "CodeSign /p/App.app (in target 'App' from project 'App')",
            "/p/App.app: errSecInternalComponent",
            codeSignFailed,
        ])

        XCTAssertEqual(failedCommands(in: events), ["/p/App.app: errSecInternalComponent \(codeSignFailed)"])
    }

    /// The event is attributed to the failure line, as a linker error is to its final line.
    func testTrackingLineParserAttributesTheEventToTheFailureLine() {
        var parser = TrackingLineParser()
        _ = parser.feed("/p/App.app: errSecInternalComponent")
        let (range, result) = parser.feed(codeSignFailed)

        guard case .consumed(.commandFailed) = result else {
            return XCTFail("Expected .consumed(.commandFailed), got \(result)")
        }
        XCTAssertEqual(range, 2 ... 2)
    }
}
