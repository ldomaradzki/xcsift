import Foundation
import XCTest

@testable import xcsift

final class StreamingLineReaderTests: XCTestCase {
    func testEmitsCompleteLinesBeforeReadingTheNextChunk() throws {
        let log = EventLog()
        var source = ChunkSource(
            chunks: [
                Data("App.swift:4:2: war".utf8),
                Data("ning: unused value\n** BUILD SUC".utf8),
                Data("CEEDED **".utf8),
            ],
            log: log
        )
        var lines: [String] = []
        var reader = StreamingLineReader(chunkSize: 64)

        let scan = try reader.consume(from: &source) { line in
            log.entries.append("line:\(line)")
            lines.append(line)
        }

        XCTAssertEqual(
            lines,
            [
                "App.swift:4:2: warning: unused value",
                "** BUILD SUCCEEDED **",
            ]
        )
        XCTAssertEqual(
            log.entries,
            [
                "read:0",
                "read:1",
                "line:App.swift:4:2: warning: unused value",
                "read:2",
                "read:3",
                "line:** BUILD SUCCEEDED **",
            ]
        )
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testPOSIXSourceReadsPipedInput() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data("first line\nsecond line".utf8))
        try pipe.fileHandleForWriting.close()
        var source = POSIXInputSource(
            fileDescriptor: pipe.fileHandleForReading.fileDescriptor
        )
        var reader = StreamingLineReader(chunkSize: 4)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["first line", "second line"])
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testOversizedLineIsDiscardedBeforeItsBytesAccumulate() throws {
        var source = ChunkSource(
            chunks: [
                Data(repeating: 0x41, count: 100),
                Data("\n** BUILD SUCCEEDED **".utf8),
            ],
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 128, maximumLineBytes: 32)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["", "** BUILD SUCCEEDED **"])
        XCTAssertEqual(scan.oversizedLinesDropped, 1)
        XCTAssertLessThanOrEqual(scan.maximumBufferedBytes, 32)
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testPreservesUTF8ScalarsSplitAcrossSingleByteChunks() throws {
        let input = "警告🙂\n"
        var source = ChunkSource(
            chunks: input.utf8.map { Data([$0]) },
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 1)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["警告🙂", ""])
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testInvalidUTF8BytesDoNotDiscardTheLine() throws {
        var source = ChunkSource(
            chunks: [Data("main.swift:1:1: error: bad ".utf8) + Data([0xFF]) + Data(" byte\n".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader()
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines.first?.hasPrefix("main.swift:1:1: error: bad"), true)
        XCTAssertEqual(lines.first?.contains("byte"), true)
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testPreservesEmptyLinesAndUnterminatedFinalLine() throws {
        var source = ChunkSource(
            chunks: [Data("\n\nlast line".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader()
        var lines: [String] = []

        _ = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["", "", "last line"])
    }

    func testPreservesCarriageReturnsFromCRLFInput() throws {
        var source = ChunkSource(
            chunks: [Data("first\r\nsecond\r\n".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader()
        var lines: [String] = []

        _ = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["first\r", "second\r", ""])
    }

    func testSingleChunkLinesPreserveBufferAndOversizeSemantics() throws {
        var source = ChunkSource(
            chunks: [Data("1234\n\n12345\né\n".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 64, maximumLineBytes: 4)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["1234", "", "", "é", ""])
        XCTAssertEqual(scan.oversizedLinesDropped, 1)
        XCTAssertEqual(scan.maximumBufferedBytes, 4)
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testUnicodeWhitespaceDoesNotCountAsInputContent() throws {
        var source = ChunkSource(
            chunks: [Data("\u{2003}\n\t".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader()

        let scan = try reader.consume(from: &source) { _ in }

        XCTAssertFalse(scan.containsNonWhitespace)
    }
}

private final class EventLog {
    var entries: [String] = []
}

private struct ChunkSource: InputChunkSource {
    let chunks: [Data]
    let log: EventLog
    private var index = 0

    init(chunks: [Data], log: EventLog) {
        self.chunks = chunks
        self.log = log
    }

    mutating func read(upToCount _: Int) throws -> Data? {
        log.entries.append("read:\(index)")
        defer { index += 1 }
        guard index < chunks.count else { return nil }
        return chunks[index]
    }
}
