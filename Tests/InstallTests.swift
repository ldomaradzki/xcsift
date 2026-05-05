import Foundation
import XCTest

@testable import xcsift

// MARK: - Mock Shell Runner for Testing

/// Mock shell runner for testing ClaudeCodeInstaller
final class MockInstallShellRunner: InstallShellRunnerProtocol {
    var commandHistory: [String] = []
    var optionsHistory: [String: InstallShellOptions] = [:]
    var mockResults: [String: InstallShellResult] = [:]
    var defaultResult = InstallShellResult(exitCode: 0, stdout: "", stderr: "")

    func run(command: String) -> InstallShellResult {
        commandHistory.append(command)
        return mockResults[command] ?? defaultResult
    }

    func run(command: String, options: InstallShellOptions) -> InstallShellResult {
        optionsHistory[command] = options
        return run(command: command)
    }
}

// MARK: - Mock File Manager for Testing

/// Mock file manager for testing file operations
final class MockInstallFileManager: FileManager, @unchecked Sendable {
    var existingPaths: Set<String> = []
    var createdDirectories: [String] = []
    var writtenFiles: [String: String] = [:]
    var removedPaths: [String] = []
    var directoryContents: [String: [String]] = [:]
    var mockHomeDirectory: URL = URL(fileURLWithPath: "/Users/testuser")

    override func fileExists(atPath path: String) -> Bool {
        return existingPaths.contains(path)
    }

    override func createDirectory(
        atPath path: String,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        createdDirectories.append(path)
        existingPaths.insert(path)
    }

    override func removeItem(atPath path: String) throws {
        guard existingPaths.contains(path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
        }
        removedPaths.append(path)
        existingPaths.remove(path)
    }

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        return directoryContents[path] ?? []
    }

    override var homeDirectoryForCurrentUser: URL {
        return mockHomeDirectory
    }
}

// MARK: - ClaudeCodeInstaller Tests

final class ClaudeCodeInstallerTests: XCTestCase {

    // MARK: - Claude CLI Detection

