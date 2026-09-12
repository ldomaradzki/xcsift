import Foundation
import TestUtils
import XCTest

@testable import xcsift

final class MCPProxySessionTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        config: ResolvedConfig = MCPFixtures.resolvedConfig(),
        injectTools: Bool = true,
        buildToolPattern: String = MCPDefaults.buildToolPattern,
        verbose: Bool = false,
        maximumPendingRequests: Int = 4096,
        fileSystem: MockFileSystem = MCPFixtures.fileSystem()
    ) -> MCPProxySession {
        MCPProxySession(
            options: MCPProxySession.Options(
                settings: BuildOutputSifter.Settings(parse: config.parse, render: config.render),
                injectTools: injectTools,
                buildToolPattern: buildToolPattern,
                verbose: verbose,
                maximumPendingRequests: maximumPendingRequests
            ),
            fileSystem: fileSystem
        )
    }

    private func toServer(_ actions: [MCPProxySession.Action]) -> [String] {
        actions.compactMap {
            guard case let .toServer(data) = $0 else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private func toClient(_ actions: [MCPProxySession.Action]) -> [JSONValue] {
        actions.compactMap {
            guard case let .toClient(data) = $0 else { return nil }
            return JSONValue.parse(data)
        }
    }

    private func logs(_ actions: [MCPProxySession.Action]) -> [String] {
        actions.compactMap {
            guard case let .log(text) = $0 else { return nil }
            return text
        }
    }

    /// The bytes sent to the client, whatever diagnostics accompany them.
    private func passedThrough(_ actions: [MCPProxySession.Action]) -> String? {
        for action in actions {
            if case let .toClient(data) = action { return String(decoding: data, as: UTF8.self) }
        }
        return nil
    }

    private func message(_ json: String) -> Data { Data(json.utf8) }

    private func encoded(_ text: String) -> String {
        String(decoding: JSONValue.string(text).serialized(), as: UTF8.self)
    }

    private func toolResult(id: String, text: String, extra: String = "") -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"result":{\#(extra)"content":[{"type":"text","text":\#(encoded(text))}]}}"#
    }

    private func call(id: String, name: String) -> Data {
        message(#"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)"}}"#)
    }

    // MARK: - Transparency

    func testForwardsClientMessagesVerbatim() {
        let session = makeSession()
        let request = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#

        XCTAssertEqual(toServer(session.handleClientMessage(message(request))), [request])
    }

    func testForwardsNonJSONVerbatim() {
        let session = makeSession()
        XCTAssertEqual(toServer(session.handleClientMessage(message("garbage"))), ["garbage"])
        XCTAssertEqual(passedThrough(session.handleServerMessage(message("garbage"))), "garbage")
    }

    /// JSON-RPC batches are a top-level array. They are forwarded rather than rewritten, which is
    /// worth pinning: build output inside a batch is deliberately not sifted.
    func testForwardsBatchesVerbatim() {
        let session = makeSession()
        let batch = #"[{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"build_sim"}}]"#

        XCTAssertEqual(toServer(session.handleClientMessage(message(batch))), [batch])
        XCTAssertEqual(passedThrough(session.handleServerMessage(message(batch))), batch)
    }

    /// Requests the server sends to the client (sampling, roots, elicitation) carry an id *and* a
    /// method; they must never be mistaken for a response to a tool call.
    func testForwardsServerInitiatedRequestsVerbatim() {
        let session = makeSession()
        let request = #"{"jsonrpc":"2.0","id":1,"method":"sampling/createMessage","params":{}}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(request))), request)
    }

    func testForwardsNotificationsVerbatim() {
        let session = makeSession()
        let notification = #"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(notification))), notification)
    }

    func testLeavesResponsesForUntrackedRequestsAlone() {
        let session = makeSession()
        let response = toolResult(id: "99", text: MCPFixtures.failingBuild)

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    func testLeavesErrorResponsesAlone() {
        let session = makeSession()
        _ = session.handleClientMessage(call(id: "4", name: "build_sim"))
        let response = #"{"jsonrpc":"2.0","id":4,"error":{"code":-32602,"message":"nope"}}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    // MARK: - Rewriting tool results

    func testRewritesBuildOutputInTrackedToolResult() throws {
        let session = makeSession()
        _ = session.handleClientMessage(call(id: "4", name: "build_sim"))
        let response = toolResult(id: "4", text: MCPFixtures.failingBuild, extra: #""isError":true,"#)

        let result = try XCTUnwrap(toClient(session.handleServerMessage(message(response))).first?["result"])
        let text = try XCTUnwrap(result["content"]?.arrayValue?.first?["text"]?.stringValue)

        XCTAssertEqual(MCPFixtures.field("status", of: text)?.stringValue, "failed")
        XCTAssertEqual(result["isError"]?.boolValue, true, "the upstream error flag must survive")
    }

    /// A rewrite re-serializes the whole result, so every sibling key the server sent has to come
    /// back out the other side.
    func testRewritePreservesSiblingKeys() throws {
        let session = makeSession()
        _ = session.handleClientMessage(call(id: "4", name: "build_sim"))
        let response = toolResult(
            id: "4",
            text: MCPFixtures.failingBuild,
            extra: #""structuredContent":{"status":"failed"},"_meta":{"trace":"abc"},"#
        )

        let result = try XCTUnwrap(toClient(session.handleServerMessage(message(response))).first?["result"])

        XCTAssertEqual(result["structuredContent"]?["status"]?.stringValue, "failed")
        XCTAssertEqual(result["_meta"]?["trace"]?.stringValue, "abc")
    }

    func testLeavesNonTextContentUntouched() throws {
        let session = makeSession()
        _ = session.handleClientMessage(call(id: "5", name: "screenshot"))
        let response =
            #"{"jsonrpc":"2.0","id":5,"result":{"content":[{"type":"image","data":"AAAA","mimeType":"image/png"}]}}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    func testResponseIsOnlyRewrittenOnce() throws {
        let session = makeSession()
        _ = session.handleClientMessage(call(id: "6", name: "build_sim"))
        let response = toolResult(id: "6", text: MCPFixtures.failingBuild)

        _ = session.handleServerMessage(message(response))
        // A duplicate id is no longer tracked, so the second response passes through untouched.
        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    func testTracksStringRequestIDs() throws {
        let session = makeSession()
        _ = session.handleClientMessage(call(id: "\"abc\"", name: "build_sim"))
        let response = toolResult(id: "\"abc\"", text: MCPFixtures.failingBuild)

        let text = try XCTUnwrap(
            toClient(session.handleServerMessage(message(response))).first?["result"]?["content"]?
                .arrayValue?.first?["text"]?.stringValue
        )
        XCTAssertEqual(MCPFixtures.field("status", of: text)?.stringValue, "failed")
    }

    /// JSON-RPC says a numeric id *should not* be fractional, so a client may still send one, and
    /// an id beyond `Int` decodes as a double. Neither may switch the proxy off.
    func testTracksFractionalAndOversizedRequestIDs() throws {
        for id in ["1.5", "12345678901234567890"] {
            let session = makeSession()
            _ = session.handleClientMessage(call(id: id, name: "build_sim"))
            let response = toolResult(id: id, text: MCPFixtures.failingBuild)

            let text = try XCTUnwrap(
                toClient(session.handleServerMessage(message(response))).first?["result"]?["content"]?
                    .arrayValue?.first?["text"]?.stringValue
            )
            XCTAssertEqual(MCPFixtures.field("status", of: text)?.stringValue, "failed", "id \(id)")
        }
    }

    // MARK: - Build-tool gate

    func testFollowsReferencedLogsOnlyForBuildShapedTools() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.warningBuild
        let summary = "Done.\nFiles: /tmp/logs/build.log"

        for (tool, expectedBlocks) in [("build_sim", 2), ("read_file", 1)] {
            let session = makeSession(
                config: MCPFixtures.resolvedConfig(warnings: true),
                fileSystem: fileSystem
            )
            _ = session.handleClientMessage(call(id: "7", name: tool))
            let actions = session.handleServerMessage(message(toolResult(id: "7", text: summary)))

            let blocks: Int
            if let rewritten = toClient(actions).first?["result"]?["content"]?.arrayValue {
                blocks = rewritten.count
            } else {
                blocks = 1
            }
            XCTAssertEqual(blocks, expectedBlocks, "tool \(tool)")
        }
    }

    /// The gate narrows what the proxy reads from disk, so a pattern that does not compile must
    /// fail closed rather than open every tool up.
    func testAnInvalidBuildToolPatternFailsClosed() {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/logs/build.log"] = MCPFixtures.warningBuild

        let session = makeSession(
            config: MCPFixtures.resolvedConfig(warnings: true),
            buildToolPattern: "(build",
            fileSystem: fileSystem
        )
        _ = session.handleClientMessage(call(id: "8", name: "build_sim"))
        let response = toolResult(id: "8", text: "Done.\nFiles: /tmp/logs/build.log")

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    // MARK: - Injected tool

    func testAdvertisesTheParseLogTool() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"build_sim"}]}}"#

        let tools = try XCTUnwrap(
            toClient(session.handleServerMessage(message(response))).first?["result"]?["tools"]?.arrayValue
        )
        XCTAssertEqual(tools.compactMap { $0["name"]?.stringValue }, ["build_sim", MCPProxySession.injectedToolName])
    }

    func testDoesNotAdvertiseOnAPaginatedPage() throws {
        let session = makeSession(verbose: true)
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":2,"result":{"nextCursor":"more","tools":[{"name":"build_sim"}]}}"#

        let actions = session.handleServerMessage(message(response))
        XCTAssertEqual(passedThrough(actions), response)
        XCTAssertTrue(logs(actions).contains { $0.contains("paginated") })
    }

    /// A server that declares a tools capability and then answers with a bare object still leaves
    /// the client asking what tools there are. The proxy has one, so the answer is a list of one.
    func testAdvertisesIntoAListingWithNoToolsArray() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":2,"result":{"nothing":true}}"#

        let result = try XCTUnwrap(toClient(session.handleServerMessage(message(response))).first?["result"])
        XCTAssertEqual(
            result["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue },
            [MCPProxySession.injectedToolName]
        )
        XCTAssertEqual(result["nothing"]?.boolValue, true, "the server's own fields must survive")
    }

    /// A `tools` value that is not an array is a shape the proxy does not understand, and it does
    /// not overwrite what it cannot read.
    func testLeavesANonArrayToolsValueAlone() throws {
        let session = makeSession(verbose: true)
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":2,"result":{"tools":"soon"}}"#

        let actions = session.handleServerMessage(message(response))
        XCTAssertEqual(passedThrough(actions), response)
        XCTAssertTrue(logs(actions).contains { $0.contains("not an array") })
    }

    /// Declaring a tools capability the server does not have leaves the proxy owning the listing
    /// that capability promises: forwarding `tools/list` to a server with no tools returns
    /// method-not-found, and the client would see a protocol error instead of the injected tool.
    func testAnswersToolsListItselfWhenTheServerDeclaresNoTools() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        _ = session.handleServerMessage(
            message(#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"resources":{}}}}"#)
        )

        let actions = session.handleClientMessage(
            message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#)
        )

        XCTAssertEqual(toServer(actions), [], "a server with no tools must not be asked for a listing")
        let result = try XCTUnwrap(toClient(actions).first?["result"])
        XCTAssertEqual(
            result["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue },
            [MCPProxySession.injectedToolName]
        )
    }

    /// The client may get its `tools/list` out before the proxy has seen the initialize response —
    /// two pumps, no ordering between them — so the rejection is handled from the server side too.
    func testAnswersAnUnsupportedToolsListWithTheInjectedTool() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}"#

        let result = try XCTUnwrap(toClient(session.handleServerMessage(message(response))).first?["result"])
        XCTAssertEqual(
            result["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue },
            [MCPProxySession.injectedToolName]
        )
    }

    /// Any other failure is the server's to report, and substituting a result would hide it.
    func testPassesOtherToolsListErrorsThrough() {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32603,"message":"Internal error"}}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    /// A server that declares tools of its own still owns its listing.
    func testForwardsToolsListWhenTheServerDeclaresTools() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        _ = session.handleServerMessage(
            message(#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"tools":{}}}}"#)
        )

        let request = #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#
        XCTAssertEqual(toServer(session.handleClientMessage(message(request))), [request])
    }

    func testInjectionCanBeDisabled() throws {
        let session = makeSession(injectTools: false)
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"build_sim"}]}}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    /// A client only asks for tools when the server said it has them, so a server that declares no
    /// tools capability would otherwise hide the injected tool.
    func testDeclaresAToolsCapabilityWhenTheServerHasNone() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        let response =
            #"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"resources":{}},"protocolVersion":"2025-06-18"}}"#

        let result = try XCTUnwrap(toClient(session.handleServerMessage(message(response))).first?["result"])
        XCTAssertNotNil(result["capabilities"]?["tools"])
        XCTAssertNotNil(result["capabilities"]?["resources"], "the server's own capabilities must survive")
    }

    func testLeavesAnExistingToolsCapabilityAlone() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        let response = #"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"tools":{"listChanged":true}}}}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(response))), response)
    }

    /// If the upstream server provides a tool of the same name, it owns it: advertising a second
    /// one would be a protocol error, and intercepting its calls would hide the real tool.
    func testYieldsTheInjectedNameToTheUpstreamServer() throws {
        let session = makeSession()
        _ = session.handleClientMessage(message(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let listing = #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"\#(MCPProxySession.injectedToolName)"}]}}"#

        XCTAssertEqual(passedThrough(session.handleServerMessage(message(listing))), listing)

        let request =
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"\#(MCPProxySession.injectedToolName)","arguments":{"path":"/tmp/x.log"}}}"#
        XCTAssertEqual(toServer(session.handleClientMessage(message(request))), [request])
    }

    func testAnswersTheParseLogToolWithoutCallingUpstream() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/Users/me/logs/build.log"] = MCPFixtures.failingBuild
        let session = makeSession(fileSystem: fileSystem)

        let actions = session.handleClientMessage(
            message(
                #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"xcsift_parse_build_log","arguments":{"path":"~/logs/build.log"}}}"#
            )
        )

        XCTAssertTrue(toServer(actions).isEmpty, "the injected tool must never reach the upstream server")
        let reply = try XCTUnwrap(toClient(actions).first)
        XCTAssertEqual(reply["id"]?.intValue, 7)
        let text = try XCTUnwrap(reply["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertEqual(MCPFixtures.field("errors", of: text)?.arrayValue?.count, 1)
    }

    func testParseLogToolHonoursPerCallFormat() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/build.log"] = MCPFixtures.failingBuild
        let session = makeSession(fileSystem: fileSystem)

        let actions = session.handleClientMessage(
            message(
                #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"xcsift_parse_build_log","arguments":{"path":"/tmp/build.log","format":"toon"}}}"#
            )
        )
        let text = try XCTUnwrap(
            toClient(actions).first?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue
        )
        XCTAssertTrue(text.hasPrefix("status: failed"))
    }

    /// The tool's schema offers json and toon. Annotations have no meaning over MCP, and neither
    /// does a format nobody defined.
    func testParseLogToolRefusesFormatsOutsideItsSchema() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/build.log"] = MCPFixtures.failingBuild
        let session = makeSession(fileSystem: fileSystem)

        for format in ["github-actions", "yaml"] {
            let actions = session.handleClientMessage(
                message(
                    #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"xcsift_parse_build_log","arguments":{"path":"/tmp/build.log","format":"\#(format)"}}}"#
                )
            )
            let reply = try XCTUnwrap(toClient(actions).first)
            XCTAssertEqual(reply["result"]?["isError"]?.boolValue, true, "format \(format)")
            let text = try XCTUnwrap(reply["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
            XCTAssertTrue(text.contains("json"), "the reply should say what is accepted")
        }
    }

    func testParseLogToolReportsWhyItCouldNotRead() throws {
        let session = makeSession()
        let actions = session.handleClientMessage(
            message(
                #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"xcsift_parse_build_log","arguments":{"path":"/nope.log"}}}"#
            )
        )

        let reply = try XCTUnwrap(toClient(actions).first)
        XCTAssertEqual(reply["result"]?["isError"]?.boolValue, true)
        let text = try XCTUnwrap(reply["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertTrue(text.contains("/nope.log"))
        XCTAssertTrue(text.contains("could not be read"))
    }

    func testParseLogToolSaysWhenAFileIsNotBuildOutput() throws {
        let fileSystem = MCPFixtures.fileSystem()
        fileSystem.fileContents["/tmp/notes.txt"] = "shopping list"
        let session = makeSession(fileSystem: fileSystem)

        let actions = session.handleClientMessage(
            message(
                #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"xcsift_parse_build_log","arguments":{"path":"/tmp/notes.txt"}}}"#
            )
        )
        let text = try XCTUnwrap(
            toClient(actions).first?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue
        )
        XCTAssertTrue(text.contains("does not read like"))
    }

    func testParseLogToolRequiresAPath() throws {
        let session = makeSession()
        let actions = session.handleClientMessage(
            message(
                #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"xcsift_parse_build_log","arguments":{}}}"#
            )
        )

        XCTAssertEqual(toClient(actions).first?["result"]?["isError"]?.boolValue, true)
    }

    func testInjectedToolIsForwardedWhenInjectionIsDisabled() {
        let session = makeSession(injectTools: false)
        let request =
            #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"xcsift_parse_build_log","arguments":{"path":"/tmp/x.log"}}}"#

        XCTAssertEqual(toServer(session.handleClientMessage(message(request))), [request])
    }

    // MARK: - Bookkeeping

    /// A client that never reads its responses must not grow the proxy without bound. The cost is
    /// that the oldest request stops being rewritten, and under `--verbose` that is said out loud.
    func testDropsTheOldestRequestWhenTooManyAreInFlight() throws {
        let session = makeSession(verbose: true, maximumPendingRequests: 2)
        _ = session.handleClientMessage(call(id: "1", name: "build_sim"))
        _ = session.handleClientMessage(call(id: "2", name: "build_sim"))
        let evicting = session.handleClientMessage(call(id: "3", name: "build_sim"))

        XCTAssertTrue(logs(evicting).contains { $0.contains("stopped tracking") })

        let stale = toolResult(id: "1", text: MCPFixtures.failingBuild)
        XCTAssertEqual(passedThrough(session.handleServerMessage(message(stale))), stale)

        let tracked = toolResult(id: "3", text: MCPFixtures.failingBuild)
        XCTAssertNotEqual(passedThrough(session.handleServerMessage(message(tracked))), tracked)
    }
}
