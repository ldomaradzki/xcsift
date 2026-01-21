# ``xcsift``

A Swift CLI tool to parse and format xcodebuild/SPM output for coding agents, optimized for token efficiency.

## Overview

xcsift transforms verbose Xcode build output into concise, structured formats that coding agents and LLMs can efficiently parse and act upon. Unlike `xcbeautify` and `xcpretty` which focus on human-readable output, xcsift prioritizes information density and machine readability.

### Key Features

- **Multiple output formats** — JSON (default), TOON (30-60% fewer tokens), or GitHub Actions
- **Configuration files** — Store default options in `.xcsift.toml` for project-wide or user-wide defaults
- **Structured error reporting** — Clear categorization of errors, warnings, linker errors, and test failures
- **Test analysis** — Duration tracking, slow test detection (`--slow-threshold`), automatic flaky test detection
- **Automatic code coverage** — Converts `.profraw` (SPM) and `.xcresult` (xcodebuild) automatically
- **GitHub Actions integration** — Auto-detected workflow annotations with inline PR comments
- **Token efficiency** — TOON format reduces API costs for LLM-based tools

### Basic Usage

```bash
# Pipe xcodebuild output to xcsift
xcodebuild build 2>&1 | xcsift

# Use TOON format for LLM consumption
xcodebuild build 2>&1 | xcsift --format toon

# Include code coverage
swift test --enable-code-coverage 2>&1 | xcsift --coverage

# Detect slow tests (>1s threshold)
swift test 2>&1 | xcsift --slow-threshold 1.0
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Usage>
- <doc:PluginInstallation>

### Reference

- <doc:OutputFormats>
- <doc:CodeCoverage>
- <doc:Configuration>
