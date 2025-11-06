# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

xcsift is a Swift command-line tool that parses and formats xcodebuild/SPM output for coding agents. It transforms verbose Xcode build output into token-efficient JSON format optimized for machine readability rather than human consumption.

## Commands

### Building
```bash
swift build
swift build -c release
```

### Testing
```bash
swift test
```

### Installation
```bash
swift build -c release
cp .build/release/xcsift /usr/local/bin/
```

### Running the Tool
```bash
# Basic usage (reads from stdin)
# IMPORTANT: Always use 2>&1 to capture stderr (where compiler errors and warnings are written)
xcodebuild build 2>&1 | xcsift

# Test output parsing
xcodebuild test 2>&1 | xcsift

# Swift Package Manager
swift build 2>&1 | xcsift
swift test 2>&1 | xcsift

# Print detailed warnings list (by default only warning count is shown in summary)
swift build 2>&1 | xcsift --print-warnings
xcodebuild build 2>&1 | xcsift --print-warnings

# Quiet mode - suppress output when build succeeds with no warnings or errors
swift build 2>&1 | xcsift --quiet
xcodebuild build 2>&1 | xcsift -q

# Code coverage - automatically converts .profraw/.xcresult to JSON (no manual conversion needed!)

# SPM: auto-detects and converts .profraw files (summary-only by default)
swift test --enable-code-coverage 2>&1 | xcsift --coverage
swift test --enable-code-coverage 2>&1 | xcsift -c

# xcodebuild: auto-detects and converts .xcresult bundles (searches DerivedData automatically!)
# Automatically filters coverage to tested target only
xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage

# Show detailed per-file coverage (default is summary-only for token efficiency)
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-details
xcodebuild test 2>&1 | xcsift -c --coverage-details

# Specify custom coverage path (optional - auto-detects by default)
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-path .build/arm64-apple-macosx/debug/codecov
xcodebuild test 2>&1 | xcsift --coverage --coverage-path path/to/file.xcresult

# Auto-detection and conversion:
# SPM (.profraw → .profdata → JSON via llvm tools):
#   - .build/debug/codecov
#   - .build/arm64-apple-macosx/debug/codecov
#   - .build/x86_64-apple-macosx/debug/codecov
#   - .build/arm64-unknown-linux-gnu/debug/codecov
#   - .build/x86_64-unknown-linux-gnu/debug/codecov
#
# xcodebuild (.xcresult → JSON via xcrun xccov):
#   - ~/Library/Developer/Xcode/DerivedData/**/*.xcresult (searches automatically)
#   - Current directory/**/*.xcresult
```

## Architecture

The codebase follows a simple two-component architecture:

### Core Components

1. **main.swift** - Entry point using Swift ArgumentParser
   - Reads from stdin and coordinates parsing/output
   - Outputs JSON format only

2. **OutputParser.swift** - Core parsing logic
   - `OutputParser` class with regex-based line parsing
   - Defines data structures: `BuildResult`, `BuildSummary`, `BuildError`, `BuildWarning`, `FailedTest`, `CodeCoverage`, `FileCoverage`
   - Pattern matching for various Xcode/SPM output formats
   - Extracts file paths, line numbers, and messages from build output
   - Parses code coverage data from SPM coverage JSON files

### Data Flow
1. Stdin input → `readStandardInput()`
2. Raw text → `OutputParser.parse()` → line-by-line regex matching
3. Parsed data → `BuildResult` struct
4. Output formatting (JSON/compact) → stdout

### Key Features
- **Error/Warning Parsing**: Multiple regex patterns handle various Xcode error formats
- **Test Failure Detection**: XCUnit assertion failures and general test failures
- **Build Time Extraction**: Captures build duration from output
- **File/Line Mapping**: Extracts precise source locations for navigation
- **Code Coverage with Auto-Conversion**: Automatically converts coverage files to JSON when `--coverage` flag is used
  - **Auto-detection**: Searches multiple default paths for both SPM and xcodebuild formats
  - **Target filtering**: Automatically extracts tested target name from xcodebuild output and filters coverage to that target only
  - **Summary-only mode** (default): Outputs only line coverage percentage to minimize token usage
  - **Details mode** (with `--coverage-details`): Includes full per-file coverage data
  - **SPM auto-conversion**: Finds `.profraw` files, locates test binary, runs `llvm-profdata merge` and `llvm-cov export`
    - `.profraw` → `.profdata` → JSON (fully automatic)
  - **xcodebuild auto-conversion**: Finds `.xcresult` bundles, runs `xcrun xccov view --report --json`
    - `.xcresult` → JSON (fully automatic)
  - **No manual steps**: Works out of the box with both build systems
    - SPM: `swift test --enable-code-coverage 2>&1 | xcsift --coverage`
    - xcodebuild: `xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage`
  - Supports both formats seamlessly

## Testing

Tests are in `Tests/OutputParserTests.swift` using XCTest framework. Test cases cover:
- Error parsing from various Xcode formats
- Warning detection
- Failed test extraction
- Multi-error scenarios
- Build time parsing
- Edge cases (missing files, deprecated functions)
- Code coverage data structures and parsing
- JSON encoding with and without coverage data
- SPM coverage format parsing
- xcodebuild coverage format parsing (decimal and percentage formats)
- Format auto-detection
- Target extraction from xcodebuild output
- Coverage target filtering
- Summary-only vs details mode for coverage output

Run individual tests:
```bash
swift test --filter OutputParserTests.testParseError
```

## Dependencies

- **Swift ArgumentParser**: CLI argument handling (Package.swift dependency)
- **Foundation**: Core Swift framework for regex, JSON encoding, string processing
- **XCTest**: Testing framework (test target only)

## Output Formats

The tool outputs structured data optimized for coding agents:

- **JSON**: Structured format with `status`, `summary`, `errors`, `warnings` (optional), `failed_tests`, `coverage` (optional)
  - **Summary always includes warning count**: `{"summary": {"warnings": N, ...}}`
  - **Summary includes coverage percentage** (when `--coverage` flag is used): `{"summary": {"coverage_percent": X.X, ...}}`
  - **Detailed warnings list** (with `--print-warnings` flag): `{"warnings": [{"file": "...", "line": N, "message": "..."}]}`
  - **Default behavior** (without flag): Only shows warning count in summary, omits detailed warnings array to reduce token usage
  - **Quiet mode** (with `--quiet` or `-q` flag): Produces no output when build succeeds with zero warnings and zero errors
  - **Coverage data** (with `--coverage` flag):
    - **Summary-only mode** (default - token-efficient): Only includes coverage percentage in summary
      ```json
      {
        "summary": {
          "coverage_percent": 85.5
        }
      }
      ```
    - **Details mode** (with `--coverage-details` flag): Includes per-file coverage details
      ```json
      {
        "coverage": {
          "line_coverage": 85.5,
          "files": [
            {
              "path": "/path/to/file.swift",
              "name": "file.swift",
              "line_coverage": 92.5,
              "covered_lines": 37,
              "executable_lines": 40
            }
          ]
        }
      }
      ```
    - **Target filtering** (xcodebuild only): Automatically extracts tested target from stdout and filters coverage to that target only
    - Supports both SPM (`swift test --enable-code-coverage`) and xcodebuild (`-enableCodeCoverage YES`) formats
    - Automatically detects format and parses accordingly
    - Warns to stderr if target was detected but no matching coverage data found
