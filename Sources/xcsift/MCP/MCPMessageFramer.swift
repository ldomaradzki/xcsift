import Foundation

/// Splits a byte stream into newline-delimited JSON-RPC messages, the framing used by the MCP
/// stdio transport.
///
/// A message is buffered only up to the configured limit; past that its bytes are handed back as
/// ``Event/passthrough(_:)`` chunks and copied straight to the peer, so peak memory stays near the
/// limit rather than the message size. Screenshots and other base64 payloads therefore stream
/// through without a size cliff.
///
/// The trade-off is that an oversized message is never decoded, so a raw build transcript returned
/// inline above the limit passes through unsifted.
struct MCPMessageFramer {
    enum Event: Equatable, Sendable {
        /// A complete message, without its trailing newline.
        case message(Data)
        /// Raw bytes of an oversized message that must be forwarded exactly as received.
        /// `isFinalChunk` marks the chunk that carries the message's terminating newline, so a
        /// writer can keep the whole sequence exclusive and never let another thread splice into
        /// the middle of a message.
        case passthrough(Data, isFinalChunk: Bool)
        /// The peer closed mid-message after this many of its bytes were already forwarded. What
        /// reached the peer is a truncated line, which is worth saying out loud.
        case truncated(byteCount: Int)
    }

    private let maximumBufferedBytes: Int
    private var pending = Data()
    private var isForwardingOversizedMessage = false
    private var forwardedOversizedBytes = 0

    init(maximumBufferedBytes: Int = 4 * 1024 * 1024) {
        precondition(maximumBufferedBytes > 0, "maximumBufferedBytes must be greater than zero")
        self.maximumBufferedBytes = maximumBufferedBytes
    }

    mutating func append(_ chunk: Data, emit: (Event) throws -> Void) rethrows {
        var index = chunk.startIndex

        while index < chunk.endIndex {
            guard let newline = chunk[index...].firstIndex(of: UInt8(ascii: "\n")) else {
                try buffer(chunk[index...], emit: emit)
                return
            }

            if isForwardingOversizedMessage {
                try emit(.passthrough(Data(chunk[index ... newline]), isFinalChunk: true))
                isForwardingOversizedMessage = false
                forwardedOversizedBytes = 0
            } else {
                try buffer(chunk[index ..< newline], emit: emit)
                if isForwardingOversizedMessage {
                    try emit(.passthrough(Data(chunk[newline ... newline]), isFinalChunk: true))
                    isForwardingOversizedMessage = false
                    forwardedOversizedBytes = 0
                } else {
                    try emit(.message(pending))
                    pending.removeAll(keepingCapacity: true)
                }
            }

            index = chunk.index(after: newline)
        }
    }

    /// Flushes a trailing message that the peer left unterminated before closing the stream.
    mutating func finish(emit: (Event) throws -> Void) rethrows {
        if isForwardingOversizedMessage {
            isForwardingOversizedMessage = false
            try emit(.truncated(byteCount: forwardedOversizedBytes))
            forwardedOversizedBytes = 0
            return
        }
        guard !pending.isEmpty else { return }
        let message = pending
        pending.removeAll(keepingCapacity: true)
        try emit(.message(message))
    }

    private mutating func buffer(
        _ bytes: Data.SubSequence,
        emit: (Event) throws -> Void
    ) rethrows {
        guard !isForwardingOversizedMessage else {
            forwardedOversizedBytes += bytes.count
            try emit(.passthrough(Data(bytes), isFinalChunk: false))
            return
        }

        guard pending.count + bytes.count <= maximumBufferedBytes else {
            forwardedOversizedBytes = pending.count + bytes.count
            if !pending.isEmpty {
                try emit(.passthrough(pending, isFinalChunk: false))
                pending.removeAll(keepingCapacity: true)
            }
            try emit(.passthrough(Data(bytes), isFinalChunk: false))
            isForwardingOversizedMessage = true
            return
        }

        pending.append(contentsOf: bytes)
    }
}
