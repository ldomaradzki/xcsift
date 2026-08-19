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
