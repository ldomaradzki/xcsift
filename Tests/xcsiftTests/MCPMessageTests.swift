import Foundation
import XCTest

@testable import xcsift

// MARK: - JSONValue

final class JSONValueTests: XCTestCase {

    func testParsesEveryJSONType() throws {
        let data = Data(
            #"{"s":"x","i":7,"d":1.5,"b":true,"n":null,"a":[1,"two"],"o":{"k":"v"}}"#.utf8
        )
        let value = try XCTUnwrap(JSONValue.parse(data))

        XCTAssertEqual(value["s"]?.stringValue, "x")
        XCTAssertEqual(value["i"]?.intValue, 7)
        XCTAssertEqual(value["d"]?.doubleValue, 1.5)
        XCTAssertEqual(value["b"]?.boolValue, true)
        XCTAssertEqual(value["n"], .null)
        XCTAssertEqual(value["a"]?.arrayValue?.count, 2)
        XCTAssertEqual(value["o"]?["k"]?.stringValue, "v")
    }

    func testReturnsNilForInvalidJSON() {
        XCTAssertNil(JSONValue.parse(Data("not json".utf8)))
        XCTAssertNil(JSONValue.parse(Data()))
    }

    func testSerializationIsSingleLineEvenWithEmbeddedNewlines() throws {
        let value = JSONValue.object(["text": .string("line one\nline two\ttab \"quoted\"")])
        let serialized = try XCTUnwrap(String(data: value.serialized(), encoding: .utf8))

        XCTAssertFalse(serialized.contains("\n"))
        XCTAssertEqual(serialized, #"{"text":"line one\nline two\ttab \"quoted\""}"#)
    }

    func testSerializationEscapesControlCharacters() throws {
        let value = JSONValue.object(["c": .string("\u{01}")])
        let serialized = try XCTUnwrap(String(data: value.serialized(), encoding: .utf8))
        XCTAssertEqual(serialized, "{\"c\":\"\\u0001\"}")
    }

    func testRoundTripPreservesStructure() throws {
        let original = Data(#"{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"hi"}]}}"#.utf8)
        let parsed = try XCTUnwrap(JSONValue.parse(original))
        let reparsed = try XCTUnwrap(JSONValue.parse(parsed.serialized()))

        XCTAssertEqual(parsed, reparsed)
        XCTAssertEqual(reparsed["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue, "hi")
    }

    func testSubscriptSetterReplacesValue() {
        var value = JSONValue.object(["a": .int(1)])
        value["a"] = .string("two")
        XCTAssertEqual(value["a"]?.stringValue, "two")
    }

    func testIntegralDoublesSerializeWithoutExponent() throws {
        let value = JSONValue.object(["n": .double(3.0)])
        XCTAssertEqual(String(data: value.serialized(), encoding: .utf8), #"{"n":3}"#)
    }
}

// MARK: - Framing

final class MCPMessageFramerTests: XCTestCase {

    private func drain(
        _ chunks: [String],
        maximumBufferedBytes: Int = 4 * 1024 * 1024,
        finish: Bool = true
    ) -> [MCPMessageFramer.Event] {
        var framer = MCPMessageFramer(maximumBufferedBytes: maximumBufferedBytes)
        var events: [MCPMessageFramer.Event] = []
        for chunk in chunks {
            framer.append(Data(chunk.utf8)) { events.append($0) }
        }
        if finish {
            framer.finish { events.append($0) }
        }
        return events
    }

    private func messages(_ events: [MCPMessageFramer.Event]) -> [String] {
        events.compactMap {
            guard case let .message(data) = $0 else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private func passthrough(_ events: [MCPMessageFramer.Event]) -> String {
        events.compactMap {
            guard case let .passthrough(data, _) = $0 else { return nil }
            return String(decoding: data, as: UTF8.self)
        }.joined()
    }

    /// The chunk carrying the terminating newline is what releases a writer's exclusive hold on
    /// the stream, so exactly one chunk per oversized message must be marked final.
    private func finalChunks(_ events: [MCPMessageFramer.Event]) -> Int {
        events.filter {
            guard case let .passthrough(_, isFinal) = $0 else { return false }
            return isFinal
        }.count
    }

    private func truncations(_ events: [MCPMessageFramer.Event]) -> [Int] {
        events.compactMap {
            guard case let .truncated(byteCount) = $0 else { return nil }
            return byteCount
        }
    }

    func testSplitsMessagesOnNewlines() {
        let events = drain(["{\"a\":1}\n{\"b\":2}\n"])
        XCTAssertEqual(messages(events), ["{\"a\":1}", "{\"b\":2}"])
    }

    func testReassemblesMessageSplitAcrossChunks() {
        let events = drain(["{\"a\":", "1}", "\n"])
        XCTAssertEqual(messages(events), ["{\"a\":1}"])
    }

    func testFlushesUnterminatedTrailingMessage() {
        let events = drain(["{\"a\":1}"])
        XCTAssertEqual(messages(events), ["{\"a\":1}"])
    }

    func testEmitsEmptyMessageForBlankLine() {
        let events = drain(["\n{\"a\":1}\n"])
        XCTAssertEqual(messages(events), ["", "{\"a\":1}"])
    }

    /// An oversized message must reach the peer byte for byte, newline included, so framing on the
    /// wire survives payloads too large to buffer.
    func testForwardsOversizedMessageVerbatim() {
        let big = String(repeating: "x", count: 64)
        let events = drain(["{\"a\":\"\(big)\"}\n{\"b\":2}\n"], maximumBufferedBytes: 16)

        XCTAssertEqual(passthrough(events), "{\"a\":\"\(big)\"}\n")
        XCTAssertEqual(messages(events), ["{\"b\":2}"])
        XCTAssertEqual(finalChunks(events), 1, "the terminating chunk must be marked exactly once")
    }

    func testOversizedMessageSpanningChunksStaysInSync() {
        let events = drain(
            ["{\"a\":\"12345678901234567890", "1234567890\"}", "\n", "{\"b\":2}\n"],
            maximumBufferedBytes: 8
        )

        XCTAssertEqual(passthrough(events), "{\"a\":\"123456789012345678901234567890\"}\n")
        XCTAssertEqual(messages(events), ["{\"b\":2}"])
        XCTAssertEqual(finalChunks(events), 1)
    }

    /// Bytes of a truncated message have already reached the peer, so the peer's framing is broken
    /// through no fault of its own. That is worth reporting rather than dropping quietly.
    func testReportsAnOversizedMessageThePeerNeverTerminated() {
        let events = drain(["{\"a\":\"123456789012345678901234567890"], maximumBufferedBytes: 8)

        XCTAssertEqual(truncations(events), [36], "6 bytes of prefix plus 30 of payload reached the peer")
        XCTAssertEqual(messages(events), [])
        XCTAssertEqual(finalChunks(events), 0)
    }

    func testCompletedOversizedMessageIsNotReportedAsTruncated() {
        let events = drain(["{\"a\":\"1234567890\"}\n"], maximumBufferedBytes: 8)
        XCTAssertEqual(truncations(events), [])
    }
}
