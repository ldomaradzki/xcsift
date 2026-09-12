import Foundation
import XCSiftCore

/// The protocol-aware half of the proxy: it decides, message by message, what to forward, what to
/// rewrite, and what to answer itself.
///
/// Everything the session does not understand is forwarded byte for byte, so a client talking to an
/// upstream server through the proxy sees the traffic it would have seen without it — including
/// server-initiated requests (sampling, roots, elicitation), progress notifications, and protocol
/// versions the proxy has never heard of. Three kinds of message are not forwarded unchanged: tool
/// results carrying build output, `tools/list` results (which gain ``injectedToolName``), and calls
/// to that tool, which the session answers itself.
///
/// The session holds no mutable state of its own; the in-flight request table does, behind its own
/// lock, so the two pump directions never block each other.
///
/// `@unchecked Sendable` covers the injected file system, which is read-only here and, for the
/// `FileManager` used in production, documented as safe to call from several threads.
struct MCPProxySession: @unchecked Sendable {

    /// A JSON-RPC id. The specification says a number id *should not* be fractional, so a client
    /// may still send one, and ids beyond `Int` decode as doubles: tracking keys on the serialized
    /// form to stay total over every shape an id can take.
    struct RequestID: Hashable, Sendable {
        let json: JSONValue
        private let key: String

        init?(_ value: JSONValue?) {
            switch value {
            case .int, .string, .double:
                guard let value else { return nil }
                json = value
                key = String(decoding: value.serialized(), as: UTF8.self)
            default:
                return nil
            }
        }

        // Identity is the id's serialized form: `1` and `1.0` are the same id to a peer, and
        // `JSONValue` itself is not `Hashable`.
        static func == (lhs: RequestID, rhs: RequestID) -> Bool { lhs.key == rhs.key }

        func hash(into hasher: inout Hasher) { hasher.combine(key) }
    }

    enum Action: Equatable, Sendable {
        /// Bytes for the upstream server's stdin.
        case toServer(Data)
        /// Bytes for the client's stdout.
        case toClient(Data)
        /// A diagnostic for stderr.
        case log(String)

        /// Whether this action answers the client rather than passing work upstream.
        var answersTheClient: Bool {
            if case .toClient = self { return true }
            return false
        }
    }

    struct Options: Sendable {
        var settings: BuildOutputSifter.Settings
        /// Advertise and serve ``MCPProxySession/injectedToolName``.
        var injectTools: Bool = true
        /// Tools whose output may have a referenced build log re-parsed from disk.
        var buildToolPattern: String = MCPDefaults.buildToolPattern
        var verbose: Bool = false
        /// How many in-flight `tools/call` ids to track before dropping the oldest.
        var maximumPendingRequests: Int = 4096
    }

    static let injectedToolName = "xcsift_parse_build_log"

    enum PendingRequest: Sendable {
        case initialize
        case toolCall(name: String)
        case toolsList
    }

    private let options: Options
    private let fileSystem: FileSystemProtocol
    private let buildToolMatcher: NSRegularExpression?
    private let pending: PendingRequestTable

    init(options: Options, fileSystem: FileSystemProtocol = FileManager.default) {
        self.options = options
        self.fileSystem = fileSystem
        buildToolMatcher = try? NSRegularExpression(pattern: options.buildToolPattern)
        pending = PendingRequestTable(capacity: options.maximumPendingRequests)
    }

    // MARK: - Client → server

    func handleClientMessage(_ data: Data) -> [Action] {
        guard let message = JSONValue.parse(data), let object = message.objectValue,
            let method = object["method"]?.stringValue
        else {
            return [.toServer(data)]
        }

        let id = RequestID(object["id"])

        switch method {
        case "tools/call":
            let name = object["params"]?["name"]?.stringValue

            // The upstream server may expose a tool of the same name; then it owns it, and
            // intercepting the call would hide the real one.
            if options.injectTools, name == Self.injectedToolName, !pending.upstreamOwnsInjectedName {
                guard let id else {
                    return note("a \(Self.injectedToolName) call without an id cannot be answered; forwarding it")
                        + [.toServer(data)]
                }
                return handleInjectedToolCall(id: id, arguments: object["params"]?["arguments"])
            }

            guard let name else { break }
            guard let id else {
                return note(
                    "tools/call for \(name) has an id shape that cannot be tracked; its result will pass through"
                )
                    + [.toServer(data)]
            }
            return remember(.toolCall(name: name), for: id) + [.toServer(data)]

        case "tools/list":
            guard options.injectTools, let id else { break }

            // A server that declared no tools of its own answers `tools/list` with a
            // method-not-found error, and forwarding that on leaves the client with a protocol
            // failure and no sight of the injected tool. The capability was the proxy's to
            // declare, so the listing is the proxy's to answer. A server that declares tools owns
            // the listing as before, injected tool appended to it.
            if pending.injectedToolsCapability {
                return note("answered tools/list here; the server declares no tools capability")
                    + [.toClient(Self.injectedToolsListResult(id: id))]
            }
            return remember(.toolsList, for: id) + [.toServer(data)]

        case "initialize":
            guard options.injectTools, let id else { break }
            return remember(.initialize, for: id) + [.toServer(data)]

        default:
            break
        }

        return [.toServer(data)]
    }

