import ArgumentParser
import Foundation
import XCSiftCore

/// `xcsift mcp` — an MCP proxy that puts xcsift in front of an Xcode MCP server.
struct MCPProxyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Proxy an Xcode MCP server and sift its build output through xcsift",
        usage: "xcsift mcp [options] [-- <server command> [args...]]",
        discussion: """
            Speaks MCP on stdio in both directions: the coding agent connects to xcsift, and xcsift
            runs the real Xcode MCP server as a child process. Messages are forwarded byte for byte
            except tool results carrying build output, `tools/list` (which gains the tool below) and
            calls to that tool, which xcsift answers itself.

            The server command goes after `--`. With none, Xcode's built-in MCP server is used
            through its stdio bridge (Xcode 26+, enabled in Xcode > Settings > Intelligence or with
            `sudo xcrun mcp-server enable`):
              xcsift mcp                                    # same as: xcsift mcp -- xcrun mcpbridge
              xcsift mcp -f toon --build-info -- xcrun mcpbridge
              xcsift mcp -- /usr/local/bin/my-xcode-mcp     # any other stdio server

            Two shapes of upstream output are handled:
              * Raw xcodebuild/SPM transcripts are replaced by the sifted result.
              * Summaries that reference a build log on disk keep their text, and what they left
                out is appended from that log (--on-summary controls this).

            The proxy also adds an xcsift_parse_build_log tool so the agent can ask for the
            complete diagnostics behind any build log (--no-inject-tools disables it).

            Print a client configuration snippet instead of running:
              xcsift mcp --print-config
            """
    )

    @OptionGroup var sifting: SiftingOptions

    @Option(
        name: .long,
        help: "What to do when the server already summarised the build but references a log: append, replace or off"
    )
    var onSummary: BuildOutputSifter.SummaryStrategy = .append

    @Option(
        name: .long,
        help: "Minimum line count before output carrying two or more weak build markers counts as a raw transcript"
    )
    var minRawLines: Int = MCPDefaults.minimumRawLines

    @Option(name: .long, help: "Maximum build log size to parse, in megabytes (1-4096)")
    var maxLogSize: Int = MCPDefaults.maximumLogMegabytes

    @Flag(
        inversion: .prefixedNo,
        help: "Advertise the xcsift_parse_build_log tool alongside the server's own tools"
    )
    var injectTools: Bool = true

    @Option(
        name: .long,
        help: "Regex matching tool names whose referenced build logs may be parsed"
    )
    var buildToolPattern: String = MCPDefaults.buildToolPattern

    @Flag(name: .long, help: "Log proxy activity to stderr")
    var verbose: Bool = false

    @Flag(name: .long, help: "Print an MCP client configuration snippet and exit")
    var printConfig: Bool = false

    // `.postTerminator` over `.captureForPassthrough`: passthrough would swallow `--help` into
    // `upstream` and break `xcsift mcp --help`. It also keeps the proxy's flags and the server's
    // from colliding — everything the child needs sits after `--`.
    @Argument(
        parsing: .postTerminator,
        help: ArgumentHelp(
            "The upstream MCP server command. Default: xcrun mcpbridge (Xcode's built-in server)",
            valueName: "server command"
        )
    )
    var upstream: [String] = []

    func validate() throws {
        do {
            _ = try NSRegularExpression(pattern: buildToolPattern)
        } catch {
            throw ValidationError(
                "--build-tool-pattern is not a valid regular expression: \(error.localizedDescription)"
            )
        }

        guard minRawLines >= 1 else {
            throw ValidationError("--min-raw-lines must be at least 1.")
        }
        guard maxLogSize >= 1, maxLogSize <= 4096 else {
            throw ValidationError("--max-log-size must be between 1 and 4096 megabytes.")
        }
    }

    func run() throws {
        let resolved = try resolveConfig()

        guard resolved.format != .githubActions else {
            throw ValidationError(
                """
                --format github-actions is for CI annotations and has no meaning over MCP. Use json \
                or toon (a `format = "github-actions"` line in .xcsift.toml reaches the proxy too; \
                override it with -f json).
                """
            )
        }

        let command = resolvedUpstream

        if printConfig {
            print(clientConfigurationSnippet(for: command))
            return
        }

        let settings = BuildOutputSifter.Settings(
            config: resolved,
            summaryStrategy: onSummary,
            minimumRawLines: minRawLines,
            maximumLogBytes: maxLogSize * 1024 * 1024
        )

        let options = MCPProxySession.Options(
            settings: settings,
            injectTools: injectTools,
            buildToolPattern: buildToolPattern,
            verbose: verbose
        )

        let status: Int32
        do {
            status = try MCPProxyRunner(upstream: command, options: options).run()
        } catch let error as MCPProxyRunner.LaunchError {
            FileHandle.standardError.write(Data("Error: \(error.description)\n".utf8))
            throw ExitCode.failure
        }

        guard status == 0 else { throw ExitCode(status) }
    }

    private var resolvedUpstream: [String] {
        // ArgumentParser consumes the first `--` itself; a second one (`xcsift mcp -- -- server`)
        // arrives as a value. Strip it: it is a separator for the user, not an argument.
        let given = upstream.first == "--" ? Array(upstream.dropFirst()) : upstream
        return given.isEmpty ? MCPDefaults.upstream : given
    }

    private func resolveConfig() throws -> ResolvedConfig {
        do {
            return try sifting.resolve()
        } catch let error as ConfigError {
            FileHandle.standardError.write(Data("Error: \(error.description)\n".utf8))
            throw ExitCode.failure
        }
    }

    /// Reproduces the invocation as a client configuration, including every option that changes
    /// how the proxy behaves. `--verbose` and `--print-config` are left out: one is a diagnostic
    /// and the other is this command.
    func clientConfigurationSnippet(for command: [String]) -> String {
        var args: [String] = ["mcp"]

        if let config = sifting.config { args += ["--config", config] }
        if let format = sifting.format { args += ["--format", format.rawValue] }
        if sifting.warnings { args.append("--warnings") }
        if sifting.warningsAsErrors { args.append("--Werror") }
        if sifting.coverage { args.append("--coverage") }
        if sifting.coverageDetails { args.append("--coverage-details") }
        if let path = sifting.coveragePath { args += ["--coverage-path", path] }
        if sifting.buildInfo { args.append("--build-info") }
        if sifting.executable { args.append("--executable") }
        if let slowThreshold = sifting.slowThreshold { args += ["--slow-threshold", String(slowThreshold)] }
        if sifting.xcbeautify { args.append("--xcbeautify") }
        if let delimiter = sifting.toonDelimiter { args += ["--toon-delimiter", delimiter.rawValue] }
        if let folding = sifting.toonKeyFolding { args += ["--toon-key-folding", folding.rawValue] }
        if let depth = sifting.toonFlattenDepth { args += ["--toon-flatten-depth", String(depth)] }
        if onSummary != .append { args += ["--on-summary", onSummary.rawValue] }
        if minRawLines != MCPDefaults.minimumRawLines { args += ["--min-raw-lines", String(minRawLines)] }
        if maxLogSize != MCPDefaults.maximumLogMegabytes { args += ["--max-log-size", String(maxLogSize)] }
        if buildToolPattern != MCPDefaults.buildToolPattern { args += ["--build-tool-pattern", buildToolPattern] }
        if !injectTools { args.append("--no-inject-tools") }

        args.append("--")
        args += command

        let encodedArgs = String(decoding: JSONValue.array(args.map(JSONValue.string)).serialized(), as: UTF8.self)
        let encodedCommand = String(decoding: JSONValue.string(Self.proxyExecutablePath).serialized(), as: UTF8.self)

        return """
            {
              "mcpServers": {
                "xcode": {
                  "command": \(encodedCommand),
                  "args": \(encodedArgs)
                }
              }
            }
            """
    }

    /// An absolute path when the proxy was launched by path, so a client with a minimal PATH can
    /// still find it; otherwise the bare name the user already has on their PATH.
    private static var proxyExecutablePath: String {
        guard let argv0 = CommandLine.arguments.first, argv0.contains("/") else { return "xcsift" }
        return URL(fileURLWithPath: argv0).standardizedFileURL.path
    }
}

extension BuildOutputSifter.SummaryStrategy: ExpressibleByArgument {}
