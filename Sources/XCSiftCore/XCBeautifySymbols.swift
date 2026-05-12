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
}