    // MARK: - Server → client

    func handleServerMessage(_ data: Data) -> [Action] {
        guard var message = JSONValue.parse(data), let object = message.objectValue else {
            return [.toClient(data)]
        }

        // Only responses carry a result for a request we tracked; requests from the server itself
        // also have an id but always carry a method too. `forget` runs before the result check on
        // purpose: an error response must clear its entry too.
        guard object["method"] == nil,
            let id = RequestID(object["id"]),
            let request = pending.forget(id)
        else {
            return [.toClient(data)]
        }

        guard var result = object["result"], result.objectValue != nil else {
            // An error for a tracked request. One of them is worth answering rather than passing
            // on: a server with no tools of its own rejects `tools/list` as an unknown method, and
            // the client would take that for a protocol failure and never see the injected tool.
            // Only "method not found" is answered — any other failure is the server's to report.
            if case .toolsList = request, options.injectTools, object["error"]?["code"]?.intValue == -32601 {
                return note("the server does not implement tools/list; answered with \(Self.injectedToolName)")
                    + [.toClient(Self.injectedToolsListResult(id: id))]
            }
            return [.toClient(data)]
        }

        var actions: [Action] = []
        var changed = false

        switch request {
        case .initialize:
            let outcome = declareToolsCapability(in: &result)
            changed = outcome.changed
            if options.verbose {
                actions += outcome.notes.map { .log("xcsift: initialize: \($0)") }
            }
        case let .toolCall(name):
            let outcome = rewriteToolResult(&result, toolName: name)
            changed = outcome.changed
            if options.verbose {
                actions += outcome.notes.map { .log("xcsift: \(name): \($0)") }
            }
        case .toolsList:
            let outcome = advertiseInjectedTool(in: &result)
            changed = outcome.changed
            if options.verbose {
                actions += outcome.notes.map { .log("xcsift: tools/list: \($0)") }
            }
        }

        guard changed else { return actions + [.toClient(data)] }

        message["result"] = result
        return actions + [.toClient(message.serialized())]
    }

    // MARK: - Tool result rewriting

    private struct RewriteOutcome {
        var changed = false
        var notes: [String] = []
    }

    private func rewriteToolResult(_ result: inout JSONValue, toolName: String) -> RewriteOutcome {
        guard let content = result["content"]?.arrayValue else { return RewriteOutcome() }

        let sifter = BuildOutputSifter(settings: options.settings, fileSystem: fileSystem)
        let trust: BuildOutputSifter.ToolTrust = isBuildTool(toolName) ? .buildShaped : .unknown
        var rewritten: [JSONValue] = []
        var outcome = RewriteOutcome()

        for block in content {
            guard block["type"]?.stringValue == "text", let text = block["text"]?.stringValue else {
                rewritten.append(block)
                continue
            }

            let sifted = sifter.sift(text: text, trust: trust)
            outcome.notes += sifted.notes

            if let replacement = sifted.replacement {
                var replaced = block
                replaced["text"] = .string(replacement)
                rewritten.append(replaced)
                outcome.notes.append(
                    "replaced \(text.utf8.count) bytes of build output with \(replacement.utf8.count) bytes"
                )
            } else {
                rewritten.append(block)
            }

            for addition in sifted.additions {
                rewritten.append(.object(["type": .string("text"), "text": .string(addition)]))
                outcome.notes.append("appended \(addition.utf8.count) bytes parsed from the build log")
            }

            outcome.changed = outcome.changed || sifted.changesContent
        }

        guard outcome.changed else { return outcome }
        result["content"] = .array(rewritten)
        return outcome
    }

