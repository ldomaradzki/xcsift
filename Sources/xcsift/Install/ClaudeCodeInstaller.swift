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
    /// Marketplace add failed and stderr has NOT been shown to the user yet —
    /// embed `stderr` in the description.
    case marketplaceAddFailed(stderr: String)
    /// Marketplace add failed and stderr was already streamed live — the
    /// description points the user to the output above instead of repeating it.
    case marketplaceAddFailedStreamed
    case marketplaceAddTimedOut(seconds: Int)
    case pluginInstallFailed(stderr: String)
    case pluginInstallTimedOut(seconds: Int)
    case pluginUninstallFailed(stderr: String)
    case pluginUninstallTimedOut(seconds: Int)
    case marketplaceRemoveFailed(stderr: String)
    case shellCommandFailed(command: String, stderr: String)

    var description: String {
        switch self {
        case .claudeCLINotFound:
            return
                "Claude CLI not found. Please install Claude Code first: https://claude.ai/download"
        case .marketplaceAddFailed(let stderr):
            return "Failed to add marketplace: \(stderr)"
        case .marketplaceAddFailedStreamed:
            return "Failed to add marketplace (see output above)."
        case .marketplaceAddTimedOut(let seconds):
            return Self.timeoutDescription(
                command: "claude plugin marketplace add",
                target: ClaudeCodeInstaller.marketplaceRepo,
                seconds: seconds
            )
        case .pluginInstallFailed(let stderr):
            return "Failed to install plugin: \(stderr)"
        case .pluginInstallTimedOut(let seconds):
            return Self.timeoutDescription(
                command: "claude plugin install",
                target: ClaudeCodeInstaller.pluginName,
                seconds: seconds
            )
        case .pluginUninstallFailed(let stderr):
            return "Failed to uninstall plugin: \(stderr)"
        case .pluginUninstallTimedOut(let seconds):
            return Self.timeoutDescription(
                command: "claude plugin uninstall",
                target: ClaudeCodeInstaller.pluginName,
                seconds: seconds
            )
        case .marketplaceRemoveFailed(let stderr):
            return "Failed to remove marketplace: \(stderr)"
        case .shellCommandFailed(let command, let stderr):
            return "Shell command failed (\(command)): \(stderr)"
        }
    }

    private static func timeoutDescription(command: String, target: String, seconds: Int) -> String {
        return """
            Failed: `\(command) \(target)` timed out after \(seconds) seconds.

            This usually means the command is waiting for git credentials it \
            cannot read (xcsift runs claude without a TTY, so any interactive \
            prompt hangs forever).

            To diagnose, run the command directly in your terminal:
                \(command) \(target)

            Common fixes:
              - Configure a git credential helper for github.com
              - Add an SSH key to your GitHub account
              - For corporate setups: ensure your proxy / GHE host trust is \
            configured before installing the plugin
            """
    }
}

/// Outcome of a shell command execution. Modeled as a sum type so the three
/// possible terminations (normal exit / timeout / launch failure) are exhaustive
/// at the compiler level — callers must handle all three or the build breaks.
enum InstallShellOutcome {
    /// Subprocess started and ran to completion. `status` is the real POSIX
    /// exit status (0–255); `stdout`/`stderr` are the captured streams,
    /// trimmed of trailing whitespace.
    case exited(status: Int32, stdout: String, stderr: String)

    /// Subprocess exceeded `options.timeout` and was terminated. Streams
    /// contain whatever was captured before the kill — NOT trimmed, because
    /// partial-line tails near the kill point are diagnostically meaningful.
    case timedOut(stdout: String, stderr: String)

    /// Subprocess could not be launched at all (e.g. `/bin/bash` missing).
    /// `message` describes the launch error; streams are empty by definition.
    case launchFailed(message: String)
}

/// Options for shell command execution.
struct InstallShellOptions {
    /// Maximum wall-clock time the subprocess may run before being terminated.
    /// `nil` means no timeout. Negative values are clamped to zero (immediate
    /// timeout) by `DispatchSourceTimer`.
    let timeout: TimeInterval?

    /// Environment to pass to the subprocess. `nil` inherits the parent process
    /// environment as-is.
    let environment: [String: String]?

