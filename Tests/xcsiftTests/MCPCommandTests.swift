import ArgumentParser
import Foundation
import XCTest

@testable import xcsift

/// The `xcsift mcp` command surface: what a user types, and what they get told when it is wrong.
final class MCPCommandTests: XCTestCase {

    private func parse(_ arguments: [String]) throws -> MCPProxyCommand {
        try MCPProxyCommand.parse(arguments)
    }

    private func snippetArgs(_ arguments: [String], upstream: [String] = MCPDefaults.upstream) throws -> [String] {
        let command = try parse(arguments)
        let snippet = command.clientConfigurationSnippet(for: upstream)
        let args = try XCTUnwrap(
            JSONValue.parse(Data(snippet.utf8))?["mcpServers"]?["xcode"]?["args"]?.arrayValue
        )
        return args.compactMap(\.stringValue)
    }

    // MARK: - Configuration snippet

    func testSnippetDefaultsToXcodesOwnServer() throws {
        XCTAssertEqual(try snippetArgs(["--print-config"]), ["mcp", "--", "xcrun", "mcpbridge"])
    }

    func testSnippetIsValidJSON() throws {
        let snippet = try parse(["--print-config"]).clientConfigurationSnippet(for: MCPDefaults.upstream)
        let parsed = try XCTUnwrap(JSONValue.parse(Data(snippet.utf8)))

        XCTAssertNotNil(parsed["mcpServers"]?["xcode"]?["command"]?.stringValue)
    }

    /// A user who composes a command and then asks for the snippet must get that same command back,
    /// not a subset that behaves differently.
    func testSnippetReproducesEveryOptionThatChangesBehaviour() throws {
        let args = try snippetArgs([
            "--format", "toon",
            "--warnings",
            "--Werror",
            "--build-info",
            "--executable",
            "--slow-threshold", "1.5",
            "--xcbeautify",
            "--toon-delimiter", "pipe",
            "--toon-key-folding", "safe",
            "--toon-flatten-depth", "3",
            "--on-summary", "replace",
            "--min-raw-lines", "5",
            "--max-log-size", "8",
            "--no-inject-tools",
            "--print-config",
        ])

        for expected in [
            "--format", "toon", "--warnings", "--Werror", "--build-info", "--executable",
            "--slow-threshold", "--xcbeautify", "--toon-delimiter", "pipe", "--toon-key-folding",
            "safe", "--toon-flatten-depth", "3", "--on-summary", "replace", "--min-raw-lines", "5",
            "--max-log-size", "8", "--no-inject-tools",
        ] {
            XCTAssertTrue(args.contains(expected), "snippet is missing \(expected)")
        }
    }

