import Foundation

/// Registers `xcsift mcp` with Claude Code, and takes the registration back out.
///
/// The proxy is configuration rather than an installed artefact: what there is to remove is one
/// `mcpServers` entry pointing at this binary. Going through `claude mcp add` / `claude mcp remove`
/// instead of editing JSON leaves the file format Claude Code's business, and means the entry a
/// user added by hand — the `claude mcp add --transport stdio xcode -- xcsift mcp` the README
/// documents — is removed by the same command.
struct MCPServerInstaller {

    enum Failure: Error, CustomStringConvertible {
        case claudeCLINotFound
        case alreadyRegistered(name: String)
        case addFailed(name: String, stderr: String)
        case removeFailed(name: String, stderr: String)
        case timedOut(command: String, seconds: Int)
        case launchFailed(command: String, message: String)

        var description: String {
            switch self {
            case .claudeCLINotFound:
                return "Claude CLI not found. Please install Claude Code first: https://claude.ai/download"
            case let .alreadyRegistered(name):
                return """
                    An MCP server named '\(name)' is already registered. Re-register it with \
                    --force, remove it with `xcsift mcp --uninstall`, or pick another name with \
                    --server-name.
                    """
            case let .addFailed(name, stderr):
                return "Failed to register '\(name)' with Claude Code: \(stderr)"
            case let .removeFailed(name, stderr):
                return "Failed to remove '\(name)' from Claude Code: \(stderr)"
            case let .timedOut(command, seconds):
                return "`\(command)` did not finish within \(seconds) seconds."
            case let .launchFailed(command, message):
                return "Failed to run `\(command)`: \(message)"
            }
        }
    }

    /// The name Xcode's own server is conventionally registered under, so replacing the bridge
    /// with the proxy is the same entry rather than a second one the agent also sees.
    static let defaultServerName = "xcode"

    static let commandTimeoutSeconds: TimeInterval = 60

    /// Phrases the `claude` CLI uses for the two idempotent no-ops this command can hit.
    private static let alreadyExistsMarkers = ["already exists", "already configured"]
    /// `claude mcp remove` answers a name it does not know with `No MCP server named "x".`
    private static let notFoundMarkers = [
        "no mcp server named", "no mcp server found", "not found", "does not exist",
    ]

    let shellRunner: InstallShellRunnerProtocol

    init(shellRunner: InstallShellRunnerProtocol = DefaultInstallShellRunner()) {
        self.shellRunner = shellRunner
    }

    /// - Returns: the `claude` command that was run, so the caller can show what it did.
    @discardableResult
    func install(
        name: String,
        scope: String?,
        command: String,
        arguments: [String],
        force: Bool
    ) throws -> String {
        guard isClaudeCLIAvailable() else { throw Failure.claudeCLINotFound }

        // Re-registering is a remove and an add: `claude mcp add` refuses an existing name, and
        // silently leaving the old entry in place would keep the agent on the old flags.
        if force { _ = try? remove(name: name, scope: scope) }

        var parts = ["claude", "mcp", "add"]
        if let scope { parts += ["--scope", Self.quoted(scope)] }
        parts += ["--transport", "stdio", Self.quoted(name), "--", Self.quoted(command)]
        parts += arguments.map(Self.quoted)
        let addCommand = parts.joined(separator: " ")

        switch run(addCommand) {
        case let .exited(status, stdout, stderr):
            guard status != 0 else { return addCommand }
            if Self.matches(stdout: stdout, stderr: stderr, markers: Self.alreadyExistsMarkers) {
                throw Failure.alreadyRegistered(name: name)
            }
            throw Failure.addFailed(name: name, stderr: Self.reason(stdout: stdout, stderr: stderr))
        case .timedOut:
            throw Failure.timedOut(command: addCommand, seconds: Int(Self.commandTimeoutSeconds))
        case let .launchFailed(message):
            throw Failure.launchFailed(command: addCommand, message: message)
        }
    }

    /// - Returns: whether an entry was actually removed. Removing what was never registered is
    ///   not a failure — the end state is the one that was asked for.
    @discardableResult
    func remove(name: String, scope: String?) throws -> Bool {
        guard isClaudeCLIAvailable() else { throw Failure.claudeCLINotFound }

        var parts = ["claude", "mcp", "remove"]
        // With no scope, `claude mcp remove` takes the entry out of whichever scope holds it —
        // which is what someone removing a proxy they configured some time ago wants.
        if let scope { parts += ["--scope", Self.quoted(scope)] }
        parts.append(Self.quoted(name))
        let removeCommand = parts.joined(separator: " ")

        switch run(removeCommand) {
        case let .exited(status, stdout, stderr):
            if status == 0 { return true }
            if Self.matches(stdout: stdout, stderr: stderr, markers: Self.notFoundMarkers) { return false }
            throw Failure.removeFailed(name: name, stderr: Self.reason(stdout: stdout, stderr: stderr))
        case .timedOut:
            throw Failure.timedOut(command: removeCommand, seconds: Int(Self.commandTimeoutSeconds))
        case let .launchFailed(message):
            throw Failure.launchFailed(command: removeCommand, message: message)
        }
    }

    func isClaudeCLIAvailable() -> Bool {
        guard case let .exited(status, _, _) = run("which claude") else { return false }
        return status == 0
    }

    private func run(_ command: String) -> InstallShellOutcome {
        shellRunner.run(command: command, options: InstallShellOptions(timeout: Self.commandTimeoutSeconds))
    }

    /// Everything handed to `/bin/bash -c` is quoted: `--build-tool-pattern` is a regular
    /// expression, and a `|` or a space in one would otherwise be the shell's to act on.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static func matches(stdout: String, stderr: String, markers: [String]) -> Bool {
        let combined = (stdout + "\n" + stderr).lowercased()
        return markers.contains { combined.contains($0) }
    }

    /// The CLI reports some failures on stdout, so an empty stderr must not become an empty reason.
    private static func reason(stdout: String, stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? stdout.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }
}