    /// When `true`, mirror subprocess stdout/stderr to the parent's stdout/stderr
    /// in real time so the user sees progress instead of a silent terminal.
    let streamOutput: Bool

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

/// Protocol for shell command execution (install commands).
///
/// Conformers MUST implement `run(command:options:)`. The simpler
/// `run(command:)` is provided as an extension shim that calls the options-aware
/// method with defaults — this moves "honor timeout/environment" from a runtime
/// `assertionFailure` (no-op in release) into the compiler's hands.
protocol InstallShellRunnerProtocol {
    func run(command: String, options: InstallShellOptions) -> InstallShellOutcome
}

extension InstallShellRunnerProtocol {
    /// Convenience overload — runs the command with default options.
    func run(command: String) -> InstallShellOutcome {
        return run(command: command, options: InstallShellOptions())
    }
}

/// Handles Claude Code plugin installation via the `claude` CLI
struct ClaudeCodeInstaller {

    /// The GitHub repository for the xcsift marketplace
    static let marketplaceRepo = "ldomaradzki/xcsift"

    /// The plugin name
    static let pluginName = "xcsift"

    /// Timeout applied to every `claude` subprocess. `claude plugin marketplace
    /// add` shells out to `git clone`; in environments without a configured
    /// credential helper, git can hang forever on a TTY-less prompt.
    static let claudeCommandTimeoutSeconds: TimeInterval = 120

    /// Backwards-compat alias used by tests.
    static let marketplaceAddTimeoutSeconds: TimeInterval = claudeCommandTimeoutSeconds

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
        let outcome = shellRunner.run(
            command: "which claude",
            options: InstallShellOptions(timeout: Self.claudeLookupTimeoutSeconds)
        )
        if case .exited(let status, _, _) = outcome {
            return status == 0
        }
        return false
    }

