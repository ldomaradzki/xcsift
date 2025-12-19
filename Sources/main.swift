import ArgumentParser
import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif
import ToonFormat

// MARK: - Stderr Helper

/// Thread-safe wrapper for writing to stderr
private func writeToStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

// MARK: - Format Types

enum FormatType: String, ExpressibleByArgument {
    case json
    case toon
    case githubActions = "github-actions"
}

enum TOONDelimiterType: String, ExpressibleByArgument {
    case comma
    case tab
    case pipe

    var toonDelimiter: TOONEncoder.Delimiter {
        switch self {
        case .comma: return .comma
        case .tab: return .tab
        case .pipe: return .pipe
        }
    }
}

enum TOONKeyFoldingType: String, ExpressibleByArgument {
    case disabled
    case safe

    var toonKeyFolding: TOONEncoder.KeyFolding {
        switch self {
        case .disabled: return .disabled
        case .safe: return .safe
        }
    }
}

func getVersion() -> String {
    // Try to get version from git tag during build
    #if DEBUG
        return "dev"
    #else
        return "VERSION_PLACEHOLDER"  // This will be replaced by build script
    #endif
}

struct XCSift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcsift",
        abstract: "A Swift tool to parse and format xcodebuild output for coding agents",
        usage:
            "xcodebuild [options] 2>&1 | xcsift [--format|-f json|toon|github-actions] [--warnings|-w] [--Werror|-W] [--quiet|-q] [--coverage|-c] [--executable|-e] [--config PATH] [--init] [--version|-v] [--help|-h]",
        discussion: """
            xcsift parses xcodebuild/SPM output and formats it as JSON, TOON, or GitHub Actions.

            Important: Always use 2>&1 to redirect stderr to stdout.

            Basic examples:
              xcodebuild build 2>&1 | xcsift
              xcodebuild test 2>&1 | xcsift -w
              swift build 2>&1 | xcsift --warnings
              swift test 2>&1 | xcsift
              swift build 2>&1 | xcsift --quiet
              swift build 2>&1 | xcsift --Werror
              swift test --enable-code-coverage 2>&1 | xcsift --coverage
              xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage
              xcsift -c --coverage-path .build/debug/codecov

            Executable targets:
              xcodebuild build 2>&1 | xcsift --executable
              xcodebuild build 2>&1 | xcsift -e

            Slow/flaky test detection:
              swift test 2>&1 | xcsift --slow-threshold 1.0
              xcodebuild test 2>&1 | xcsift --slow-threshold 0.5

            Build info (per-target phases, timing, dependencies):
              xcodebuild build 2>&1 | xcsift --build-info
              swift build 2>&1 | xcsift --build-info

            TOON format (30-60% fewer tokens for LLMs):
              xcodebuild build 2>&1 | xcsift -f toon
              swift test 2>&1 | xcsift -f toon -w -c

            GitHub Actions (auto-appended on CI):
              On CI, JSON/TOON output is followed by GitHub Actions annotations.
              Use -f github-actions for annotations only (no JSON/TOON).

            Configuration file:
              xcsift --init                      # Generate .xcsift.toml template
              xcsift --config ~/my-config.toml  # Use custom config file

              Config files are searched in order:
              1. .xcsift.toml in current directory
              2. ~/.config/xcsift/config.toml

              CLI flags override config file values.

            Configuration options:
              --toon-delimiter [comma|tab|pipe]  # Default: comma
              --toon-key-folding [disabled|safe] # Default: disabled
              --toon-flatten-depth N             # Default: unlimited
              --slow-threshold N                 # Slow test threshold in seconds
              --build-info                       # Per-target phases and timing
            """,
        helpNames: [.short, .long]
    )

    @Flag(name: [.short, .long], help: "Show version information")
    var version: Bool = false

    @Flag(name: .long, help: "Generate example configuration file (.xcsift.toml) in current directory")
    var `init`: Bool = false

    @Option(name: .long, help: "Path to configuration file (default: auto-detect .xcsift.toml)")
    var config: String?

    @Flag(name: [.short, .long], help: "Print detailed warnings list (by default only warning count is shown)")
    var warnings: Bool = false

    @Flag(
        name: [.customShort("W"), .customLong("Werror")],
        help: "Treat warnings as errors (build fails if warnings present)"
    )
    var warningsAsErrors: Bool = false

    @Flag(name: [.short, .long], help: "Suppress output when build succeeds with no warnings or errors")
    var quiet: Bool = false

    @Flag(name: [.short, .long], help: "Include code coverage data (auto-converts .profraw files)")
    var coverage: Bool = false

    @Option(name: .long, help: "Path to code coverage directory or JSON file (default: auto-detect in .build/)")
    var coveragePath: String?

    @Flag(name: .long, help: "Include detailed per-file coverage data (default: summary only)")
    var coverageDetails: Bool = false

    @Flag(name: [.short, .long], help: "Include executable targets generated by the build")
    var executable: Bool = false

    @Flag(name: .long, help: "Include per-target build phases and timing")
    var buildInfo: Bool = false

    @Option(
        name: [.customShort("f"), .long],
        help: "Output format (json, toon, or github-actions). Default: json. On CI, annotations are auto-appended."
    )
    var format: FormatType?

    /// Detects if running in GitHub Actions CI environment
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
    }

    @Option(name: .long, help: "TOON delimiter (comma, tab, or pipe). Default: comma")
    var toonDelimiter: TOONDelimiterType?

    @Option(
        name: .long,
        help:
            "TOON key folding (disabled or safe). Default: disabled. When safe, nested single-key objects collapse to dotted paths"
    )
    var toonKeyFolding: TOONKeyFoldingType?

    @Option(name: .long, help: "TOON flatten depth limit for key folding. Default: unlimited")
    var toonFlattenDepth: Int?

    @Option(
        name: .long,
        help: "Threshold in seconds for slow test detection (e.g., 1.0). Tests exceeding this are marked as slow."
    )
    var slowThreshold: Double?

    func run() throws {
        // Handle --version
        if version {
            print(getVersion())
            return
        }

        // Handle --init
        if `init` {
            try generateConfigFile()
            return
        }

        // Load and merge configuration
        let configLoader = ConfigLoader()
        let fileConfig: Configuration?

        do {
            fileConfig = try configLoader.loadConfig(explicitPath: config)
        } catch let error as ConfigError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }

        // Merge config file with CLI args
        let resolved = ConfigMerger.merge(
            config: fileConfig,
            cliFormat: format,
            cliWarnings: warnings,
            cliWarningsAsErrors: warningsAsErrors,
            cliQuiet: quiet,
            cliCoverage: coverage,
            cliCoverageDetails: coverageDetails,
            cliCoveragePath: coveragePath,
            cliSlowThreshold: slowThreshold,
            cliBuildInfo: buildInfo,
            cliExecutable: executable,
            cliToonDelimiter: toonDelimiter,
            cliToonKeyFolding: toonKeyFolding,
            cliToonFlattenDepth: toonFlattenDepth
        )

        // Check if stdin is a terminal (no piped input) before trying to read
        if isatty(STDIN_FILENO) == 1 {
            throw ValidationError(
                "No input provided. Please pipe xcodebuild output to xcsift.\n\nExample: xcodebuild build | xcsift"
            )
        }

        let parser = OutputParser()
        let input = readStandardInput()

        // Check if input is empty
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError(
                "No input provided. Please pipe xcodebuild output to xcsift.\n\nExample: xcodebuild build | xcsift"
            )
        }

        // Parse coverage if requested
        var coverageData: CodeCoverage? = nil
        if resolved.coverage {
            let path = resolved.coveragePath ?? ""
            let targetFilter = parser.extractTestedTarget(from: input)
            coverageData = CoverageParser.parseCoverageFromPath(path, targetFilter: targetFilter)

            // Warn if target filter was extracted but no coverage data was found
            if let filter = targetFilter, coverageData == nil {
                writeToStderr(
                    "Warning: Target '\(filter)' was detected but no matching coverage data was found.\n"
                )
            }
        }

        let result = parser.parse(
            input: input,
            printWarnings: resolved.warnings,
            warningsAsErrors: resolved.warningsAsErrors,
            coverage: coverageData,
            printCoverageDetails: resolved.coverageDetails,
            slowThreshold: resolved.slowThreshold,
            printBuildInfo: resolved.buildInfo,
            printExecutables: resolved.executable
        )
        outputResult(result, resolved: resolved)
    }

    private func generateConfigFile() throws {
        let configLoader = ConfigLoader()
        let filename = ConfigLoader.configFileName
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(filename).path

        // Check if file already exists
        if FileManager.default.fileExists(atPath: path) {
            writeToStderr("Error: \(filename) already exists in current directory\n")
            throw ExitCode.failure
        }

        // Write template
        let template = configLoader.generateTemplate()
        do {
            try template.write(toFile: path, atomically: true, encoding: .utf8)
            print("Created \(filename)")
        } catch {
            writeToStderr("Error: Failed to create \(filename): \(error.localizedDescription)\n")
            throw ExitCode.failure
        }
    }

    private func readStandardInput() -> String {
        if #available(macOS 10.15.4, *) {
            // Use modern API that properly handles EOF
            do {
                let data = try FileHandle.standardInput.readToEnd() ?? Data()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
        } else {
            // Fallback for older systems
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func outputResult(_ result: BuildResult, resolved: ResolvedConfig) {
        // In quiet mode, suppress output if build succeeded with no warnings or errors
        if resolved.quiet && result.status == "success" && result.summary.warnings == 0 {
            return
        }

        switch resolved.format {
        case .githubActions:
            // Explicit github-actions format: only annotations
            outputGitHubActions(result)
        case .toon:
            outputTOON(result, resolved: resolved)
            // Auto-append GitHub Actions annotations on CI
            if isCI {
                outputGitHubActions(result)
            }
        case .json:
            outputJSON(result)
            // Auto-append GitHub Actions annotations on CI
            if isCI {
                outputGitHubActions(result)
            }
        }
    }

    private func outputJSON(_ result: BuildResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if #available(macOS 10.15, *) {
            encoder.outputFormatting.insert(.withoutEscapingSlashes)
        }

        do {
            let jsonData = try encoder.encode(result)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("Error encoding JSON: \(error)")
        }
    }

    private func outputTOON(_ result: BuildResult, resolved: ResolvedConfig) {
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = resolved.toonDelimiter.toonDelimiter
        encoder.keyFolding = resolved.toonKeyFolding.toonKeyFolding
        if let depth = resolved.toonFlattenDepth {
            encoder.flattenDepth = depth
        }

        do {
            let toonData = try encoder.encode(result)
            if let toonString = String(data: toonData, encoding: .utf8) {
                print(toonString)
            } else {
                writeToStderr("Error: TOON data is not valid UTF-8\n")
            }
        } catch {
            writeToStderr("Error encoding TOON: \(error)\n")
        }
    }

    private func outputGitHubActions(_ result: BuildResult) {
        let output = result.formatGitHubActions()
        print(output)
    }

}

XCSift.main()
