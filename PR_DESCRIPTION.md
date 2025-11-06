# Fix: Filter out JSON-like lines to prevent false error detection

## Problem
When xcodebuild output contains Swift compiler warning/note messages with string interpolation patterns (like `\(variable)`), the parser was incorrectly matching these patterns as actual build errors. This caused false positives where builds that succeeded were reported as failed.

Example of the issue:
```
/Path/To/File.swift:79:41: warning: string interpolation produces a debug description for an optional value; did you mean to make this explicit?

            return "Encryption error: \(message)"

                                        ^~~~~~~

/Path/To/File.swift:79:41: note: use 'String(describing:)' to silence this warning

            return "Encryption error: \(message)"

                                        ^~~~~~~

                                        String(describing:  )

/Path/To/File.swift:79:41: note: provide a default value to avoid this warning

            return "Encryption error: \(message)"

                                        ^~~~~~~

                                                ?? <#default value#>
```

These compiler warning/note lines were being parsed as 3 actual build errors, even though the manual Xcode build succeeded. The parser was matching the `\(message)` pattern in the note messages as error messages.

## Solution
- Added `isJSONLikeLine()` helper function to detect lines that look like structured data (JSON) or contain patterns that could be misinterpreted as error messages
- Updated `parseError()` and `parseWarning()` to skip these lines before attempting to parse
- Enhanced detection to handle:
  - JSON key-value patterns (`"key" : "value"`)
  - JSON array/object markers (`{`, `}`, `[`, `]`)
  - Escaped quotes and backslashes (like `\(variable)` patterns in compiler notes)
  - Indented structured data
  - Lines containing `error:` or `warning:` within structured/JSON context
  - Compiler note lines with string interpolation patterns that could be mistaken for error messages

## Testing
- Added test cases using the actual problematic compiler output that caused the issue
- Test verifies that compiler note lines with string interpolation patterns (`\(variable)`) are filtered correctly
- Test verifies that real build errors are still detected when mixed with compiler note lines
- All existing tests pass

## Changes
- `Sources/OutputParser.swift`: Added JSON detection logic
- `Tests/OutputParserTests.swift`: Added test cases for JSON filtering

## Verification
After this fix, compiler warning/note lines with interpolation patterns are correctly filtered:
```bash
# Test with actual problematic lines
cat << 'EOF' | xcsift
/Path/To/File.swift:79:41: warning: string interpolation produces a debug description for an optional value; did you mean to make this explicit?
            return "Encryption error: \(message)"
                                        ^~~~~~~
/Path/To/File.swift:79:41: note: use 'String(describing:)' to silence this warning
            return "Encryption error: \(message)"
                                        ^~~~~~~
EOF
# Output: status: "success", errors: 0 (warnings: 1, correctly parsed)

Real errors are still detected:
```bash
echo 'main.swift:15:5: error: use of undeclared identifier' | xcsift
# Output: status: "failed", errors: 1
```

