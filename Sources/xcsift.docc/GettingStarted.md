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
# Install from custom tap
brew tap ldomaradzki/xcsift
brew install xcsift
```

### Using Mint

```bash
mint install ldomaradzki/xcsift
```

### Using mise

```bash
# Install globally from mise registry
mise use -g xcsift

# Or explicitly via github backend (downloads binary)
mise use -g github:ldomaradzki/xcsift

# For project-local installation (adds to .mise.toml)
mise use xcsift

# Or add to your .mise.toml manually
# [tools]
# xcsift = "latest"
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

## What's Next

- <doc:Usage> — Complete CLI reference
- <doc:Configuration> — Configuration file format and options
- <doc:OutputFormats> — JSON, TOON, and GitHub Actions formats
- <doc:CodeCoverage> — Automatic coverage conversion
