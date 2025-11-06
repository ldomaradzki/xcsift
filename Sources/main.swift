import ArgumentParser
import Foundation
import Darwin

func getVersion() -> String {
    // Try to get version from git tag during build
    #if DEBUG
    return "dev"
    #else
    return "VERSION_PLACEHOLDER" // This will be replaced by build script
    #endif
}

struct XCSift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcsift",
        abstract: "A Swift tool to parse and format xcodebuild output for coding agents",
        usage: "xcodebuild [options] 2>&1 | xcsift [--warnings|-w] [--quiet|-q] [--coverage|-c] [--version|-v] [--help|-h]",
        discussion: """
        xcsift reads xcodebuild output from stdin and outputs structured JSON.

        Important: Always use 2>&1 to redirect stderr to stdout. This ensures all
        compiler errors, warnings, and build output are captured.

        Examples:
          xcodebuild build 2>&1 | xcsift
          xcodebuild test 2>&1 | xcsift -w
          swift build 2>&1 | xcsift --warnings
          swift test 2>&1 | xcsift
          swift build 2>&1 | xcsift --quiet
          swift test --enable-code-coverage 2>&1 | xcsift --coverage
          xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage
          xcsift -c --coverage-path .build/debug/codecov
        """,
        helpNames: [.short, .long]
    )
    
    @Flag(name: [.short, .long], help: "Show version information")
    var version: Bool = false

    @Flag(name: [.short, .long], help: "Print detailed warnings list (by default only warning count is shown)")
    var warnings: Bool = false

    @Flag(name: [.short, .long], help: "Suppress output when build succeeds with no warnings or errors")
    var quiet: Bool = false

    @Flag(name: [.short, .long], help: "Include code coverage data (auto-converts .profraw files)")
    var coverage: Bool = false

    @Option(name: .long, help: "Path to code coverage directory or JSON file (default: auto-detect in .build/)")
    var coveragePath: String?

    @Flag(name: .long, help: "Include detailed per-file coverage data (default: summary only)")
    var coverageDetails: Bool = false

    func run() throws {
        if version {
            print(getVersion())
            return
        }

        // Check if stdin is a terminal (no piped input) before trying to read
        if isatty(STDIN_FILENO) == 1 {
            throw ValidationError("No input provided. Please pipe xcodebuild output to xcsift.\n\nExample: xcodebuild build | xcsift")
        }

        let parser = OutputParser()
        let input = readStandardInput()

        // Check if input is empty
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("No input provided. Please pipe xcodebuild output to xcsift.\n\nExample: xcodebuild build | xcsift")
        }

        // Parse coverage if requested
        var coverageData: CodeCoverage? = nil
        if coverage {
            let path = coveragePath ?? ""
            let targetFilter = parser.extractTestedTarget(from: input)
            coverageData = OutputParser.parseCoverageFromPath(path, targetFilter: targetFilter)

            // Warn if target filter was extracted but no coverage data was found
            if let filter = targetFilter, coverageData == nil {
                fputs("Warning: Target '\(filter)' was detected but no matching coverage data was found.\n", stderr)
            }
        }

        let result = parser.parse(input: input, printWarnings: warnings, coverage: coverageData, printCoverageDetails: coverageDetails)
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
        outputJSON(result)
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
    
}

XCSift.main()