    /// Values reach the snippet as JSON strings, so a quote or a backslash in a pattern must not
    /// produce a configuration the client cannot parse.
    func testSnippetEscapesAwkwardValues() throws {
        let args = try snippetArgs(["--build-tool-pattern", #"build|te"st\d"#, "--print-config"])
        XCTAssertTrue(args.contains(#"build|te"st\d"#))
    }

    func testSnippetCarriesTheUpstreamCommandLast() throws {
        let args = try snippetArgs(["--print-config"], upstream: ["/usr/local/bin/my-mcp", "serve"])
        XCTAssertEqual(args.suffix(3), ["--", "/usr/local/bin/my-mcp", "serve"])
    }

    /// ArgumentParser eats the first `--`; a second one is a value, and it is the user's separator
    /// rather than an argument for the server.
    func testASecondTerminatorIsNotPassedToTheServer() throws {
        let command = try parse(["--print-config", "--", "--", "xcrun", "mcpbridge"])

        XCTAssertEqual(command.upstream, ["--", "xcrun", "mcpbridge"], "the parser hands over the extra terminator")
        XCTAssertEqual(
            try snippetArgs(["--print-config"], upstream: ["xcrun", "mcpbridge"]),
            ["mcp", "--", "xcrun", "mcpbridge"]
        )
    }

    // MARK: - Validation

    func testRejectsAnInvalidBuildToolPattern() {
        XCTAssertThrowsError(try parse(["--build-tool-pattern", "(build"])) { error in
            XCTAssertTrue(
                "\(error)".contains("--build-tool-pattern"),
                "the message must name the flag, got: \(error)"
            )
        }
    }

    func testRejectsNonsenseLimits() {
        XCTAssertThrowsError(try parse(["--min-raw-lines", "0"]))
        XCTAssertThrowsError(try parse(["--max-log-size", "0"]))
        // Large enough to overflow the megabyte multiplication if it were not bounded.
        XCTAssertThrowsError(try parse(["--max-log-size", "99999999999999"]))
    }

    func testAcceptsLimitsAtTheEdges() throws {
        XCTAssertEqual(try parse(["--min-raw-lines", "1"]).minRawLines, 1)
        XCTAssertEqual(try parse(["--max-log-size", "4096"]).maxLogSize, 4096)
    }

    /// `github-actions` is for CI annotations. It can arrive from a project's config file as well
    /// as from the flag, so the refusal says both.
    func testRefusesGitHubActionsFormatFromAConfigFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcsift-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = directory.appendingPathComponent("config.toml")
        try #"format = "github-actions""#.write(to: config, atomically: true, encoding: .utf8)

        let command = try parse(["--config", config.path, "--print-config"])
        XCTAssertThrowsError(try command.run()) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("github-actions"), message)
            XCTAssertTrue(message.contains(".xcsift.toml"), "the message should name the config file: \(message)")
        }
    }

    func testInjectToolsFlagHasAPositiveDefaultAndANegation() throws {
        XCTAssertTrue(try parse([]).injectTools)
        XCTAssertFalse(try parse(["--no-inject-tools"]).injectTools)
        XCTAssertTrue(try parse(["--inject-tools"]).injectTools)
    }

    // MARK: - Registration flags

    func testRefusesTwoCommandsAtOnce() {
        XCTAssertThrowsError(try parse(["--install", "--uninstall"]))
        XCTAssertThrowsError(try parse(["--install", "--print-config"]))
    }

    func testRejectsAScopeClaudeCodeDoesNotHave() {
        XCTAssertThrowsError(try parse(["--install", "--scope", "global"])) { error in
            XCTAssertTrue("\(error)".contains("--scope"), "\(error)")
        }
        XCTAssertNoThrow(try parse(["--install", "--scope", "user"]))
    }

    func testRejectsAnEmptyServerName() {
        XCTAssertThrowsError(try parse(["--uninstall", "--server-name", ""]))
    }

    /// A registration must run what the snippet promises, so both come from one argument list.
    func testRegistrationCarriesTheSameArgumentsAsTheSnippet() throws {
        let command = try parse(["--install", "--format", "toon", "--on-summary", "replace"])
        XCTAssertEqual(
            command.proxyArguments(for: MCPDefaults.upstream),
            ["mcp", "--format", "toon", "--on-summary", "replace", "--", "xcrun", "mcpbridge"]
        )
    }

    /// Shared flags are declared once, on the root command's option group, because the root
    /// consumes its own options wherever they appear — a re-declared `--warnings` would read false.
    func testSharedFlagsReachTheSubcommand() throws {
        let command = try parse(["--warnings", "--format", "toon"])

        XCTAssertTrue(command.sifting.warnings)
        XCTAssertEqual(command.sifting.format, .toon)
    }
}

// MARK: - Registering the proxy with Claude Code

final class MCPServerInstallerTests: XCTestCase {

    private func makeInstaller(_ runner: MockInstallShellRunner) -> MCPServerInstaller {
        MCPServerInstaller(shellRunner: runner)
    }

    private func addCommand(in runner: MockInstallShellRunner) -> String? {
        runner.commandHistory.first { $0.hasPrefix("claude mcp add") }
    }

    func testRegistersTheProxyAsAStdioServer() throws {
        let runner = MockInstallShellRunner()
        try makeInstaller(runner).install(
            name: "xcode",
            scope: "user",
            command: "/usr/local/bin/xcsift",
            arguments: ["mcp", "--format", "toon", "--", "xcrun", "mcpbridge"],
            force: false
        )

        XCTAssertEqual(
            addCommand(in: runner),
            "claude mcp add --scope 'user' --transport stdio 'xcode' -- '/usr/local/bin/xcsift' "
                + "'mcp' '--format' 'toon' '--' 'xcrun' 'mcpbridge'"
        )
    }

