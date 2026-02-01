import Foundation

/// Error types for Claude Code installation
enum ClaudeCodeInstallerError: Error, CustomStringConvertible {
    case claudeCLINotFound
    case marketplaceAddFailed(stderr: String)
    case pluginInstallFailed(stderr: String)
    case pluginUninstallFailed(stderr: String)
    case marketplaceRemoveFailed(stderr: String)
    case shellCommandFailed(command: String, stderr: String)

    var description: String {
        switch self {
        case .claudeCLINotFound:
            return
                "Claude CLI not found. Please install Claude Code first: https://claude.ai/download"
        case .marketplaceAddFailed(let stderr):
            return "Failed to add marketplace: \(stderr)"
        case .pluginInstallFailed(let stderr):
            return "Failed to install plugin: \(stderr)"
        case .pluginUninstallFailed(let stderr):
            return "Failed to uninstall plugin: \(stderr)"
        case .marketplaceRemoveFailed(let stderr):
            return "Failed to remove marketplace: \(stderr)"
        case .shellCommandFailed(let command, let stderr):
            return "Shell command failed (\(command)): \(stderr)"
        }
    }
}

/// Result of a shell command execution
struct InstallShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

/// Protocol for shell command execution (install commands)
protocol InstallShellRunnerProtocol {
    func run(command: String) -> InstallShellResult
}

/// Handles Claude Code plugin installation via the `claude` CLI
struct ClaudeCodeInstaller {

    /// The GitHub repository for the xcsift marketplace
    static let marketplaceRepo = "ldomaradzki/xcsift"

    /// The plugin name
    static let pluginName = "xcsift"

    /// Protocol for running shell commands (for testability)
    let shellRunner: InstallShellRunnerProtocol

    init(shellRunner: InstallShellRunnerProtocol = DefaultInstallShellRunner()) {
        self.shellRunner = shellRunner
    }

    /// Check if the Claude CLI is available
    func isClaudeCLIAvailable() -> Bool {
        let result = shellRunner.run(command: "which claude")
        return result.exitCode == 0
    }

    /// Install the Claude Code plugin
    func install() throws {
        // Check if Claude CLI is available
        guard isClaudeCLIAvailable() else {
            throw ClaudeCodeInstallerError.claudeCLINotFound
        }

        // Add marketplace
        let addResult = shellRunner.run(
            command: "claude plugin marketplace add \(Self.marketplaceRepo)"
        )
        if addResult.exitCode != 0 {
            // Ignore "already added" errors
            if !addResult.stderr.contains("already") && !addResult.stdout.contains("already") {
                throw ClaudeCodeInstallerError.marketplaceAddFailed(stderr: addResult.stderr)
            }
        }

        // Install plugin
        let installResult = shellRunner.run(
            command: "claude plugin install \(Self.pluginName)"
        )
        if installResult.exitCode != 0 {
            // Ignore "already installed" errors
            if !installResult.stderr.contains("already")
                && !installResult.stdout.contains("already")
            {
                throw ClaudeCodeInstallerError.pluginInstallFailed(stderr: installResult.stderr)
            }
        }
    }

    /// Uninstall the Claude Code plugin
    func uninstall() throws {
        // Check if Claude CLI is available
        guard isClaudeCLIAvailable() else {
            throw ClaudeCodeInstallerError.claudeCLINotFound
        }

        // Uninstall plugin
        let uninstallResult = shellRunner.run(
            command: "claude plugin uninstall \(Self.pluginName)"
        )
        if uninstallResult.exitCode != 0 {
            // Ignore "not installed" errors
            if !uninstallResult.stderr.contains("not installed")
                && !uninstallResult.stdout.contains("not installed")
                && !uninstallResult.stderr.contains("not found")
                && !uninstallResult.stdout.contains("not found")
            {
                throw ClaudeCodeInstallerError.pluginUninstallFailed(stderr: uninstallResult.stderr)
            }
        }

        // Optionally remove marketplace (ignore errors but log them)
        let marketplaceRemoveResult = shellRunner.run(
            command: "claude plugin marketplace remove \(Self.marketplaceRepo)"
        )
        if marketplaceRemoveResult.exitCode != 0 {
            // Log to stderr but don't fail - this is a best-effort cleanup
            FileHandle.standardError.write(
                Data(
                    "Warning: Failed to remove marketplace (this is usually safe to ignore): \(marketplaceRemoveResult.stderr)\n"
                        .utf8
                )
            )
        }
    }
}

/// Default shell runner implementation for install commands
struct DefaultInstallShellRunner: InstallShellRunnerProtocol {
    func run(command: String) -> InstallShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return InstallShellResult(
                exitCode: process.terminationStatus,
                stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            return InstallShellResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
    }
}
