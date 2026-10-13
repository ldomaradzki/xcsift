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
    /// One line for each option that the user set and that has no effect now, for stderr.
    var deprecations: [String] = []
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
    ///   - cliToonKeyFolding: TOON key folding from CLI (nil if not explicitly set). It has no
    ///     effect on the output; it only decides whether ``ResolvedConfig/deprecations`` says so.
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

        // Key folding: CLI > config. The output is the same either way; the user is told when
        // they asked for the folded form. The flatten depth only ever limited folding.
        let toonKeyFolding = cliToonKeyFolding ?? config.toon?.keyFolding?.toTOONKeyFoldingType
        var deprecations: [String] = []
        if toonKeyFolding == .safe {
            deprecations.append(keyFoldingDeprecation)
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
                toonDelimiter: toonDelimiter
            ),
            quiet: quiet,
            exitOnFailure: exitOnFailure,
            deprecations: deprecations
        )
    }

    /// TOON specification 4.0 removed key folding, and folded output does not conform to 4.1. A
    /// consumer that follows the specification reads `build_info.targets` as one key, so xcsift
    /// always writes nested objects.
    static let keyFoldingDeprecation =
        "Warning: TOON key folding has no effect. TOON specification 4.0 removed it, so xcsift writes "
        + "nested objects. Remove --toon-key-folding and --toon-flatten-depth, or key_folding and "
        + "flatten_depth in the configuration file."

    /// Returns nil for empty strings, otherwise returns the string
    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}
