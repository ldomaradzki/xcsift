# Release Notes - xcsift v1.0.9

## 🎉 New Features

### Warning Detection and Reporting
xcsift now captures and reports warnings from both Swift compiler and linters like SwiftLint!

**Key Features:**
- **Token-efficient design**: By default, only shows warning count in summary (reduces token usage for coding agents)
- **Optional detailed output**: Use `--print-warnings` flag to see full warnings list with file paths, line numbers, and messages
- **Universal detection**: Works with Swift compiler warnings, SwiftLint warnings, and other build tool warnings
- **Same format as errors**: Warnings use the same structured JSON format as errors for consistency

**Examples:**
```bash
# Show warning count only (default)
swift build 2>&1 | xcsift
# Output: {"summary": {"warnings": 5, ...}}

# Show detailed warnings list
swift build 2>&1 | xcsift --print-warnings
# Output includes: {"warnings": [{"file": "...", "line": 42, "message": "..."}]}
```

### SwiftLint Integration Support
Added SwiftLint as an optional SPM build plugin dependency to demonstrate linter integration:
- Detects TODO comments when SwiftLint's `todo` rule is enabled
- Captures all SwiftLint violations as warnings
- Compatible with existing SwiftLint configurations via `.swiftlint.yml`

**Note**: SwiftLint is included as a build plugin but is optional. You can remove it if not needed, or configure it via `.swiftlint.yml` to customize which rules are enforced.

## 🔧 Technical Changes

### OutputParser.swift
- Added `BuildWarning` struct with file, line, and message fields
- Updated `BuildSummary` to include warning count (always shown)
- Updated `BuildResult` with warnings array (conditionally serialized based on `printWarnings` flag)
- Implemented custom Codable encoding to handle conditional warnings output
- Added `parseWarning()` method with regex patterns matching Swift compiler and linter output formats
- Optimized line parsing with fast-path filtering for warning detection

### main.swift
- Added `--print-warnings` flag using ArgumentParser
- Passed flag through to parser for conditional output control

### Testing
- Added 5 comprehensive unit tests for warning detection:
  - Single warning parsing
  - Multiple warnings parsing
  - Mixed errors and warnings
  - Flag behavior (warnings array omitted without flag, included with flag)
- All tests pass (20 total: 18 existing + 5 new warning tests)
- Manual testing verified with swift build, swift test, xcodebuild build, and xcodebuild test

### Documentation
- Updated CLAUDE.md with `--print-warnings` examples
- Updated README.md with warning behavior documentation
- Updated `--help` output with new flag description

## 📦 Installation

### Homebrew
```bash
brew upgrade ldomaradzki/xcsift/xcsift
```

### Manual
```bash
git clone https://github.com/ldomaradzki/xcsift.git
cd xcsift
swift build -c release
cp .build/release/xcsift /usr/local/bin/
```

## 📝 Full Changelog
- **Added**: Warning detection from Swift compiler output
- **Added**: Warning detection from SwiftLint and other linters
- **Added**: `--print-warnings` flag for optional detailed warnings output
- **Added**: Warning count in summary (always shown)
- **Added**: SwiftLint build plugin integration (optional)
- **Added**: `.swiftlint.yml` configuration with TODO detection
- **Added**: 5 comprehensive unit tests for warning parsing
- **Improved**: Token efficiency by showing only warning count by default
- **Updated**: Documentation (CLAUDE.md, README.md) with warnings examples

---

**Full Diff**: https://github.com/ldomaradzki/xcsift/compare/v1.0.8...v1.0.9
