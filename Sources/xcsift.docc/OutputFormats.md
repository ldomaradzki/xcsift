# Output Formats

Understanding JSON, TOON, and GitHub Actions output formats.

## Overview

xcsift supports three output formats optimized for different use cases:

- **JSON** — Standard structured format, maximum compatibility
- **TOON** — Token-efficient format for LLMs (30-60% fewer tokens)
- **GitHub Actions** — Workflow annotations for PR integration

## JSON Format

The default format outputs structured JSON with build status, summary, and detailed error information.

### Structure

```json
{
  "status": "failed",
  "summary": {
    "errors": 1,
    "warnings": 2,
    "failed_tests": 0,
    "linker_errors": 0,
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
  ]
}
```

### Fields

| Field | Description |
|-------|-------------|
| `status` | `"succeeded"` or `"failed"` |
| `summary.errors` | Count of compiler errors |
| `summary.warnings` | Count of warnings |
| `summary.failed_tests` | Count of failed tests |
| `summary.linker_errors` | Count of linker errors |
| `summary.passed_tests` | Count of passed tests (if available) |
| `summary.build_time` | Build duration in seconds |
| `summary.coverage_percent` | Line coverage percentage (with `--coverage`) |

### Optional Arrays

- `errors[]` — Always included when errors exist
- `warnings[]` — Only with `--warnings` flag
- `linker_errors[]` — Included when linker errors detected
- `failed_tests[]` — Included when test failures detected
- `coverage{}` — Only with `--coverage --coverage-details`

### Linker Errors

Two types of linker errors are captured:

**Undefined Symbols:**
```json
{
  "symbol": "_OBJC_CLASS_$_MissingClass",
  "architecture": "arm64",
  "referenced_from": "ViewController.o",
  "message": "",
  "conflicting_files": []
}
```

**Duplicate Symbols:**
```json
{
  "symbol": "_globalConfiguration",
  "architecture": "arm64",
  "referenced_from": "",
  "message": "",
  "conflicting_files": ["/path/to/ConfigA.o", "/path/to/ConfigB.o"]
}
```

## TOON Format

TOON (Token-Oriented Object Notation) provides 30-60% token reduction compared to JSON, ideal for LLM consumption.

### Example Output

```toon
status: failed
summary:
  errors: 1
  warnings: 3
  failed_tests: 0
  linker_errors: 0
errors[1]{file,line,message}:
  main.swift,15,"use of undeclared identifier \"unknown\""
warnings[3]{file,line,message}:
  Parser.swift,20,"immutable value \"result\" was never used"
  Parser.swift,25,"variable \"foo\" was never mutated"
  Model.swift,30,"initialization of immutable value \"bar\" was never used"
```

### Features

- **Tabular arrays** — Uniform arrays shown as compact tables
- **Indentation-based** — Similar to YAML structure
- **Human-readable** — Easy to scan while optimized for machines

### Token Savings Example

Same build output (1 error, 3 warnings):
- JSON: 652 bytes
- TOON: 447 bytes
- **Savings: 31.4%**

### Configuration Options

| Option | Values | Description |
|--------|--------|-------------|
| `--toon-delimiter` | `comma`, `tab`, `pipe` | Table delimiter |
| `--toon-key-folding` | `disabled`, `safe` | Collapse nested objects |
| `--toon-flatten-depth` | Integer | Limit folding depth |

## GitHub Actions Format

On GitHub Actions (when `GITHUB_ACTIONS=true`), xcsift automatically appends workflow annotations after JSON/TOON output.

### Behavior Matrix

| Environment | Format Flag | Output |
|-------------|-------------|--------|
| Local | (none) | JSON |
| Local | `-f toon` | TOON |
| Local | `-f github-actions` | Annotations only |
| **CI** | **(none)** | **JSON + Annotations** |
| **CI** | **`-f toon`** | **TOON + Annotations** |
| CI | `-f github-actions` | Annotations only |

### Annotation Types

```
::error file=main.swift,line=15,col=5::use of undeclared identifier 'unknown'
::warning file=Parser.swift,line=20,col=10::immutable value 'result' was never used
::notice ::Build failed, 1 error, 2 warnings
```

### Workflow Example

```yaml
- name: Build
  run: |
    set -o pipefail
    xcodebuild build 2>&1 | xcsift
    # Outputs JSON + annotations automatically on CI
```

## Choosing a Format

| Use Case | Recommended Format |
|----------|-------------------|
| LLM/AI tools | TOON (`-f toon`) |
| JSON tooling integration | JSON (default) |
| CI/CD with GitHub | Auto-detected |
| Debugging | JSON with `--warnings` |
| API cost optimization | TOON |
