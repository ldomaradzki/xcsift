import Foundation
import XCTest

@testable import xcsift

/// Drives the built `xcsift mcp` binary against a canned MCP server, covering the parts unit tests
/// cannot reach: process launch, stdio framing across two real pipes, shutdown, and the stderr
/// diagnostics a user actually sees.
final class MCPProxyEndToEndTests: XCTestCase {

    func testProxiesInitializeListAndSiftsABuildResult() throws {
        let server = try CannedServer(
            responses: [
                #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","serverInfo":{"name":"canned","version":"1"}}}"#,
                #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"build_sim","description":"Build"}]}}"#,
                Self.toolResult(id: 3, text: MCPFixtures.failingBuild),
            ]
        )
        let proxy = try ProxyProcess(upstream: server.command, arguments: ["--warnings"])
        defer { proxy.terminate() }

        proxy.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let initialize = try proxy.receive()
        XCTAssertEqual(initialize["result"]?["serverInfo"]?["name"]?.stringValue, "canned")

        proxy.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#)
        let tools = try proxy.receive()["result"]?["tools"]?.arrayValue ?? []
        XCTAssertEqual(
            tools.compactMap { $0["name"]?.stringValue },
            ["build_sim", MCPProxySession.injectedToolName]
        )

        proxy.send(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"build_sim","arguments":{}}}"#)
        let result = try XCTUnwrap(try proxy.receive()["result"])
        let text = try XCTUnwrap(result["content"]?.arrayValue?.first?["text"]?.stringValue)

        XCTAssertEqual(MCPFixtures.field("status", of: text)?.stringValue, "failed")
        XCTAssertFalse(text.contains("CompileSwiftSources"), "build noise must not survive sifting")
        XCTAssertEqual(result["isError"]?.boolValue, true)

