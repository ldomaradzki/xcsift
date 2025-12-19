import Foundation

// MARK: - Resolved Configuration

/// Resolved configuration after merging file config with CLI arguments.
/// All values are concrete (non-optional) after merge.
struct ResolvedConfig: Sendable {
    let format: FormatType
    let warnings: Bool
    let warningsAsErrors: Bool
    let quiet: Bool
    let coverage: Bool
    let coverageDetails: Bool
    let coveragePath: String?
    let slowThreshold: Double?
    let buildInfo: Bool
    let executable: Bool
    let toonDelimiter: TOONDelimiterType
    let toonKeyFolding: TOONKeyFoldingType
    let toonFlattenDepth: Int?
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
    ///   - cliToonDelimiter: TOON delimiter from CLI (nil if not explicitly set)
    ///   - cliToonKeyFolding: TOON key folding from CLI (nil if not explicitly set)
    ///   - cliToonFlattenDepth: TOON flatten depth from CLI (nil if not set)
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
        cliToonDelimiter: TOONDelimiterType?,
        cliToonKeyFolding: TOONKeyFoldingType?,
        cliToonFlattenDepth: Int?
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
            format: format,
            warnings: warnings,
            warningsAsErrors: warningsAsErrors,
            quiet: quiet,
            coverage: coverage,
            coverageDetails: coverageDetails,
            coveragePath: coveragePath,
            slowThreshold: slowThreshold,
            buildInfo: buildInfo,
            executable: executable,
            toonDelimiter: toonDelimiter,
            toonKeyFolding: toonKeyFolding,
            toonFlattenDepth: toonFlattenDepth
        )
    }

    /// Returns nil for empty strings, otherwise returns the string
    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}
