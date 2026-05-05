import Foundation

/// Error types for Claude Code installation
enum ClaudeCodeInstallerError: Error, CustomStringConvertible {
    case claudeCLINotFound
    case marketplaceAddFailed(stderr: String)
    case marketplaceAddTimedOut(seconds: Int)
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
        case .marketplaceAddTimedOut(let seconds):
            return """
                Failed to add marketplace: timed out after \(seconds) seconds.

                This usually means `claude plugin marketplace add` is waiting for git \
                credentials it cannot read (xcsift runs claude without a TTY, so any \
                interactive prompt hangs forever).

                To diagnose, run the command directly in your terminal:
                    claude plugin marketplace add ldomaradzki/xcsift

                Common fixes:
                  - Configure a git credential helper for github.com
                  - Add an SSH key to your GitHub account
                  - For corporate setups: ensure your proxy / GHE host trust is \
                configured before installing the plugin

                See: https://github.com/ldomaradzki/xcsift/issues/67
                """
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

/// Sentinel exit code returned by `DefaultInstallShellRunner` when the subprocess
/// is terminated because it exceeded the configured timeout.
let installShellTimeoutExitCode: Int32 = -2

/// Options for shell command execution.
struct InstallShellOptions {
    /// Maximum wall-clock time the subprocess may run before being terminated.
    /// `nil` means no timeout.
    var timeout: TimeInterval?

    /// Environment to pass to the subprocess. `nil` inherits the parent process
    /// environment as-is. Override to inject vars like `GIT_TERMINAL_PROMPT=0`.
    var environment: [String: String]?

    /// When `true`, mirror subprocess stdout/stderr to the parent's stdout/stderr
    /// in real time so the user sees progress instead of a silent terminal.
    var streamOutput: Bool

    init(
        timeout: TimeInterval? = nil,
        environment: [String: String]? = nil,
        streamOutput: Bool = false
    ) {
        self.timeout = timeout
        self.environment = environment
        self.streamOutput = streamOutput
    }
}

/// Protocol for shell command execution (install commands)
protocol InstallShellRunnerProtocol {
    func run(command: String) -> InstallShellResult
    func run(command: String, options: InstallShellOptions) -> InstallShellResult
}

extension InstallShellRunnerProtocol {
    /// Default forwards the options-aware overload to the simple one so existing
    /// mocks keep working without changes.
    func run(command: String, options: InstallShellOptions) -> InstallShellResult {
        run(command: command)
    }
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

    /// Timeout (seconds) applied to `claude plugin marketplace add`. The command
    /// shells out to `git clone`; in corporate environments without a configured
    /// credential helper, git can hang forever on a TTY-less prompt
    /// (see anthropics/claude-code#14485 and ldomaradzki/xcsift#67).
    static let marketplaceAddTimeoutSeconds: Int = 120

    /// Build the environment for `claude plugin marketplace add`.
    /// We inherit the parent environment and force git into non-interactive mode
    /// so a missing credential helper fails fast instead of hanging.
    static func marketplaceAddEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/bin/true"
        return env
    }

    /// Install the Claude Code plugin
    func install() throws {
        // Check if Claude CLI is available
        guard isClaudeCLIAvailable() else {
            throw ClaudeCodeInstallerError.claudeCLINotFound
        }

        // Add marketplace.
        // Apply timeout + non-interactive git env + live output to defend against
        // the upstream hang where `git clone` blocks on a credential prompt with
        // no TTY (anthropics/claude-code#14485).
        let addOptions = InstallShellOptions(
            timeout: TimeInterval(Self.marketplaceAddTimeoutSeconds),
            environment: Self.marketplaceAddEnvironment(),
            streamOutput: true
        )
        let addResult = shellRunner.run(
            command: "claude plugin marketplace add \(Self.marketplaceRepo)",
            options: addOptions
        )
        if addResult.exitCode == installShellTimeoutExitCode {
            throw ClaudeCodeInstallerError.marketplaceAddTimedOut(
                seconds: Self.marketplaceAddTimeoutSeconds
            )
        }
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
        run(command: command, options: InstallShellOptions())
    }

    func run(command: String, options: InstallShellOptions) -> InstallShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let env = options.environment {
            process.environment = env
        }

        // Thread-safe accumulator. `readabilityHandler` runs on background
        // queues, and the timeout closure also touches `didTimeOut`. A reference
        // type lets `@Sendable` closures mutate the same instance under a lock.
        let state = ProcessState()
        let streamOutput = options.streamOutput

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            state.appendStdout(chunk)
            if streamOutput {
                FileHandle.standardOutput.write(chunk)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            state.appendStderr(chunk)
            if streamOutput {
                FileHandle.standardError.write(chunk)
            }
        }

        do {
            try process.run()

            if let timeout = options.timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
                    guard let process, process.isRunning else { return }
                    state.markTimedOut()
                    process.terminate()
                }
            }

            process.waitUntilExit()

            // Detach handlers so the pipes' file descriptors can be released.
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let snapshot = state.snapshot()

            if snapshot.timedOut {
                return InstallShellResult(
                    exitCode: installShellTimeoutExitCode,
                    stdout: String(data: snapshot.stdout, encoding: .utf8) ?? "",
                    stderr: String(data: snapshot.stderr, encoding: .utf8) ?? ""
                )
            }

            let stdout = String(data: snapshot.stdout, encoding: .utf8) ?? ""
            let stderr = String(data: snapshot.stderr, encoding: .utf8) ?? ""

            return InstallShellResult(
                exitCode: process.terminationStatus,
                stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return InstallShellResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
    }
}

/// Lock-protected reference type that lets `@Sendable` closures running on
/// background queues mutate the subprocess output buffers safely.
private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var timedOut = false

    func appendStdout(_ chunk: Data) {
        lock.lock()
        stdout.append(chunk)
        lock.unlock()
    }

    func appendStderr(_ chunk: Data) {
        lock.lock()
        stderr.append(chunk)
        lock.unlock()
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    func snapshot() -> (stdout: Data, stderr: Data, timedOut: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr, timedOut)
    }
}
