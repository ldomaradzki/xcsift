import Foundation
import XCTest

final class ExitOnFailureEndToEndTests: XCTestCase {
    func testCompletedSkippedRunExitsSuccessfully() throws {
        let input = """
            ➜ Test "requires service" (aka 'requiresService()') skipped.
            ✔ Test run with 1 test passed after 0.001 seconds.
            """

        let output = try runXCSift(input: input)

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.json["status"] as? String, "success")
        XCTAssertEqual((output.json["summary"] as? [String: Any])?["passed_tests"] as? Int, 0)
        XCTAssertTrue(output.stderr.isEmpty)
    }

    func testTruncatedSkippedRunExitsWithFailure() throws {
        let output = try runXCSift(input: "➜ Test requiresService() skipped.")

        XCTAssertEqual(output.exitCode, 1)
        XCTAssertEqual(output.json["status"] as? String, "incomplete")
        XCTAssertTrue(output.stderr.contains("incomplete"))
    }

    func testFailureMentioningSkippedTestsExitsWithFailureAndKeepsLocation() throws {
        let input = """
            ✘ Test foo() recorded an issue at Tests.swift:42:5: "2 tests skipped."
            ✘ Test foo() failed after 0.001 seconds with 1 issue.
            ✘ Test run with 1 test failed after 0.001 seconds with 1 issue.
            """

        let output = try runXCSift(input: input)

        XCTAssertEqual(output.exitCode, 1)
        XCTAssertEqual(output.json["status"] as? String, "failed")
        let failure = try XCTUnwrap((output.json["failed_tests"] as? [[String: Any]])?.first)
        XCTAssertEqual(failure["file"] as? String, "Tests.swift")
        XCTAssertEqual(failure["line"] as? Int, 42)
        XCTAssertEqual(failure["message"] as? String, "\"2 tests skipped.\"")
    }

    private func runXCSift(input: String) throws -> (exitCode: Int32, json: [String: Any], stderr: String) {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".toml")
        try Data().write(to: config)
        defer { try? FileManager.default.removeItem(at: config) }

        let process = Process()
        process.executableURL = Self.executable
        process.arguments = ["-E", "--format", "json", "--config", config.path]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "GITHUB_ACTIONS")
        process.environment = environment
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [String: Any]),
            String(decoding: errorOutput, as: UTF8.self)
        )
    }

    private static var executable: URL {
        #if os(macOS)
            for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
                return bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("xcsift")
            }
        #endif
        return Bundle.main.bundleURL.appendingPathComponent("xcsift")
    }
}
