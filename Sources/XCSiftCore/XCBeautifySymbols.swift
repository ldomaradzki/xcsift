// MARK: - xcbeautify Parsing Constants

/// Markers used by xcbeautify (https://github.com/cpisciotta/xcbeautify) for formatted output.
/// Used by Tuist and other tools that wrap xcodebuild.
/// Source: https://github.com/cpisciotta/xcbeautify/blob/main/Sources/XcbeautifyLib/Constants.swift
enum XCBeautifySymbols {
    static let error = "❌"
    static let asciiError = "[x]"
    static let warning = "⚠️"
    static let asciiWarning = "[!]"
    static let pass = "✔"
    static let fail = "✖"
    static let pending = "⧖"
    static let completion = "▸"
    static let measure = "◷"
    static let skipped = "⊘"

    // Test result lines of the terminal renderer, each indented by `indent`:
    // `✔ <test> (<t> seconds)`, `✖ <test>, <reason>`, `✖ <test> (<t> seconds) <n> issue(s)`
    // (Swift Testing), and `✔ [<Suite>] <test> on '<device>' (<t> seconds)` (parallel testing).
    // The GitHub Actions renderer indents a failing XCTest test's message the same way.
    static let indent = "    "
    static let reasonSeparator = ", "
    static let durationOpen = " ("
    static let durationClose = " seconds)"
    static let issuesSuffix = " issue(s)"
    static let suiteOpen = "["
    static let suiteClose = "] "
    static let deviceInfix = " on '"
    // Earlier xcsift fixtures write `✔ <test> passed (<t> seconds)`.
    static let passedSuffix = " passed"
    static let failedSuffix = " failed"

    // GitHub Actions renderer (`--renderer github-actions`, which Tuist selects when `GITHUB_ACTIONS`
    // is set) writes diagnostics as workflow commands instead of `[x]` and `[!]`:
    // `::error file=<path>,line=<n>,col=<n>::<message>`, or `::error ::<message>` without a location.
    static let workflowError = "::error"
    static let workflowWarning = "::warning"
    static let workflowMessageSeparator = "::"
    static let workflowFileKey = "file="
    static let workflowLineKey = ",line="
    static let workflowColumnKey = ",col="

    // Terminal status line (xcbeautify rewrites `** <PHASE> SUCCEEDED **` to "<Phase> Succeeded").
    // The rewrite drops the `**` brackets, so the phase name is the only thing that separates a
    // marker from ordinary run-script output. Match the known phases, not the bare suffix.
    static let succeededSuffix = " Succeeded"
    static let succeededMarkers = [
        "Build Succeeded",
        "Build For Testing Succeeded",
        "Test Succeeded",
        "Test Execute Succeeded",
        "Test Without Building Succeeded",
        "Analyze Succeeded",
        "Analyze For Testing Succeeded",
        "Archive Succeeded",
        "Export Succeeded",
        "Clean Succeeded",
        "Install Succeeded",
        "Installsrc Succeeded",
        "Installhdrs Succeeded",
        "Installloc Succeeded",
        "Docbuild Succeeded",
    ]
}
