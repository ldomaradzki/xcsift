#!/bin/bash
# xcsift pre-tool hook for Claude Code
# Intercepts xcodebuild and swift build/test commands and pipes through xcsift

set -e

# Read tool input from stdin (JSON with tool_input field)
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
    # No command field, allow as-is
    echo '{"decision": "allow"}'
    exit 0
fi

# Check if xcsift is available
if ! command -v xcsift &> /dev/null; then
    # xcsift not installed, allow command as-is
    echo '{"decision": "allow"}'
    exit 0
fi

# Patterns that should be piped through xcsift
# Match: xcodebuild, swift build, swift test (with any arguments)
# But NOT: already piped through xcsift
if echo "$COMMAND" | grep -qE '^\s*(xcodebuild|swift\s+(build|test))\b' && \
   ! echo "$COMMAND" | grep -q 'xcsift'; then

    # Add 2>&1 if not present (to capture stderr)
    if ! echo "$COMMAND" | grep -q '2>&1'; then
        COMMAND="$COMMAND 2>&1"
    fi

    # Pipe through xcsift with TOON format
    MODIFIED_COMMAND="$COMMAND | xcsift -f toon"

    # Return modified command
    jq -n --arg cmd "$MODIFIED_COMMAND" '{"decision": "allow", "updatedCommand": $cmd}'
else
    # Not a build command, allow as-is
    echo '{"decision": "allow"}'
fi
