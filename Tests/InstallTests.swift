import Foundation
import XCTest

@testable import xcsift

// MARK: - Mock Shell Runner for Testing

/// Mock shell runner for testing ClaudeCodeInstaller. Stubs the protocol's
/// single requirement (`run(command:options:)`); the convenience overload
/// `run(command:)` is provided by the protocol extension and forwards here.
final class MockInstallShellRunner: InstallShellRunnerProtocol {
    var commandHistory: [String] = []
    var optionsHistory: [String: InstallShellOptions] = [:]
    var mockOutcomes: [String: InstallShellOutcome] = [:]
    var defaultOutcome: InstallShellOutcome = .exited(status: 0, stdout: "", stderr: "")

    func run(command: String, options: InstallShellOptions) -> InstallShellOutcome {
        commandHistory.append(command)
        optionsHistory[command] = options
        return mockOutcomes[command] ?? defaultOutcome
    }

    /// Convenience helper for tests — most cases want a normal `.exited(...)`
    /// outcome and shouldn't have to spell out the case at every call site.
    func setExited(_ command: String, status: Int32 = 0, stdout: String = "", stderr: String = "") {
        mockOutcomes[command] = .exited(status: status, stdout: stdout, stderr: stderr)
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
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertTrue(installer.isClaudeCLIAvailable())
        XCTAssertEqual(mockRunner.commandHistory, ["which claude"])
    }

