import Foundation
import XCTest

@testable import xcsift

// MARK: - Configuration Decoding Tests

final class ConfigurationDecodingTests: XCTestCase {

    // MARK: - Full Configuration

    func testDecodeFullConfiguration() throws {
        let toml = """
            format = "toon"
            warnings = true
            werror = true
            quiet = true
            slow_threshold = 2.5
            coverage = true
            coverage_details = true
            coverage_path = "/custom/path"
            build_info = true
            executable = true
            exit_on_failure = true

            [toon]
            delimiter = "pipe"
            key_folding = "safe"
            flatten_depth = 3
            """

        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        mockFS.fileContents["/test/config.toml"] = toml

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: "/test/config.toml")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.format, .toon)
        XCTAssertEqual(config?.warnings, true)
        XCTAssertEqual(config?.werror, true)
        XCTAssertEqual(config?.quiet, true)
        XCTAssertEqual(config?.slowThreshold, 2.5)
        XCTAssertEqual(config?.coverage, true)
        XCTAssertEqual(config?.coverageDetails, true)
        XCTAssertEqual(config?.coveragePath, "/custom/path")
        XCTAssertEqual(config?.buildInfo, true)
        XCTAssertEqual(config?.executable, true)
        XCTAssertEqual(config?.exitOnFailure, true)
        XCTAssertEqual(config?.toon?.delimiter, .pipe)
        XCTAssertEqual(config?.toon?.keyFolding, .safe)
        XCTAssertEqual(config?.toon?.flattenDepth, 3)
    }

    // MARK: - Partial Configuration

    func testDecodePartialConfiguration() throws {
        let toml = """
            format = "json"
            warnings = true
            """

        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        mockFS.fileContents["/test/config.toml"] = toml

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: "/test/config.toml")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.format, .json)
        XCTAssertEqual(config?.warnings, true)
        // All other fields should be nil
        XCTAssertNil(config?.werror)
        XCTAssertNil(config?.quiet)
        XCTAssertNil(config?.slowThreshold)
        XCTAssertNil(config?.coverage)
        XCTAssertNil(config?.coverageDetails)
        XCTAssertNil(config?.coveragePath)
        XCTAssertNil(config?.buildInfo)
        XCTAssertNil(config?.executable)
        XCTAssertNil(config?.exitOnFailure)
        XCTAssertNil(config?.toon)
    }

    // MARK: - Empty Configuration

    func testDecodeEmptyConfiguration() throws {
        let toml = ""

        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        mockFS.fileContents["/test/config.toml"] = toml

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: "/test/config.toml")

        XCTAssertNotNil(config)
        XCTAssertNil(config?.format)
        XCTAssertNil(config?.warnings)
        XCTAssertNil(config?.toon)
    }

    // MARK: - Exit On Failure

    func testDecodeExitOnFailure() throws {
        let toml = """
            exit_on_failure = true
            """

        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        mockFS.fileContents["/test/config.toml"] = toml

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: "/test/config.toml")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.exitOnFailure, true)
    }

    func testDecodeExitOnFailureFalse() throws {
        let toml = """
            exit_on_failure = false
            """

        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        mockFS.fileContents["/test/config.toml"] = toml

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: "/test/config.toml")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.exitOnFailure, false)
    }

    // MARK: - TOON Section Only

    func testDecodeTOONSectionOnly() throws {
        let toml = """
            [toon]
            delimiter = "tab"
            key_folding = "disabled"
            """

        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        mockFS.fileContents["/test/config.toml"] = toml

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: "/test/config.toml")

        XCTAssertNotNil(config)
        XCTAssertNil(config?.format)
        XCTAssertEqual(config?.toon?.delimiter, .tab)
        XCTAssertEqual(config?.toon?.keyFolding, .disabled)
        XCTAssertNil(config?.toon?.flattenDepth)
    }

    // MARK: - Format Variants

    func testDecodeAllFormatValues() throws {
        let formats = [
            ("json", FormatOption.json), ("toon", FormatOption.toon), ("github-actions", FormatOption.githubActions),
        ]

        for (tomlValue, expected) in formats {
            let toml = "format = \"\(tomlValue)\""
            let mockFS = MockFileSystem()
            mockFS.existingPaths.insert("/test/config.toml")
            mockFS.fileContents["/test/config.toml"] = toml

            let loader = ConfigLoader(fileSystem: mockFS)
            let config = try loader.loadConfig(explicitPath: "/test/config.toml")

            XCTAssertEqual(config?.format, expected, "Format '\(tomlValue)' should decode to \(expected)")
        }
    }

    // MARK: - Delimiter Variants

    func testDecodeAllDelimiterValues() throws {
        let delimiters = [
            ("comma", DelimiterOption.comma), ("tab", DelimiterOption.tab), ("pipe", DelimiterOption.pipe),
        ]

        for (tomlValue, expected) in delimiters {
            let toml = """
                [toon]
                delimiter = "\(tomlValue)"
                """
            let mockFS = MockFileSystem()
            mockFS.existingPaths.insert("/test/config.toml")
            mockFS.fileContents["/test/config.toml"] = toml

            let loader = ConfigLoader(fileSystem: mockFS)
            let config = try loader.loadConfig(explicitPath: "/test/config.toml")

            XCTAssertEqual(config?.toon?.delimiter, expected, "Delimiter '\(tomlValue)' should decode to \(expected)")
        }
    }
}

