# xcsift

A Swift command-line tool to parse and format xcodebuild/SPM output for coding agents, optimized for token efficiency.

## Overview

`xcsift` is designed to process verbose Xcode build output and transform it into a concise, structured format that coding agents can efficiently parse and act upon. Unlike `xcbeautify` and `xcpretty` which focus on human-readable output, `xcsift` prioritizes information density and machine readability.

## Features

- **Token-efficient JSON output** - Structured format optimized for coding agents
- **Structured error reporting** - Clear categorization of errors, warnings, and test failures
- **File/line number extraction** - Easy navigation to problematic code locations
- **Build status summary** - Quick overview of build results
- **Automatic code coverage conversion** - Converts .profraw (SPM) and .xcresult (xcodebuild) to JSON automatically
- **Target filtering** - Automatically filters xcodebuild coverage to tested target only
- **Summary-only mode** - Default coverage output includes only percentage (token-efficient)
- **Quiet mode** - Suppress output when build succeeds with no warnings or errors

## Installation

### Option 1: Homebrew (Recommended)

```bash
# Install from custom tap
brew tap ldomaradzki/xcsift
brew install xcsift

# Or install directly from formula
brew install https://raw.githubusercontent.com/ldomaradzki/xcsift/master/homebrew-formula/xcsift.rb
```

### Option 2: Download Pre-built Binary

Download the latest release from [GitHub Releases](https://github.com/ldomaradzki/xcsift/releases):

```bash
# Download and extract
curl -L https://github.com/ldomaradzki/xcsift/releases/latest/download/xcsift-vX.X.X-macos-arm64.tar.gz | tar -xz

# Move to PATH
mv xcsift /usr/local/bin/xcsift
chmod +x /usr/local/bin/xcsift

# If you get a quarantine warning when running xcsift:
# Remove the quarantine attribute (macOS security feature)
xattr -d com.apple.quarantine /usr/local/bin/xcsift
```

> **Note**: This binary is not code-signed with an Apple Developer ID certificate. macOS will show a security warning when first running it. The `xattr` command above removes the quarantine flag. For open source projects, Apple's $99/year Developer Program is required for code signing - there are no free alternatives for macOS.

### Option 3: Build from Source

```bash
git clone https://github.com/ldomaradzki/xcsift.git
cd xcsift
swift build -c release
cp .build/release/xcsift /usr/local/bin/
```

## Usage

Pipe xcodebuild output directly to xcsift:

```bash
xcodebuild [flags] 2>&1 | xcsift
```

**Important**: Always use `2>&1` to redirect stderr to stdout. This ensures all compiler errors, warnings, and build output are captured, removing noise and providing clean, structured JSON output.

Currently outputs JSON format only.

### Examples

```bash
# Basic usage with JSON output (warning count shown in summary only)
xcodebuild build 2>&1 | xcsift

# Print detailed warnings list (useful for fixing warnings)
xcodebuild build 2>&1 | xcsift --print-warnings
xcodebuild build 2>&1 | xcsift -w

# Quiet mode - suppress output when build succeeds with no warnings or errors
xcodebuild build 2>&1 | xcsift --quiet
swift build 2>&1 | xcsift -q

# Code coverage - automatic conversion from .profraw or .xcresult to JSON
# Default: summary-only mode (line coverage percentage only - token-efficient)
# xcodebuild automatically searches ~/Library/Developer/Xcode/DerivedData for latest .xcresult
# and filters to tested target only
swift test --enable-code-coverage 2>&1 | xcsift --coverage
xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage
xcodebuild test 2>&1 | xcsift -c

# Show detailed per-file coverage (use when you need file-by-file breakdown)
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-details
xcodebuild test 2>&1 | xcsift -c --coverage-details

# Specify custom coverage path (optional - auto-detects by default)
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-path .build/arm64-apple-macosx/debug/codecov

# Test output parsing
xcodebuild test 2>&1 | xcsift

# Swift Package Manager support
swift build 2>&1 | xcsift
swift test 2>&1 | xcsift
```

## Output Format

### JSON Format

```json
{
  "status": "failed",
  "summary": {
    "errors": 2,
    "warnings": 1,
    "failed_tests": 2,
    "passed_tests": 28,
    "build_time": "3.2",
    "coverage_percent": 85.5
  },
  "errors": [
    {
      "file": "main.swift",
      "line": 15,
      "message": "use of undeclared identifier 'unknown'"
    }
  ],
  "warnings": [
    {
      "file": "ViewController.swift",
      "line": 23,
      "message": "variable 'temp' was never used; consider removing it"
    }
  ],
  "failed_tests": [
    {
      "test": "Test assertion",
      "message": "XCTAssertEqual failed: (\"invalid\") is not equal to (\"valid\")"
    }
  ],
  "coverage": {
    "line_coverage": 85.5,
    "files": [
      {
        "path": "/path/to/ViewController.swift",
        "name": "ViewController.swift",
        "line_coverage": 92.5,
        "covered_lines": 37,
        "executable_lines": 40
      }
    ]
  }
}
```

**Note on warnings:** By default, only the warning count appears in `summary.warnings`. The detailed `warnings` array (shown above) is only included when using the `--print-warnings` flag. This reduces token usage for coding agents that don't need to process every warning.

**Note on coverage:** The `coverage` section is only included when using the `--coverage-details` flag:
- **Summary-only mode** (default): Only includes coverage percentage in summary for maximum token efficiency
  ```json
  {
    "summary": {
      "coverage_percent": 85.5
    }
  }
  ```
- **Details mode** (with `--coverage-details`): Includes full `files` array as shown in the example above
- **Target filtering** (xcodebuild only): Automatically extracts tested target from stdout and shows coverage for that target only
- xcsift automatically converts `.profraw` files (SPM) or `.xcresult` bundles (xcodebuild) to JSON format without requiring manual llvm-cov or xccov commands


## Comparison with xcbeautify/xcpretty

| Feature | xcsift | xcbeautify | xcpretty |
|---------|---------|------------|----------|
| **Target audience** | Coding agents | Humans | Humans |
| **Output format** | JSON | Colorized text | Formatted text |
| **Token efficiency** | High | Medium | Low |
| **Machine readable** | Yes | No | Limited |
| **Error extraction** | Structured | Visual | Visual |
| **Code coverage** | Auto-converts | No | No |
| **Build time** | Fast | Fast | Slower |

## Development

### Running Tests

```bash
swift test
```

### Building

```bash
swift build
```

## License

MIT License