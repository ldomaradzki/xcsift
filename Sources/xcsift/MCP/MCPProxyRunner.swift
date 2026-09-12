import Foundation
import XCSiftCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Runs the upstream Xcode MCP server as a child process and pumps stdio between it and the client.
///
/// The two directions are independent blocking loops that share no mutable state, so neither peer
/// can stall the other, and the upstream server's stderr is inherited untouched — its own logging
/// keeps reaching the client's log exactly as before.
struct MCPProxyRunner {

    enum LaunchError: Error, CustomStringConvertible {
        case missingCommand
        case commandNotFound(String)
        case launchFailed(command: String, underlying: Error)

        var description: String {
            switch self {
            case .missingCommand:
                return "No upstream MCP server command given. Example: xcsift mcp -- xcrun mcpbridge"
            case let .commandNotFound(command) where command.contains("/"):
                return "Upstream MCP server '\(command)' was not found or is not executable."
            case let .commandNotFound(command):
                return """
                    Upstream MCP server '\(command)' was not found on PATH\
                    \(ProcessInfo.processInfo.environment["PATH"] == nil ? " (PATH is unset)" : ""). \
                    Install it, or pass another server after `--`.
                    """
            case let .launchFailed(command, underlying):
                return "Failed to launch upstream MCP server '\(command)': \(underlying.localizedDescription)"
            }
        }
    }

    /// How a pump loop ended. A read error is not an end of conversation, and saying so keeps the
    /// proxy from blaming the upstream server for the client's broken stream.
    private enum PumpEnd {
        case endOfStream(sawBytes: Bool)
        case readFailed(Error, sawBytes: Bool)

        var sawBytes: Bool {
            switch self {
            case let .endOfStream(sawBytes), let .readFailed(_, sawBytes): return sawBytes
            }
        }
    }

    private let upstream: [String]
    private let session: MCPProxySession
    private let verbose: Bool

    init(upstream: [String], options: MCPProxySession.Options, fileSystem: FileSystemProtocol = FileManager.default) {
        self.upstream = upstream
        session = MCPProxySession(options: options, fileSystem: fileSystem)
        verbose = options.verbose
    }

    /// Runs until the upstream server exits, returning its exit status.
    func run() throws -> Int32 {
        guard let command = upstream.first else { throw LaunchError.missingCommand }

        // A closed pipe must surface as a short write, not as a signal that kills the proxy while
        // the other direction still has messages to deliver.
        signal(SIGPIPE, SIG_IGN)

        guard let executable = Self.resolve(command) else {
            throw LaunchError.commandNotFound(command)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = Array(upstream.dropFirst())

        let serverInput = Pipe()
        let serverOutput = Pipe()
        process.standardInput = serverInput
        process.standardOutput = serverOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw LaunchError.launchFailed(command: command, underlying: error)
        }

        // The child is addressed by pid from here on. `Process` is not Sendable and the pump thread
        // must be able to end the child while the main thread waits on it.
        let pid = process.processIdentifier

        let toServer = FileDescriptorWriter(owning: serverInput.fileHandleForWriting)
        let toClient = FileDescriptorWriter(borrowing: STDOUT_FILENO)
        let toLog = FileDescriptorWriter(borrowing: STDERR_FILENO)
        let activity = ProxyActivity()

        if verbose {
            toLog.write(Data("xcsift: proxying \(upstream.joined(separator: " "))\n".utf8))
        }

        let session = self.session
        let verbose = self.verbose
        let clientPump = Thread {
            let end = Self.pump(
                descriptor: STDIN_FILENO,
                passthrough: toServer,
                toServer: toServer,
                toClient: toClient,
                toLog: toLog,
                handle: { message in
                    let actions = session.handleClientMessage(message)
                    if actions.contains(where: \.answersTheClient) { activity.recordLocalReply() }
                    return actions
                }
            )

            if case let .readFailed(error, _) = end {
                toLog.write(Data("xcsift: reading the client stream failed: \(error.localizedDescription)\n".utf8))
            }

            // Closing the server's stdin is how a well-behaved MCP server learns to shut down.
            toServer.close()
            Self.shutdown(pid: pid, isFinished: { activity.serverStreamClosed }, log: verbose ? toLog : nil)
        }
        clientPump.stackSize = 4 * 1024 * 1024
        clientPump.start()

        let serverEnd = Self.pump(
            descriptor: serverOutput.fileHandleForReading.fileDescriptor,
            passthrough: toClient,
            toServer: toServer,
            toClient: toClient,
            toLog: toLog,
            handle: { session.handleServerMessage($0) }
        )

        activity.recordServerStreamClosed()

        if case let .readFailed(error, _) = serverEnd {
            toLog.write(
                Data("xcsift: reading the upstream server's output failed: \(error.localizedDescription)\n".utf8)
            )
            // Nobody is draining the child's stdout any more, so waiting on it could hang forever.
            Self.shutdown(pid: pid, isFinished: { false }, gracePeriod: 0, log: verbose ? toLog : nil)
        }

        process.waitUntilExit()

        // Only a server that ended its stream cleanly without ever answering is a server worth
        // explaining. A read failure has already been reported, and a session the proxy answered
        // itself never needed the upstream at all.
        if case .endOfStream(sawBytes: false) = serverEnd, !activity.answeredTheClient {
            toLog.write(Data(Self.silentServerDiagnostic(for: upstream, status: process.terminationStatus).utf8))
        }

        return process.terminationStatus
    }