    /// Build the environment for `claude plugin marketplace add`. Forces git
    /// into non-interactive mode so a missing credential helper fails fast
    /// instead of hanging on a TTY-less prompt. Preserves any pre-existing
    /// `GIT_ASKPASS` so users with a working credential helper keep their
    /// working flow; `SSH_ASKPASS` is intentionally NOT a guard here because
    /// git ignores it for HTTPS clones.
    static func marketplaceAddEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        if env["GIT_ASKPASS"] == nil {
            env["GIT_ASKPASS"] = "/bin/true"
        }
        return env
    }

    /// Standard options for any `claude plugin …` command. Always applies a
    /// hard timeout and the non-interactive git environment so a misbehaving
    /// subprocess can't hang indefinitely.
    private static func claudeCommandOptions(streamOutput: Bool) -> InstallShellOptions {
        InstallShellOptions(
            timeout: claudeCommandTimeoutSeconds,
            environment: marketplaceAddEnvironment(),
            streamOutput: streamOutput
        )
    }

    private static func matchesAny(stdout: String, stderr: String, markers: [String]) -> Bool {
        let combined = (stdout + "\n" + stderr).lowercased()
        return markers.contains { combined.contains($0) }
    }

    /// Install the Claude Code plugin
    func install() throws {
        guard isClaudeCLIAvailable() else {
            throw ClaudeCodeInstallerError.claudeCLINotFound
        }

        let addCommand = "claude plugin marketplace add \(Self.marketplaceRepo)"
        let addOutcome = shellRunner.run(
            command: addCommand,
            options: Self.claudeCommandOptions(streamOutput: true)
        )
        switch addOutcome {
        case .exited(let status, let stdout, let stderr):
            if status != 0
                && !Self.matchesAny(stdout: stdout, stderr: stderr, markers: Self.alreadyAddedMarkers)
            {
                throw ClaudeCodeInstallerError.marketplaceAddFailedStreamed
            }
        case .timedOut:
            throw ClaudeCodeInstallerError.marketplaceAddTimedOut(
                seconds: Int(Self.claudeCommandTimeoutSeconds)
            )
        case .launchFailed(let message):
            throw ClaudeCodeInstallerError.shellCommandFailed(
                command: addCommand,
                stderr: message
            )
        }

        let installCommand = "claude plugin install \(Self.pluginName)"
        let installOutcome = shellRunner.run(
            command: installCommand,
            options: Self.claudeCommandOptions(streamOutput: false)
        )
        switch installOutcome {
        case .exited(let status, let stdout, let stderr):
            if status != 0
                && !Self.matchesAny(
                    stdout: stdout,
                    stderr: stderr,
                    markers: Self.alreadyInstalledMarkers
                )
            {
                throw ClaudeCodeInstallerError.pluginInstallFailed(stderr: stderr)
            }
        case .timedOut:
            throw ClaudeCodeInstallerError.pluginInstallTimedOut(
                seconds: Int(Self.claudeCommandTimeoutSeconds)
            )
        case .launchFailed(let message):
            throw ClaudeCodeInstallerError.shellCommandFailed(
                command: installCommand,
                stderr: message
            )
        }
    }

    /// Uninstall the Claude Code plugin
    func uninstall() throws {
        guard isClaudeCLIAvailable() else {
            throw ClaudeCodeInstallerError.claudeCLINotFound
        }

        let uninstallCommand = "claude plugin uninstall \(Self.pluginName)"
        let uninstallOutcome = shellRunner.run(
            command: uninstallCommand,
            options: Self.claudeCommandOptions(streamOutput: false)
        )
        switch uninstallOutcome {
        case .exited(let status, let stdout, let stderr):
            if status != 0
                && !Self.matchesAny(
                    stdout: stdout,
                    stderr: stderr,
                    markers: Self.notInstalledMarkers
                )
            {
                throw ClaudeCodeInstallerError.pluginUninstallFailed(stderr: stderr)
            }
        case .timedOut:
            throw ClaudeCodeInstallerError.pluginUninstallTimedOut(
                seconds: Int(Self.claudeCommandTimeoutSeconds)
            )
        case .launchFailed(let message):
            throw ClaudeCodeInstallerError.shellCommandFailed(
                command: uninstallCommand,
                stderr: message
            )
        }

        let removeCommand = "claude plugin marketplace remove \(Self.marketplaceRepo)"
        let removeOutcome = shellRunner.run(
            command: removeCommand,
            options: Self.claudeCommandOptions(streamOutput: false)
        )
        switch removeOutcome {
        case .exited(let status, let stdout, let stderr):
            if status != 0
                && !Self.matchesAny(
                    stdout: stdout,
                    stderr: stderr,
                    markers: Self.notInstalledMarkers
                )
            {
                FileHandle.standardError.write(
                    Data(
                        ("Warning: marketplace removal failed unexpectedly: "
                            + stderr + "\n"
                            + "To clean up manually, run: " + removeCommand + "\n").utf8
                    )
                )
            }
        case .timedOut:
            FileHandle.standardError.write(
                Data(
                    ("Warning: marketplace removal timed out after "
                        + "\(Int(Self.claudeCommandTimeoutSeconds)) seconds.\n"
                        + "To clean up manually, run: " + removeCommand + "\n").utf8
                )
            )
        case .launchFailed(let message):
            FileHandle.standardError.write(
                Data(
                    ("Warning: marketplace removal could not be launched: "
                        + message + "\n").utf8
                )
            )
        }
    }
}