        XCTAssertEqual(proxy.finish(), 0, "closing the client stream must shut the proxy down cleanly")
    }

    /// A message too large to buffer is copied through in chunks, and the next message must stay in
    /// sync behind it. This is the framing resync path at its real 4 MiB threshold.
    func testStreamsAnOversizedMessageThroughAndStaysInSync() throws {
        let payload = String(repeating: "x", count: 4 * 1024 * 1024 + 256 * 1024)
        let server = try CannedServer(
            responses: [
                #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}"#,
                #"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"\#(payload)"}]}}"#,
                Self.toolResult(id: 3, text: MCPFixtures.failingBuild),
            ]
        )
        let proxy = try ProxyProcess(upstream: server.command, arguments: ["--verbose"])
        defer { proxy.terminate() }

        proxy.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        _ = try proxy.receive()

        proxy.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"screenshot","arguments":{}}}"#)
        let big = try proxy.receive(timeout: 60)
        XCTAssertEqual(big["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue?.count, payload.count)

        proxy.send(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"build_sim","arguments":{}}}"#)
        let sifted = try proxy.receive()
        let text = try XCTUnwrap(sifted["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertEqual(MCPFixtures.field("status", of: text)?.stringValue, "failed")
    }

    func testExitsWithFailureWhenTheUpstreamCannotBeLaunched() throws {
        let proxy = try ProxyProcess(upstream: ["/nonexistent/xcode-mcp"], arguments: [])
        defer { proxy.terminate() }

        XCTAssertNotEqual(proxy.finish(), 0)
        XCTAssertTrue(proxy.collectedErrorOutput().contains("not found"))
    }

    /// A server that exits without answering leaves the client with an empty stream. The proxy has
    /// to say so, or the failure is undiagnosable.
    func testReportsAServerThatNeverAnswers() throws {
        let proxy = try ProxyProcess(upstream: ["/usr/bin/true"], arguments: [])
        defer { proxy.terminate() }

        XCTAssertEqual(proxy.finish(), 0)
        XCTAssertTrue(
            proxy.collectedErrorOutput().contains("without sending a message"),
            "expected a diagnostic, got: \(proxy.collectedErrorOutput())"
        )
    }

    /// A server that ignores its closed stdin must not outlive the client that started it, and a
    /// server that also ignores SIGTERM must still be stopped.
    func testShutdownEscalatesToSIGKILL() throws {
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/bin/sh")
        server.arguments = ["-c", "trap '' TERM; while true; do sleep 1; done"]
        try server.run()

        MCPProxyRunner.shutdown(
            pid: server.processIdentifier,
            isFinished: { false },
            gracePeriod: 0.2,
            terminationPeriod: 0.5
        )
        server.waitUntilExit()

        XCTAssertEqual(server.terminationReason, .uncaughtSignal)
        XCTAssertEqual(server.terminationStatus, SIGKILL)
    }

    func testShutdownLetsAWellBehavedServerExitOnItsOwn() throws {
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/bin/sh")
        server.arguments = ["-c", "exit 0"]
        try server.run()

        // The server is reported finished at once, so nothing is signalled.
        MCPProxyRunner.shutdown(
            pid: server.processIdentifier,
            isFinished: { true },
            gracePeriod: 2,
            terminationPeriod: 0.5
        )
        server.waitUntilExit()

        XCTAssertEqual(server.terminationReason, .exit)
        XCTAssertEqual(server.terminationStatus, 0)
    }

    func testSilentServerDiagnosticExplainsXcodeSetup() {
        let message = MCPProxyRunner.silentServerDiagnostic(for: ["xcrun", "mcpbridge"], status: 1)

        XCTAssertTrue(message.contains("xcrun mcpbridge"))
        XCTAssertTrue(message.contains("Settings > Intelligence"))
        XCTAssertTrue(message.contains("sudo xcrun mcp-server enable"))
    }

    func testSilentServerDiagnosticStaysGenericForOtherServers() {
        let message = MCPProxyRunner.silentServerDiagnostic(for: ["/usr/local/bin/my-xcode-mcp", "serve"], status: 127)

        XCTAssertTrue(message.contains("status 127"))
        XCTAssertFalse(message.contains("Intelligence"))
    }

    private static func toolResult(id: Int, text: String) -> String {
        let encoded = String(decoding: JSONValue.string(text).serialized(), as: UTF8.self)
        return
            #"{"jsonrpc":"2.0","id":\#(id),"result":{"isError":true,"content":[{"type":"text","text":\#(encoded)}]}}"#
    }
}

// MARK: - Canned upstream server

/// A POSIX-shell MCP server that answers the Nth request with the Nth canned response.
private final class CannedServer {
    let command: [String]
    private let directory: URL

    init(responses: [String]) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcsift-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, response) in responses.enumerated() {
            try response.write(
                to: directory.appendingPathComponent("\(index + 1).json"),
                atomically: true,
                encoding: .utf8
            )
        }

        let script = directory.appendingPathComponent("server.sh")
        try """
        i=0
        while IFS= read -r line; do
          i=$((i + 1))
          f="\(directory.path)/$i.json"
          if [ -s "$f" ]; then
            cat "$f"
            echo
          fi
        done
        """.write(to: script, atomically: true, encoding: .utf8)

        command = ["/bin/sh", script.path]
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Proxy under test

private final class ProxyProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let reader: MessageReader
    private let errorReader: MessageReader

    init(upstream: [String], arguments: [String]) throws {
        process.executableURL = Self.executable
        process.arguments = ["mcp"] + arguments + ["--"] + upstream
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        reader = MessageReader(handle: output.fileHandleForReading)
        errorReader = MessageReader(handle: errorOutput.fileHandleForReading, retainingEverything: true)
        try process.run()
    }

    func send(_ message: String) {
        input.fileHandleForWriting.write(Data((message + "\n").utf8))
    }

    /// A proxy that stops answering is the failure this test exists to catch, so a timeout fails
    /// rather than skips.
    func receive(timeout: TimeInterval = 15) throws -> JSONValue {
        guard let line = reader.next(timeout: timeout) else {
            let state = process.isRunning ? "still running" : "gone (status \(process.terminationStatus))"
            XCTFail(
                "the proxy produced no message within \(timeout)s: \(reader.bytesSeen) bytes arrived "
                    + "without a newline, the proxy is \(state), stderr: \(collectedErrorOutput())"
            )
            throw ProxyFailure.noMessage
        }
        guard let value = JSONValue.parse(Data(line.utf8)) else {
            throw ProxyFailure.notJSON(String(line.prefix(200)))
        }
        return value
    }

    func collectedErrorOutput() -> String {
        errorReader.drained()
    }

    /// Waits for the proxy to exit, with a deadline: a shutdown deadlock must fail the test rather
    /// than hang the job.
    func finish(timeout: TimeInterval = 20) -> Int32 {
        try? input.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            XCTFail("the proxy did not exit within \(timeout)s; stderr: \(collectedErrorOutput())")
            process.terminate()
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    private enum ProxyFailure: Error {
        case noMessage
        case notJSON(String)
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

/// Collects newline-delimited messages from a pipe so tests can wait on them with a deadline.
///
/// Only the bytes appended since the last search are scanned for a newline: a pipe hands over small
/// chunks, and re-scanning the whole buffer each time made a multi-megabyte message take half a
/// minute on CI.
private final class MessageReader: @unchecked Sendable {
    private let condition = NSCondition()
    private let retainsEverything: Bool
    private var lines: [String] = []
    private var buffer = Data()
    private var scanned = 0
    private var everything = Data()
    private var receivedBytes = 0
    private var isClosed = false

    init(handle: FileHandle, retainingEverything: Bool = false) {
        retainsEverything = retainingEverything
        let thread = Thread { [self] in
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { break }
                ingest(data)
            }
            condition.lock()
            isClosed = true
            condition.broadcast()
            condition.unlock()
        }
        thread.stackSize = 512 * 1024
        thread.start()
    }

    func next(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }

        while lines.isEmpty, !isClosed {
            guard condition.wait(until: deadline) else { return nil }
        }
        return lines.isEmpty ? nil : lines.removeFirst()
    }

    /// How many bytes have arrived, whether or not they form a message yet.
    var bytesSeen: Int {
        condition.lock()
        defer { condition.unlock() }
        return receivedBytes
    }

    /// Everything seen so far, for asserting on stderr.
    func drained() -> String {
        condition.lock()
        defer { condition.unlock() }
        return String(decoding: everything, as: UTF8.self)
    }

    private func ingest(_ data: Data) {
        condition.lock()
        defer { condition.unlock() }

        receivedBytes += data.count
        if retainsEverything { everything.append(data) }
        buffer.append(data)

        var searchStart = buffer.index(buffer.startIndex, offsetBy: scanned)
        while let newline = buffer[searchStart...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex ..< newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex ... newline)
            if !line.isEmpty { lines.append(line) }
            searchStart = buffer.startIndex
        }
        scanned = buffer.count

        condition.broadcast()
    }
}
