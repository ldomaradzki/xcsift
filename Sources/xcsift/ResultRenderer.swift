import Foundation
import ToonFormat
import XCSiftCore

/// Encodes a ``BuildResult`` in the format the user asked for.
///
/// ``json(_:)`` and ``toon(_:config:)`` are shared by the stdin pipeline and the MCP proxy, so both
/// encode a given result identically. ``render(_:config:)`` is the proxy's entry point.
enum ResultRenderer {

    /// Renders in the resolved format.
    ///
    /// This throws rather than returning the encoder's error text: over MCP the returned string
    /// *is* the tool result, and an error message must never take the place of a build's output.
    static func render(_ result: BuildResult, config: ResolvedConfig) throws -> String {
        switch config.format {
        case .json:
            return try json(result)
        case .toon:
            return try toon(result, config: config)
        case .githubActions:
            // `xcsift mcp` refuses this format up front, so this branch exists for totality only.
            return result.formatGitHubActions()
        }
    }

    static func json(_ result: BuildResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if #available(macOS 10.15, *) {
            encoder.outputFormatting.insert(.withoutEscapingSlashes)
        }

        let data = try encoder.encode(result)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RenderError.invalidUTF8
        }
        return string
    }

    static func toon(_ result: BuildResult, config: ResolvedConfig) throws -> String {
        let encoder = TOONEncoder()
        encoder.indent = 2
        encoder.delimiter = config.toonDelimiter.toonDelimiter
        encoder.keyFolding = config.toonKeyFolding.toonKeyFolding
        if let depth = config.toonFlattenDepth {
            encoder.flattenDepth = depth
        }

        let data = try encoder.encode(result)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RenderError.invalidUTF8
        }
        return string
    }

    enum RenderError: Error, CustomStringConvertible {
        case invalidUTF8

        var description: String {
            switch self {
            case .invalidUTF8: return "encoded data is not valid UTF-8"
            }
        }
    }
}