/// Default shell runner implementation for install commands.
struct DefaultInstallShellRunner: InstallShellRunnerProtocol {
    func run(command: String, options: InstallShellOptions) -> InstallShellOutcome {
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

        do {
            try process.run()

            if let timeout = options.timeout {
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { [weak process] in
                    guard let process, process.isRunning else { return }
                    let pid = process.processIdentifier
                    state.markTimedOut()
                    process.terminate()

                    let escalation = DispatchSource.makeTimerSource(queue: .global())
                    escalation.schedule(deadline: .now() + 5)
                    escalation.setEventHandler { [weak process] in
                        guard let process, process.isRunning else { return }
                        // BFS the whole descendant tree (children,
                        // grandchildren, askpass/ssh helpers) and SIGKILL
                        // each — direct-child enumeration alone misses the
                        // grandchildren that hold the pipe write ends open.
                        Self.killDescendantsRecursive(of: pid)
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
            state.takeKillEscalationTimer()?.cancel()

            // Tear down readability handlers BEFORE draining so a late-firing
            // dispatch event can't race the explicit `read()` in drainPipe on
            // the same FD. With handlers cleared, drainPipe is the sole
            // reader of any data still buffered in the pipe.
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            // Close write ends so any orphaned grandchildren that inherited
            // the pipes don't keep `read()` blocked when we drain. Failure
            // here is load-bearing — if close fails, drainPipe could block —
            // so log instead of silently swallowing.
            Self.closeOrLog(stdoutPipe.fileHandleForWriting, label: "stdout pipe write end")
            Self.closeOrLog(stderrPipe.fileHandleForWriting, label: "stderr pipe write end")

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

            let snapshot = state.snapshot()

            // `markTimedOut` is only invoked from the timer handler, and the
            // handler bails out early when `process.isRunning == false` — so
            // the flag means "we observed a still-running process at the
            // deadline and signalled it." The parent's actual termination
            // reason can vary (uncaughtSignal if SIGTERM/SIGKILL hit it
            // directly, exit if bash propagated a child's death code), but
            // either way the user's command was forcibly cut short.
            if snapshot.timedOut {
                return .timedOut(
                    stdout: decode(snapshot.stdout),
                    stderr: decode(snapshot.stderr)
                )
            }

            return .exited(
                status: process.terminationStatus,
                stdout: decode(snapshot.stdout).trimmingCharacters(in: .whitespacesAndNewlines),
                stderr: decode(snapshot.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            timeoutTimer?.cancel()
            state.takeKillEscalationTimer()?.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return .launchFailed(
                message: "Failed to launch '/bin/bash -c \(command)': \(error.localizedDescription)"
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

    /// Close a `FileHandle` and log the failure to stderr if it can't close.
    /// The pipe-write-end close is load-bearing — if it fails, drainPipe could
    /// block forever on an orphaned grandchild — so silent failure here would
    /// mask the exact bug class this runner exists to prevent.
    fileprivate static func closeOrLog(_ handle: FileHandle, label: String) {
        do {
            try handle.close()
        } catch {
            FileHandle.standardError.write(
                Data(
                    ("Warning: failed to close \(label): "
                        + error.localizedDescription + "\n").utf8
                )
            )
        }
    }

    /// Recursive descendant walk via `pgrep -P` BFS. Kills the whole
    /// descendant tree before SIGKILL'ing the root, so orphaned grandchildren
    /// (git, askpass, ssh) release the pipe write ends and let drainPipe
    /// return. Foundation does not expose a way to put the child in its own
    /// process group, so we cannot use the simpler `kill(-pgid, SIGKILL)`.
    /// Best-effort — if `pgrep` is unavailable, the caller's drain still
    /// makes progress thanks to `O_NONBLOCK`.
    fileprivate static func killDescendantsRecursive(of root: pid_t) {
        var frontier: [pid_t] = [root]
        var visited: Set<pid_t> = [root]
        while !frontier.isEmpty {
            var nextFrontier: [pid_t] = []
            for parent in frontier {
                let children = directChildren(of: parent)
                for child in children where !visited.contains(child) {
                    visited.insert(child)
                    nextFrontier.append(child)
                }
            }
            for pid in nextFrontier {
                kill(pid, SIGKILL)
            }
            frontier = nextFrontier
        }
    }

    /// Enumerate direct children of `parent` via `pgrep -P`. Failures (missing
    /// pgrep, non-zero exit, decode error) surface to stderr — silent failure
    /// here means orphaned grandchildren remain holding pipe write-ends and
    /// the user has no diagnostic trail.
    fileprivate static func directChildren(of parent: pid_t) -> [pid_t] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/bin/bash")
        pgrep.arguments = ["-c", "pgrep -P \(parent) || true"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        pgrep.standardOutput = outPipe
        pgrep.standardError = errPipe
        do {
            try pgrep.run()
        } catch {
            FileHandle.standardError.write(
                Data(
                    ("Warning: could not enumerate descendants of pid "
                        + "\(parent): " + error.localizedDescription + "\n").utf8
                )
            )
            return []
        }
        // Drain stderr eagerly so pgrep can't block on a full stderr buffer.
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        if pgrep.terminationStatus != 0 && pgrep.terminationStatus != 1 {
            // pgrep exits 1 on no-matches (treated as success here); any
            // other non-zero is unexpected (binary missing, signal, etc.).
            let errMessage = String(data: errData, encoding: .utf8) ?? ""
            FileHandle.standardError.write(
                Data(
                    ("Warning: pgrep -P \(parent) exited "
                        + "\(pgrep.terminationStatus): " + errMessage + "\n").utf8
                )
            )
            return []
        }
        guard let listing = String(data: outData, encoding: .utf8) else { return [] }
        var pids: [pid_t] = []
        for line in listing.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = pid_t(trimmed) {
                pids.append(pid)
            }
        }
        return pids
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
