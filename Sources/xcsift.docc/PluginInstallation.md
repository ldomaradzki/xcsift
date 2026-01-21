# Plugin Installation

Install xcsift plugins for Claude Code, Codex, and Cursor to automate build output processing.

## Overview

xcsift provides built-in commands to install and uninstall plugins for popular coding assistants. These plugins automatically pipe xcodebuild and swift build output through xcsift, providing structured error reporting without manual intervention.

## Supported Plugins

- **Claude Code** — Marketplace plugin with automatic hook integration
- **Codex** — Skill-based integration for xcsift commands
- **Cursor** — Project-level or global hook installation

## Claude Code Plugin

### Installation

Install the xcsift plugin from the Claude Code marketplace:

```bash
xcsift install-claude-code
```

This command performs two operations:
1. Adds the xcsift repository to the Claude Code marketplace: `claude plugin marketplace add ldomaradzki/xcsift`
2. Installs the plugin: `claude plugin install xcsift`

**Requirements:**
- Claude Code CLI must be installed
- Internet connection to access GitHub marketplace

After installation, xcodebuild and swift build commands are automatically piped through xcsift.

### Uninstallation

Remove the Claude Code plugin:

```bash
xcsift uninstall-claude-code
```

This removes the plugin but keeps the marketplace repository entry for faster reinstallation.

## Codex Skill

### Installation

Install the xcsift skill for Codex:

```bash
xcsift install-codex
```

This creates a skill file at:
- `~/.codex/skills/xcsift/SKILL.md` (global installation)

The skill provides command documentation and usage examples for xcsift within Codex.

**Requirements:**
- Codex skills directory must be accessible

### Uninstallation

Remove the Codex skill:

```bash
xcsift uninstall-codex
```

Deletes the skill directory from `~/.codex/skills/xcsift/`.

## Cursor Hooks

### Installation

Install xcsift hooks for Cursor at project level (default):

```bash
xcsift install-cursor
```

Or install globally for all projects:

```bash
xcsift install-cursor --global
```

**Project-level installation** creates:
- `.cursor/hooks.json` — Hook configuration
- `.cursor/hooks/pre-xcsift.sh` — Shell script for build output processing

**Global installation** creates hooks in:
- `~/.cursor/hooks.json`
- `~/.cursor/hooks/pre-xcsift.sh`

**Requirements:**
- Cursor must be configured to use hooks
- Hooks must be enabled in Cursor settings

After installation, xcodebuild and swift build commands are automatically processed by xcsift.

### Uninstallation

Remove Cursor hooks (detects project vs global automatically):

```bash
xcsift uninstall-cursor
```

Removes hook files and cleans up the hooks directory if empty.

## Verification

After installing any plugin, verify the installation:

### Claude Code

```bash
# Check plugin status
claude plugin list

# Test with a build
xcodebuild build 2>&1  # Should show xcsift-formatted output
```

### Codex

```bash
# Check skills directory
ls -la ~/.codex/skills/xcsift/

# Use the skill in Codex
# Type: /xcsift
```

### Cursor

```bash
# Check hooks (project-level)
cat .cursor/hooks.json

# Check hooks (global)
cat ~/.cursor/hooks.json

# Test with a build
xcodebuild build 2>&1  # Should show xcsift-formatted output
```

## Troubleshooting

### Claude Code: "Command not found: claude"

The Claude Code CLI is not installed or not in your PATH. Install it from [claude.ai/code](https://claude.ai/code).

### Codex: "Failed to create skill directory"

The `~/.codex/skills/` directory doesn't exist or isn't writable. Create it manually:

```bash
mkdir -p ~/.codex/skills/
```

### Cursor: "Failed to create hooks directory"

The `.cursor/` directory doesn't exist. Ensure you're in a project directory or use `--global` for user-wide installation.

### Hooks Not Executing

Verify that:
1. Hooks are enabled in your tool's settings
2. Hook files have execute permissions: `chmod +x .cursor/hooks/pre-xcsift.sh`
3. The `xcsift` binary is in your PATH: `which xcsift`

## Related Commands

See <doc:Usage> for xcsift command-line options and flags that work with installed plugins.
