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

### Formatting
**IMPORTANT:** Always run before committing changes:
```bash
swift format --recursive --in-place Sources Tests
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
swift build 2>&1 | xcsift --warnings
xcodebuild build 2>&1 | xcsift --warnings

# Quiet mode - suppress output when build succeeds with no warnings or errors
swift build 2>&1 | xcsift --quiet
xcodebuild build 2>&1 | xcsift -q

# Werror mode - treat warnings as errors (build fails if warnings present)
swift build 2>&1 | xcsift --Werror
xcodebuild build 2>&1 | xcsift -W

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

# TOON format (30-60% fewer tokens for LLMs)
# Token-Oriented Object Notation - optimized for LLM consumption

# Basic TOON output
xcodebuild build 2>&1 | xcsift --format toon
xcodebuild build 2>&1 | xcsift -f toon

# TOON with warnings
swift build 2>&1 | xcsift -f toon --warnings
xcodebuild build 2>&1 | xcsift -f toon -w

# TOON with coverage
swift test --enable-code-coverage 2>&1 | xcsift -f toon --coverage
xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift -f toon -c

# Combine all flags
xcodebuild test 2>&1 | xcsift -f toon -w -c --coverage-details

# TOON format features:
# - 30-60% token reduction compared to JSON
# - Tabular format for uniform arrays (errors, warnings, tests)
# - Human-readable indentation-based structure
# - Ideal for LLM consumption and API cost reduction
# - Works with all existing flags (--quiet, --coverage, --warnings)

# TOON Configuration - customize delimiter and length markers

# Delimiter options (default: comma):
# - comma: CSV-style format (default, most compact)
# - tab: TSV-style format (better for Excel/spreadsheet import)
# - pipe: Alternative separator (good for data with many commas)

# Tab delimiter - useful for Excel/spreadsheet import
xcodebuild build 2>&1 | xcsift -f toon --toon-delimiter tab
swift build 2>&1 | xcsift --format toon --toon-delimiter tab

# Pipe delimiter - alternative when data contains many commas
xcodebuild test 2>&1 | xcsift -f toon --toon-delimiter pipe

# Length marker options (default: none):
# - none: [3]{file,line,message}: (default, most compact)
# - hash: [#3]{file,line,message}: (Ruby/Perl-style length prefix)

# Hash length marker - adds # prefix to array counts
xcodebuild build 2>&1 | xcsift -f toon --toon-length-marker hash
swift build 2>&1 | xcsift --format toon --toon-length-marker hash

# Combine configuration options
xcodebuild test 2>&1 | xcsift -f toon --toon-delimiter tab --toon-length-marker hash -w -c
swift test 2>&1 | xcsift -f toon --toon-delimiter pipe --toon-length-marker hash --coverage-details

# TOON Key Folding - collapses nested single-key objects into dotted paths
# Key folding options (default: disabled):
# - disabled: Normal nested output (default)
# - safe: Collapses {a:{b:{c:1}}} → a.b.c: 1 when all keys are valid identifiers

# Enable key folding for more compact output
xcodebuild build 2>&1 | xcsift -f toon --toon-key-folding safe
swift build 2>&1 | xcsift --format toon --toon-key-folding safe

# Flatten depth - limits how deep key folding goes (default: unlimited)
xcodebuild build 2>&1 | xcsift -f toon --toon-key-folding safe --toon-flatten-depth 3
swift build 2>&1 | xcsift -f toon --toon-key-folding safe --toon-flatten-depth 2

# Combine all TOON options
xcodebuild test 2>&1 | xcsift -f toon --toon-delimiter pipe --toon-length-marker hash --toon-key-folding safe --toon-flatten-depth 5 -w -c
```

## Architecture

The codebase follows a simple two-component architecture:

### Core Components

1. **main.swift** - Entry point using Swift ArgumentParser
   - Reads from stdin and coordinates parsing/output
   - Outputs JSON or TOON format (controlled by `--format` / `-f` flag)

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
4. Output formatting (JSON or TOON) → stdout

### Key Features
- **Error/Warning Parsing**: Multiple regex patterns handle various Xcode error formats
- **Linker Error Parsing**: Captures undefined symbols, missing frameworks/libraries, architecture mismatches, and duplicate symbols (with structured conflicting file paths)
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

Tests are in `Tests/*.swift` using XCTest framework.

### Test Fixtures

Real-world output samples are stored in `Tests/Fixtures/` for integration tests:
- **build.txt** (~2.7MB) - Large successful xcodebuild output for performance testing
- **swift-testing-output.txt** (~11KB) - Swift Testing output with 23 passed tests
- **linker-error-output.txt** - Real linker error output with undefined symbols

To add new fixtures:
1. Create the file in `Tests/Fixtures/`
2. Add to `Package.swift` resources: `.copy("Fixtures/your-file.txt")`
3. Load in tests via `Bundle.module.url(forResource: "your-file", withExtension: "txt")`

### Test Coverage

Test cases cover:
- Error parsing from various Xcode formats
- Warning detection
- **Linker error parsing** (14 tests):
  - Undefined symbol errors
  - Multiple undefined symbols
  - Architecture mismatch errors
  - Framework/library not found
  - Duplicate symbols with structured conflicting_files parsing
  - Duplicate symbols with double quotes
  - Duplicate symbols JSON encoding
  - Mixed compiler and linker errors
  - Swift mangled symbols
  - Real-world linker error output (fixture-based test)
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
- **TOON format encoding** (24 tests):
  - Basic TOON encoding
  - TOON with errors, warnings, and failed tests
  - TOON with linker errors
  - TOON with code coverage
  - Token efficiency verification (30-60% reduction)
  - Summary-only vs details mode in TOON format
  - **TOON key folding features** (7 tests):
    - Key folding disabled by default
    - Key folding safe mode
    - Flatten depth default value
    - Flatten depth custom configuration
    - Key folding with build results
    - Key folding combined with flatten depth
    - Combined TOON configuration

