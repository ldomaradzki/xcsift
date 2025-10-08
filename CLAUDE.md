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
# IMPORTANT: Always use 2>&1 to capture stderr (where compiler errors are written)
xcodebuild build 2>&1 | xcsift

# Test output parsing
xcodebuild test 2>&1 | xcsift

# Swift Package Manager
swift build 2>&1 | xcsift
swift test 2>&1 | xcsift
```

## Architecture

The codebase follows a simple two-component architecture:

### Core Components

1. **main.swift** - Entry point using Swift ArgumentParser
   - Reads from stdin and coordinates parsing/output
   - Outputs JSON format only

2. **OutputParser.swift** - Core parsing logic
   - `OutputParser` class with regex-based line parsing
   - Defines data structures: `BuildResult`, `BuildSummary`, `BuildError`, `BuildWarning`, `FailedTest`
   - Pattern matching for various Xcode/SPM output formats
   - Extracts file paths, line numbers, and messages from build output

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

## Testing

Tests are in `Tests/OutputParserTests.swift` using XCTest framework. Test cases cover:
- Error parsing from various Xcode formats
- Warning detection
- Failed test extraction
- Multi-error scenarios
- Build time parsing
- Edge cases (missing files, deprecated functions)

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

- **JSON**: Structured format with `status`, `summary`, `errors`, `warnings`, `failed_tests`