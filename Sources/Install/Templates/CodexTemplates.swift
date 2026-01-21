import Foundation

/// Templates for Codex skill installation
enum CodexTemplates {

    /// The SKILL.md content for Codex
    static let skillMarkdown = """
        ---
        name: xcsift
        description: Use xcsift for Swift and Xcode build output. Activate when running swift build, swift test, or xcodebuild commands. Pipe output through xcsift for structured TOON format optimized for LLM consumption.
        ---

        # xcsift - Xcode Build Output Formatter

        xcsift is a Swift command-line tool that parses and formats xcodebuild/SPM output for coding agents. It transforms verbose Xcode build output into token-efficient TOON format optimized for machine readability.

        ## When to Use

        Use xcsift when running Swift or Xcode build commands:
        - `xcodebuild build`
        - `xcodebuild test`
        - `swift build`
        - `swift test`

        ## Usage Pattern

        Always pipe build output through xcsift with stderr redirected:

        ```bash
        # Basic usage
        xcodebuild build 2>&1 | xcsift -f toon
        swift build 2>&1 | xcsift -f toon

        # With warnings
        xcodebuild build 2>&1 | xcsift -f toon -w

        # With code coverage
        swift test --enable-code-coverage 2>&1 | xcsift -f toon -c
        xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift -f toon -c

        # With executable targets
        xcodebuild build 2>&1 | xcsift -f toon -e

        # Strict CI mode (fail on warnings)
        xcodebuild build 2>&1 | xcsift -f toon -W -E
        ```

        ## Key Flags

        | Flag | Description |
        |------|-------------|
        | `-f toon` | TOON format (30-60% fewer tokens) |
        | `-w` | Show detailed warnings |
        | `-W` | Treat warnings as errors |
        | `-q` | Quiet mode (no output on success) |
        | `-c` | Include code coverage |
        | `-e` | Include executable targets |
        | `-E` | Exit with failure on build failure |
        | `--build-info` | Per-target phases and timing |

        ## Output Format

        TOON format provides structured output optimized for LLMs:

        ```toon
        status: failed
        summary:
          errors: 1
          warnings: 3
        errors[1]{file,line,message}:
          main.swift,15,"use of undeclared identifier"
        warnings[3]{file,line,message}:
          Parser.swift,20,"unused variable"
        ```

        ## Important Notes

        - Always use `2>&1` to capture stderr (where compiler errors are written)
        - TOON format reduces tokens by 30-60% compared to raw xcodebuild output
        - When running build commands, always add `| xcsift -f toon` to the end

        ## Example Workflow

        1. Build the project:
           ```bash
           swift build 2>&1 | xcsift -f toon
           ```

        2. If build fails, analyze the structured error output

        3. Run tests with coverage:
           ```bash
           swift test --enable-code-coverage 2>&1 | xcsift -f toon -c
           ```

        4. For CI pipelines, use strict mode:
           ```bash
           xcodebuild build 2>&1 | xcsift -f toon -W -E
           ```
        """
}
