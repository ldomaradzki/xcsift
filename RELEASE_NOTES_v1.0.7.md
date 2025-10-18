# Release v1.0.7

## What's Changed

### 🐛 Bug Fixes
- **Fix duplicate error messages in JSON output**: Swift compiler outputs each error twice (file location + visual caret line). xcsift now filters out the visual error lines to prevent duplicate entries in the JSON output, ensuring each error appears only once with proper file/line information.

### 📚 Documentation
- **Update all documentation to use `2>&1`**: All usage examples now include `2>&1` redirection to properly capture stderr output where compiler errors are written. This ensures complete error reporting in the JSON output.
- Updated README.md, CLAUDE.md, and command-line help text with proper stderr redirection examples

### ✨ Improvements
- Added unit test for Swift compiler visual error line filtering
- Improved help text to explain the importance of stderr redirection

### 🙏 Contributors
Special thanks to:
- **@NachoSoto** for contributing passed test count tracking in PR #5

## Installation

### Homebrew
```bash
brew upgrade ldomaradzki/xcsift/xcsift
```

### Direct Download
Download the latest release from the [releases page](https://github.com/ldomaradzki/xcsift/releases/tag/v1.0.7).

## Usage
Always use `2>&1` to redirect stderr to stdout:
```bash
xcodebuild build 2>&1 | xcsift
xcodebuild test 2>&1 | xcsift
swift build 2>&1 | xcsift
swift test 2>&1 | xcsift
```

**Full Changelog**: https://github.com/ldomaradzki/xcsift/compare/v1.0.6...v1.0.7
