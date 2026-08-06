import Foundation
import XCSiftCore
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

protocol InputChunkSource {
    mutating func read(upToCount count: Int) throws -> Data?
}

struct POSIXInputSource: InputChunkSource {
    let fileDescriptor: Int32

    mutating func read(upToCount count: Int) throws -> Data? {
        var data = Data(count: count)

        while true {
            let bytesRead = data.withUnsafeMutableBytes { buffer in
                #if canImport(Darwin)
                    Darwin.read(fileDescriptor, buffer.baseAddress, count)
                #elseif canImport(Glibc)
                    Glibc.read(fileDescriptor, buffer.baseAddress, count)
                #elseif canImport(Musl)
                    Musl.read(fileDescriptor, buffer.baseAddress, count)
                #endif
            }

            if bytesRead > 0 {
                data.removeSubrange(bytesRead ..< data.count)
                return data
            }
            if bytesRead == 0 {
                return nil
            }
            if errno == EINTR {
                continue
            }

            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

struct InputScan {
    let containsNonWhitespace: Bool
    let maximumBufferedBytes: Int
    let oversizedLinesDropped: Int
}

struct StreamingLineReader {
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private var pendingBytes = Data()
    private var receivedBytes = false
    private var endedWithNewline = false
    private var containsNonWhitespace = false
    private var isDiscardingOversizedLine = false
    private var maximumBufferedBytes = 0
    private var oversizedLinesDropped = 0

    init(chunkSize: Int = 64 * 1024, maximumLineBytes: Int = LineParser.maximumLineBytes) {
        precondition(chunkSize > 0, "chunkSize must be greater than zero")
        precondition(maximumLineBytes > 0, "maximumLineBytes must be greater than zero")
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
    }

    mutating func consume<Source: InputChunkSource>(
        from source: inout Source,
        onLine: (String) throws -> Void
    ) throws -> InputScan {
        while let chunk = try source.read(upToCount: chunkSize) {
            guard !chunk.isEmpty else { continue }
            receivedBytes = true
            endedWithNewline = chunk.last == 0x0A

            try chunk.withUnsafeBytes { buffer in
                var segmentStart = 0
                while let newline = Self.firstNewline(in: buffer, startingAt: segmentStart) {
                    try emitCompleteSegment(buffer[segmentStart ..< newline], to: onLine)
                    segmentStart = newline + 1
                }
                append(buffer[segmentStart...])
            }
        }

        if isDiscardingOversizedLine || !pendingBytes.isEmpty {
            try emitPendingLine(to: onLine)
        } else if receivedBytes && endedWithNewline {
            try onLine("")
        }

        return InputScan(
            containsNonWhitespace: containsNonWhitespace,
            maximumBufferedBytes: maximumBufferedBytes,
            oversizedLinesDropped: oversizedLinesDropped
        )
    }

    private static func firstNewline(
        in buffer: UnsafeRawBufferPointer,
        startingAt start: Int
    ) -> Int? {
        guard start < buffer.count, let baseAddress = buffer.baseAddress else { return nil }

        #if canImport(Darwin)
            let match = Darwin.memchr(baseAddress.advanced(by: start), 0x0A, buffer.count - start)
        #elseif canImport(Glibc)
            let match = Glibc.memchr(baseAddress.advanced(by: start), 0x0A, buffer.count - start)
        #elseif canImport(Musl)
            let match = Musl.memchr(baseAddress.advanced(by: start), 0x0A, buffer.count - start)
        #endif

        guard let match else { return nil }
        return baseAddress.distance(to: UnsafeRawPointer(match))
    }

    private mutating func emitCompleteSegment<Bytes: Collection>(
        _ bytes: Bytes,
        to onLine: (String) throws -> Void
    ) throws where Bytes.Element == UInt8 {
        if isDiscardingOversizedLine || !pendingBytes.isEmpty {
            append(bytes)
            try emitPendingLine(to: onLine)
            return
        }

        guard bytes.count <= maximumLineBytes else {
            isDiscardingOversizedLine = true
            try emitPendingLine(to: onLine)
            return
        }

        maximumBufferedBytes = max(maximumBufferedBytes, bytes.count)
        try emitDecodedLine(String(decoding: bytes, as: UTF8.self), to: onLine)
    }

    private mutating func append<Bytes: Collection>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        guard !bytes.isEmpty, !isDiscardingOversizedLine else { return }
        guard pendingBytes.count + bytes.count <= maximumLineBytes else {
            pendingBytes.removeAll(keepingCapacity: true)
            isDiscardingOversizedLine = true
            return
        }
        pendingBytes.append(contentsOf: bytes)
        maximumBufferedBytes = max(maximumBufferedBytes, pendingBytes.count)
    }

    private mutating func emitPendingLine(to onLine: (String) throws -> Void) throws {
        if isDiscardingOversizedLine {
            oversizedLinesDropped += 1
            isDiscardingOversizedLine = false
            pendingBytes.removeAll(keepingCapacity: true)
            // The bytes are intentionally unavailable for a full Unicode whitespace scan. Treat
            // any oversized line as content so a real build invocation is never rejected as empty.
            containsNonWhitespace = true
            try onLine("")
            return
        }

        let line = String(decoding: pendingBytes, as: UTF8.self)
        pendingBytes.removeAll(keepingCapacity: true)
        try emitDecodedLine(line, to: onLine)
    }

    private mutating func emitDecodedLine(
        _ line: String,
        to onLine: (String) throws -> Void
    ) throws {
        if !containsNonWhitespace {
            let whitespace = CharacterSet.whitespacesAndNewlines
            containsNonWhitespace = line.unicodeScalars.contains {
                !whitespace.contains($0)
            }
        }
        try onLine(line)
    }
}
