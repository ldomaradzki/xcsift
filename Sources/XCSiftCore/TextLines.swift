/// Splits whole text into lines the way the streaming reader splits a stream: on the newline byte.
///
/// `String.split(separator: "\n")` never matches a CRLF line ending, because Swift treats `\r\n` as
/// one `Character` — a log written by a tool that emits CRLF would come back as a single line and
/// parse as nothing at all. Every entry point that takes complete text rather than a stream goes
/// through here, so the two paths agree on what a line is.
public enum TextLines {
    public static func split(_ input: String) -> [String] {
        input.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
    }
}