// MARK: - ConfigLoader Tests

final class ConfigLoaderTests: XCTestCase {

    // MARK: - File Not Found

    func testExplicitPathNotFoundThrowsError() {
        let mockFS = MockFileSystem()
        // Don't add path to existingPaths

        let loader = ConfigLoader(fileSystem: mockFS)

        XCTAssertThrowsError(try loader.loadConfig(explicitPath: "/nonexistent/config.toml")) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError")
                return
            }
            if case .fileNotFound(let path) = configError {
                XCTAssertEqual(path, "/nonexistent/config.toml")
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    // MARK: - Auto-detection

    func testAutoDetectCWDConfig() throws {
        let mockFS = MockFileSystem()
        mockFS.mockCurrentDirectory = "/project"
        mockFS.existingPaths.insert("/project/.xcsift.toml")
        mockFS.fileContents["/project/.xcsift.toml"] = "format = \"toon\""

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: nil)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.format, .toon)
    }

    func testAutoDetectUserConfig() throws {
        let mockFS = MockFileSystem()
        mockFS.mockCurrentDirectory = "/project"
        mockFS.mockHomeDirectory = URL(fileURLWithPath: "/home/user")
        // No CWD config
        mockFS.existingPaths.insert("/home/user/.config/xcsift/config.toml")
        mockFS.fileContents["/home/user/.config/xcsift/config.toml"] = "format = \"github-actions\""

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: nil)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.format, .githubActions)
    }

    func testAutoDetectPrioritizeCWDOverUserConfig() throws {
        let mockFS = MockFileSystem()
        mockFS.mockCurrentDirectory = "/project"
        mockFS.mockHomeDirectory = URL(fileURLWithPath: "/home/user")
        // Both configs exist
        mockFS.existingPaths.insert("/project/.xcsift.toml")
        mockFS.fileContents["/project/.xcsift.toml"] = "format = \"toon\""
        mockFS.existingPaths.insert("/home/user/.config/xcsift/config.toml")
        mockFS.fileContents["/home/user/.config/xcsift/config.toml"] = "format = \"github-actions\""

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: nil)

        // Should use CWD config, not user config
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.format, .toon)
    }

    func testNoConfigReturnsNil() throws {
        let mockFS = MockFileSystem()
        mockFS.mockCurrentDirectory = "/project"
        mockFS.mockHomeDirectory = URL(fileURLWithPath: "/home/user")
        // No config files exist

        let loader = ConfigLoader(fileSystem: mockFS)
        let config = try loader.loadConfig(explicitPath: nil)

        XCTAssertNil(config)
    }

    // MARK: - Read Error

    func testReadErrorThrowsError() {
        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        // Don't add file contents - will throw NSFileNoSuchFileError

        let loader = ConfigLoader(fileSystem: mockFS)

        XCTAssertThrowsError(try loader.loadConfig(explicitPath: "/test/config.toml")) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError")
                return
            }
            if case .readError(let path, _) = configError {
                XCTAssertEqual(path, "/test/config.toml")
            } else {
                XCTFail("Expected readError error, got \(configError)")
            }
        }
    }

    // MARK: - Syntax Error

    func testInvalidTOMLSyntaxThrowsError() {
        let mockFS = MockFileSystem()
        mockFS.existingPaths.insert("/test/config.toml")
        mockFS.fileContents["/test/config.toml"] = "format = \"unclosed string"

        let loader = ConfigLoader(fileSystem: mockFS)

        XCTAssertThrowsError(try loader.loadConfig(explicitPath: "/test/config.toml")) { error in
            guard let configError = error as? ConfigError else {
                XCTFail("Expected ConfigError, got \(error)")
                return
            }
            if case .syntaxError = configError {
                // Success
            } else {
                XCTFail("Expected syntaxError error, got \(configError)")
            }
        }
    }

    // MARK: - Template Generation

    func testGenerateTemplateContainsAllOptions() {
        let loader = ConfigLoader()
        let template = loader.generateTemplate()

        // Check key options are present
        XCTAssertTrue(template.contains("format = \"json\""))
        XCTAssertTrue(template.contains("warnings = false"))
        XCTAssertTrue(template.contains("werror = false"))
        XCTAssertTrue(template.contains("quiet = false"))
        XCTAssertTrue(template.contains("slow_threshold = 1.0"))
        XCTAssertTrue(template.contains("coverage = false"))
        XCTAssertTrue(template.contains("coverage_details = false"))
        XCTAssertTrue(template.contains("coverage_path = \"\""))
        XCTAssertTrue(template.contains("build_info = false"))
        XCTAssertTrue(template.contains("executable = false"))
        XCTAssertTrue(template.contains("exit_on_failure = false"))
        XCTAssertTrue(template.contains("[toon]"))
        XCTAssertTrue(template.contains("delimiter = \"comma\""))
        XCTAssertTrue(template.contains("key_folding = \"disabled\""))
        XCTAssertTrue(template.contains("flatten_depth = 0"))
    }
}