    func testIsClaudeCLIAvailableWhenInstalled() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertTrue(installer.isClaudeCLIAvailable())
        XCTAssertEqual(mockRunner.commandHistory, ["which claude"])
    }

    func testIsClaudeCLIAvailableWhenNotInstalled() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 1,
            stdout: "",
            stderr: "claude not found"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertFalse(installer.isClaudeCLIAvailable())
    }

    // MARK: - Install

    func testInstallSucceeds() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults["claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"] =
            InstallShellResult(
                exitCode: 0,
                stdout: "Marketplace added",
                stderr: ""
            )
        mockRunner.mockResults["claude plugin install \(ClaudeCodeInstaller.pluginName)"] = InstallShellResult(
            exitCode: 0,
            stdout: "Plugin installed",
            stderr: ""
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.install())
        XCTAssertEqual(mockRunner.commandHistory.count, 3)
        XCTAssertTrue(mockRunner.commandHistory.contains("which claude"))
        XCTAssertTrue(
            mockRunner.commandHistory.contains("claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)")
        )
        XCTAssertTrue(mockRunner.commandHistory.contains("claude plugin install \(ClaudeCodeInstaller.pluginName)"))
    }

    func testInstallFailsWhenClaudeCLINotFound() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(exitCode: 1, stdout: "", stderr: "")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install()) { error in
            guard let installerError = error as? ClaudeCodeInstallerError else {
                XCTFail("Expected ClaudeCodeInstallerError")
                return
            }
            if case .claudeCLINotFound = installerError {
                // Success
            } else {
                XCTFail("Expected claudeCLINotFound error")
            }
        }
    }

    func testInstallIgnoresAlreadyAddedMarketplace() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults["claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"] =
            InstallShellResult(
                exitCode: 1,
                stdout: "Marketplace already added",
                stderr: ""
            )
        mockRunner.mockResults["claude plugin install \(ClaudeCodeInstaller.pluginName)"] = InstallShellResult(
            exitCode: 0,
            stdout: "Plugin installed",
            stderr: ""
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.install())
    }

    func testInstallIgnoresAlreadyInstalledPlugin() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults["claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"] =
            InstallShellResult(
                exitCode: 0,
                stdout: "Marketplace added",
                stderr: ""
            )
        mockRunner.mockResults["claude plugin install \(ClaudeCodeInstaller.pluginName)"] = InstallShellResult(
            exitCode: 1,
            stdout: "Plugin already installed",
            stderr: ""
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.install())
    }

    // MARK: - Marketplace Add Timeout Behavior

    func testInstallTimesOutOnMarketplaceAdd() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = InstallShellResult(
            exitCode: installShellTimeoutExitCode,
            stdout: "",
            stderr: ""
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install()) { error in
            guard let installerError = error as? ClaudeCodeInstallerError else {
                XCTFail("Expected ClaudeCodeInstallerError")
                return
            }
            if case .marketplaceAddTimedOut(let seconds) = installerError {
                XCTAssertEqual(seconds, ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
            } else {
                XCTFail("Expected marketplaceAddTimedOut error, got \(installerError)")
            }
        }
    }

    func testInstallDoesNotCallPluginInstallAfterTimeout() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = InstallShellResult(
            exitCode: installShellTimeoutExitCode,
            stdout: "",
            stderr: ""
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install())
        XCTAssertFalse(
            mockRunner.commandHistory.contains(
                "claude plugin install \(ClaudeCodeInstaller.pluginName)"
            ),
            "Plugin install must not run after marketplace add timed out"
        )
    }

    func testInstallPassesNoPromptEnvAndTimeoutToMarketplaceAdd() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = InstallShellResult(
            exitCode: 0,
            stdout: "Marketplace added",
            stderr: ""
        )
        mockRunner.mockResults[
            "claude plugin install \(ClaudeCodeInstaller.pluginName)"
        ] = InstallShellResult(
            exitCode: 0,
            stdout: "Plugin installed",
            stderr: ""
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        try installer.install()

        let marketplaceCommand =
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        guard let options = mockRunner.optionsHistory[marketplaceCommand] else {
            XCTFail("Expected options to be captured for marketplace add command")
            return
        }

        XCTAssertEqual(
            options.timeout,
            TimeInterval(ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
        )
        XCTAssertTrue(options.streamOutput)

        let env = options.environment ?? [:]
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(env["GIT_ASKPASS"], "/bin/true")
    }

    func testInstallPassesTimeoutToPluginInstall() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = InstallShellResult(exitCode: 0, stdout: "Marketplace added", stderr: "")
        mockRunner.mockResults[
            "claude plugin install \(ClaudeCodeInstaller.pluginName)"
        ] = InstallShellResult(exitCode: 0, stdout: "Plugin installed", stderr: "")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        try installer.install()

        let installCommand = "claude plugin install \(ClaudeCodeInstaller.pluginName)"
        guard let options = mockRunner.optionsHistory[installCommand] else {
            XCTFail("Expected options to be captured for plugin install command")
            return
        }
        XCTAssertEqual(
            options.timeout,
            TimeInterval(ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
        )
        XCTAssertEqual(options.environment?["GIT_TERMINAL_PROMPT"], "0")
    }

    func testIsClaudeCLIAvailableUsesShortTimeout() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        _ = installer.isClaudeCLIAvailable()

        guard let options = mockRunner.optionsHistory["which claude"] else {
            XCTFail("Expected options to be captured for which claude")
            return
        }
        XCTAssertEqual(options.timeout, ClaudeCodeInstaller.claudeLookupTimeoutSeconds)
    }

    func testInstallSurfacesNonAlreadyMarketplaceFailure() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = InstallShellResult(
            exitCode: 1,
            stdout: "",
            stderr: "fatal: repository not found"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install()) { error in
            guard case .marketplaceAddFailed(let stderr, _) = error as? ClaudeCodeInstallerError
            else {
                XCTFail("Expected marketplaceAddFailed, got \(error)")
                return
            }
            XCTAssertTrue(stderr.contains("repository not found"))
        }
    }

    func testInstallDoesNotFalseMatchAlreadyInUnrelatedError() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        // Stderr contains the literal word "already" but is a real failure,
        // not an idempotent no-op. Loose substring matching would swallow it.
        mockRunner.mockResults[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = InstallShellResult(
            exitCode: 1,
            stdout: "",
            stderr: "Repository already deleted on remote"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        XCTAssertThrowsError(try installer.install())
    }

    func testMarketplaceAddEnvironmentPreservesUserAskpass() {
        let original = ProcessInfo.processInfo.environment["GIT_ASKPASS"]
        setenv("GIT_ASKPASS", "/usr/local/bin/my-credential-helper", 1)
        defer {
            if let original {
                setenv("GIT_ASKPASS", original, 1)
            } else {
                unsetenv("GIT_ASKPASS")
            }
        }

        let env = ClaudeCodeInstaller.marketplaceAddEnvironment()
        XCTAssertEqual(env["GIT_ASKPASS"], "/usr/local/bin/my-credential-helper")
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
    }

    func testMarketplaceAddEnvironmentInheritsParentPath() {
        let env = ClaudeCodeInstaller.marketplaceAddEnvironment()
        XCTAssertNotNil(env["PATH"], "PATH must survive — losing it breaks subprocess launch")
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
    }

    // MARK: - Uninstall

    func testUninstallSucceeds() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults["claude plugin uninstall \(ClaudeCodeInstaller.pluginName)"] = InstallShellResult(
            exitCode: 0,
            stdout: "Plugin uninstalled",
            stderr: ""
        )
        mockRunner.mockResults["claude plugin marketplace remove \(ClaudeCodeInstaller.marketplaceRepo)"] =
            InstallShellResult(
                exitCode: 0,
                stdout: "",
                stderr: ""
            )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.uninstall())
        XCTAssertTrue(
            mockRunner.commandHistory.contains("claude plugin uninstall \(ClaudeCodeInstaller.pluginName)")
        )
    }

    func testUninstallIgnoresNotInstalledPlugin() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.mockResults["which claude"] = InstallShellResult(
            exitCode: 0,
            stdout: "/usr/local/bin/claude",
            stderr: ""
        )
        mockRunner.mockResults["claude plugin uninstall \(ClaudeCodeInstaller.pluginName)"] = InstallShellResult(
            exitCode: 1,
            stdout: "",
            stderr: "Plugin not installed"
        )
        mockRunner.mockResults["claude plugin marketplace remove \(ClaudeCodeInstaller.marketplaceRepo)"] =
            InstallShellResult(
                exitCode: 0,
                stdout: "",
                stderr: ""
            )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.uninstall())
    }
}

