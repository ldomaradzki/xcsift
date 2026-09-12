import ArgumentParser
import Foundation
import XCSiftCore
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

            MCP proxy (wrap an Xcode MCP server):
              xcsift mcp                     # Wrap Xcode's built-in MCP server
              xcsift mcp -f toon -- xcrun mcpbridge
              xcsift mcp --print-config      # Print a client configuration snippet
              xcsift mcp --install           # Register the proxy with Claude Code
              xcsift mcp --uninstall         # Remove that registration

            Plugin installation:
              xcsift install-claude-code     # Install Claude Code plugin
              xcsift uninstall-claude-code   # Uninstall Claude Code plugin
              xcsift install-codex           # Install Codex skill
              xcsift uninstall-codex         # Uninstall Codex skill
              xcsift install-cursor          # Install Cursor hooks (project)
              xcsift install-cursor --global # Install Cursor hooks (global)
              xcsift uninstall-cursor        # Uninstall Cursor hooks
            """,
        subcommands: [
            MCPProxyCommand.self,
            InstallClaudeCode.self,
            UninstallClaudeCode.self,
            InstallCodex.self,
            UninstallCodex.self,
            InstallCursor.self,
            UninstallCursor.self,
        ],
        helpNames: [.short, .long]
    )

    @Flag(name: [.short, .long], help: "Show version information")
    var version: Bool = false

    @Flag(name: .long, help: "Generate example configuration file (.xcsift.toml) in current directory")
    var `init`: Bool = false

    @OptionGroup var sifting: SiftingOptions

    @Flag(name: [.short, .long], help: "Suppress output when build succeeds with no warnings or errors")
    var quiet: Bool = false

    @Flag(
        name: [.customShort("E"), .customLong("exit-on-failure")],
        help: "Exit with failure code if build does not succeed"
    )
    var exitOnFailure: Bool = false

    /// Detects if running in GitHub Actions CI environment
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
    }

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
        let resolved: ResolvedConfig
        do {
            resolved = try sifting.resolve(quiet: quiet, exitOnFailure: exitOnFailure)
        } catch let error as ConfigError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }

        // Check if stdin is a terminal (no piped input) before trying to read
        if isatty(STDIN_FILENO) == 1 {
            throw ValidationError(
                "No input provided. Please pipe xcodebuild output to xcsift.\n\nExample: xcodebuild build | xcsift"
            )
        }

        var parser = StreamingOutputParser(
            printWarnings: resolved.parse.warnings,
            retainWarnings: resolved.parse.warnings || resolved.parse.warningsAsErrors,
            warningsAsErrors: resolved.parse.warningsAsErrors,
            printCoverageDetails: resolved.parse.coverageDetails,
            slowThreshold: resolved.parse.slowThreshold,
            printBuildInfo: resolved.parse.buildInfo,
            printExecutables: resolved.parse.executable,
            discoverTestedTarget: resolved.parse.coverage,
            xcbeautify: resolved.parse.xcbeautify
        )
        var inputSource = POSIXInputSource(fileDescriptor: STDIN_FILENO)
        var lineReader = StreamingLineReader()
        let inputScan: InputScan

        do {
            inputScan = try lineReader.consume(from: &inputSource) { line in
                parser.feed(line)
            }
        } catch {
            writeToStderr("Error: Failed to read standard input: \(error.localizedDescription)\n")
            throw ExitCode.failure
        }

        if inputScan.oversizedLinesDropped > 0 {
            writeToStderr(
                "hint: Ignored \(inputScan.oversizedLinesDropped) input line(s) longer than "
                    + "\(LineParser.maximumLineBytes) bytes.\n"
            )
        }

        // Check if input is empty
        if !inputScan.containsNonWhitespace {
            throw ValidationError(
                "No input provided. Please pipe xcodebuild output to xcsift.\n\nExample: xcodebuild build | xcsift"
            )
        }

        // Parse coverage if requested
        var coverageData: CodeCoverage? = nil
        if resolved.parse.coverage {
            let path = resolved.parse.coveragePath ?? ""
            let targetFilter = parser.testedTarget
            coverageData = CoverageParser.parseCoverageFromPath(path, targetFilter: targetFilter)

            // Warn if target filter was extracted but no coverage data was found
            if let filter = targetFilter, coverageData == nil {
                writeToStderr(
                    "Warning: Target '\(filter)' was detected but no matching coverage data was found.\n"
                )
            }
        }

        let result = parser.finish(coverage: coverageData)
        outputResult(result, resolved: resolved)

        if result.status == "incomplete" {
            writeToStderr(
                "hint: build output ended without a success or failure marker "
                    + "(truncated or killed?); status reported as \"incomplete\"\n"
            )
        }

        // Exit with failure if requested and build did not succeed
        if resolved.exitOnFailure && result.status != "success" {
            throw ExitCode.failure
        }
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

    private func outputResult(_ result: BuildResult, resolved: ResolvedConfig) {
        // In quiet mode, suppress output if build succeeded with no warnings or errors
        if resolved.quiet && result.status == "success" && result.summary.warnings == 0 {
            return
        }

        switch resolved.render.format {
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
        do {
            print(try ResultRenderer.json(result))
        } catch {
            print("Error encoding JSON: \(error)")
        }
    }

    private func outputTOON(_ result: BuildResult, resolved: ResolvedConfig) {
        do {
            print(try ResultRenderer.toon(result, config: resolved.render))
        } catch ResultRenderer.RenderError.invalidUTF8 {
            writeToStderr("Error: TOON data is not valid UTF-8\n")
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
