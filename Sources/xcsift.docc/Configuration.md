# Configuration

Store default options in a TOML configuration file to reduce CLI flag complexity.

## Overview

xcsift supports TOML configuration files that let you set default values for all CLI options. CLI flags always override configuration file values, so you can use a config file for project-wide defaults while still overriding specific options when needed.

## Quick Start

Generate a template configuration file in your project:

```bash
xcsift --init
```

This creates `.xcsift.toml` with all options commented out. Uncomment and modify the options you want to change.

## Config File Locations

xcsift searches for configuration files in this order:

1. **Project config**: `.xcsift.toml` in current working directory
2. **User config**: `~/.config/xcsift/config.toml` in home directory

The first file found is used. If no configuration file exists, CLI defaults apply.

### Using a Custom Config Path

Use `--config` to specify a custom configuration file:

```bash
xcodebuild build 2>&1 | xcsift --config ~/my-project-config.toml
```

If the specified file doesn't exist, xcsift fails with an error.

## Configuration File Format

All options are optional. Omit an option to use its default value.

```toml
# .xcsift.toml

# Output format: "json" (default), "toon", or "github-actions"
format = "toon"

# Warning options
warnings = true          # Print detailed warnings list (-w)
werror = false           # Treat warnings as errors (-W)

# Output control
quiet = false            # Suppress output on success (-q)

# Test analysis
slow_threshold = 1.0     # Threshold in seconds for slow test detection

# Coverage options
coverage = false         # Enable coverage output (-c)
coverage_details = false # Include per-file coverage breakdown
coverage_path = ""       # Custom path to coverage data (empty = auto-detect)

# Build info
build_info = false       # Include per-target build phases and timing
executable = false       # Include executable targets (-e)

# Exit behavior
exit_on_failure = false  # Exit with failure code if build does not succeed (-E)

# TOON format configuration
[toon]
delimiter = "comma"      # "comma", "tab", or "pipe"
key_folding = "disabled" # "disabled" or "safe"
flatten_depth = 0        # 0 = unlimited, or positive integer
```

## Option Reference

### Output Format

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `format` | string | `"json"` | Output format: `json`, `toon`, or `github-actions` |

### Warning Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `warnings` | bool | `false` | Include detailed warnings array |
| `werror` | bool | `false` | Treat warnings as errors |

### Output Control

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `quiet` | bool | `false` | Suppress output on success |

### Test Analysis

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `slow_threshold` | float | none | Threshold in seconds for slow test detection |

### Coverage Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `coverage` | bool | `false` | Enable coverage output |
| `coverage_details` | bool | `false` | Include per-file coverage breakdown |
| `coverage_path` | string | `""` | Custom path to coverage data (empty = auto-detect) |

### Build Info

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `build_info` | bool | `false` | Include per-target build phases and timing |
| `executable` | bool | `false` | Include executable targets |

### Exit Behavior

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `exit_on_failure` | bool | `false` | Exit with failure code if build does not succeed |

### TOON Configuration

Options in the `[toon]` section:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `delimiter` | string | `"comma"` | Tabular delimiter: `comma`, `tab`, or `pipe` |
| `key_folding` | string | `"disabled"` | Key folding mode: `disabled` or `safe` |
| `flatten_depth` | int | `0` | Key folding depth limit (0 = unlimited) |

## Priority Rules

**CLI flags always take precedence over configuration file values.**

When a CLI flag is provided, it overrides the config file value. When a CLI flag is not provided, the config file value is used. When neither is provided, the default value applies.

### Boolean Flags (OR Semantics)

Boolean flags (`--warnings`, `--quiet`, `--coverage`, etc.) use **OR semantics**:
- If CLI flag is passed → enabled
- If config value is `true` → enabled
- Only disabled when both CLI flag is absent AND config is `false` (or unset)

This means you **cannot disable** a boolean flag via CLI if it's enabled in the config file. To disable, you must edit or remove the config file value.

### Example

Given this configuration file:

```toml
format = "toon"
warnings = true
```

```bash
# Uses config: format=toon, warnings=true
xcodebuild build 2>&1 | xcsift

# CLI overrides format: format=json, warnings=true (from config)
xcodebuild build 2>&1 | xcsift -f json

# warnings still true (from config) — no --no-warnings flag exists
xcodebuild build 2>&1 | xcsift -f json
```

## Error Messages

Configuration errors provide user-friendly messages that tell you exactly what went wrong and where:

```
Error: Configuration file not found: /path/to/config.toml

Error: TOML syntax error at line 5, column 12: unterminated string

Error: Invalid value 'yaml' for 'format'. Valid options: json, toon, github-actions

Error: Type mismatch at 'warnings': expected Bool, found String
```

## Use Cases

### Project-Wide Defaults

Create `.xcsift.toml` in your project root with team defaults:

```toml
# Always use TOON format for token efficiency
format = "toon"

# Always show detailed warnings
warnings = true

# Set a reasonable slow test threshold
slow_threshold = 2.0
```

### User Defaults

Create `~/.config/xcsift/config.toml` for personal preferences that apply to all projects:

```toml
# Personal preference for TOON format
format = "toon"

# Custom TOON settings
[toon]
delimiter = "tab"
key_folding = "safe"
```

### CI/CD Configuration

For CI, you might want different settings:

```toml
# .xcsift.toml for CI
format = "json"
warnings = true
werror = true            # Fail on warnings
exit_on_failure = true   # Return non-zero exit code on failure
coverage = true
coverage_details = true
build_info = true
```

**Tip:** Combining `werror = true` and `exit_on_failure = true` ensures your CI pipeline fails on any errors, warnings, or test failures. This is useful for enforcing code quality standards.

## Topics

### Related

- <doc:Usage>
- <doc:OutputFormats>
