import XCSiftCore
import XCTest

@testable import xcsift

/// What ``ResultRenderer`` writes, for the stdin pipeline and the MCP proxy alike.
final class ResultRendererTests: XCTestCase {

    /// TOON specification 4.0 removed key folding. A consumer that follows the specification reads
    /// a folded `build_info.targets` as one key, so the renderer must always write nested objects.
    func testTOONWritesNestedObjectsAndNeverFoldsKeys() throws {
        let input = """
            CompileSwiftSources normal arm64 (in target 'MyApp' from project 'MyProject')
            Build target MyApp of project MyProject with configuration Debug (12.5s)
            ** BUILD SUCCEEDED ** [15.3s]
            """
        let result = OutputParser().parse(input: input, printBuildInfo: true)

        let toon = try ResultRenderer.toon(result, config: RenderConfig(format: .toon, toonDelimiter: .comma))

        XCTAssertTrue(toon.contains("build_info:\n  targets["), toon)
        XCTAssertFalse(toon.contains("build_info.targets"), toon)
    }
}