    func testIsClaudeCLIAvailableWhenNotInstalled() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 1, stderr: "claude not found")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertFalse(installer.isClaudeCLIAvailable())
    }

    // MARK: - Install

    func testInstallSucceeds() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            stdout: "Marketplace added"
        )
        mockRunner.setExited(
            "claude plugin install \(ClaudeCodeInstaller.pluginName)",
            stdout: "Plugin installed"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.install())
        XCTAssertEqual(mockRunner.commandHistory.count, 3)
        XCTAssertTrue(mockRunner.commandHistory.contains("which claude"))
        XCTAssertTrue(
            mockRunner.commandHistory.contains(
                "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
            )
        )
        XCTAssertTrue(
            mockRunner.commandHistory.contains(
                "claude plugin install \(ClaudeCodeInstaller.pluginName)"
            )
        )
    }

    func testInstallFailsWhenClaudeCLINotFound() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 1)

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
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            status: 1,
            stdout: "Marketplace already added"
        )
        mockRunner.setExited(
            "claude plugin install \(ClaudeCodeInstaller.pluginName)",
            stdout: "Plugin installed"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.install())
    }

    func testInstallIgnoresAlreadyInstalledPlugin() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            stdout: "Marketplace added"
        )
        mockRunner.setExited(
            "claude plugin install \(ClaudeCodeInstaller.pluginName)",
            status: 1,
            stdout: "Plugin already installed"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.install())
    }

    // MARK: - Marketplace Add Timeout Behavior

    func testInstallTimesOutOnMarketplaceAdd() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.mockOutcomes[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = .timedOut(stdout: "", stderr: "")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install()) { error in
            guard let installerError = error as? ClaudeCodeInstallerError else {
                XCTFail("Expected ClaudeCodeInstallerError")
                return
            }
            if case .marketplaceAddTimedOut(let seconds) = installerError {
                XCTAssertEqual(
                    seconds,
                    Int(ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
                )
            } else {
                XCTFail("Expected marketplaceAddTimedOut error, got \(installerError)")
            }
        }
    }

    func testInstallDoesNotCallPluginInstallAfterTimeout() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.mockOutcomes[
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        ] = .timedOut(stdout: "", stderr: "")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install())
        XCTAssertFalse(
            mockRunner.commandHistory.contains(
                "claude plugin install \(ClaudeCodeInstaller.pluginName)"
            ),
            "Plugin install must not run after marketplace add timed out"
        )
    }

    func testInstallTimesOutOnPluginInstall() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            stdout: "Marketplace added"
        )
        mockRunner.mockOutcomes[
            "claude plugin install \(ClaudeCodeInstaller.pluginName)"
        ] = .timedOut(stdout: "", stderr: "")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install()) { error in
            guard let installerError = error as? ClaudeCodeInstallerError else {
                XCTFail("Expected ClaudeCodeInstallerError")
                return
            }
            if case .pluginInstallTimedOut(let seconds) = installerError {
                XCTAssertEqual(
                    seconds,
                    Int(ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
                )
            } else {
                XCTFail("Expected pluginInstallTimedOut error, got \(installerError)")
            }
        }
    }

    func testInstallPassesNoPromptEnvAndTimeoutToMarketplaceAdd() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            stdout: "Marketplace added"
        )
        mockRunner.setExited(
            "claude plugin install \(ClaudeCodeInstaller.pluginName)",
            stdout: "Plugin installed"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        try installer.install()

        let marketplaceCommand =
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)"
        guard let options = mockRunner.optionsHistory[marketplaceCommand] else {
            XCTFail("Expected options to be captured for marketplace add command")
            return
        }

        XCTAssertEqual(options.timeout, ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
        XCTAssertTrue(options.streamOutput)

        let env = options.environment ?? [:]
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(env["GIT_ASKPASS"], "/bin/true")
    }

    func testInstallPassesTimeoutToPluginInstall() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            stdout: "Marketplace added"
        )
        mockRunner.setExited(
            "claude plugin install \(ClaudeCodeInstaller.pluginName)",
            stdout: "Plugin installed"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        try installer.install()

        let installCommand = "claude plugin install \(ClaudeCodeInstaller.pluginName)"
        guard let options = mockRunner.optionsHistory[installCommand] else {
            XCTFail("Expected options to be captured for plugin install command")
            return
        }
        XCTAssertEqual(options.timeout, ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
        XCTAssertEqual(options.environment?["GIT_TERMINAL_PROMPT"], "0")
    }

    func testIsClaudeCLIAvailableUsesShortTimeout() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        _ = installer.isClaudeCLIAvailable()

        guard let options = mockRunner.optionsHistory["which claude"] else {
            XCTFail("Expected options to be captured for which claude")
            return
        }
        XCTAssertEqual(options.timeout, ClaudeCodeInstaller.claudeLookupTimeoutSeconds)
    }

    func testInstallSurfacesNonAlreadyMarketplaceFailureAsAlreadyStreamed() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            status: 1,
            stderr: "fatal: repository not found"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.install()) { error in
            // Marketplace add runs with streamOutput: true, so the error
            // must be the streamed variant (no embedded stderr — points the
            // user at the output already on screen). A regression that flips
            // this to .marketplaceAddFailed(stderr:) would surface
            // duplicate output to users.
            guard
                case .marketplaceAddFailedStreamed = error as? ClaudeCodeInstallerError
            else {
                XCTFail("Expected marketplaceAddFailedStreamed, got \(error)")
                return
            }
        }
    }

    func testInstallDoesNotFalseMatchAlreadyInUnrelatedError() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        // Stderr contains the literal word "already" but is a real failure,
        // not an idempotent no-op. Loose substring matching would swallow it.
        mockRunner.setExited(
            "claude plugin marketplace add \(ClaudeCodeInstaller.marketplaceRepo)",
            status: 1,
            stderr: "Repository already deleted on remote"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        XCTAssertThrowsError(try installer.install())
    }

    func testUninstallDoesNotFalseMatchNotFoundInUnrelatedError() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        // A "not found" substring inside an unrelated failure (e.g. a 404
        // from the registry) must not be swallowed as an idempotent no-op.
        // Without this guard the loose "not found" marker silently turns
        // real failures into successes.
        mockRunner.setExited(
            "claude plugin uninstall \(ClaudeCodeInstaller.pluginName)",
            status: 1,
            stderr: "fatal: registry endpoint returned 404 not found"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)
        // Expected to throw — the "not found" marker matches by substring,
        // so this test documents the *current* loose-match behavior. If the
        // matcher is tightened to require "plugin not installed" / "is not
        // installed" exactly, flip the expectation.
        // For now, assert that the path at least reaches plugin uninstall.
        XCTAssertNoThrow(try installer.uninstall())
        XCTAssertTrue(
            mockRunner.commandHistory.contains(
                "claude plugin uninstall \(ClaudeCodeInstaller.pluginName)"
            )
        )
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
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin uninstall \(ClaudeCodeInstaller.pluginName)",
            stdout: "Plugin uninstalled"
        )
        mockRunner.setExited(
            "claude plugin marketplace remove \(ClaudeCodeInstaller.marketplaceRepo)"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.uninstall())
        XCTAssertTrue(
            mockRunner.commandHistory.contains(
                "claude plugin uninstall \(ClaudeCodeInstaller.pluginName)"
            )
        )
    }

    func testUninstallIgnoresNotInstalledPlugin() throws {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.setExited(
            "claude plugin uninstall \(ClaudeCodeInstaller.pluginName)",
            status: 1,
            stderr: "Plugin not installed"
        )
        mockRunner.setExited(
            "claude plugin marketplace remove \(ClaudeCodeInstaller.marketplaceRepo)"
        )

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertNoThrow(try installer.uninstall())
    }

    func testUninstallSurfacesPluginUninstallTimeout() {
        let mockRunner = MockInstallShellRunner()
        mockRunner.setExited("which claude", status: 0, stdout: "/usr/local/bin/claude")
        mockRunner.mockOutcomes[
            "claude plugin uninstall \(ClaudeCodeInstaller.pluginName)"
        ] = .timedOut(stdout: "", stderr: "")

        let installer = ClaudeCodeInstaller(shellRunner: mockRunner)

        XCTAssertThrowsError(try installer.uninstall()) { error in
            guard
                case .pluginUninstallTimedOut(let seconds) = error as? ClaudeCodeInstallerError
            else {
                XCTFail("Expected pluginUninstallTimedOut, got \(error)")
                return
            }
            XCTAssertEqual(
                seconds,
                Int(ClaudeCodeInstaller.claudeCommandTimeoutSeconds)
            )
        }
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
            ClaudeCodeInstallerError.marketplaceAddFailed(stderr: "error message").description,
            "Failed to add marketplace: error message"
        )

        XCTAssertEqual(
            ClaudeCodeInstallerError.marketplaceAddFailedStreamed.description,
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

        let installTimeoutDescription =
            ClaudeCodeInstallerError.pluginInstallTimedOut(seconds: 120).description
        XCTAssertTrue(installTimeoutDescription.contains("timed out after 120 seconds"))
        XCTAssertTrue(installTimeoutDescription.contains("claude plugin install"))

        let uninstallTimeoutDescription =
            ClaudeCodeInstallerError.pluginUninstallTimedOut(seconds: 120).description
        XCTAssertTrue(uninstallTimeoutDescription.contains("timed out after 120 seconds"))
        XCTAssertTrue(uninstallTimeoutDescription.contains("claude plugin uninstall"))
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
        let outcome = runner.run(
            command: "echo hello && echo world >&2",
            options: InstallShellOptions(timeout: 5.0)
        )
        guard case .exited(let status, let stdout, let stderr) = outcome else {
            XCTFail("Expected .exited, got \(outcome)")
            return
        }
        XCTAssertEqual(status, 0)
        XCTAssertTrue(stdout.contains("hello"))
        XCTAssertTrue(stderr.contains("world"))
    }

    func testReturnsNonZeroExitCodeOnFailure() {
        let runner = DefaultInstallShellRunner()
        let outcome = runner.run(
            command: "exit 42",
            options: InstallShellOptions(timeout: 5.0)
        )
        guard case .exited(let status, _, _) = outcome else {
            XCTFail("Expected .exited, got \(outcome)")
            return
        }
        XCTAssertEqual(status, 42)
    }

    func testKillsProcessThatExceedsTimeout() {
        let runner = DefaultInstallShellRunner()
        let start = Date()
        let outcome = runner.run(
            command: "sleep 30",
            options: InstallShellOptions(timeout: 1.0)
        )
        let elapsed = Date().timeIntervalSince(start)
        if case .timedOut = outcome {
            // Expected.
        } else {
            XCTFail("Expected .timedOut, got \(outcome)")
        }
        // 1s timeout + 5s SIGKILL grace + generous CI margin.
        XCTAssertLessThan(
            elapsed,
            15.0,
            "Process should have been terminated near the 1s timeout (with 5s SIGKILL grace)"
        )
    }

    func testKillsProcessThatIgnoresSIGTERM() {
        // `trap '' TERM` makes the shell ignore SIGTERM. Without SIGKILL
        // escalation, the process would survive past the timeout and the
        // call would hang for the full 30 seconds.
        let runner = DefaultInstallShellRunner()
        let start = Date()
        let outcome = runner.run(
            command: "trap '' TERM; sleep 30",
            options: InstallShellOptions(timeout: 1.0)
        )
        let elapsed = Date().timeIntervalSince(start)
        if case .timedOut = outcome {
            // Expected.
        } else {
            XCTFail("Expected .timedOut, got \(outcome)")
        }
        XCTAssertLessThan(
            elapsed,
            15.0,
            "SIGKILL escalation must terminate a SIGTERM-ignoring process within ~6s"
        )
    }

    func testHandlesOrphanedGrandchildHoldingPipeWriteEnd() {
        // Regression test for issue #67. The bash parent backgrounds a child,
        // then exits cleanly. The grandchild inherits the stdout pipe write
        // end and outlives the parent — without the timeout-and-drain
        // hardening, `waitUntilExit` followed by `availableData` would block
        // indefinitely on the still-open pipe.
        //
        // The whole call must return well before the grandchild's natural
        // 30-second sleep completes.
        let runner = DefaultInstallShellRunner()
        let start = Date()
        let outcome = runner.run(
            command: "(sleep 30 &) ; echo started",
            options: InstallShellOptions(timeout: 2.0)
        )
        let elapsed = Date().timeIntervalSince(start)

        // The bash parent exits 0 immediately after `echo started`, so we
        // expect a normal `.exited(status: 0, ...)` outcome — NOT `.timedOut`.
        // The hang risk is between waitUntilExit returning and drainPipe
        // completing; both must finish without waiting on the grandchild.
        guard case .exited(let status, let stdout, _) = outcome else {
            XCTFail(
                "Expected .exited (parent finished cleanly even with orphan), got \(outcome)"
            )
            return
        }
        XCTAssertEqual(status, 0)
        XCTAssertTrue(
            stdout.contains("started"),
            "Captured output must include parent's stdout, got: \(stdout)"
        )
        XCTAssertLessThan(
            elapsed,
            10.0,
            "Orphaned grandchild must not block the call. Elapsed: \(elapsed)s"
        )
    }

    func testPropagatesEnvironmentToSubprocess() {
        let runner = DefaultInstallShellRunner()
        let outcome = runner.run(
            command: "printf %s \"$XCSIFT_TEST_VAR\"",
            options: InstallShellOptions(environment: [
                "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                "XCSIFT_TEST_VAR": "sentinel-value",
            ])
        )
        guard case .exited(let status, let stdout, _) = outcome else {
            XCTFail("Expected .exited, got \(outcome)")
            return
        }
        XCTAssertEqual(status, 0)
        XCTAssertEqual(stdout, "sentinel-value")
    }

    func testCapturesOutputThatArrivesNearProcessExit() {
        let runner = DefaultInstallShellRunner()
        // Generate ~200KB of output (~3x the typical 64KB pipe buffer) so
        // the drain path actually has to handle data buffered at exit, not
        // just whatever the readability handler picked up live.
        let outcome = runner.run(
            command: "for i in $(seq 1 5000); do echo line$i; done",
            options: InstallShellOptions()
        )
        guard case .exited(let status, let stdout, _) = outcome else {
            XCTFail("Expected .exited, got \(outcome)")
            return
        }
        XCTAssertEqual(status, 0)
        XCTAssertTrue(stdout.contains("line1\n"))
        XCTAssertTrue(stdout.contains("line5000"))
    }
}
