import Foundation
import TOML

// MARK: - Configuration Struct

/// Represents xcsift configuration loaded from TOML file.
/// All fields are Optional to support partial configs - CLI defaults apply when nil.
struct Configuration: Codable, Sendable {
    var format: FormatOption?
    var warnings: Bool?
    var werror: Bool?
    var quiet: Bool?
    var slowThreshold: Double?
    var coverage: Bool?
    var coverageDetails: Bool?
    var coveragePath: String?
    var buildInfo: Bool?
    var executable: Bool?
    var toon: TOONConfiguration?

    enum CodingKeys: String, CodingKey {
        case format
        case warnings
        case werror
        case quiet
        case slowThreshold = "slow_threshold"
        case coverage
        case coverageDetails = "coverage_details"
        case coveragePath = "coverage_path"
        case buildInfo = "build_info"
        case executable
        case toon
    }

    init() {}
}

// MARK: - TOON Configuration Section

/// TOON-specific configuration section [toon]
struct TOONConfiguration: Codable, Sendable {
    var delimiter: DelimiterOption?
    var keyFolding: KeyFoldingOption?
    var flattenDepth: Int?

    enum CodingKeys: String, CodingKey {
        case delimiter
        case keyFolding = "key_folding"
        case flattenDepth = "flatten_depth"
    }
}

// MARK: - Option Types for TOML

/// Format option for TOML (string-based for readability)
enum FormatOption: String, Codable, Sendable {
    case json
    case toon
    case githubActions = "github-actions"

    var toFormatType: FormatType {
        switch self {
        case .json: return .json
        case .toon: return .toon
        case .githubActions: return .githubActions
        }
    }
}

/// Delimiter option for TOML
enum DelimiterOption: String, Codable, Sendable {
    case comma
    case tab
    case pipe

    var toTOONDelimiterType: TOONDelimiterType {
        switch self {
        case .comma: return .comma
        case .tab: return .tab
        case .pipe: return .pipe
        }
    }
}

/// Key folding option for TOML
enum KeyFoldingOption: String, Codable, Sendable {
    case disabled
    case safe

    var toTOONKeyFoldingType: TOONKeyFoldingType {
        switch self {
        case .disabled: return .disabled
        case .safe: return .safe
        }
    }
}
