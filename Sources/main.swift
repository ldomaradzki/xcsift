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
        usage: "xcodebuild [options] 2>&1 | xcsift",
        discussion: """
        xcsift reads xcodebuild output from stdin and outputs structured JSON.

        Important: Always use 2>&1 to redirect stderr to stdout. This ensures all
        compiler errors, warnings, and build output are captured.

        Examples:
          xcodebuild build 2>&1 | xcsift
          xcodebuild test 2>&1 | xcsift
          swift build 2>&1 | xcsift
          swift test 2>&1 | xcsift
        """,
        helpNames: [.short, .long]
    )
    
    @Flag(name: [.short, .long], help: "Show version information")
    var version: Bool = false
    
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
        
        let result = parser.parse(input: input)
        outputResult(result)
    }
    
    private func readStandardInput() -> String {
        var buffer = Data()
        
        while true {
            let available = FileHandle.standardInput.availableData
            if available.isEmpty {
                break
            }
            buffer.append(available)
            
            // Small delay to allow more data to arrive
            usleep(10000) // 10ms
            
            // Check if no more data is available
            let nextAvailable = FileHandle.standardInput.availableData
            if nextAvailable.isEmpty {
                break
            }
        }
        
        return String(data: buffer, encoding: .utf8) ?? ""
    }
    
    private func outputResult(_ result: BuildResult) {
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