// MARK: - ConfigMerger Tests

final class ConfigMergerTests: XCTestCase {

    // MARK: - CLI Overrides Config

    func testCLIFormatOverridesConfig() {
        var config = Configuration()
        config.format = .toon

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: .json,  // CLI should override
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertEqual(resolved.format, .json)
    }

    func testCLIBooleanFlagsOverrideConfig() {
        var config = Configuration()
        config.warnings = false
        config.quiet = true

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: true,  // CLI true should win
            cliWarningsAsErrors: false,
            cliQuiet: false,  // CLI false, config true -> true (OR logic)
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertEqual(resolved.warnings, true)
        XCTAssertEqual(resolved.quiet, true)  // Config value because CLI false = "not set"
    }

    func testCLIToonOptionsOverrideConfig() {
        var config = Configuration()
        config.toon = TOONConfiguration()
        config.toon?.delimiter = .comma
        config.toon?.keyFolding = .disabled
        config.toon?.flattenDepth = 5

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: .pipe,  // CLI should override
            cliToonKeyFolding: .safe,  // CLI should override
            cliToonFlattenDepth: 3  // CLI should override
        )

        XCTAssertEqual(resolved.toonDelimiter, .pipe)
        XCTAssertEqual(resolved.toonKeyFolding, .safe)
        XCTAssertEqual(resolved.toonFlattenDepth, 3)
    }

    // MARK: - Config Used When CLI Not Set

    func testConfigUsedWhenCLINotSet() {
        var config = Configuration()
        config.format = .toon
        config.warnings = true
        config.werror = true
        config.quiet = true
        config.coverage = true
        config.slowThreshold = 2.5

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,  // Not set
            cliWarnings: false,  // Not set (false = default)
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertEqual(resolved.format, .toon)
        XCTAssertEqual(resolved.warnings, true)
        XCTAssertEqual(resolved.warningsAsErrors, true)
        XCTAssertEqual(resolved.quiet, true)
        XCTAssertEqual(resolved.coverage, true)
        XCTAssertEqual(resolved.slowThreshold, 2.5)
    }

    func testConfigTOONUsedWhenCLINotSet() {
        var config = Configuration()
        config.toon = TOONConfiguration()
        config.toon?.delimiter = .tab
        config.toon?.keyFolding = .safe
        config.toon?.flattenDepth = 10

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,  // Not set
            cliToonKeyFolding: nil,  // Not set
            cliToonFlattenDepth: nil  // Not set
        )

        XCTAssertEqual(resolved.toonDelimiter, .tab)
        XCTAssertEqual(resolved.toonKeyFolding, .safe)
        XCTAssertEqual(resolved.toonFlattenDepth, 10)
    }

    // MARK: - Defaults When Neither Set

    func testDefaultsWhenNeitherSet() {
        let resolved = ConfigMerger.merge(
            config: nil,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertEqual(resolved.format, .json)
        XCTAssertEqual(resolved.warnings, false)
        XCTAssertEqual(resolved.warningsAsErrors, false)
        XCTAssertEqual(resolved.quiet, false)
        XCTAssertEqual(resolved.coverage, false)
        XCTAssertEqual(resolved.coverageDetails, false)
        XCTAssertNil(resolved.coveragePath)
        XCTAssertNil(resolved.slowThreshold)
        XCTAssertEqual(resolved.buildInfo, false)
        XCTAssertEqual(resolved.executable, false)
        XCTAssertEqual(resolved.exitOnFailure, false)
        XCTAssertEqual(resolved.toonDelimiter, .comma)
        XCTAssertEqual(resolved.toonKeyFolding, .disabled)
        XCTAssertNil(resolved.toonFlattenDepth)
    }

    // MARK: - Empty Coverage Path

    func testEmptyCoveragePathTreatedAsNil() {
        var config = Configuration()
        config.coveragePath = ""  // Empty string

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertNil(resolved.coveragePath)
    }

    func testNonEmptyCoveragePathPreserved() {
        var config = Configuration()
        config.coveragePath = "/custom/path"

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertEqual(resolved.coveragePath, "/custom/path")
    }

    // MARK: - Zero Flatten Depth

    func testZeroFlattenDepthTreatedAsUnlimited() {
        var config = Configuration()
        config.toon = TOONConfiguration()
        config.toon?.flattenDepth = 0  // 0 = unlimited

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertNil(resolved.toonFlattenDepth)  // 0 becomes nil (unlimited)
    }
}

