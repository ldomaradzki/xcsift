import Foundation

// MARK: - Resolved Configuration

/// Resolved configuration after merging file config with CLI arguments.
/// All values are concrete (non-optional) after merge.
/// What the parser needs: which findings to keep, and how to judge them. Every value here can
/// change what a build's output is found to *be*.
struct ParseConfig: Sendable {
    var warnings: Bool
    var warningsAsErrors: Bool
    var coverage: Bool
    var coverageDetails: Bool
    var coveragePath: String?
    var slowThreshold: Double?
    var buildInfo: Bool
    var executable: Bool
    var xcbeautify: Bool
}

/// What the renderer needs: the encoding, and the shape it takes. Nothing here can change what the
/// result says — which is why a renderer is handed this and not the rest.
struct RenderConfig: Sendable {
    var format: FormatType
    var toonDelimiter: TOONDelimiterType
    var toonKeyFolding: TOONKeyFoldingType
    var toonFlattenDepth: Int?
}

/// A resolved configuration: the two halves a result passes through, and what the pipeline then
/// does with it.
///
/// The halves are separate so that what a consumer is given says what it can do. The MCP proxy
/// takes both and never sees ``quiet`` or ``exitOnFailure`` — the two values documented as having
/// no meaning over MCP, now by construction rather than by promise.
///
/// `var` on purpose: the proxy overrides a few of these per tool call, and a hand-written
/// field-by-field copy would silently reset whatever is added here next.
struct ResolvedConfig: Sendable {
    var parse: ParseConfig
    var render: RenderConfig
    /// Suppress output when the build succeeded with nothing to report.
    var quiet: Bool
    /// Exit non-zero when the build did not succeed.
    var exitOnFailure: Bool
}

// MARK: - Config Merger

/// Merges configuration from file with CLI arguments.
/// CLI arguments take precedence over config file values.
enum ConfigMerger {

    /// Merges config file values with CLI arguments.
    /// - Parameters:
    ///   - config: Configuration from file (may be nil if no file found)
    ///   - cliFormat: Format from CLI (nil if not explicitly set)
    ///   - cliWarnings: Warnings flag from CLI
    ///   - cliWarningsAsErrors: Werror flag from CLI
    ///   - cliQuiet: Quiet flag from CLI
    ///   - cliCoverage: Coverage flag from CLI
    ///   - cliCoverageDetails: Coverage details flag from CLI
    ///   - cliCoveragePath: Coverage path from CLI (nil if not set)
    ///   - cliSlowThreshold: Slow threshold from CLI (nil if not set)
    ///   - cliBuildInfo: Build info flag from CLI
    ///   - cliExecutable: Executable flag from CLI
    ///   - cliExitOnFailure: Exit on failure flag from CLI
    ///   - cliToonDelimiter: TOON delimiter from CLI (nil if not explicitly set)
    ///   - cliToonKeyFolding: TOON key folding from CLI (nil if not explicitly set)
    ///   - cliToonFlattenDepth: TOON flatten depth from CLI (nil if not set)
    ///   - cliXcbeautify: xcbeautify input parsing flag from CLI
    /// - Returns: Resolved configuration with all values set
    static func merge(
        config: Configuration?,
        cliFormat: FormatType?,
        cliWarnings: Bool,
        cliWarningsAsErrors: Bool,
        cliQuiet: Bool,
        cliCoverage: Bool,
        cliCoverageDetails: Bool,
        cliCoveragePath: String?,
        cliSlowThreshold: Double?,
        cliBuildInfo: Bool,
        cliExecutable: Bool,
        cliExitOnFailure: Bool,
        cliToonDelimiter: TOONDelimiterType?,
        cliToonKeyFolding: TOONKeyFoldingType?,
        cliToonFlattenDepth: Int?,
        cliXcbeautify: Bool = false
    ) -> ResolvedConfig {

        let config = config ?? Configuration()

        // Format: CLI > config > default (json)
        let format: FormatType
        if let cliFormat = cliFormat {
            format = cliFormat
        } else if let configFormat = config.format {
            format = configFormat.toFormatType
        } else {
            format = .json
        }

        // Boolean flags: CLI true overrides config; if CLI is false, use config or default false
        // This means: if user passes --warnings on CLI, it's true regardless of config
        // If user doesn't pass --warnings, use config value or default false
        let warnings = cliWarnings || (config.warnings ?? false)
        let warningsAsErrors = cliWarningsAsErrors || (config.werror ?? false)
        let quiet = cliQuiet || (config.quiet ?? false)
        let coverage = cliCoverage || (config.coverage ?? false)
        let coverageDetails = cliCoverageDetails || (config.coverageDetails ?? false)
        let buildInfo = cliBuildInfo || (config.buildInfo ?? false)
        let executable = cliExecutable || (config.executable ?? false)
        let exitOnFailure = cliExitOnFailure || (config.exitOnFailure ?? false)
        let xcbeautify = cliXcbeautify || (config.xcbeautify ?? false)

        // Optional string/numeric values: CLI > config > nil
        let coveragePath = cliCoveragePath ?? nonEmptyString(config.coveragePath)
        let slowThreshold = cliSlowThreshold ?? config.slowThreshold

        // TOON options: CLI > config > default
        let toonDelimiter: TOONDelimiterType
        if let cliDelimiter = cliToonDelimiter {
            toonDelimiter = cliDelimiter
        } else if let configDelimiter = config.toon?.delimiter {
            toonDelimiter = configDelimiter.toTOONDelimiterType
        } else {
            toonDelimiter = .comma
        }

        let toonKeyFolding: TOONKeyFoldingType
        if let cliKeyFolding = cliToonKeyFolding {
            toonKeyFolding = cliKeyFolding
        } else if let configKeyFolding = config.toon?.keyFolding {
            toonKeyFolding = configKeyFolding.toTOONKeyFoldingType
        } else {
            toonKeyFolding = .disabled
        }

        let toonFlattenDepth: Int?
        if let cliDepth = cliToonFlattenDepth {
            toonFlattenDepth = cliDepth
        } else if let configDepth = config.toon?.flattenDepth, configDepth > 0 {
            toonFlattenDepth = configDepth
        } else {
            toonFlattenDepth = nil
        }

        return ResolvedConfig(
            parse: ParseConfig(
                warnings: warnings,
                warningsAsErrors: warningsAsErrors,
                coverage: coverage,
                coverageDetails: coverageDetails,
                coveragePath: coveragePath,
                slowThreshold: slowThreshold,
                buildInfo: buildInfo,
                executable: executable,
                xcbeautify: xcbeautify
            ),
            render: RenderConfig(
                format: format,
                toonDelimiter: toonDelimiter,
                toonKeyFolding: toonKeyFolding,
                toonFlattenDepth: toonFlattenDepth
            ),
            quiet: quiet,
            exitOnFailure: exitOnFailure
        )
    }

    /// Returns nil for empty strings, otherwise returns the string
    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}
