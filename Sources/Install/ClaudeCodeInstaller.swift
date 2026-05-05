import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Error types for Claude Code installation
enum ClaudeCodeInstallerError: Error, CustomStringConvertible {
    case claudeCLINotFound
    case marketplaceAddFailed(stderr: String, alreadyStreamed: Bool)
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
        case .marketplaceAddFailed(let stderr, let alreadyStreamed):
            if alreadyStreamed {
                return "Failed to add marketplace (see output above)."
            }
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
/// is terminated because it exceeded the configured timeout. Negative so it can
/// never collide with a real POSIX exit status (0–255 unsigned).
let installShellTimeoutExitCode: Int32 = -2

/// Sentinel exit code returned when the subprocess could not be launched at all
/// (e.g. `/bin/bash` missing). Distinct from a real `-1` exit and from the
/// timeout sentinel.
let installShellLaunchFailedExitCode: Int32 = -3

/// Options for shell command execution.
struct InstallShellOptions {
    /// Maximum wall-clock time the subprocess may run before being terminated.
    /// `nil` means no timeout.
    var timeout: TimeInterval?

    /// Environment to pass to the subprocess. `nil` inherits the parent process
    /// environment as-is.
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
    /// Default forwards to the simple overload. Conformers that need timeout,
    /// environment overrides, or output streaming MUST override this — silently
    /// dropping options can mask hangs and credential mis-configuration.
    func run(command: String, options: InstallShellOptions) -> InstallShellResult {
        assertionFailure(
            "InstallShellRunnerProtocol conformer must override run(command:options:) "
                + "to honor timeout/environment/streamOutput"
        )
        return run(command: command)
    }
}

/// Handles Claude Code plugin installation via the `claude` CLI
struct ClaudeCodeInstaller {

    /// The GitHub repository for the xcsift marketplace
    static let marketplaceRepo = "ldomaradzki/xcsift"

    /// The plugin name
    static let pluginName = "xcsift"

    /// Timeout (seconds) applied to every `claude` subprocess. `claude plugin
    /// marketplace add` shells out to `git clone`; in environments without a
    /// configured credential helper, git can hang forever on a TTY-less prompt.
    static let claudeCommandTimeoutSeconds: Int = 120

    /// Backwards-compat alias used by tests.
    static let marketplaceAddTimeoutSeconds: Int = claudeCommandTimeoutSeconds

    /// Short timeout for `which claude` — should resolve in milliseconds.
    static let claudeLookupTimeoutSeconds: TimeInterval = 10

    /// Phrases the upstream `claude` CLI uses to indicate idempotent no-ops.
    /// We match these exactly (case-insensitive) instead of looking for the
    /// loose substring "already", which produces false positives like
    /// "Repository already deleted" or "key has already been revoked".
    private static let alreadyAddedMarkers: [String] = [
        "marketplace already exists",
        "marketplace already added",
        "is already added",
        "already added",
    ]

    private static let alreadyInstalledMarkers: [String] = [
        "plugin already installed",
        "is already installed",
        "already installed",
    ]

    private static let notInstalledMarkers: [String] = [
        "plugin not installed",
        "is not installed",
        "not installed",
        "not found",
    ]

    /// Protocol for running shell commands (for testability)
    let shellRunner: InstallShellRunnerProtocol

    init(shellRunner: InstallShellRunnerProtocol = DefaultInstallShellRunner()) {
        self.shellRunner = shellRunner
    }

    /// Check if the Claude CLI is available
    func isClaudeCLIAvailable() -> Bool {
        let result = shellRunner.run(
            command: "which claude",
            options: InstallShellOptions(timeout: Self.claudeLookupTimeoutSeconds)
        )
        return result.exitCode == 0
    }

    /// Build the environment for `claude plugin marketplace add`. Forces git
    /// into non-interactive mode so a missing credential helper fails fast
    /// instead of hanging on a TTY-less prompt. Preserves any pre-existing
    /// `GIT_ASKPASS`/`SSH_ASKPASS` so users with a working credential helper
    /// keep their working flow.
    static func marketplaceAddEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        if env["GIT_ASKPASS"] == nil && env["SSH_ASKPASS"] == nil {
            env["GIT_ASKPASS"] = "/bin/true"
        }
        return env
    }

