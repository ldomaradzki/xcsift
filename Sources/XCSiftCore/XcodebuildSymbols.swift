// MARK: - xcodebuild/SPM Parsing Constants

/// String constants for raw xcodebuild and SPM output patterns.
/// Extracted from inline literals to reduce duplication and improve discoverability.
enum XcodebuildSymbols {
    // Diagnostic format patterns (used in parseError/parseWarning)
    static let errorFormat = ": error: "
    static let warningFormat = ": warning: "
    static let noteFormat = ": note: "
    static let fatalErrorFormat = ": Fatal error: "
    static let fatalErrorSuffix = ": Fatal error"

    // Runtime log noise (os_log/NSLog output that embeds `: error:`/`: warning:` but is not a diagnostic)
    static let coreDataLogPrefix = "CoreData: "

    // Fast-path filter keywords
    static let errorKeyword = "error:"
    static let warningKeyword = "warning:"
    static let noteKeyword = "note:"
    static let fatalErrorKeyword = "Fatal error"
    static let passedKeyword = "passed"
    static let failedKeyword = "failed"
    static let startedSuffix = "' started"
    static let recordedIssue = "recorded an issue"
    static let signalCode = "signal code "
    static let restartingAfter = "Restarting after"

    // Test patterns
    static let testCasePrefix = "Test Case '"
    static let testCaseLowerPrefix = "Test case '"  // parallel testing format
    static let testPassedSuffix = "' passed ("
    static let testFailedSuffix = "' failed ("
    static let testPassedOnSuffix = "' passed on '"
    static let testFailedOnSuffix = "' failed on '"
    /// Xcode's console log restates a test failure as `<file>:test failure:<message>`, without the
    /// test's name — a rendering of a failure the transcript also reports in full elsewhere.
    static let testFailureRestatement = ":test failure:"
    /// Stands in for the test a failure could not be attributed to.
    static let unnamedTestFailure = "Test assertion"
    static let testSuitePrefix = "Test Suite '"
    static let testSuiteLowerPrefix = "Test suite '"
    static let testSuiteStartedSuffix = "' started"
    static let testSuitePassedMarker = " passed"
    static let testSuiteFailedMarker = " failed"

    // Swift Testing symbols (macOS Private Use Area + Linux fallback)
    static let swiftTestingPass = "✓"
    /// Xcode's own console transcript writes the heavy check, not the light one the terminal uses.
    static let swiftTestingPassHeavy = "✔"
    static let swiftTestingFail = "✘"
    static let swiftTestingStartedPrefix = "◇ Test "
    static let swiftTestingRunStarted = "◇ Test run started."
    static let emojiError = "❌"
    // U+100135 (macOS PUA) / U+21B3 (Linux) — carries #expect custom comment on the line after recorded-issue
    static let swiftTestingDetailsPrefix = "􀄵"
    static let swiftTestingDetailsPrefixFallback = "↳"

    // Build status — xcodebuild ends every operation with `** <PHASE> SUCCEEDED/FAILED **`
    // (BUILD, TEST, TEST EXECUTE, ARCHIVE, EXPORT, CLEAN, INSTALL, ANALYZE …)
    static let succeededMarkerSuffix = " SUCCEEDED **"
    static let failedMarkerSuffix = " FAILED **"
    // The two keywords below route a line to the status parser. They are wider than the two
    // markers above on purpose: the fast-path filter must not drop a line the parser still reads.
    static let succeededKeyword = "SUCCEEDED"
    static let failedUppercaseKeyword = "FAILED"
    static let testFailed = "TEST FAILED"
    static let testExecuteFailed = "TEST EXECUTE FAILED"
    static let buildComplete = "Build complete!"
    static let buildSucceededInPrefix = "Build succeeded in "
    static let buildFailedAfterPrefix = "Build failed after "
    static let secondsKeyword = " seconds"

    // File extensions
    static let swiftFilePattern = ".swift:"
    static let objectFileExt = ".o"
    static let archiveFileExt = ".a"
    static let appBundleExt = ".app"

    // Linker patterns
    static let undefinedSymbols = "Undefined symbols for architecture "
    static let referencedFrom = "\", referenced from:"
    static let frameworkNotFound = "ld: framework not found "
    static let libraryNotFound = "ld: library not found for "
    static let duplicateSymbolSingle = "duplicate symbol '"
    static let duplicateSymbolDouble = "duplicate symbol \""

    // Executable / target patterns
    static let registerWithLaunchServices = "RegisterWithLaunchServices"
    static let validate = "Validate"
    static let inTarget = "(in target '"

    // Dependency graph
    static let targetPrefix = "Target '"
    static let dependencyOnTarget = "dependency on target '"

    // SPM phases
    static let spmCompiling = "] Compiling "
    static let spmLinking = "] Linking "
}