// MARK: - ExitOnFailure Logic Tests

final class ExitOnFailureTests: XCTestCase {

    // MARK: - Exit Behavior Logic

    /// Tests that exitOnFailure=true + status="failed" should exit with failure
    func testExitOnFailureWithFailedStatus() {
        let parser = OutputParser()
        let input = """
            /path/to/file.swift:10:5: error: use of undeclared identifier 'unknown'
            """
        let result = parser.parse(input: input)

        // Verify build failed
        XCTAssertEqual(result.status, "failed")

        // With exitOnFailure=true, should indicate failure
        let resolved = ConfigMerger.merge(
            config: nil,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: true,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertTrue(resolved.exitOnFailure)
        // Exit condition: exitOnFailure && status != "success"
        let shouldExitWithFailure = resolved.exitOnFailure && result.status != "success"
        XCTAssertTrue(shouldExitWithFailure, "Should exit with failure when exitOnFailure=true and status=failed")
    }

    /// Tests that exitOnFailure=true + status="success" should exit normally
    func testExitOnFailureWithSuccessStatus() {
        let parser = OutputParser()
        let input = """
            Building for debugging...
            Build complete!
            """
        let result = parser.parse(input: input)

        // Verify build succeeded
        XCTAssertEqual(result.status, "success")

        // With exitOnFailure=true, should NOT indicate failure for success
        let resolved = ConfigMerger.merge(
            config: nil,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: true,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertTrue(resolved.exitOnFailure)
        // Exit condition: exitOnFailure && status != "success"
        let shouldExitWithFailure = resolved.exitOnFailure && result.status != "success"
        XCTAssertFalse(shouldExitWithFailure, "Should NOT exit with failure when exitOnFailure=true and status=success")
    }

    /// Tests that exitOnFailure=false + status="failed" should NOT exit with failure
    func testNoExitOnFailureWithFailedStatus() {
        let parser = OutputParser()
        let input = """
            /path/to/file.swift:10:5: error: use of undeclared identifier 'unknown'
            """
        let result = parser.parse(input: input)

        // Verify build failed
        XCTAssertEqual(result.status, "failed")

        // With exitOnFailure=false, should NOT exit with failure
        let resolved = ConfigMerger.merge(
            config: nil,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertFalse(resolved.exitOnFailure)
        // Exit condition: exitOnFailure && status != "success"
        let shouldExitWithFailure = resolved.exitOnFailure && result.status != "success"
        XCTAssertFalse(shouldExitWithFailure, "Should NOT exit with failure when exitOnFailure=false")
    }

    /// Tests exitOnFailure with test failures (status="failed")
    func testExitOnFailureWithTestFailures() {
        let parser = OutputParser()
        let input = """
            Test Case '-[MyTests testExample]' started.
            /path/to/Tests.swift:25: error: -[MyTests testExample] : XCTAssertTrue failed
            Test Case '-[MyTests testExample]' failed (0.001 seconds).
            Test Suite 'MyTests' failed at 2024-01-01 12:00:00.
            """
        let result = parser.parse(input: input)

        // Verify build failed due to test failures
        XCTAssertEqual(result.status, "failed")
        XCTAssertEqual(result.summary.failedTests, 1)

        let resolved = ConfigMerger.merge(
            config: nil,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: true,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        let shouldExitWithFailure = resolved.exitOnFailure && result.status != "success"
        XCTAssertTrue(shouldExitWithFailure, "Should exit with failure when tests fail")
    }

    /// Tests combination of --Werror and --exit-on-failure
    func testWerrorAndExitOnFailureCombined() {
        let parser = OutputParser()
        let input = """
            /path/to/file.swift:10:5: warning: variable 'unused' was never used
            Building for debugging...
            Build complete!
            """
        // warningsAsErrors=true makes this "failed" status
        let result = parser.parse(input: input, printWarnings: true, warningsAsErrors: true)

        // Verify build failed due to warnings treated as errors
        XCTAssertEqual(result.status, "failed")
        // When warningsAsErrors is true, warnings are converted to errors
        // so warnings count becomes 0 and errors count increases
        XCTAssertEqual(result.summary.warnings, 0, "Warnings should be 0 as they are converted to errors")
        XCTAssertEqual(result.summary.errors, 1, "Errors should include the converted warning")

        let resolved = ConfigMerger.merge(
            config: nil,
            cliFormat: nil,
            cliWarnings: true,
            cliWarningsAsErrors: true,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: true,
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertTrue(resolved.warningsAsErrors)
        XCTAssertTrue(resolved.exitOnFailure)

        let shouldExitWithFailure = resolved.exitOnFailure && result.status != "success"
        XCTAssertTrue(
            shouldExitWithFailure,
            "Should exit with failure when --Werror and --exit-on-failure are combined and warnings present"
        )
    }

    // MARK: - ConfigMerger exitOnFailure Tests

    func testConfigMergerExitOnFailureCLIOverridesConfig() {
        var config = Configuration()
        config.exitOnFailure = false

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: true,  // CLI should override
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertTrue(resolved.exitOnFailure)
    }

    func testConfigMergerExitOnFailureFromConfig() {
        var config = Configuration()
        config.exitOnFailure = true

        let resolved = ConfigMerger.merge(
            config: config,
            cliFormat: nil,
            cliWarnings: false,
            cliWarningsAsErrors: false,
            cliQuiet: false,
            cliCoverage: false,
            cliCoverageDetails: false,
            cliCoveragePath: nil,
            cliSlowThreshold: nil,
            cliBuildInfo: false,
            cliExecutable: false,
            cliExitOnFailure: false,  // CLI not set (false = default)
            cliToonDelimiter: nil,
            cliToonKeyFolding: nil,
            cliToonFlattenDepth: nil
        )

        XCTAssertTrue(resolved.exitOnFailure)  // Config value because CLI false = "not set"
    }
}

// MARK: - ConfigError Description Tests

final class ConfigErrorTests: XCTestCase {

    func testFileNotFoundDescription() {
        let error = ConfigError.fileNotFound(path: "/test/config.toml")
        XCTAssertEqual(error.description, "Configuration file not found: /test/config.toml")
    }

    func testSyntaxErrorWithLineDescription() {
        let error = ConfigError.syntaxError(line: 5, column: 12, message: "unterminated string")
        XCTAssertEqual(error.description, "TOML syntax error at line 5, column 12: unterminated string")
    }

    func testSyntaxErrorWithoutLineDescription() {
        let error = ConfigError.syntaxError(line: 0, column: 0, message: "invalid format")
        XCTAssertEqual(error.description, "TOML syntax error: invalid format")
    }

    func testInvalidValueDescription() {
        let error = ConfigError.invalidValue(
            key: "format",
            value: "yaml",
            validOptions: ["json", "toon", "github-actions"]
        )
        XCTAssertEqual(
            error.description,
            "Invalid value 'yaml' for 'format'. Valid options: json, toon, github-actions"
        )
    }

    func testReadErrorDescription() {
        let underlying = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        let error = ConfigError.readError(path: "/test/config.toml", underlying: underlying)
        XCTAssertTrue(error.description.contains("Failed to read '/test/config.toml'"))
    }

    func testTomlNotAvailableDescription() {
        let error = ConfigError.tomlNotAvailable
        XCTAssertEqual(
            error.description,
            "Configuration files are not supported in this build. Use CLI flags instead."
        )
    }
}
