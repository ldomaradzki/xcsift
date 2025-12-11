# ``xcsift``

A Swift CLI tool to parse and format xcodebuild/SPM output for coding agents, optimized for token efficiency.

## Overview

xcsift transforms verbose Xcode build output into concise, structured formats that coding agents and LLMs can efficiently parse and act upon. Unlike `xcbeautify` and `xcpretty` which focus on human-readable output, xcsift prioritizes information density and machine readability.

### Key Features

- **Multiple output formats** — JSON (default), TOON (30-60% fewer tokens), or GitHub Actions
- **Structured error reporting** — Clear categorization of errors, warnings, linker errors, and test failures
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
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Usage>

### Reference

- <doc:OutputFormats>
- <doc:CodeCoverage>
