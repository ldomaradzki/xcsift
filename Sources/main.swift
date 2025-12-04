import ArgumentParser
import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif
import TOONEncoder

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

enum TOONLengthMarkerType: String, ExpressibleByArgument {
    case none
    case hash

    var toonLengthMarker: TOONEncoder.LengthMarker {
        switch self {
        case .none: return .none
        case .hash: return .hash
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
            "xcodebuild [options] 2>&1 | xcsift [--format|-f json|toon|github-actions] [--toon-delimiter comma|tab|pipe] [--toon-length-marker none|hash] [--warnings|-w] [--Werror|-W] [--quiet|-q] [--coverage|-c] [--version|-v] [--help|-h]",
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

            TOON format (30-60% fewer tokens for LLMs):
              xcodebuild build 2>&1 | xcsift -f toon
              swift test 2>&1 | xcsift -f toon -w -c

            GitHub Actions (auto-appended on CI):
              On CI, JSON/TOON output is followed by GitHub Actions annotations.
              Use -f github-actions for annotations only (no JSON/TOON).

            Configuration options:
              --toon-delimiter [comma|tab|pipe]  # Default: comma
              --toon-length-marker [none|hash]   # Default: none
              --toon-key-folding [disabled|safe] # Default: disabled
              --toon-flatten-depth N             # Default: unlimited
            """,
        helpNames: [.short, .long]
    )

    @Flag(name: [.short, .long], help: "Show version information")
    var version: Bool = false

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

    @Option(
        name: [.customShort("f"), .long],
        help: "Output format (json, toon, or github-actions). Default: json. On CI, annotations are auto-appended."
    )
    var format: FormatType = .json

    /// Detects if running in GitHub Actions CI environment
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
    }

    @Option(name: .long, help: "TOON delimiter (comma, tab, or pipe). Default: comma")
    var toonDelimiter: TOONDelimiterType = .comma

    @Option(name: .long, help: "TOON length marker (none or hash). Default: none")
    var toonLengthMarker: TOONLengthMarkerType = .none

    @Option(
        name: .long,
        help:
            "TOON key folding (disabled or safe). Default: disabled. When safe, nested single-key objects collapse to dotted paths"
    )
    var toonKeyFolding: TOONKeyFoldingType = .disabled

    @Option(name: .long, help: "TOON flatten depth limit for key folding. Default: unlimited")
    var toonFlattenDepth: Int?

    func run() throws {
        if version {
            print(getVersion())
            return
        }

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
        if coverage {
            let path = coveragePath ?? ""
            let targetFilter = parser.extractTestedTarget(from: input)
            coverageData = CoverageParser.parseCoverageFromPath(path, targetFilter: targetFilter)

            // Warn if target filter was extracted but no coverage data was found
            if let filter = targetFilter, coverageData == nil {
                writeToStderr("Warning: Target '\(filter)' was detected but no matching coverage data was found.\n")
            }
        }

        let result = parser.parse(
            input: input,
            printWarnings: warnings,
            warningsAsErrors: warningsAsErrors,
            coverage: coverageData,
            printCoverageDetails: coverageDetails
        )
        outputResult(result, quiet: quiet)
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

    private func outputResult(_ result: BuildResult, quiet: Bool) {
        // In quiet mode, suppress output if build succeeded with no warnings or errors
        if quiet && result.status == "success" && result.summary.warnings == 0 {
            return
        }

        switch format {
        case .githubActions:
            // Explicit github-actions format: only annotations
            outputGitHubActions(result)
        case .toon:
            outputTOON(result)
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

    private func outputTOON(_ result: BuildResult) {
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = toonDelimiter.toonDelimiter
        encoder.lengthMarker = toonLengthMarker.toonLengthMarker
        encoder.keyFolding = toonKeyFolding.toonKeyFolding
        if let depth = toonFlattenDepth {
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
