import Foundation
import XCTest

@testable import xcsift

/// Guards the plugin files that xcsift ships to Claude Code, Cursor, and Codex.
///
/// Each fact below lives in more than one file, and the copies must agree: the hook decision logic
/// sits in the Cursor template plus two scripts in `plugins/`, and the plugin version sits in three
/// manifests. These tests read every copy, so a partial edit fails instead of shipping.
final class PluginFilesTests: XCTestCase {

    private struct Hook {
        let name: String
        let path: String
        /// The JSON key that the hook uses when it rewrites the command.
        let rewriteKey: String
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let rewrittenCommands = [
        "xcodebuild build",
        "xcodebuild test -scheme App",
        "swift build",
        "swift test --filter FooTests",
        "cd App && xcodebuild build",
    ]

    private static let passedThroughCommands = [
        "xcodebuild -version",
        "xcodebuild -list -json",
        "xcodebuild -showBuildSettings -json",
        "xcodebuild -project app.xcodeproj -scheme app -showTestPlans -json",
        "xcodebuild -showsdks",
        "swift build --show-bin-path",
        "swift test --help",
        "swift package resolve",
        "xcodebuild build 2>&1 | xcsift -f toon",
        "xcodebuild build > log.txt",
        "xcodebuild-foo build",
        "git commit -m \"fix xcodebuild build flags\"",
    ]

    private var sandbox: URL!
    private var searchPath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()

        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcsift-hook-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        // The hooks pass every command through when xcsift is absent from PATH.
        let stub = sandbox.appendingPathComponent("xcsift")
        try "#!/bin/sh\nexit 0\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        searchPath = "\(sandbox.path):\(inherited)"
    }

    override func tearDownWithError() throws {
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func testBuildCommandsAreRewritten() throws {
        for hook in try hooks() {
            for command in Self.rewrittenCommands {
                let rewritten = try rewrittenCommand(from: hook, command: command)
                XCTAssertEqual(
                    rewritten,
                    "{ \(command) ; } 2>&1 | xcsift -f toon",
                    "\(hook.name) rewrote '\(command)' incorrectly"
                )
            }
        }
    }

    func testInformationalAndRedirectedCommandsPassThrough() throws {
        for hook in try hooks() {
            for command in Self.passedThroughCommands {
                let rewritten = try rewrittenCommand(from: hook, command: command)
                XCTAssertNil(
                    rewritten,
                    "\(hook.name) must not rewrite '\(command)'"
                )
            }
        }
    }

    func testCursorTemplateMatchesCheckedInScript() throws {
        let checkedIn = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("plugins/cursor/hooks/pre-xcsift.sh"),
            encoding: .utf8
        )

        XCTAssertEqual(
            CursorTemplates.hookScript,
            checkedIn.trimmingCharacters(in: .newlines),
            "CursorTemplates.hookScript and plugins/cursor/hooks/pre-xcsift.sh must stay equal"
        )
    }

    func testPluginVersionsAgree() throws {
        let manifest = try json(at: "plugins/claude-code/.claude-plugin/plugin.json")
        let marketplace = try json(at: ".claude-plugin/marketplace.json")
        let plugins = try XCTUnwrap(marketplace["plugins"] as? [[String: Any]])

        let skill = try String(
            contentsOf: Self.repoRoot
                .appendingPathComponent("plugins/claude-code/skills/xcsift/SKILL.md"),
            encoding: .utf8
        )
        let skillVersion = skill.split(separator: "\n")
            .first { $0.hasPrefix("version:") }?
            .dropFirst("version:".count)
            .trimmingCharacters(in: .whitespaces)

        let expected = try XCTUnwrap(manifest["version"] as? String)
        XCTAssertEqual(
            plugins.first?["version"] as? String,
            expected,
            "marketplace.json must carry the plugin.json version"
        )
        XCTAssertEqual(
            skillVersion,
            expected,
            "The Claude Code SKILL.md must carry the plugin.json version"
        )
    }

    private func json(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent(relativePath))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Helpers

    private func hooks() throws -> [Hook] {
        guard Self.isOnPath("jq") else {
            throw XCTSkip("The hook scripts require jq")
        }

        let template = sandbox.appendingPathComponent("cursor-template.sh")
        try CursorTemplates.hookScript.write(to: template, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: template.path)

        return [
            Hook(
                name: "CursorTemplates.hookScript",
                path: template.path,
                rewriteKey: "updated_input"
            ),
            Hook(
                name: "plugins/cursor/hooks/pre-xcsift.sh",
                path: Self.repoRoot.appendingPathComponent("plugins/cursor/hooks/pre-xcsift.sh")
                    .path,
                rewriteKey: "updated_input"
            ),
            Hook(
                name: "plugins/claude-code/scripts/pre-xcsift.sh",
                path: Self.repoRoot
                    .appendingPathComponent("plugins/claude-code/scripts/pre-xcsift.sh").path,
                rewriteKey: "updatedInput"
            ),
        ]
    }

    /// Returns the command that the hook substitutes, or nil when the hook passes the command on.
    private func rewrittenCommand(from hook: Hook, command: String) throws -> String? {
        let payload = try JSONSerialization.data(withJSONObject: ["tool_input": ["command": command]])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [hook.path]
        process.environment = ["PATH": searchPath]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        input.fileHandleForWriting.write(payload)
        input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("\(hook.name) produced no JSON for '\(command)'")
            return nil
        }
        return Self.command(in: root, under: hook.rewriteKey)
    }

    private static func command(in object: [String: Any], under key: String) -> String? {
        if let rewrite = object[key] as? [String: Any] {
            return rewrite["command"] as? String
        }
        for value in object.values {
            if let child = value as? [String: Any],
                let found = command(in: child, under: key)
            {
                return found
            }
        }
        return nil
    }

    private static func isOnPath(_ tool: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { directory in
            FileManager.default.isExecutableFile(atPath: "\(directory)/\(tool)")
        }
    }
}
