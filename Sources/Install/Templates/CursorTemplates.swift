import Foundation

/// Templates for Cursor hook installation
enum CursorTemplates {

    /// The hooks.json content for Cursor (project-level)
    static let projectHooksJSON = """
        {
          "version": 1,
          "hooks": {
            "beforeShellExecution": [
              {
                "command": "./.cursor/hooks/pre-xcsift.sh"
              }
            ]
          }
        }
        """

    /// The hooks.json content for Cursor (global-level)
    static let globalHooksJSON = """
        {
          "version": 1,
          "hooks": {
            "beforeShellExecution": [
              {
                "command": "~/.cursor/hooks/pre-xcsift.sh"
              }
            ]
          }
        }
        """

    /// The pre-xcsift.sh hook script content
    static let hookScript = """
        #!/bin/bash
        # xcsift pre-shell hook for Cursor
        # Intercepts xcodebuild and swift build/test commands and pipes through xcsift

        # Read the command from environment or argument
        COMMAND="${CURSOR_SHELL_COMMAND:-$1}"

        if [ -z "$COMMAND" ]; then
            # No command, allow execution
            echo '{"permission": "allow"}'
            exit 0
        fi

        # Check if xcsift is available
        if ! command -v xcsift &> /dev/null; then
            # xcsift not installed, allow command as-is
            echo '{"permission": "allow"}'
            exit 0
        fi

        # Check if jq is available (required for JSON output)
        if ! command -v jq &> /dev/null; then
            # jq not installed, allow command as-is
            echo '{"permission": "allow"}'
            exit 0
        fi

        # Patterns that should be piped through xcsift
        # Match: xcodebuild, swift build, swift test (with any arguments)
        # But NOT: already piped through xcsift
        if echo "$COMMAND" | grep -qE '^\\s*(xcodebuild|swift\\s+(build|test))\\b' && \\
           ! echo "$COMMAND" | grep -q 'xcsift'; then

            # Add 2>&1 if not present (to capture stderr)
            if ! echo "$COMMAND" | grep -q '2>&1'; then
                COMMAND="$COMMAND 2>&1"
            fi

            # Pipe through xcsift with TOON format
            MODIFIED_COMMAND="$COMMAND | xcsift -f toon"

            # Return modified command
            jq -n --arg cmd "$MODIFIED_COMMAND" '{"permission": "allow", "updatedCommand": $cmd}'
        else
            # Not a build command, allow as-is
            echo '{"permission": "allow"}'
        fi
        """

    /// The SKILL.md content for Cursor
    /// Uses the shared template from SharedTemplates
    static let skillMarkdown = SharedTemplates.skillMarkdown
}