    /// A pattern that does not compile fails *closed*: the gate exists to keep the proxy from
    /// reading paths that merely appear in an unrelated tool's output, and a typo must not widen
    /// it. `xcsift mcp` rejects an invalid pattern at startup, so this is the second line only.
    private func isBuildTool(_ name: String) -> Bool {
        guard let buildToolMatcher else { return false }
        let range = NSRange(name.startIndex ..< name.endIndex, in: name)
        return buildToolMatcher.firstMatch(in: name, range: range) != nil
    }

    // MARK: - Injected tool

    private func advertiseInjectedTool(in result: inout JSONValue) -> RewriteOutcome {
        // A paginated listing is only complete on its last page; adding the tool earlier would
        // duplicate it or hide it behind a cursor the client may never follow.
        guard result["nextCursor"] == nil else {
            return RewriteOutcome(notes: ["paginated page, \(Self.injectedToolName) not advertised here"])
        }
        guard let listing = result["tools"] else {
            // A server that declares the capability may still answer with a bare object. The
            // client asked what tools exist; the proxy has one, so the answer is a list of one.
            result["tools"] = .array([Self.injectedToolDescriptor])
            return RewriteOutcome(changed: true, notes: ["advertised \(Self.injectedToolName) into an empty listing"])
        }
        guard var tools = listing.arrayValue else {
            return RewriteOutcome(notes: ["tools is not an array, \(Self.injectedToolName) not advertised"])
        }

        if tools.contains(where: { $0["name"]?.stringValue == Self.injectedToolName }) {
            pending.recordUpstreamOwnsInjectedName()
            return RewriteOutcome(notes: ["the upstream server already provides \(Self.injectedToolName)"])
        }

        tools.append(Self.injectedToolDescriptor)
        result["tools"] = .array(tools)
        return RewriteOutcome(changed: true, notes: ["advertised \(Self.injectedToolName)"])
    }

    /// A client only calls `tools/list` when the server said it has tools. The proxy does have
    /// one, so a server that declares no tools capability would otherwise hide it.
    private func declareToolsCapability(in result: inout JSONValue) -> RewriteOutcome {
        guard var capabilities = result["capabilities"], capabilities.objectValue != nil else {
            return RewriteOutcome()
        }
        guard capabilities["tools"] == nil else { return RewriteOutcome() }

        capabilities["tools"] = .object([:])
        result["capabilities"] = capabilities
        // Remembered because the proxy now has to serve the listing that capability promises.
        pending.recordInjectedToolsCapability()
        return RewriteOutcome(changed: true, notes: ["declared a tools capability for \(Self.injectedToolName)"])
    }