    /// A server that exits without ever writing a message looks, to the client, like a server that
    /// simply does not work. Xcode's built-in server does exactly that when MCP is switched off, so
    /// say what to turn on rather than leaving an empty stream behind.
    static func silentServerDiagnostic(for upstream: [String], status: Int32) -> String {
        let command = upstream.joined(separator: " ")
        var message = "xcsift: upstream MCP server '\(command)' exited (status \(status)) without sending a message.\n"

        if upstream.contains(where: { $0.contains("mcpbridge") || $0.contains("mcp-server") }) {
            message += """
                xcsift: Xcode's built-in server answers only when MCP is enabled — turn it on in \
                Xcode > Settings > Intelligence, or run `sudo xcrun mcp-server enable`, and keep a \
                project open (`xcrun mcp-server status` reports the current state).

                """
        }

        return message
    }

    /// The shutdown sequence the MCP specification prescribes once the client's stream closes:
    /// give the server time to exit on its own, then SIGTERM, then SIGKILL. Without it a server
    /// that ignores a closed stdin would outlive the client that started it.
    ///
    /// Whether the server is finished is decided by `isFinished` — normally "its stdout reached
    /// end of stream" — rather than by asking the operating system. Reaping the child here with
    /// `waitpid` would race Foundation's own reaper and can leave `waitUntilExit` waiting for an
    /// exit status something else already collected.
    static func shutdown(
        pid: pid_t,
        isFinished: @escaping () -> Bool,
        gracePeriod: TimeInterval = 5,
        terminationPeriod: TimeInterval = 2,
        log: FileDescriptorWriter? = nil
    ) {
        guard !wait(until: isFinished, within: gracePeriod) else { return }
        log?.write(Data("xcsift: upstream server did not exit on its own; sending SIGTERM\n".utf8))
        kill(pid, SIGTERM)

        guard !wait(until: isFinished, within: terminationPeriod) else { return }
        log?.write(Data("xcsift: upstream server ignored SIGTERM; sending SIGKILL\n".utf8))
        kill(pid, SIGKILL)
    }

    private static func wait(until isFinished: () -> Bool, within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isFinished() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return isFinished()
    }

    /// Finds the upstream executable the way a shell would. Resolving it here rather than handing
    /// the name to `Process` means a missing server is reported by name, instead of arriving as an
    /// exit status with no explanation.
    private static func resolve(_ command: String) -> URL? {
        if command.contains("/") {
            let url = URL(fileURLWithPath: command)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":") where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: - Pumping

    private static func pump(
        descriptor: Int32,
        passthrough: FileDescriptorWriter,
        toServer: FileDescriptorWriter,
        toClient: FileDescriptorWriter,
        toLog: FileDescriptorWriter,
        handle: (Data) -> [MCPProxySession.Action]
    ) -> PumpEnd {
        var source = POSIXInputSource(fileDescriptor: descriptor)
        var framer = MCPMessageFramer()
        var sawBytes = false

        // An oversized message leaves in many chunks. The destination is held exclusively for the
        // whole sequence, because the other pump thread writes to the same stream — an injected
        // tool reply landing mid-message would terminate the line early and desynchronise framing.
        var isForwardingOversizedMessage = false

        func apply(_ event: MCPMessageFramer.Event) {
            switch event {
            case let .passthrough(bytes, isFinalChunk):
                if !isForwardingOversizedMessage {
                    passthrough.beginExclusiveMessage()
                    isForwardingOversizedMessage = true
                }
                passthrough.write(bytes)
                if isFinalChunk {
                    passthrough.endExclusiveMessage()
                    isForwardingOversizedMessage = false
                }
            case let .truncated(byteCount):
                if isForwardingOversizedMessage {
                    passthrough.endExclusiveMessage()
                    isForwardingOversizedMessage = false
                }
                toLog.write(
                    Data(
                        "xcsift: the peer closed mid-message; \(byteCount) forwarded bytes are a truncated message\n"
                            .utf8
                    )
                )
            case let .message(message):
                for action in handle(message) {
                    switch action {
                    case let .toServer(data):
                        toServer.write(data + newline)
                    case let .toClient(data):
                        toClient.write(data + newline)
                    case let .log(text):
                        toLog.write(Data((text + "\n").utf8))
                    }
                }
            }
        }

        while true {
            let chunk: Data?
            do {
                chunk = try source.read(upToCount: readChunkSize)
            } catch {
                framer.finish(emit: apply)
                if isForwardingOversizedMessage { passthrough.endExclusiveMessage() }
                return .readFailed(error, sawBytes: sawBytes)
            }

            guard let chunk, !chunk.isEmpty else { break }
            sawBytes = true
            framer.append(chunk, emit: apply)
        }

        framer.finish(emit: apply)
        if isForwardingOversizedMessage { passthrough.endExclusiveMessage() }
        return .endOfStream(sawBytes: sawBytes)
    }

    private static let readChunkSize = 64 * 1024
    private static let newline = Data([UInt8(ascii: "\n")])
}

// MARK: - Session activity

/// Records whether the proxy answered the client on its own, which is what tells a session that
/// never needed the upstream server from one the server failed to serve.
private final class ProxyActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var localReplies = 0
    private var serverFinished = false