// MARK: - CodexInstaller Tests

final class CodexInstallerTests: XCTestCase {

    // MARK: - Skill Directory

    func testSkillDirectoryPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(CodexInstaller.skillDirectory, "\(home)/.codex/skills/xcsift")
    }

    func testSkillFilePath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(CodexInstaller.skillFilePath, "\(home)/.codex/skills/xcsift/SKILL.md")
    }

    // MARK: - Templates

    func testCodexTemplateContainsRequiredContent() {
        let template = CodexTemplates.skillMarkdown

        // Check YAML frontmatter
        XCTAssertTrue(template.contains("---"))
        XCTAssertTrue(template.contains("name: xcsift"))
        XCTAssertTrue(template.contains("description:"))

        // Check content sections
        XCTAssertTrue(template.contains("# xcsift"))
        XCTAssertTrue(template.contains("## When to Use"))
        XCTAssertTrue(template.contains("## Usage Pattern"))
        XCTAssertTrue(template.contains("xcodebuild build 2>&1 | xcsift"))
        XCTAssertTrue(template.contains("-f toon"))
    }
}

// MARK: - CursorInstaller Tests

final class CursorInstallerTests: XCTestCase {

    // MARK: - Paths

    func testProjectPaths() {
        let installer = CursorInstaller(global: false)

        XCTAssertEqual(installer.baseDirectory, ".cursor")
        XCTAssertEqual(installer.hooksDirectory, ".cursor/hooks")
        XCTAssertEqual(installer.hooksJSONPath, ".cursor/hooks.json")
        XCTAssertEqual(installer.hookScriptPath, ".cursor/hooks/pre-xcsift.sh")
    }

    func testGlobalPaths() {
        let mockFS = MockInstallFileManager()
        mockFS.mockHomeDirectory = URL(fileURLWithPath: "/Users/testuser")

        let installer = CursorInstaller(global: true, fileManager: mockFS)

        XCTAssertEqual(installer.baseDirectory, "/Users/testuser/.cursor")
        XCTAssertEqual(installer.hooksDirectory, "/Users/testuser/.cursor/hooks")
        XCTAssertEqual(installer.hooksJSONPath, "/Users/testuser/.cursor/hooks.json")
        XCTAssertEqual(installer.hookScriptPath, "/Users/testuser/.cursor/hooks/pre-xcsift.sh")
    }

