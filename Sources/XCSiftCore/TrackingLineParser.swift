// MARK: - TrackingLineParser

/// A wrapper around ``LineParser`` that stamps each emitted event with the range of 1-based
/// input line numbers that **produced** the event.
///
/// ``LineParser`` uses look-ahead buffering and an internal event queue, so a call to
/// ``feed(_:)`` may return an event that was produced by an earlier line, or by several lines
/// merged together (e.g. a Swift Testing failure and its trailing `↳` comment). `TrackingLineParser`
/// maintains a FIFO queue of pending line ranges that mirrors the inner queue, allowing each
/// event to be paired with the exact span of source lines that contributed to it.
///
/// ```swift
/// var parser = TrackingLineParser()
/// for line in lines {
///     let (lineRange, result) = parser.feed(line)
///     if case .consumed(let event) = result {
///         print("lines \(lineRange!): \(event)")
///     }
/// }
/// for (lineRange, event) in parser.flush() {
///     print("lines \(lineRange): \(event)")
/// }
/// ```
public struct TrackingLineParser: Sendable {

    // MARK: - State

    private var inner: LineParser
    private var lineCounter: Int = 0

    /// FIFO queue of source line ranges awaiting delivery.
    ///
    /// An entry is pushed for each net-new event the current `feed` call contributes to the
    /// inner buffer. An entry is popped for every `.consumed` result from `feed`, and for each
    /// event returned by `flush`. When the current line's text is merged into an already-buffered
    /// event (rather than merely triggering delivery of one), the front entry's upper bound is
    /// extended to the current line instead of pushing a new entry.
    private var pendingLineRanges: [ClosedRange<Int>] = []

    // MARK: - Init

    /// Creates a new `TrackingLineParser`.
    ///
    /// - Parameter xcbeautify: Forwarded directly to the underlying ``LineParser``.
    public init(xcbeautify: Bool = false) {
        self.inner = LineParser(xcbeautify: xcbeautify)
    }

    // MARK: - Forwarded properties

    /// Forwarded from ``LineParser/didEmitXcbeautifyHint``.
    public var didEmitXcbeautifyHint: Bool { inner.didEmitXcbeautifyHint }

    /// Forwarded from ``LineParser/sawSuccessMarker``.
    public var sawSuccessMarker: Bool { inner.sawSuccessMarker }

    /// Forwarded from ``LineParser/sawFailureMarker``.
    public var sawFailureMarker: Bool { inner.sawFailureMarker }

    // MARK: - Parsing

    /// Feeds one line to the underlying ``LineParser`` and returns the result paired with the
    /// range of 1-based input line numbers that **produced** the event.
    ///
    /// The returned `lineRange` reflects the line(s) that caused the event to be enqueued
    /// internally or whose text was folded into it — which may be earlier than the line
    /// currently being fed, due to look-ahead buffering. When the result is `.ignored`,
    /// `lineRange` is `nil`.
    ///
    /// - Parameter line: A single raw line of build output.
    /// - Returns: A tuple of `(lineRange, LineResult)`.
    @discardableResult
    public mutating func feed(_ line: String) -> (lineRange: ClosedRange<Int>?, LineResult) {
        lineCounter += 1
        let currentLine = lineCounter

        // Snapshot inner queue depth before and after to detect how many net-new future
        // events the current line contributes to the inner buffer.
        let pendingBefore = inner.pendingEventCount
        let result = inner.feed(line)
        let pendingAfter = inner.pendingEventCount
        let didMerge = inner.didMergeCurrentLine
        let droppedDeadBufferedLine = inner.droppedDeadBufferedLine

        switch result {
        case .ignored:
            guard droppedDeadBufferedLine else {
                // Line matched nothing; no event will ever be attributed to it.
                return (nil, result)
            }
            // The buffered look-ahead slot resolved without producing an event (its text never
            // matched the expected format) — discard the stale slot reserved for it, since no
            // future feed()/flush() call will ever deliver an event for that line.
            if !pendingLineRanges.isEmpty {
                pendingLineRanges.removeFirst()
            }
            // The current line may still have contributed its own event as overflow (see the
            // non-comment-continuation branch of `flushRecordedIssue`). `extraSlots` isolates
            // that net-new contribution the same way the `.consumed` branch below does.
            let extraSlots = pendingAfter - pendingBefore
            let pushCount = max(0, 1 + extraSlots)
            for _ in 0 ..< pushCount {
                pendingLineRanges.append(currentLine ... currentLine)
            }
            return (nil, result)

        case .buffering:
            // Line entered pendingRecordedIssueLine — exactly 1 future event guaranteed.
            // pendingAfter == pendingBefore + 1 by definition; push one slot.
            pendingLineRanges.append(currentLine ... currentLine)
            return (currentLine ... currentLine, result)

        case .consumed:
            if didMerge, let front = pendingLineRanges.first {
                // The current line's text was folded into the front-of-queue event's content
                // (e.g. a `↳` comment-continuation line) — extend its range rather than
                // attributing the current line to a separate, unrelated slot.
                pendingLineRanges[0] = front.lowerBound ... currentLine
            } else {
                // One queued event was just delivered. The current line may also have contributed
                // net-new entries to the inner buffer. `extraSlots` captures that delta:
                //   > 0 — overflow (e.g. fatalError double-event, Path A side-effect enqueue)
                //   = 0 — current line produced exactly one new queued event (normal path)
                //   < 0 — current line only triggered delivery of an unrelated buffered event
                //          and produced no future event of its own
                let extraSlots = pendingAfter - pendingBefore
                // Push currentLine once per net-new future event it contributed.
                // When extraSlots == 0: push once (normal case).
                // When extraSlots == -1: push zero times (drain trigger, no orphaned slot).
                // When extraSlots == 1: push twice (double-event path).
                let pushCount = max(0, 1 + extraSlots)
                for _ in 0 ..< pushCount {
                    pendingLineRanges.append(currentLine ... currentLine)
                }
            }
            let sourceLineRange = pendingLineRanges.removeFirst()
            return (sourceLineRange, result)
        }
    }

    /// Flushes all buffered state and returns remaining events paired with their source line ranges.
    ///
    /// Mirrors ``LineParser/flush()``; call once after all lines have been fed.
    ///
    /// - Returns: An array of `(lineRange: ClosedRange<Int>, ParseEvent)` pairs. The `lineRange`
    ///   collapses to the current line alone for events that have no attributable source line
    ///   (e.g. synthetic crash events emitted by the underlying parser when no buffered line
    ///   caused them directly).
    public mutating func flush() -> [(lineRange: ClosedRange<Int>, ParseEvent)] {
        let events = inner.flush()
        var out: [(lineRange: ClosedRange<Int>, ParseEvent)] = []
        out.reserveCapacity(events.count)
        for event in events {
            let lineRange = pendingLineRanges.isEmpty ? lineCounter ... lineCounter : pendingLineRanges.removeFirst()
            out.append((lineRange, event))
        }
        // Clear any orphaned entries that did not produce an event (e.g. unemitted state
        // left over after a run that ended without all buffers draining normally).
        pendingLineRanges.removeAll()
        return out
    }
}
