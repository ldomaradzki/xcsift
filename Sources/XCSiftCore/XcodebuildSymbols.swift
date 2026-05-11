// MARK: - xcodebuild/SPM Parsing Constants

/// String constants for raw xcodebuild and SPM output patterns.
/// Extracted from inline literals to reduce duplication and improve discoverability.
enum XcodebuildSymbols {
    // Diagnostic format patterns (used in parseError/parseWarning)
    static let errorFormat = ": error: "
    static let warningFormat = ": warning: "
    static let fatalErrorFormat = ": Fatal error: "
    static let fatalErrorSuffix = ": Fatal error"

    // Fast-path filter keywords
    static let errorKeyword = "error:"
    static let warningKeyword = "warning:"
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
    static let testSuitePrefix = "Test Suite '"
    static let testSuiteLowerPrefix = "Test suite '"
    static let testSuiteStartedSuffix = "' started"
    static let testSuitePassedMarker = " passed"
    static let testSuiteFailedMarker = " failed"
    static let selectedTestsSuite = "Selected tests"

    // Swift Testing symbols (macOS Private Use Area + Linux fallback)
    static let swiftTestingPass = "✓"
    static let swiftTestingFail = "✘"
    static let emojiError = "❌"

    // Build status
    static let buildSucceeded = "** BUILD SUCCEEDED **"
    static let buildFailed = "** BUILD FAILED **"
    static let buildFailedKeyword = "BUILD FAILED"
    static let testFailed = "TEST FAILED"
    static let buildComplete = "Build complete!"
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