    /// Standard options for any `claude plugin …` command. Always applies a
    /// hard timeout and the non-interactive git environment so a misbehaving
    /// subprocess can't hang indefinitely.
    private static func claudeCommandOptions(streamOutput: Bool) -> InstallShellOptions {
        InstallShellOptions(
            timeout: TimeInterval(claudeCommandTimeoutSeconds),
            environment: marketplaceAddEnvironment(),
            streamOutput: streamOutput
        )
    }

    private static func matchesAny(_ result: InstallShellResult, markers: [String]) -> Bool {
        let combined = (result.stdout + "\n" + result.stderr).lowercased()
        return markers.contains { combined.contains($0) }
    }

    /// Install the Claude Code plugin
    func install() throws {
        guard isClaudeCLIAvailable() else {
            throw ClaudeCodeInstallerError.claudeCLINotFound
        }

        let addResult = shellRunner.run(
            command: "claude plugin marketplace add \(Self.marketplaceRepo)",
            options: Self.claudeCommandOptions(streamOutput: true)
        )
        if addResult.exitCode == installShellTimeoutExitCode {
            throw ClaudeCodeInstallerError.marketplaceAddTimedOut(
                seconds: Self.claudeCommandTimeoutSeconds
            )
        }
        if addResult.exitCode != 0
            && !Self.matchesAny(addResult, markers: Self.alreadyAddedMarkers)
        {
            throw ClaudeCodeInstallerError.marketplaceAddFailed(
                stderr: addResult.stderr,
                alreadyStreamed: true
            )
        }

        let installResult = shellRunner.run(
            command: "claude plugin install \(Self.pluginName)",
            options: Self.claudeCommandOptions(streamOutput: false)
        )
        if installResult.exitCode != 0
            && !Self.matchesAny(installResult, markers: Self.alreadyInstalledMarkers)
        {
            throw ClaudeCodeInstallerError.pluginInstallFailed(stderr: installResult.stderr)
        }
    }

    /// Uninstall the Claude Code plugin
    func uninstall() throws {
        guard isClaudeCLIAvailable() else {
            throw ClaudeCodeInstallerError.claudeCLINotFound
        }

        let uninstallResult = shellRunner.run(
            command: "claude plugin uninstall \(Self.pluginName)",
            options: Self.claudeCommandOptions(streamOutput: false)
        )
        if uninstallResult.exitCode != 0
            && !Self.matchesAny(uninstallResult, markers: Self.notInstalledMarkers)
        {
            throw ClaudeCodeInstallerError.pluginUninstallFailed(stderr: uninstallResult.stderr)
        }

        let marketplaceRemoveResult = shellRunner.run(
            command: "claude plugin marketplace remove \(Self.marketplaceRepo)",
            options: Self.claudeCommandOptions(streamOutput: false)
        )
        if marketplaceRemoveResult.exitCode != 0
            && !Self.matchesAny(marketplaceRemoveResult, markers: Self.notInstalledMarkers)
        {
            FileHandle.standardError.write(
                Data(
                    ("Warning: marketplace removal failed unexpectedly: "
                        + marketplaceRemoveResult.stderr + "\n"
                        + "To clean up manually, run: claude plugin marketplace remove "
                        + Self.marketplaceRepo + "\n").utf8
                )
            )
        }
    }
}

