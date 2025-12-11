# Code Coverage

Automatic code coverage conversion and reporting.

## Overview

xcsift automatically converts coverage data from both Swift Package Manager and xcodebuild formats without requiring manual llvm-cov or xccov commands.

## Enabling Coverage

### Swift Package Manager

```bash
swift test --enable-code-coverage 2>&1 | xcsift --coverage
```

### xcodebuild

```bash
xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage
```

## Output Modes

### Summary-Only (Default)

By default, only the coverage percentage is included for token efficiency:

```json
{
  "summary": {
    "coverage_percent": 85.5
  }
}
```

### Details Mode

Use `--coverage-details` for per-file breakdown:

```bash
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-details
```

Output:
```json
{
  "summary": {
    "coverage_percent": 85.5
  },
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

## Auto-Detection

xcsift automatically searches for coverage data in common locations:

### SPM Paths
- `.build/debug/codecov`
- `.build/arm64-apple-macosx/debug/codecov`
- `.build/x86_64-apple-macosx/debug/codecov`

### xcodebuild Paths
- `~/Library/Developer/Xcode/DerivedData/**/*.xcresult`
- `./**/*.xcresult`

### Custom Path

Override auto-detection with `--coverage-path`:

```bash
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-path .build/arm64-apple-macosx/debug/codecov
```

## Automatic Conversion

### SPM Coverage

xcsift performs automatic conversion:
1. Finds `.profraw` files
2. Locates test binary
3. Runs `llvm-profdata merge`
4. Runs `llvm-cov export`

### xcodebuild Coverage

xcsift handles xcresult bundles:
1. Finds latest `.xcresult` bundle
2. Runs `xcrun xccov view --report --json`
3. Extracts target from build output
4. Filters coverage to tested target only

## Target Filtering

For xcodebuild, xcsift automatically extracts the tested target name from stdout and filters coverage to that target only. This prevents unrelated framework coverage from cluttering the output.

If no matching coverage data is found, a warning is printed to stderr.

## Platform Support

| Platform | Coverage Support |
|----------|-----------------|
| macOS 15+ | Full support |
| Linux (Swift 6.0+) | Not available (macOS tools required) |

## TOON Format

Coverage works with TOON format:

```bash
swift test --enable-code-coverage 2>&1 | xcsift -f toon --coverage
```

Summary-only TOON output:
```toon
status: succeeded
summary:
  errors: 0
  warnings: 0
  failed_tests: 0
  passed_tests: 42
  coverage_percent: 85.5
```
