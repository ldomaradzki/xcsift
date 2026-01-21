import ArgumentParser
import Foundation

// MARK: - Stderr Helper

/// Thread-safe wrapper for writing to stderr
private func writeToStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

// MARK: - Claude Code Commands

struct InstallClaudeCode: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-claude-code",
        abstract: "Install xcsift plugin for Claude Code",
        discussion: """
            Installs the xcsift plugin for Claude Code via the marketplace.

            This command runs:
              1. claude plugin marketplace add ldomaradzki/xcsift
              2. claude plugin install xcsift

            Requirements:
              - Claude Code CLI must be installed
              - Internet connection to access GitHub marketplace

            After installation, xcodebuild and swift build commands will
            automatically be piped through xcsift for structured output.
            """
    )

    func run() throws {
        let installer = ClaudeCodeInstaller()

        do {
            try installer.install()
            print("Successfully installed xcsift plugin for Claude Code")
            print("Build commands will now be automatically formatted with xcsift")
        } catch let error as ClaudeCodeInstallerError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }
    }
}

struct UninstallClaudeCode: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-claude-code",
        abstract: "Uninstall xcsift plugin from Claude Code",
        discussion: """
            Removes the xcsift plugin from Claude Code.

            This command runs:
              1. claude plugin uninstall xcsift
              2. claude plugin marketplace remove ldomaradzki/xcsift

            Requirements:
              - Claude Code CLI must be installed
            """
    )

    func run() throws {
        let installer = ClaudeCodeInstaller()

        do {
            try installer.uninstall()
            print("Successfully uninstalled xcsift plugin from Claude Code")
        } catch let error as ClaudeCodeInstallerError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }
    }
}

// MARK: - Codex Commands

struct InstallCodex: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-codex",
        abstract: "Install xcsift skill for OpenAI Codex CLI",
        discussion: """
            Installs the xcsift skill file for OpenAI Codex CLI.

            Target: ~/.codex/skills/xcsift/SKILL.md

            Note: Codex does not support hooks. The skill provides instructions
            that guide the AI to manually apply the xcsift pattern when running
            build commands.

            Use --force to overwrite an existing installation.
            """
    )

    @Flag(name: .long, help: "Overwrite existing installation")
    var force: Bool = false

    func run() throws {
        let installer = CodexInstaller()

        do {
            try installer.install(force: force)
            print("Successfully installed xcsift skill for Codex")
            print("Location: \(CodexInstaller.skillFilePath)")
        } catch let error as CodexInstallerError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }
    }
}

struct UninstallCodex: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-codex",
        abstract: "Uninstall xcsift skill from OpenAI Codex CLI",
        discussion: """
            Removes the xcsift skill from OpenAI Codex CLI.

            Removes: ~/.codex/skills/xcsift/
            """
    )

    func run() throws {
        let installer = CodexInstaller()

        do {
            try installer.uninstall()
            print("Successfully uninstalled xcsift skill from Codex")
        } catch let error as CodexInstallerError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }
    }
}

// MARK: - Cursor Commands

struct InstallCursor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-cursor",
        abstract: "Install xcsift hooks for Cursor",
        discussion: """
            Installs xcsift hooks for Cursor editor.

            By default, installs to the current project (.cursor/).
            Use --global to install to ~/.cursor/ for all projects.

            Files created:
              - hooks.json (hook configuration)
              - hooks/pre-xcsift.sh (hook script)

            Use --force to overwrite existing installation.
            """
    )

    @Flag(name: .long, help: "Install globally to ~/.cursor/ instead of .cursor/")
    var global: Bool = false

    @Flag(name: .long, help: "Overwrite existing installation")
    var force: Bool = false

    func run() throws {
        let installer = CursorInstaller(global: global)

        do {
            try installer.install(force: force)
            let location = global ? "~/.cursor/" : ".cursor/"
            print("Successfully installed xcsift hooks for Cursor")
            print("Location: \(location)")
            print("Build commands will now be automatically formatted with xcsift")
        } catch let error as CursorInstallerError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }
    }
}

struct UninstallCursor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall-cursor",
        abstract: "Uninstall xcsift hooks from Cursor",
        discussion: """
            Removes xcsift hooks from Cursor editor.

            By default, removes from the current project (.cursor/).
            Use --global to remove from ~/.cursor/.
            """
    )

    @Flag(name: .long, help: "Uninstall from ~/.cursor/ instead of .cursor/")
    var global: Bool = false

    func run() throws {
        let installer = CursorInstaller(global: global)

        do {
            try installer.uninstall()
            let location = global ? "~/.cursor/" : ".cursor/"
            print("Successfully uninstalled xcsift hooks from Cursor (\(location))")
        } catch let error as CursorInstallerError {
            writeToStderr("Error: \(error.description)\n")
            throw ExitCode.failure
        }
    }
}