    func testOmitsTheScopeWhenNoneWasAsked() throws {
        let runner = MockInstallShellRunner()
        try makeInstaller(runner).install(
            name: "xcode",
            scope: nil,
            command: "xcsift",
            arguments: ["mcp"],
            force: false
        )

        XCTAssertEqual(addCommand(in: runner), "claude mcp add --transport stdio 'xcode' -- 'xcsift' 'mcp'")
    }

    /// `--build-tool-pattern` is a regular expression, and it reaches `/bin/bash -c` as text.
    func testQuotesArgumentsTheShellWouldOtherwiseActOn() throws {
        let runner = MockInstallShellRunner()
        try makeInstaller(runner).install(
            name: "xcode",
            scope: nil,
            command: "xcsift",
            arguments: ["mcp", "--build-tool-pattern", #"(build|test) 'x'"#],
            force: false
        )

        let command = try XCTUnwrap(addCommand(in: runner))
        XCTAssertTrue(command.hasSuffix(#"'--build-tool-pattern' '(build|test) '\''x'\'''"#), command)
    }

    func testSaysWhenTheNameIsTaken() {
        let runner = MockInstallShellRunner()
        runner.setExited("which claude")
        runner.defaultOutcome = .exited(status: 1, stdout: "", stderr: "A server named xcode already exists")

        XCTAssertThrowsError(
            try makeInstaller(runner).install(
                name: "xcode",
                scope: nil,
                command: "xcsift",
                arguments: ["mcp"],
                force: false
            )
        ) { error in
            XCTAssertTrue("\(error)".contains("--force"), "the way out should be in the message: \(error)")
        }
    }

    /// Re-registering has to take the old entry out first: `claude mcp add` refuses an existing
    /// name, and an entry left behind would keep the agent on the old flags.
    func testForceReplacesTheExistingRegistration() throws {
        let runner = MockInstallShellRunner()
        try makeInstaller(runner).install(
            name: "xcode",
            scope: nil,
            command: "xcsift",
            arguments: ["mcp"],
            force: true
        )

        let claudeCommands = runner.commandHistory.filter { $0.hasPrefix("claude mcp") }
        XCTAssertEqual(claudeCommands.first, "claude mcp remove 'xcode'")
        XCTAssertTrue(try XCTUnwrap(claudeCommands.last).hasPrefix("claude mcp add"))
    }

    func testRemovesTheRegistration() throws {
        let runner = MockInstallShellRunner()
        XCTAssertTrue(try makeInstaller(runner).remove(name: "xcode", scope: "user"))
        XCTAssertTrue(runner.commandHistory.contains("claude mcp remove --scope 'user' 'xcode'"))
    }

    /// Removing what was never registered leaves the end state that was asked for, so it is
    /// reported rather than thrown — a user tidying up should not have to care which it was.
    func testRemovingSomethingUnregisteredIsNotAFailure() throws {
        let runner = MockInstallShellRunner()
        runner.setExited("claude mcp remove 'xcode'", status: 1, stderr: #"No MCP server named "xcode"."#)

        XCTAssertFalse(try makeInstaller(runner).remove(name: "xcode", scope: nil))
    }

    func testReportsARemovalThatFailedForAnotherReason() {
        let runner = MockInstallShellRunner()
        runner.setExited("claude mcp remove 'xcode'", status: 1, stderr: "config file is read-only")

        XCTAssertThrowsError(try makeInstaller(runner).remove(name: "xcode", scope: nil)) { error in
            XCTAssertTrue("\(error)".contains("read-only"), "\(error)")
        }
    }

    func testNeedsTheClaudeCLI() {
        let runner = MockInstallShellRunner()
        runner.setExited("which claude", status: 1)

        XCTAssertThrowsError(try makeInstaller(runner).remove(name: "xcode", scope: nil)) { error in
            XCTAssertTrue("\(error)".contains("Claude Code"), "\(error)")
        }
    }
}
