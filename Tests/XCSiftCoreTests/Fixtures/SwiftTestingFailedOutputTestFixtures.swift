// Intentionally failing Swift Testing cases for swift-testing-failed-output.txt.
// Regenerate from the repository root (exit status 1 is expected):
// swiftc Tests/XCSiftCoreTests/Fixtures/SwiftTestingFailedOutputTestFixtures.swift -o /tmp/xcsift-failure-fixture
// /tmp/xcsift-failure-fixture > Tests/XCSiftCoreTests/Fixtures/swift-testing-failed-output.txt 2>&1
import Testing

@Suite(.serialized)
struct FailureFixtures {
    enum FixtureError: Error {
        case invalid
    }

    @Test func expectationFailure() {
        let actual = 1
        #expect(actual == 2, "Values should match")
    }

    @Test func requirementFailure() throws {
        let value: Int? = nil
        _ = try #require(value, "A value is required")
    }

    @Test func thrownError() throws {
        throw FixtureError.invalid
    }

    @Test func explicitIssue() {
        Issue.record("An explicit failure")
    }

    @Test func missingExpectedError() {
        #expect(throws: FixtureError.self) {}
    }

    @Test func unexpectedError() {
        #expect(throws: Never.self) { throw FixtureError.invalid }
    }

    @Test(arguments: ["invalid", "bad: value at noon"])
    func parameterizedFailure(value: String) {
        #expect(value == "valid", "The argument must be valid")
    }

    @Test("Multiple arguments", arguments: [(1, 2)])
    func multipleArgumentFailure(actual: Int, expected: Int) {
        #expect(actual == expected)
    }

    @Test func multipleIssues() {
        #expect(Bool(false))
        Issue.record("A second issue in the same test")
    }

    @Test func missingKnownIssue() {
        withKnownIssue("This failure no longer occurs") {}
    }
}

let _: Never = await Testing.__swiftPMEntryPoint()
