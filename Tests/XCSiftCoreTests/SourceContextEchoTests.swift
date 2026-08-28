import XCTest

import XCSiftCore

/// Tests for compiler source-context echo (issue #78).
///
/// A `file:line:col: error:/warning:/note:` header is followed by the offending source line,
/// indented, and a caret line. The echoed source can carry `: error: ` inside a string literal or
/// a comment. Those bytes are not a diagnostic. Indentation alone must not decide this: indented
/// tool output stands on its own and stays reportable.
final class SourceContextEchoTests: XCTestCase {
    func testEchoedSourceLineWithErrorTextDoesNotFailTheBuild() {
        let parser = OutputParser()
        let input = """
            /p/M.swift:8:19: warning: expression took 4ms to type-check (limit: 1ms)
                    let msg = "upload: error: " + String(1) + String(2)
                              ^~~~~~~~~~~~~~~~~
            Build complete!
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.warnings, 1)
    }

    func testEchoedSourceLineWithWarningTextIsNotAWarning() {
        let parser = OutputParser()
        let input = """
            /p/M.swift:8:19: error: cannot find 'bar' in scope
                    let msg = "upload: warning: " + bar()
                              ^~~~~~~~~~~~~~~~~~~
            ** BUILD FAILED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.summary.warnings, 0)
    }

    func testEchoedSourceLineUnderNoteHeaderIsNotADiagnostic() {
        let parser = OutputParser()
        let input = """
            /p/A.swift:36:39: warning: call to main actor-isolated initializer
                    dateProvider: DateProviding = LiveDateProvider(),
                                                  ^
            /p/B.swift:16:8: note: calls from outside the actor context are asynchronous
                init() { log("actor: error: none") }
                ^
            Build complete!
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.summary.errors, 0)
        XCTAssertEqual(result.summary.warnings, 1)
    }

    /// Indented tool output is not source context. Dropping it would report a broken build as a
    /// successful one.
    func testIndentedToolErrorStillFailsTheBuild() {
        let parser = OutputParser()
        let input = """
                swiftgen: error: template not found
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
    }

    func testIndentedScriptPhaseFailureStillFailsTheBuild() {
        let parser = OutputParser()
        let input = """
                Command PhaseScriptExecution failed with a nonzero exit code
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
    }

    /// The caret line ends the block, so the next indented line is tool output again.
    func testCaretLineClosesTheEchoBlock() {
        let parser = OutputParser()
        let input = """
            /p/M.swift:1:1: warning: expression took 4ms to type-check (limit: 1ms)
                    let msg = "upload: error: " + String(1)
                              ^~~~~~~~~~~~~~~~~
                swiftgen: error: template not found
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors[0].message, "template not found")
        XCTAssertEqual(result.summary.warnings, 1)
    }

    func testDiagnosticAfterAnEchoBlockIsStillParsed() {
        let parser = OutputParser()
        let input = """
            /p/M.swift:1:1: warning: expression took 4ms to type-check (limit: 1ms)
                    let msg = "upload: error: " + String(1)
                              ^~~~~~~~~~~~~~~~~
            /p/N.swift:9:5: error: cannot find 'bar' in scope
            ** BUILD FAILED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.errors, 1)
        XCTAssertEqual(result.errors[0].file, "/p/N.swift")
        XCTAssertEqual(result.errors[0].line, 9)
        XCTAssertEqual(result.summary.warnings, 1)
    }

    /// Tool output such as `swiftgen: error: …` carries no `:line:` location, so it must not open
    /// a block and hide the indented line that follows it.
    func testToolErrorDoesNotOpenAnEchoBlock() {
        let parser = OutputParser()
        let input = """
            swiftgen: error: template not found
                sourcery: error: could not parse the model
            ** BUILD SUCCEEDED **
            """

        let result = parser.parse(input: input)

        XCTAssertEqual(result.summary.errors, 2)
    }
}