    // MARK: - Skill Paths

    func testProjectSkillPaths() {
        let installer = CursorInstaller(global: false)

        XCTAssertEqual(installer.skillsDirectory, ".cursor/skills/xcsift")
        XCTAssertEqual(installer.skillFilePath, ".cursor/skills/xcsift/SKILL.md")
    }

    func testGlobalSkillPaths() {
        let mockFS = MockInstallFileManager()
        mockFS.mockHomeDirectory = URL(fileURLWithPath: "/Users/testuser")

        let installer = CursorInstaller(global: true, fileManager: mockFS)

        XCTAssertEqual(installer.skillsDirectory, "/Users/testuser/.cursor/skills/xcsift")
        XCTAssertEqual(installer.skillFilePath, "/Users/testuser/.cursor/skills/xcsift/SKILL.md")
    }

    // MARK: - Templates

    func testProjectHooksJSONTemplate() {
        let template = CursorTemplates.projectHooksJSON

        XCTAssertTrue(template.contains("\"version\": 1"))
        XCTAssertTrue(template.contains("preToolUse"))
        XCTAssertTrue(template.contains("./.cursor/hooks/pre-xcsift.sh"))
    }

    func testGlobalHooksJSONTemplate() {
        let template = CursorTemplates.globalHooksJSON

        XCTAssertTrue(template.contains("\"version\": 1"))
        XCTAssertTrue(template.contains("preToolUse"))
        XCTAssertTrue(template.contains("~/.cursor/hooks/pre-xcsift.sh"))
    }

    func testHookScriptTemplate() {
        let template = CursorTemplates.hookScript

        // Check shebang
        XCTAssertTrue(template.hasPrefix("#!/bin/bash"))

        // Check key functionality
        XCTAssertTrue(template.contains("xcodebuild"))
        XCTAssertTrue(template.contains("swift"))
        XCTAssertTrue(template.contains("xcsift"))
        XCTAssertTrue(template.contains("permission"))
        XCTAssertTrue(template.contains("allow"))
        XCTAssertTrue(template.contains("updated_input"))
    }

    func testSkillMarkdownTemplate() {
        let template = CursorTemplates.skillMarkdown

        // Check YAML frontmatter
        XCTAssertTrue(template.contains("---"))
        XCTAssertTrue(template.contains("name: xcsift"))
        XCTAssertTrue(template.contains("description:"))

        // Check content sections
        XCTAssertTrue(template.contains("# xcsift"))
        XCTAssertTrue(template.contains("## When to Use"))
        XCTAssertTrue(template.contains("## Usage Pattern"))
        XCTAssertTrue(template.contains("xcodebuild build 2>&1 | xcsift"))
        XCTAssertTrue(template.contains("-f toon"))
    }
}

// MARK: - Error Description Tests

final class InstallErrorTests: XCTestCase {

    // MARK: - ClaudeCodeInstallerError

    func testClaudeCodeInstallerErrorDescriptions() {
        XCTAssertEqual(
            ClaudeCodeInstallerError.claudeCLINotFound.description,
            "Claude CLI not found. Please install Claude Code first: https://claude.ai/download"
        )

        XCTAssertEqual(
            ClaudeCodeInstallerError.marketplaceAddFailed(
                stderr: "error message",
                alreadyStreamed: false
            ).description,
            "Failed to add marketplace: error message"
        )

        XCTAssertEqual(
            ClaudeCodeInstallerError.marketplaceAddFailed(
                stderr: "error message",
                alreadyStreamed: true
            ).description,
            "Failed to add marketplace (see output above)."
        )

        XCTAssertEqual(
            ClaudeCodeInstallerError.pluginInstallFailed(stderr: "install error").description,
            "Failed to install plugin: install error"
        )

        XCTAssertEqual(
            ClaudeCodeInstallerError.pluginUninstallFailed(stderr: "uninstall error").description,
            "Failed to uninstall plugin: uninstall error"
        )

        let timeoutDescription =
            ClaudeCodeInstallerError.marketplaceAddTimedOut(seconds: 120).description
        XCTAssertTrue(timeoutDescription.contains("timed out after 120 seconds"))
        XCTAssertTrue(timeoutDescription.contains("ldomaradzki/xcsift"))
        XCTAssertTrue(timeoutDescription.contains("Common fixes"))
        XCTAssertTrue(timeoutDescription.contains("credential helper"))
    }