    private static let injectedToolDescriptor: JSONValue = .object([
        "name": .string(injectedToolName),
        "description": .string(
            """
            Parse a raw xcodebuild or Swift Package Manager log with xcsift and return a compact \
            structured result: errors with file and line, linker errors, failed tests and timings. \
            Pass warnings or build_info to add the full warning list or per-target phases. Use it \
            on the build log path reported by the Xcode build and test tools to see the complete \
            diagnostics behind a truncated summary.
            """
        ),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Path to the build log. A leading ~ is expanded."),
                ]),
                "format": .object([
                    "type": .string("string"),
                    "enum": .array([.string("json"), .string("toon")]),
                    "description": .string("Output format. Defaults to the proxy's configured format."),
                ]),
                "warnings": .object([
                    "type": .string("boolean"),
                    "description": .string("Include the full warning list instead of only the count."),
                ]),
                "build_info": .object([
                    "type": .string("boolean"),
                    "description": .string("Include per-target phases, timing and dependencies."),
                ]),
            ]),
            "required": .array([.string("path")]),
        ]),
    ])

    private func handleInjectedToolCall(id: RequestID, arguments: JSONValue?) -> [Action] {
        guard let path = arguments?["path"]?.stringValue, !path.isEmpty else {
            return [.toClient(Self.errorResult(id: id, message: "xcsift: 'path' is required."))]
        }

        let requestedFormat = arguments?["format"]?.stringValue
        var format: FormatType?
        if let requestedFormat {
            // The schema offers json and toon only; github-actions annotations are meaningless
            // over MCP, so an out-of-schema value is refused rather than quietly reinterpreted.
            guard let parsed = FormatType(rawValue: requestedFormat), parsed != .githubActions else {
                return [
                    .toClient(
                        Self.errorResult(
                            id: id,
                            message: "xcsift: 'format' must be \"json\" or \"toon\", not \"\(requestedFormat)\"."
                        )
                    )
                ]
            }
            format = parsed
        }

        var settings = options.settings
        settings.config = Self.overriding(
            settings.config,
            format: format,
            warnings: arguments?["warnings"]?.boolValue,
            buildInfo: arguments?["build_info"]?.boolValue
        )

        let expanded = expandTilde(path)
        let sifter = BuildOutputSifter(settings: settings, fileSystem: fileSystem)

        switch sifter.parseLog(atPath: expanded) {
        case let .success(sifted):
            return [.toClient(Self.textResult(id: id, text: sifted))]
        case let .failure(reason):
            return [
                .toClient(
                    Self.errorResult(id: id, message: "xcsift: \(expanded): \(reason.description).")
                )
            ]
        }
    }

    private func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        let home = fileSystem.homeDirectoryForCurrentUser.path
        return (home.hasSuffix("/") ? String(home.dropLast()) : home) + path.dropFirst(1)
    }

    private static func overriding(
        _ config: ResolvedConfig,
        format: FormatType?,
        warnings: Bool?,
        buildInfo: Bool?
    ) -> ResolvedConfig {
        var overridden = config
        if let format { overridden.format = format }
        if let warnings { overridden.warnings = warnings }
        if let buildInfo { overridden.buildInfo = buildInfo }
        return overridden
    }

    /// The listing for a server that has no tools of its own: the injected tool, alone.
    private static func injectedToolsListResult(id: RequestID) -> Data {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id.json,
            "result": .object(["tools": .array([injectedToolDescriptor])]),
        ]).serialized()
    }

    private static func textResult(id: RequestID, text: String) -> Data {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id.json,
            "result": .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])])]),
        ]).serialized()
    }

    private static func errorResult(id: RequestID, message: String) -> Data {
        JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id.json,
            "result": .object([
                "isError": .bool(true),
                "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
            ]),
        ]).serialized()
    }

    // MARK: - Diagnostics

    private func remember(_ request: PendingRequest, for id: RequestID) -> [Action] {
        let evicted = pending.remember(request, for: id)
        guard options.verbose, evicted > 0 else { return [] }
        return [
            .log("xcsift: stopped tracking \(evicted) request(s) over the \(options.maximumPendingRequests) in flight")
        ]
    }

    private func note(_ text: String) -> [Action] {
        options.verbose ? [.log("xcsift: \(text)")] : []
    }
}

// MARK: - In-flight requests

/// The proxy's only mutable state: which requests are outstanding, and whether the upstream server
/// turned out to own the injected tool's name.
///
/// Kept behind its own lock so the client and server pumps contend for nothing else — a sift that
/// reads and parses a large log must not hold up the other direction.
private final class PendingRequestTable: @unchecked Sendable {
    private struct Entry {
        let request: MCPProxySession.PendingRequest
        let sequence: UInt64
    }

    private let capacity: Int
    private let lock = NSLock()
    private var entries: [MCPProxySession.RequestID: Entry] = [:]
    private var nextSequence: UInt64 = 0
    private var upstreamOwnsName = false
    private var injectedCapability = false

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// - Returns: how many entries were dropped to stay within capacity. A client that never reads
    ///   its responses must not grow the proxy without bound; dropping the oldest costs only the
    ///   rewrite of a long-abandoned request.
    func remember(_ request: MCPProxySession.PendingRequest, for id: MCPProxySession.RequestID) -> Int {
        lock.lock()
        defer { lock.unlock() }

        entries[id] = Entry(request: request, sequence: nextSequence)
        nextSequence += 1

        var evicted = 0
        while entries.count > capacity {
            guard let oldest = entries.min(by: { $0.value.sequence < $1.value.sequence })?.key else { break }
            entries.removeValue(forKey: oldest)
            evicted += 1
        }
        return evicted
    }

    func forget(_ id: MCPProxySession.RequestID) -> MCPProxySession.PendingRequest? {
        lock.lock()
        defer { lock.unlock() }
        return entries.removeValue(forKey: id)?.request
    }

    func recordInjectedToolsCapability() {
        lock.lock()
        injectedCapability = true
        lock.unlock()
    }

    /// Whether the proxy, not the server, is the reason the client believes there are tools.
    var injectedToolsCapability: Bool {
        lock.lock()
        defer { lock.unlock() }
        return injectedCapability
    }

    func recordUpstreamOwnsInjectedName() {
        lock.lock()
        upstreamOwnsName = true
        lock.unlock()
    }

    var upstreamOwnsInjectedName: Bool {
        lock.lock()
        defer { lock.unlock() }
        return upstreamOwnsName
    }
}
