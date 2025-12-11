import Foundation

/// Protocol for shell command execution, enabling dependency injection for testing
protocol ShellRunnerProtocol {
    func run(_ command: String, args: [String]) -> String?
}

/// Default implementation that executes real shell commands
struct DefaultShellRunner: ShellRunnerProtocol {
    func run(_ command: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            // Read data BEFORE waiting for exit to avoid pipe deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
