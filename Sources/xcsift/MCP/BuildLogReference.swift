import Foundation

/// Finds build-log paths that an upstream MCP server mentions in its tool output.
///
/// A server that summarises a build and keeps the full `xcodebuild` log on disk prints its path in
/// a box-drawing tree:
///
/// ```text
///   └ Files:
///      └── ~/Library/Logs/xcode-mcp/workspaces/…/logs/build_macos_….log — Build Logs
/// ```
///
/// or, when several artefacts share a directory, as a base directory with indented children:
///
/// ```text
///      └── ~/Library/Logs/xcode-mcp/workspaces/…/
///          ├── logs/test_sim_….log — Build Logs
/// ```
///
/// Recovering that path is what lets the proxy report the *complete* diagnostic set instead of the
/// handful of lines the upstream server chose to render.
enum BuildLogReference {

    /// Returns every build-log path referenced by `text`, de-duplicated.
    ///
    /// Paths found inside a JSON payload come first, ordered by key name for determinism; paths
    /// found in prose follow in order of appearance. The caller tries them in turn, so the order
    /// only decides which log is examined first.
    ///
    /// - Parameter homeDirectory: Used to expand a leading `~`.
    static func logPaths(in text: String, homeDirectory: String) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []
        var baseDirectory: String?

        // A server may answer with JSON rather than prose — Xcode's own server reports the build
        // transcript as a `fullLogPath` string value — so read the structure when there is one.
        if let json = JSONValue.parse(Data(text.utf8)) {
            collect(from: json, homeDirectory: homeDirectory, into: &paths, seen: &seen)
        }

        var baseIndent = 0

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = indentation(of: rawLine)
            let line = stripDecoration(String(rawLine))
            guard !line.isEmpty else { continue }

            // A base directory governs only the lines nested under it. Once the text steps back
            // out, a relative token belongs to nothing and must not be joined to a stale base.
            if baseDirectory != nil, indent <= baseIndent { baseDirectory = nil }

            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let candidate = trimDelimiters(String(token))
                guard !candidate.isEmpty else { continue }

                if candidate.hasSuffix("/"), isRooted(candidate) {
                    baseDirectory = expand(candidate, homeDirectory: homeDirectory)
                    baseIndent = indent
                    continue
                }

                guard isLogFile(candidate) else { continue }

                let path: String
                if isRooted(candidate) {
                    path = expand(candidate, homeDirectory: homeDirectory)
                } else if let baseDirectory {
                    path = baseDirectory + candidate
                } else {
                    continue
                }

                if seen.insert(path).inserted {
                    paths.append(path)
                }
            }
        }

        return paths
    }

    private static func collect(
        from value: JSONValue,
        homeDirectory: String,
        into paths: inout [String],
        seen: inout Set<String>
    ) {
        switch value {
        case let .string(text):
            guard isLogFile(text), isRooted(text) else { return }
            let path = expand(text, homeDirectory: homeDirectory)
            if seen.insert(path).inserted { paths.append(path) }
        case let .array(values):
            for element in values {
                collect(from: element, homeDirectory: homeDirectory, into: &paths, seen: &seen)
            }
        case let .object(values):
            for key in values.keys.sorted() {
                guard let element = values[key] else { continue }
                collect(from: element, homeDirectory: homeDirectory, into: &paths, seen: &seen)
            }
        default:
            return
        }
    }

    /// Build transcripts are written as `.log` by some servers and `.txt` by Xcode's own. The
    /// extension only nominates a candidate; the caller still checks that the file reads like
    /// build output before parsing it.
    private static func isLogFile(_ candidate: String) -> Bool {
        candidate.hasSuffix(".log") || candidate.hasSuffix(".txt")
    }

    /// Leading whitespace only: the box-drawing glyphs that follow it are decoration, and how
    /// deeply a line is nested is what says whether it is a child of the line above.
    private static func indentation(of line: Substring) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func isRooted(_ candidate: String) -> Bool {
        candidate.hasPrefix("/") || candidate.hasPrefix("~/")
    }

    private static func expand(_ path: String, homeDirectory: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return home + path.dropFirst(1)
    }

    /// Removes ANSI colour sequences and the box-drawing and bullet glyphs servers use to render
    /// file trees.
    private static func stripDecoration(_ line: String) -> String {
        var result = ""
        result.reserveCapacity(line.count)

        var iterator = line.unicodeScalars.makeIterator()
        var pending = iterator.next()

        while let scalar = pending {
            if scalar == "\u{1B}" {
                // Skip a CSI escape sequence: ESC [ params… final-byte. OSC sequences are not
                // stripped; no observed server emits them in a file tree.
                var next = iterator.next()
                if next == "[" {
                    while let parameter = iterator.next() {
                        if parameter.value >= 0x40, parameter.value <= 0x7E { break }
                    }
                    next = iterator.next()
                }
                pending = next
                continue
            }

            result.unicodeScalars.append(treeGlyphs.contains(scalar) ? " " : scalar)
            pending = iterator.next()
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private static let treeGlyphs: Set<Unicode.Scalar> = ["│", "├", "└", "─", "┃", "┣", "┗", "━", "•"]

    /// Strips the punctuation a path picks up from prose or JSON. Trimming stops once the token
    /// already ends in a log extension, so `build.log` is not eaten back to `build`.
    private static func trimDelimiters(_ token: String) -> String {
        var value = Substring(token)
        let leading: Set<Character> = ["\"", "'", "(", "[", "`", "<"]
        let trailing: Set<Character> = ["\"", "'", ")", "]", "}", "`", ">", ",", ";", ":", "."]

        while let first = value.first, leading.contains(first) {
            value = value.dropFirst()
        }
        while let last = value.last, trailing.contains(last), !isLogFile(String(value)) {
            value = value.dropLast()
        }
        return String(value)
    }
}
