import XCTest

import XCSiftCore

/// Tests for build commands that fail without a diagnostic of their own.
///
/// Xcode reports any build command that exits non-zero as
/// `Command <Name> failed with a nonzero exit code`. A compiler has already printed `error:` lines
/// by then, but CodeSign, a validation step or a compiler that crashed has not — that line, and
/// the tool output just above it, is the only record of why the build failed.
final class FailedCommandTests: XCTestCase {
    private let appex =
        "/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/App/"
        + "InstallationBuildProductsLocation/Applications/App.app/PlugIns/Stickers.appex"

    /// The shape of the archive log that prompted this: no `error:` line anywhere.
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

    func testCodeSignFailureIsReportedWithTheToolsOwnReason() {
        let result = OutputParser().parse(input: codeSignArchiveFailure)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(
            result.errors.first?.message,
            "\(appex): errSecInternalComponent Command CodeSign failed with a nonzero exit code"
        )
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

    /// A compiler that failed has said why already; its `Command SwiftCompile failed` line would
    /// only restate it.
    func testAFailedCompilerCommandIsNotRestated() {
        let input = """
            /src/App/Model.swift:3:9: error: cannot find 'undefined' in scope
            Command SwiftCompile failed with a nonzero exit code
            ** BUILD FAILED **

            The following build commands failed:
            \tSwiftCompile normal arm64 /src/App/Model.swift (in target 'App' from project 'App')
            (1 failure)
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.map(\.message), ["cannot find 'undefined' in scope"])
    }

    /// A compiler that crashed printed a backtrace, not an `error:` line.
    func testACrashedCompilerIsReported() {
        let input = """
            Stack dump:
            0.\tProgram arguments: /usr/bin/swift-frontend -frontend -c /src/App/Model.swift
            Command SwiftCompile failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(
            result.errors.first?.message.hasSuffix("Command SwiftCompile failed with a nonzero exit code"),
            true
        )
    }

    /// A failed command is evidence of failure on its own, so a log cut off before the terminal
    /// marker is no longer reported as incomplete.
    func testAFailedCommandFailsATruncatedLog() {
        let input = """
            /p/App.app: resource fork, Finder information, or similar detritus not allowed
            Command CodeSign failed with a nonzero exit code
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
    }

    /// A build that says it succeeded had no failure to explain: a nested tool whose failure a
    /// script tolerated does not fail it.
    func testAFailedCommandDoesNotOverruleASuccessfulBuild() {
        let input = """
            Command CodeSign failed with a nonzero exit code
            ** BUILD SUCCEEDED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
    }

    /// Xcode's own console transcript indents everything under the task that emitted it.
    func testAnIndentedTranscriptKeepsTheReasonAndDropsTheInvocation() {
        let input = """
              CodeSign /p/App.app (in target 'App' from project 'App')
                  /usr/bin/codesign --force --sign ABCDEF /p/App.app
              /p/App.app: errSecInternalComponent
              Command CodeSign failed with a nonzero exit code
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(
            result.errors.map(\.message),
            ["/p/App.app: errSecInternalComponent Command CodeSign failed with a nonzero exit code"]
        )
    }

    func testCRLFInputIsRecognized() {
        let input = codeSignArchiveFailure.replacingOccurrences(of: "\n", with: "\r\n")

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors.first?.message.contains("errSecInternalComponent"), true)
    }

    /// Two products failing to sign are two failures; the same one restated is one.
    func testFailedCommandsAreDeduplicatedByMessage() {
        let input = """
            /p/A.appex: errSecInternalComponent
            Command CodeSign failed with a nonzero exit code
            /p/B.appex: errSecInternalComponent
            Command CodeSign failed with a nonzero exit code
            /p/B.appex: errSecInternalComponent
            Command CodeSign failed with a nonzero exit code
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
        XCTAssertTrue(result.errors.contains { $0.message.contains("Command CodeSign failed") })
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

    /// Script phase failures keep being reported as errors in their own right.
    func testScriptPhaseFailureIsUnchanged() {
        let input = """
            /src/App/Model.swift:3:9: error: cannot find 'undefined' in scope
            The path lib/main.dart does not exist
            Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD FAILED **
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.summary.errors, 2)
    }

    /// Lines that start like the failure but are something else stay out.
    func testOnlyTheExactShapeIsAFailedCommand() {
        let input = """
            Command failed: npm install exited 1 failed with a nonzero exit code
            Command line invocation failed with a nonzero exit code
            """

        let result = OutputParser().parse(input: input)

        XCTAssertEqual(result.status, "incomplete")
        XCTAssertEqual(result.summary.errors, 0)
    }
}