/// Default shell runner implementation for install commands.
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

        var timeoutTimer: DispatchSourceTimer?
        var killEscalationTimer: DispatchSourceTimer?

        do {
            try process.run()

            if let timeout = options.timeout {
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { [weak process] in
                    guard let process, process.isRunning else { return }
                    state.markTimedOut()
                    let pid = process.processIdentifier
                    process.terminate()

                    let escalation = DispatchSource.makeTimerSource(queue: .global())
                    escalation.schedule(deadline: .now() + 5)
                    escalation.setEventHandler { [weak process] in
                        guard let process, process.isRunning else { return }
                        // Kill descendants first so orphaned grandchildren
                        // release the pipe write ends, then SIGKILL the
                        // shell. The reverse order leaves orphans holding
                        // the pipes open and blocks pipe drain.
                        Self.killDescendants(of: pid)
                        kill(pid, SIGKILL)
                    }
                    escalation.resume()
                    state.attachKillEscalationTimer(escalation)
                }
                timer.resume()
                timeoutTimer = timer
            }

            process.waitUntilExit()
            timeoutTimer?.cancel()
            killEscalationTimer = state.takeKillEscalationTimer()
            killEscalationTimer?.cancel()

            // Close write ends so any orphaned grandchildren that inherited
            // the pipes don't keep `availableData` blocked when we drain.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()

            let trailingStdout = drainPipe(stdoutPipe)
            let trailingStderr = drainPipe(stderrPipe)
            if !trailingStdout.isEmpty {
                state.appendStdout(trailingStdout)
                if streamOutput {
                    FileHandle.standardOutput.write(trailingStdout)
                }
            }
            if !trailingStderr.isEmpty {
                state.appendStderr(trailingStderr)
                if streamOutput {
                    FileHandle.standardError.write(trailingStderr)
                }
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let snapshot = state.snapshot()

            if snapshot.timedOut {
                return InstallShellResult(
                    exitCode: installShellTimeoutExitCode,
                    stdout: decode(snapshot.stdout),
                    stderr: decode(snapshot.stderr)
                )
            }

            return InstallShellResult(
                exitCode: process.terminationStatus,
                stdout: decode(snapshot.stdout).trimmingCharacters(in: .whitespacesAndNewlines),
                stderr: decode(snapshot.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            timeoutTimer?.cancel()
            killEscalationTimer?.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return InstallShellResult(
                exitCode: installShellLaunchFailedExitCode,
                stdout: "",
                stderr: "Failed to launch '/bin/bash -c \(command)': \(error.localizedDescription)"
            )
        }
    }

    /// Non-blocking drain of whatever the kernel has buffered in the pipe.
    /// Sets O_NONBLOCK on the read end first because `availableData` blocks
    /// when the buffer is empty but the write end is still open — which can
    /// happen if an orphaned grandchild inherited the pipe.
    private func drainPipe(_ pipe: Pipe) -> Data {
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                read(fd, ptr.baseAddress, ptr.count)
            }
            if n > 0 {
                collected.append(contentsOf: buffer[0 ..< n])
            } else {
                break
            }
        }
        return collected
    }

    /// SIGKILL every direct child of `parent`. Best-effort — if `pgrep` is
    /// unavailable (very minimal Linux containers), the orphaned children
    /// will be reaped by init eventually.
    fileprivate static func killDescendants(of parent: pid_t) {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/bin/bash")
        pgrep.arguments = ["-c", "pgrep -P \(parent) || true"]
        let outPipe = Pipe()
        pgrep.standardOutput = outPipe
        pgrep.standardError = Pipe()
        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let listing = String(data: data, encoding: .utf8) else { return }
        for line in listing.split(separator: "\n") {
            guard let child = pid_t(line.trimmingCharacters(in: .whitespaces)) else { continue }
            kill(child, SIGKILL)
        }
    }

    /// Decode subprocess output as UTF-8 with lossy fallback so non-UTF-8
    /// diagnostics (localized git errors, exotic locales) still reach the user
    /// rather than collapsing to an empty string.
    private func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Lock-protected reference type that lets `@Sendable` closures running on
/// background queues mutate the subprocess output buffers and timeout flag
/// safely under Swift 6 strict concurrency.
private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var timedOut = false
    private var killEscalationTimer: DispatchSourceTimer?

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

    func attachKillEscalationTimer(_ timer: DispatchSourceTimer) {
        lock.lock()
        killEscalationTimer = timer
        lock.unlock()
    }

    func takeKillEscalationTimer() -> DispatchSourceTimer? {
        lock.lock()
        defer { lock.unlock() }
        let timer = killEscalationTimer
        killEscalationTimer = nil
        return timer
    }

    func snapshot() -> (stdout: Data, stderr: Data, timedOut: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr, timedOut)
    }
}