    func recordLocalReply() {
        lock.lock()
        localReplies += 1
        lock.unlock()
    }

    var answeredTheClient: Bool {
        lock.lock()
        defer { lock.unlock() }
        return localReplies > 0
    }

    /// Set when the upstream server's stdout reaches end of stream, which is the proxy's own
    /// evidence that the server is done — no reaping required.
    func recordServerStreamClosed() {
        lock.lock()
        serverFinished = true
        lock.unlock()
    }

    var serverStreamClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return serverFinished
    }
}

// MARK: - Writing

/// A blocking, lock-guarded writer that completes short writes and reports a broken stream once.
///
/// Ownership is explicit: a writer created with ``init(borrowing:)`` never closes its descriptor —
/// closing stdout would be a bug — while ``init(owning:)`` closes through the `FileHandle` that owns
/// it, so `Pipe`'s own teardown cannot close the same descriptor a second time and take an
/// unrelated file with it.
final class FileDescriptorWriter: @unchecked Sendable {
    private let descriptor: Int32
    private let owner: FileHandle?
    // Recursive so a writer held exclusively for a multi-chunk message can still take the lock for
    // each individual write.
    private let lock = NSRecursiveLock()
    private var isClosed = false
    private var didReportFailure = false

    init(borrowing descriptor: Int32) {
        self.descriptor = descriptor
        owner = nil
    }

    init(owning handle: FileHandle) {
        descriptor = handle.fileDescriptor
        owner = handle
    }

    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }

        data.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count

            while remaining > 0 {
                let written = Self.write(descriptor, pointer, remaining)

                if written > 0 {
                    pointer = pointer.advanced(by: written)
                    remaining -= written
                    continue
                }
                if written < 0, errno == EINTR { continue }
                if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    // A non-blocking peer that has not drained its pipe is still a live peer.
                    // Waiting is the only way to avoid delivering half a message.
                    var descriptorEvent = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&descriptorEvent, 1, 1000)
                    continue
                }

                report(failure: errno, written: buffer.count - remaining, of: buffer.count)
                return
            }
        }
    }

    /// Reserves the stream until ``endExclusiveMessage()``, so a message written in several
    /// chunks cannot be interleaved with another thread's message.
    func beginExclusiveMessage() {
        lock.lock()
    }

    func endExclusiveMessage() {
        lock.unlock()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed, let owner else { return }
        isClosed = true
        try? owner.close()
    }

    /// A truncated message desynchronises newline framing for everything that follows, so the
    /// stream is abandoned rather than corrupted further — and it is reported, once.
    private func report(failure code: Int32, written: Int, of total: Int) {
        isClosed = true
        guard !didReportFailure else { return }
        didReportFailure = true

        let note =
            "xcsift: writing to fd \(descriptor) failed (errno \(code)) after \(written) of \(total) bytes; "
            + "that peer's stream is now abandoned\n"
        FileHandle.standardError.write(Data(note.utf8))
    }

    private static func write(_ descriptor: Int32, _ pointer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
            return Darwin.write(descriptor, pointer, count)
        #elseif canImport(Glibc)
            return Glibc.write(descriptor, pointer, count)
        #elseif canImport(Musl)
            return Musl.write(descriptor, pointer, count)
        #endif
    }
}
