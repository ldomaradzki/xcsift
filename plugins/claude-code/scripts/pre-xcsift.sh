#!/bin/bash
# xcsift pre-tool hook for Claude Code
# Intercepts xcodebuild and swift build/test commands and pipes through xcsift

ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'

# Read tool input from stdin (JSON with tool_input field)
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
    # No command field, allow as-is
    echo "$ALLOW"
    exit 0
fi

# Check if xcsift is available
if ! command -v xcsift &> /dev/null; then
    # xcsift not installed, allow command as-is
    echo "$ALLOW"
    exit 0
fi

# Build commands. The leading separator also matches `cd App && xcodebuild build`.
BUILD_RE='(^|[;&|][[:space:]]*)[[:space:]]*(xcodebuild|swift[[:space:]]+(build|test))([[:space:]]|$)'

# Informational commands print an answer, not a build log. xcsift discards that answer.
QUERY_RE='(^|[[:space:]])--?(version|usage|help|h|list|showsdks|showdestinations|showTestPlans|showBuildSettings|showBuildSettingsForIndex|find-executable|find-library|checkFirstLaunchStatus|create-xcframework|show-bin-path|list-tests)([[:space:]]|$)'

# Remove the redirections this hook adds, to find the redirections the user wrote.
BARE=$(printf '%s' "$COMMAND" | sed 's/2>&1//g; s/>&2//g')

if echo "$COMMAND" | grep -qE "$BUILD_RE" \
   && ! echo "$COMMAND" | grep -qE "$QUERY_RE" \
   && ! echo "$COMMAND" | grep -q 'xcsift' \
   && ! echo "$BARE" | grep -qE '[|>]'; then

    # Group the command, so each part of a `;` or `&&` chain goes to xcsift.
    MODIFIED_COMMAND="{ $COMMAND ; } 2>&1 | xcsift -f toon"

    # Return modified command with rewritten input
    jq -n --arg cmd "$MODIFIED_COMMAND" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":$cmd}}}'
else
    # Not a build command, allow as-is
    echo "$ALLOW"
fi
