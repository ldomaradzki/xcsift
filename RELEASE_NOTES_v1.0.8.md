# Release Notes - xcsift v1.0.8

## 🚀 Performance & Bug Fixes

### Fixed: Stdin Hanging on Large Files
Previously, xcsift would hang indefinitely when processing large build output files (2+ MB) piped through stdin. This release completely fixes this issue with two key improvements:

**Stdin Reading Fix:**
- Replaced custom polling-based stdin reading logic with proper `FileHandle.readToEnd()` API
- Now correctly handles EOF signals when reading from pipes
- Supports both modern macOS (10.15.4+) and older systems with appropriate fallbacks

**Parser Performance Optimization:**
- Added fast-path string filtering before regex matching to avoid catastrophic backtracking
- Optimized line splitting using `split(separator:)` instead of `components(separatedBy:)`
- Filters out irrelevant lines (empty, too long, or without error/test keywords) before expensive regex operations
- Parser now handles large files (8000+ lines, 2.6MB) in ~0.6 seconds instead of hanging indefinitely

### Testing
- Added comprehensive unit test with real-world 2.6MB build output fixture (8101 lines)
- Test validates both correctness and performance (regression test for the hang fix)
- All existing tests continue to pass

### Technical Details
The hang was caused by two issues:
1. Custom stdin reading used `availableData` with sleep delays, which didn't properly detect EOF on piped input
2. Regex patterns with `OneOrMore(.any, .reluctant)` caused catastrophic backtracking on lines that didn't match

Both issues are now resolved, making xcsift production-ready for processing large Xcode build outputs.

## Installation

### Homebrew
```bash
brew upgrade ldomaradzki/xcsift/xcsift
```

### Manual
```bash
git clone https://github.com/ldomaradzki/xcsift.git
cd xcsift
swift build -c release
cp .build/release/xcsift /usr/local/bin/
```

## Full Changelog
- **Fixed**: Stdin reading hangs on large files when piped through `cat` or similar commands
- **Fixed**: Parser performance issues with large build outputs
- **Added**: Real-world 2.6MB build output fixture for testing
- **Improved**: Line parsing performance with fast-path filtering
- **Improved**: Stdin reading using proper EOF-aware APIs

---

**Full Diff**: https://github.com/ldomaradzki/xcsift/compare/v1.0.7...v1.0.8