Run individual tests:
```bash
swift test --filter OutputParserTests.testParseError
```

## Dependencies

- **Swift ArgumentParser**: CLI argument handling (Package.swift dependency)
- **TOONEncoder**: Token-Oriented Object Notation encoder for efficient LLM output (Package.swift dependency)
- **Foundation**: Core Swift framework for regex, JSON encoding, string processing
- **XCTest**: Testing framework (test target only)

## Platform Support

- **macOS 15+**: Full support including code coverage conversion
- **Linux (Swift 6.0+)**: Full support for build/test parsing; coverage features use macOS-specific tools (`xcrun`) and return `nil` on Linux

### Linux Compatibility Notes

When modifying code, ensure Linux compatibility:
- Use conditional imports: `#if canImport(Darwin)` / `#elseif canImport(Glibc)` / `#elseif canImport(Musl)`
- Avoid `fputs(..., stderr)` — use `FileHandle.standardError.write()` for Swift 6 concurrency safety
- CI runs on both macOS and Linux (see `.github/workflows/ci.yml`)

## Output Formats

The tool outputs structured data optimized for coding agents in two formats:

### JSON Format (default)

- **JSON**: Structured format with `status`, `summary`, `errors`, `warnings` (optional), `failed_tests`, `linker_errors` (optional), `coverage` (optional)
  - **Summary always includes warning and linker error counts**: `{"summary": {"warnings": N, "linker_errors": N, ...}}`
  - **Summary includes coverage percentage** (when `--coverage` flag is used): `{"summary": {"coverage_percent": X.X, ...}}`
  - **Detailed warnings list** (with `--warnings` flag): `{"warnings": [{"file": "...", "line": N, "message": "..."}]}`
  - **Linker errors**: Two types are supported:
    - **Undefined symbols**: `{"linker_errors": [{"symbol": "_MissingClass", "architecture": "arm64", "referenced_from": "ViewController.o", "message": "", "conflicting_files": []}]}`
    - **Duplicate symbols**: `{"linker_errors": [{"symbol": "_duplicateVar", "architecture": "arm64", "referenced_from": "", "message": "", "conflicting_files": ["/path/to/FileA.o", "/path/to/FileB.o"]}]}`
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

### TOON Format (with `--format toon` / `-f toon` flag)

**TOON (Token-Oriented Object Notation)** is a compact serialization format optimized for LLM consumption, providing **30-60% token reduction** compared to JSON.

**Key Features:**
- Tabular format for uniform arrays (errors, warnings, tests, coverage files)
- Indentation-based structure (similar to YAML)
- Human-readable while optimized for machine parsing
- Works with all existing flags (`--quiet`, `--coverage`, `--warnings`)
- Ideal for reducing LLM API costs

**Example TOON Output:**

```toon
status: failed
summary:
  errors: 1
  warnings: 3
  failed_tests: 0
  passed_tests: null
  build_time: null
  coverage_percent: null
errors[1]{file,line,message}:
  main.swift,15,"use of undeclared identifier \"unknown\""
warnings[3]{file,line,message}:
  Parser.swift,20,"immutable value \"result\" was never used"
  Parser.swift,25,"variable \"foo\" was never mutated"
  Model.swift,30,"initialization of immutable value \"bar\" was never used"
```

**Token Efficiency Comparison:**

For the same build output with 1 error and 3 warnings:
- **JSON**: 652 bytes
- **TOON**: 447 bytes
- **Savings**: 31.4% (205 bytes)

**When to Use TOON:**
- Passing build output to LLM APIs (reduces costs)
- Processing large build outputs with many errors/warnings
- Automated CI/CD pipelines with LLM analysis
- Token-constrained environments

**When to Use JSON:**
- Integrating with existing JSON-based tooling
- Maximum compatibility with JSON parsers
- Pretty-printed output for human debugging

### GitHub Actions Integration (automatic on CI)

When running on GitHub Actions (`GITHUB_ACTIONS=true`), xcsift automatically appends workflow annotations after the JSON/TOON output. This creates inline annotations in PRs and the Actions UI.

**Behavior Matrix:**

| Environment | Format Flag | Output |
|-------------|-------------|--------|
| Local | (none) | JSON |
| Local | `-f json` | JSON |
| Local | `-f toon` | TOON |
| Local | `-f github-actions` | Annotations only |
| CI | (none) | JSON + Annotations |
| CI | `-f json` | JSON + Annotations |
| CI | `-f toon` | TOON + Annotations |
| CI | `-f github-actions` | Annotations only |

**Example CI Output:**
```
{
  "status": "failed",
  "summary": { "errors": 1, "warnings": 2 }
}
::error file=main.swift,line=15,col=5::use of undeclared identifier 'unknown'
::warning file=Parser.swift,line=20,col=10::immutable value 'result' was never used
::notice ::Build failed, 1 error, 2 warnings
```

**Annotations Format:**
- `::error file=X,line=Y,col=Z::message` — compile errors, test failures
- `::warning file=X,line=Y,col=Z::message` — compiler warnings
- `::notice ::summary` — build summary

**Usage in CI:**
```yaml
# GitHub Actions workflow
- name: Build
  run: xcodebuild build 2>&1 | xcsift  # JSON + annotations automatic

- name: Build with TOON
  run: xcodebuild build 2>&1 | xcsift -f toon  # TOON + annotations automatic

- name: Annotations only (no JSON/TOON)
  run: xcodebuild build 2>&1 | xcsift -f github-actions
```
