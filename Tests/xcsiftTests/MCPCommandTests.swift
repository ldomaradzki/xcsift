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

    /// Shared flags are declared once, on the root command's option group, because the root
    /// consumes its own options wherever they appear — a re-declared `--warnings` would read false.
    func testSharedFlagsReachTheSubcommand() throws {
        let command = try parse(["--warnings", "--format", "toon"])

        XCTAssertTrue(command.sifting.warnings)
        XCTAssertEqual(command.sifting.format, .toon)
    }
}