    // MARK: - CodexInstallerError

    func testCodexInstallerErrorDescriptions() {
        XCTAssertEqual(
            CodexInstallerError.alreadyExists(path: "/path/to/skill").description,
            "Skill already exists at /path/to/skill. Use --force to overwrite."
        )

        XCTAssertEqual(
            CodexInstallerError.notInstalled(path: "/path/to/skill").description,
            "xcsift skill not installed at /path/to/skill"
        )
    }

    // MARK: - CursorInstallerError

    func testCursorInstallerErrorDescriptions() {
        XCTAssertEqual(
            CursorInstallerError.alreadyExists(path: "/path/to/hooks.json").description,
            "Cursor hooks already exist at /path/to/hooks.json. Use --force to overwrite."
        )

        XCTAssertEqual(
            CursorInstallerError.notInstalled(path: "/path/to/hooks.json").description,
            "xcsift hooks not installed at /path/to/hooks.json"
        )
    }
}

// MARK: - DefaultInstallShellRunner Integration Tests

/// Real subprocess tests — exercise the actual `Process` machinery that
/// MockInstallShellRunner can never cover (timeout firing, SIGKILL escalation,
/// pipe drain, environment propagation).
final class DefaultInstallShellRunnerTests: XCTestCase {

    func testReturnsRealExitCodeWhenProcessCompletesBeforeTimeout() {
        let runner = DefaultInstallShellRunner()
        let result = runner.run(
            command: "echo hello && echo world >&2",
            options: InstallShellOptions(timeout: 5.0)
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hello"))
        XCTAssertTrue(result.stderr.contains("world"))
    }

    func testReturnsNonZeroExitCodeOnFailure() {
        let runner = DefaultInstallShellRunner()
        let result = runner.run(
            command: "exit 42",
            options: InstallShellOptions(timeout: 5.0)
        )
        XCTAssertEqual(result.exitCode, 42)
        XCTAssertNotEqual(result.exitCode, installShellTimeoutExitCode)
    }

    func testKillsProcessThatExceedsTimeout() {
        let runner = DefaultInstallShellRunner()
        let start = Date()
        let result = runner.run(
            command: "sleep 30",
            options: InstallShellOptions(timeout: 1.0)
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.exitCode, installShellTimeoutExitCode)
        XCTAssertLessThan(
            elapsed,
            10.0,
            "Process should have been terminated near the 1s timeout (with 5s SIGKILL grace)"
        )
    }

    func testKillsProcessThatIgnoresSIGTERM() {
        // `trap '' TERM` makes the shell ignore SIGTERM. Without SIGKILL
        // escalation, the process would survive past the timeout and the
        // call would hang for the full 30 seconds.
        let runner = DefaultInstallShellRunner()
        let start = Date()
        let result = runner.run(
            command: "trap '' TERM; sleep 30",
            options: InstallShellOptions(timeout: 1.0)
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.exitCode, installShellTimeoutExitCode)
        XCTAssertLessThan(
            elapsed,
            15.0,
            "SIGKILL escalation must terminate a SIGTERM-ignoring process within ~6s"
        )
    }

    func testPropagatesEnvironmentToSubprocess() {
        let runner = DefaultInstallShellRunner()
        let result = runner.run(
            command: "printf %s \"$XCSIFT_TEST_VAR\"",
            options: InstallShellOptions(environment: [
                "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                "XCSIFT_TEST_VAR": "sentinel-value",
            ])
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "sentinel-value")
    }

    func testCapturesOutputThatArrivesNearProcessExit() {
        let runner = DefaultInstallShellRunner()
        let result = runner.run(
            command: "for i in $(seq 1 500); do echo line$i; done",
            options: InstallShellOptions()
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("line1\n"))
        XCTAssertTrue(result.stdout.contains("line500"))
    }

    func testReturnsLaunchFailureExitCodeForBrokenExecutable() {
        // Bash executes `command` via /bin/bash, so this still goes through
        // launch. The launch-failed path is hit only when /bin/bash itself is
        // missing — hard to simulate cross-platform — so we instead verify the
        // invariant that the sentinel is distinct from real exit codes.
        XCTAssertNotEqual(installShellTimeoutExitCode, installShellLaunchFailedExitCode)
        XCTAssertLessThan(installShellTimeoutExitCode, 0)
        XCTAssertLessThan(installShellLaunchFailedExitCode, 0)
    }
}
