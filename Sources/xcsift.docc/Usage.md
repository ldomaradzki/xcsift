# Usage

Complete CLI reference for xcsift commands and flags.

## Overview

xcsift reads from stdin and outputs structured build results. Always redirect stderr to stdout with `2>&1` to capture all compiler output.

## Basic Syntax

```bash
xcodebuild [flags] 2>&1 | xcsift [options]
swift build 2>&1 | xcsift [options]
swift test 2>&1 | xcsift [options]
```

## Output Format Options

### `--format`, `-f`

Select output format: `json` (default), `toon`, or `github-actions`.

```bash
# JSON (default)
xcodebuild build 2>&1 | xcsift

# TOON (30-60% fewer tokens)
xcodebuild build 2>&1 | xcsift --format toon
xcodebuild build 2>&1 | xcsift -f toon

# GitHub Actions annotations only
xcodebuild build 2>&1 | xcsift -f github-actions
```

## Warning Options

### `--warnings`, `-w`

Include detailed warnings array in output. By default, only warning count is shown in summary.

```bash
# Show detailed warnings
xcodebuild build 2>&1 | xcsift --warnings
swift build 2>&1 | xcsift -w
```

### `--Werror`, `-W`

Treat warnings as errors. Build fails if any warnings are present.

```bash
xcodebuild build 2>&1 | xcsift --Werror
swift build 2>&1 | xcsift -W
```

## Quiet Mode

### `--quiet`, `-q`

Suppress output when build succeeds with no warnings or errors.

```bash
xcodebuild build 2>&1 | xcsift --quiet
swift build 2>&1 | xcsift -q
```

## Coverage Options

### `--coverage`, `-c`

Enable code coverage output. Automatically converts `.profraw` (SPM) or `.xcresult` (xcodebuild) to JSON.

```bash
swift test --enable-code-coverage 2>&1 | xcsift --coverage
xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift -c
```

### `--coverage-details`

Include per-file coverage breakdown. Default is summary-only (percentage only) for token efficiency.

```bash
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-details
```

### `--coverage-path`

Specify custom path to coverage data (optional, auto-detected by default).

```bash
swift test --enable-code-coverage 2>&1 | xcsift --coverage --coverage-path .build/arm64-apple-macosx/debug/codecov
```

## TOON Configuration

### `--toon-delimiter`

Set delimiter for TOON tabular format: `comma` (default), `tab`, or `pipe`.

```bash
xcodebuild build 2>&1 | xcsift -f toon --toon-delimiter tab
xcodebuild build 2>&1 | xcsift -f toon --toon-delimiter pipe
```

### `--toon-key-folding`

Enable key folding: `disabled` (default) or `safe`.

```bash
# Collapses {a:{b:{c:1}}} to a.b.c: 1
xcodebuild build 2>&1 | xcsift -f toon --toon-key-folding safe
```

### `--toon-flatten-depth`

Limit key folding depth (default: unlimited).

```bash
xcodebuild build 2>&1 | xcsift -f toon --toon-key-folding safe --toon-flatten-depth 3
```

## Combined Examples

```bash
# TOON with warnings
swift build 2>&1 | xcsift -f toon -w

# TOON with coverage details
swift test --enable-code-coverage 2>&1 | xcsift -f toon -c --coverage-details

# All TOON options
xcodebuild test 2>&1 | xcsift -f toon --toon-delimiter pipe --toon-key-folding safe -w -c
```

## Exit Codes

- `0` — Build succeeded
- `1` — Build failed (errors, linker errors, or test failures)
- `1` — Build has warnings (when `--Werror` is used)
