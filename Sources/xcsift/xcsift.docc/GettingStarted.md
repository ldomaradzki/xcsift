# Getting Started

Install xcsift and process your first build output.

## Overview

xcsift is a command-line tool that parses xcodebuild and Swift Package Manager output, transforming it into structured formats optimized for coding agents and LLMs.

## Requirements

- macOS 15.0 or later (full support including code coverage)
- Linux with Swift 6.0+ (build/test parsing; coverage unavailable)

## Installation

### Using Homebrew (Recommended)

```bash
brew install xcsift
```

### Using mise

```bash
# Install globally from mise registry
mise use -g xcsift

# Or explicitly via github backend (downloads binary)
mise use -g github:ldomaradzki/xcsift

# Or via the packslip backend: mise verifies each release's signed manifest
mise use -g 'packslip:github.com/ldomaradzki/xcsift[workflow=release.yml]'

# For project-local installation (adds to .mise.toml)
mise use xcsift

# Or add to your .mise.toml manually
# [tools]
# xcsift = "latest"
```

Every release after 1.6.0 publishes a signed release manifest, `packslip.sigstore.json`, beside its
archives. It is signed by this repository's release workflow and records each archive's digest,
platform, the `xcsift` executable, and what the host needs to start it: macOS 13 or later, or a Linux
with glibc 2.35 or later and `libstdc++.so.6`. With the `packslip:` backend, mise checks the signature
and the archive before unpacking it, and refuses a host that cannot run the binary.
`[workflow=release.yml]` accepts only releases signed by that workflow on a tag.

mise offers a release as `latest` once it is 24 hours old; name the version (`…@X.Y.Z`) to install a
newer one. The manifest also carries the agent skill for that version; see <doc:PluginInstallation>.

### Using Mint

```bash
mint install ldomaradzki/xcsift
```

### From Source

```bash
git clone https://github.com/ldomaradzki/xcsift.git
cd xcsift
swift build -c release
cp .build/release/xcsift /usr/local/bin/
```

## Quick Start

### Basic Build Output

Pipe xcodebuild or swift build output to xcsift:

```bash
# Important: Always use 2>&1 to capture stderr
xcodebuild build 2>&1 | xcsift

# Swift Package Manager
swift build 2>&1 | xcsift
```

### Test Output with Coverage

```bash
# SPM with coverage
swift test --enable-code-coverage 2>&1 | xcsift --coverage

# xcodebuild with coverage
xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage
```

### TOON Format for LLMs

For 30-60% token reduction when passing output to LLMs:

```bash
xcodebuild build 2>&1 | xcsift --format toon
```

### Configuration File

Generate a configuration file to store your default options:

```bash
# Generate template in current directory
xcsift --init
```

This creates `.xcsift.toml` where you can set defaults like output format, warnings, coverage, and more. CLI flags always override config file values.

### Plugin Installation

For automatic integration with coding assistants, install xcsift plugins:

```bash
# Claude Code
xcsift install-claude-code

# Codex
xcsift install-codex

# Cursor (project-level)
xcsift install-cursor

# Cursor (global)
xcsift install-cursor --global
```

See <doc:PluginInstallation> for detailed plugin documentation.

## What's Next

- <doc:Usage> — Complete CLI reference
- <doc:PluginInstallation> — Install plugins for Claude Code, Codex, and Cursor
- <doc:Configuration> — Configuration file format and options
- <doc:OutputFormats> — JSON, TOON, and GitHub Actions formats
- <doc:CodeCoverage> — Automatic coverage conversion
