import Foundation
import XCTest

@testable import xcsift

// MARK: - Mock Shell Runner for Testing

/// Mock shell runner for testing ClaudeCodeInstaller
final class MockInstallShellRunner: InstallShellRunnerProtocol {
    var commandHistory: [String] = []
    var mockResults: [String: InstallShellResult] = [:]
    var defaultResult = InstallShellResult(exitCode: 0, stdout: "", stderr: "")

    func run(command: String) -> InstallShellResult {
        commandHistory.append(command)
        return mockResults[command] ?? defaultResult
    }
}

// MARK: - Mock File Manager for Testing

/// Mock file manager for testing file operations
final class MockInstallFileManager: FileManager {
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

    // MARK: - Templates

    func testProjectHooksJSONTemplate() {
        let template = CursorTemplates.projectHooksJSON

        XCTAssertTrue(template.contains("\"version\": 1"))
        XCTAssertTrue(template.contains("beforeShellExecution"))
        XCTAssertTrue(template.contains("./.cursor/hooks/pre-xcsift.sh"))
    }

    func testGlobalHooksJSONTemplate() {
        let template = CursorTemplates.globalHooksJSON

        XCTAssertTrue(template.contains("\"version\": 1"))
        XCTAssertTrue(template.contains("beforeShellExecution"))
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
        XCTAssertTrue(template.contains("updatedCommand"))
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
            ClaudeCodeInstallerError.pluginInstallFailed(stderr: "install error").description,
            "Failed to install plugin: install error"
        )

        XCTAssertEqual(
            ClaudeCodeInstallerError.pluginUninstallFailed(stderr: "uninstall error").description,
            "Failed to uninstall plugin: uninstall error"
        )
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
