import Foundation
import TOML

// MARK: - Config Loader Errors

/// Errors that can occur during configuration loading
enum ConfigError: Error, CustomStringConvertible {
    case fileNotFound(path: String)
    case syntaxError(line: Int, column: Int, message: String)
    /// Reserved for custom validation. Currently unused — TOML library validates enums via Codable.
    case invalidValue(key: String, value: String, validOptions: [String])
    case readError(path: String, underlying: Error)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .syntaxError(let line, let column, let message):
            if line > 0 {
                return "TOML syntax error at line \(line), column \(column): \(message)"
            } else {
                return "TOML syntax error: \(message)"
            }
        case .invalidValue(let key, let value, let validOptions):
            return
                "Invalid value '\(value)' for '\(key)'. Valid options: \(validOptions.joined(separator: ", "))"
        case .readError(let path, let underlying):
            return "Failed to read '\(path)': \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Config Loader

/// Loads and parses xcsift configuration from TOML files
struct ConfigLoader {
    /// Default config file name in current directory
    static let configFileName = ".xcsift.toml"

    /// User config directory path component
    static let userConfigPath = ".config/xcsift/config.toml"

    private let fileSystem: FileSystemProtocol

    init(fileSystem: FileSystemProtocol = FileManager.default) {
        self.fileSystem = fileSystem
    }

    // MARK: - Public API

    /// Loads configuration from file.
    /// - Parameter explicitPath: If provided, load from this path only (fail if not found)
    /// - Returns: Configuration if found, nil if no config file exists (and explicitPath is nil)
    /// - Throws: ConfigError for parsing/validation errors
    func loadConfig(explicitPath: String?) throws -> Configuration? {
        let path: String

        if let explicit = explicitPath {
            // Explicit path must exist
            guard fileSystem.fileExists(atPath: explicit) else {
                throw ConfigError.fileNotFound(path: explicit)
            }
            path = explicit
        } else {
            // Search order: CWD, then user config
            guard let foundPath = findConfigFile() else {
                return nil  // No config file, use defaults
            }
            path = foundPath
        }

        return try parseConfigFile(at: path)
    }

    /// Generates a template configuration file content with all options commented out
    func generateTemplate() -> String {
        return """
            # xcsift Configuration File
            # https://github.com/ldomaradzki/xcsift
            #
            # CLI flags override values in this file.
            # All options are optional - omit to use defaults.

            # Output format: "json" (default), "toon", or "github-actions"
            # format = "json"

            # Warning options
            # warnings = false        # Print detailed warnings list (-w)
            # werror = false          # Treat warnings as errors (-W)

            # Output control
            # quiet = false           # Suppress output on success (-q)

            # Test analysis
            # slow_threshold = 1.0    # Threshold in seconds for slow test detection

            # Coverage options
            # coverage = false        # Enable coverage output (-c)
            # coverage_details = false # Include per-file coverage breakdown
            # coverage_path = ""      # Custom path to coverage data (empty = auto-detect)

            # Build info
            # build_info = false      # Include per-target build phases and timing
            # executable = false      # Include executable targets (-e)

            # TOON format configuration
            # [toon]
            # delimiter = "comma"     # "comma", "tab", or "pipe"
            # key_folding = "disabled" # "disabled" or "safe"
            # flatten_depth = 0       # 0 = unlimited, or positive integer
            """
    }

    // MARK: - Private Methods

    private func findConfigFile() -> String? {
        // 1. Check current working directory
        let cwdPath = fileSystem.currentDirectoryPath + "/" + Self.configFileName
        if fileSystem.fileExists(atPath: cwdPath) {
            return cwdPath
        }

        // 2. Check user config directory
        let userPath = fileSystem.homeDirectoryForCurrentUser.path + "/" + Self.userConfigPath
        if fileSystem.fileExists(atPath: userPath) {
            return userPath
        }

        return nil
    }

    private func parseConfigFile(at path: String) throws -> Configuration {
        let contents: String
        do {
            contents = try fileSystem.contentsOfFile(atPath: path)
        } catch {
            throw ConfigError.readError(path: path, underlying: error)
        }

        let decoder = TOMLDecoder()

        do {
            return try decoder.decode(Configuration.self, from: contents)
        } catch let error as DecodingError {
            throw mapDecodingError(error)
        } catch {
            // Generic TOML parsing error
            throw ConfigError.syntaxError(line: 0, column: 0, message: error.localizedDescription)
        }
    }

    private func mapDecodingError(_ error: DecodingError) -> ConfigError {
        switch error {
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return .syntaxError(
                line: 0,
                column: 0,
                message: "Type mismatch at '\(path)': expected \(type)"
            )
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return .syntaxError(
                line: 0,
                column: 0,
                message: "Missing value at '\(path)': expected \(type)"
            )
        case .keyNotFound(let key, let context):
            let path =
                (context.codingPath.map { $0.stringValue } + [key.stringValue]).joined(
                    separator: "."
                )
            return .syntaxError(
                line: 0,
                column: 0,
                message: "Missing key: '\(path)'"
            )
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            let message =
                path.isEmpty
                ? context.debugDescription
                : "Invalid data at '\(path)': \(context.debugDescription)"
            return .syntaxError(line: 0, column: 0, message: message)
        @unknown default:
            return .syntaxError(line: 0, column: 0, message: error.localizedDescription)
        }
    }
}
