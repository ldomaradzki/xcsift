import Foundation

/// Shared templates used across multiple installers
enum SharedTemplates {

    /// The common SKILL.md content for all editors
    static let skillMarkdown = """
        ---
        name: xcsift
        description: Use xcsift for all Swift and Xcode build commands. Pipe xcodebuild build, xcodebuild test, swift build, swift test through xcsift for structured TOON output with compile errors, warnings, test failures, code coverage, slow tests, and build timing. Essential for parsing Xcode build output, diagnosing compile errors, analyzing test results, and measuring code coverage in any Swift or Xcode project.
        ---

        # xcsift - Xcode Build Output Formatter

        xcsift parses and formats xcodebuild/SPM output into token-efficient TOON format optimized for LLM consumption. It extracts compile errors, warnings, test failures, code coverage, and build timing from verbose Xcode output.

        ## When to Use

        **Always** pipe through xcsift when running:
        - `xcodebuild build` / `xcodebuild test`
        - `swift build` / `swift test`
        - Any command that produces Xcode/SPM build output

        ## Usage Pattern

        Always redirect stderr and use TOON format:

        ```bash
        # Build
        xcodebuild build 2>&1 | xcsift -f toon
        swift build 2>&1 | xcsift -f toon

        # Test
        swift test 2>&1 | xcsift -f toon
        xcodebuild test 2>&1 | xcsift -f toon

        # With warnings
        xcodebuild build 2>&1 | xcsift -f toon -w

        # With code coverage
        swift test --enable-code-coverage 2>&1 | xcsift -f toon -c
        xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift -f toon -c

        # With detailed per-file coverage
        swift test --enable-code-coverage 2>&1 | xcsift -f toon -c --coverage-details

        # With executable targets
        xcodebuild build 2>&1 | xcsift -f toon -e

        # Strict CI mode (fail on warnings or errors)
        xcodebuild build 2>&1 | xcsift -f toon -W -E

        # Slow test detection
        swift test 2>&1 | xcsift -f toon --slow-threshold 1.0

        # Build info (per-target phases, timing, dependencies)
        xcodebuild build 2>&1 | xcsift -f toon --build-info
        ```

        ## Key Flags

        | Flag | Description |
        |------|-------------|
        | `-f toon` | TOON format (30-60% fewer tokens than JSON) |
        | `-w` | Show detailed warnings list |
        | `-W` | Treat warnings as errors (Werror) |
        | `-q` | Quiet mode (no output on clean success) |
        | `-c` | Include code coverage summary |
        | `--coverage-details` | Per-file coverage breakdown (use with `-c`) |
        | `-e` | Include executable targets |
        | `-E` | Exit with non-zero code on build failure |
        | `--build-info` | Per-target phases, timing, and dependencies |
        | `--slow-threshold N` | Flag tests slower than N seconds |
        | `--config PATH` | Use custom config file (default: `.xcsift.toml`) |
        | `--init` | Generate `.xcsift.toml` template in current directory |

        ## Interpreting TOON Output

        TOON uses indentation-based structure with tabular arrays:

        ```toon
        status: failed
        summary:
          errors: 1
          warnings: 3
          failed_tests: 2
          passed_tests: 10
          build_time: 12.4s
          test_time: 5.2s
        errors[1]{file,line,message}:
          main.swift,15,"use of undeclared identifier 'foo'"
        warnings[3]{file,line,message,type}:
          Parser.swift,20,"unused variable 'result'",compile
          View.swift,42,"Publishing changes from background threads",swiftui
          Util.swift,10,"Custom warning message",runtime
        failed_tests[2]{suite,test,file,line,message,duration}:
          MyTests,testExample,MyTests.swift,25,"XCTAssertEqual failed",0.123
          MyTests,testOther,MyTests.swift,30,"XCTAssertTrue failed",0.456
        ```

        **Key patterns:**
        - `status`: `succeeded` or `failed`
        - `errors[N]{columns}:` — tabular array with N items, column names in braces
        - `warnings` have `type`: `compile`, `runtime`, or `swiftui`
        - `failed_tests` include file/line for navigation and duration
        - `null` values mean the data wasn't available

        ## Troubleshooting

        | Problem | Solution |
        |---------|----------|
        | No errors shown but build failed | Add `2>&1` to capture stderr |
        | Coverage shows `null` | Add `--enable-code-coverage` (SPM) or `-enableCodeCoverage YES` (xcodebuild) |
        | "xcsift not found" | Install: `brew install xcsift` or build from source |
        | Coverage for wrong target | xcsift auto-filters to tested target; use `--coverage-path` to override |
        | Config not loading | Check `.xcsift.toml` in CWD or `~/.config/xcsift/config.toml` |

        ## Important

        - **Always use `2>&1`** to capture stderr (compiler errors and warnings go to stderr)
        - TOON format reduces tokens by 30-60% compared to raw xcodebuild output
        - When running build commands, always add `| xcsift -f toon` to the end
        - Flaky test detection is automatic (no flag needed) — detects tests that both pass and fail
        """
}
