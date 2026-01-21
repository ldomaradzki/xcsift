import XCTest
@testable import xcsift

class BuildPhasesTest: XCTestCase {
    let parser = OutputParser()

    func testPhaseScriptExecutionFailureBasic() {
        let output = """
            /bin/sh -c /Users/dhavalkansara/Library/Developer/Xcode/DerivedData/AFEiOS-gctxucyuhlhesnfkbuxfswkozboo/Build/Intermediates.noindex/AFEiOS.build/Debug-iphoneos/AFEiOS.build/Script-19DAA30A22C0FB0100A039E2.sh
            The path lib/main.dart does not exist
            The path  does not exist
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertNil(error.file, "PhaseScriptExecution error should not have file")
        XCTAssertNil(error.line, "PhaseScriptExecution error should not have line number")
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
        XCTAssertTrue(
            error.message.contains("The path lib/main.dart does not exist"),
            "Error message should include context from preceding lines"
        )
    }

    func testPhaseScriptExecutionWithHermesFramework() {
        let output = """
            Run script build phase '[CP-User] [Hermes] Replace Hermes for the right configuration, if needed' will be run during every build because it does not specify any outputs. To address this warning, either add output dependencies to the script phase, or configure it to run in every build by unchecking "Based on dependency analysis" in the script phase.
            PhaseScriptExecution [CP-User]\\ [Hermes]\\ Replace\\ Hermes\\ for\\ the\\ right\\ configuration,\\ if\\ needed /Library/Developer/Xcode/DerivedData/myProjectName-gzdlehmipieiindfjyfrhhcjupam/Build/Intermediates.noindex/ArchiveIntermediates/myProjectName/IntermediateBuildFilesPath/Pods.build/Release-iphoneos/hermes-engine.build/Script-46EB2E0002C950.sh (in target 'hermes-engine' from project 'Pods')
            Node found at: /var/folders/d5/f1gffcfx27ngwvmw8v8jdm7m0000gn/T/yarn--1704767526546-0.12516067745295967/node
            /Library/Developer/Xcode/DerivedData/myProjectName-gzdlehmipieiindfjyfrhhcjupam/Build/Intermediates.noindex/ArchiveIntermediates/myProjectName/IntermediateBuildFilesPath/Pods.build/Release-iphoneos/hermes-engine.build/Script-46EB2E0002C950.sh: line 9: /var/folders/d5/f1gffcfx27ngwvmw8v8jdm7m0000gn/T/yarn--1704767526546-0.12516067745295967/node: No such file or directory
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure for Hermes")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
        XCTAssertTrue(
            error.message.contains("No such file or directory"),
            "Error message should include context about missing file"
        )
    }

    func testPhaseScriptExecutionWithUnityGameAssembly() {
        let output = """
            /bin/sh -c /Users/evgeniyasenchurova/Library/Developer/Xcode/DerivedData/Unity-iPhone-gtnilxmbqexxvtcauewfdmpfbvfe/Build/Intermediates.noindex/ArchiveIntermediates/Unity-iPhone/IntermediateBuildFilesPath/Unity-iPhone.build/Release-iphoneos/GameAssembly.build/Script-C62A2A42F32E085EF849CF0B.sh
            /Users/evgeniyasenchurova/Library/Developer/Xcode/DerivedData/Unity-iPhone-gtnilxmbqexxvtcauewfdmpfbvfe/Build/Intermediates.noindex/ArchiveIntermediates/Unity-iPhone/IntermediateBuildFilesPath/Unity-iPhone.build/Release-iphoneos/GameAssembly.build/Script-C62A2A42F32E085EF849CF0B.sh: line 19: /Users/evgeniyasenchurova Downloads/ build_ios/Il2Cpp0utputProject/IL2CPP/build/deploy_arm64/il2cpp: Operation not permitted
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure for Unity")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
        XCTAssertTrue(
            error.message.contains("Operation not permitted"),
            "Error message should include operation permission error"
        )
    }

    func testPhaseScriptExecutionWithMultipleErrors() {
        let output = """
            Build started...

            Compiling Swift files...
            file.swift:10: error: Cannot find 'someFunction' in scope

            Running post-build script...
            /bin/sh -c /path/to/script.sh
            Script execution failed
            Command PhaseScriptExecution failed with a nonzero exit code

            Build complete!
            """

        let result = parser.parse(input: output)

        // Should detect both the compilation error and the PhaseScriptExecution failure
        XCTAssertEqual(
            result.summary.errors,
            2,
            "Should detect both compilation error and PhaseScriptExecution failure"
        )

        // Find the PhaseScriptExecution error
        let phaseError = result.errors.first { $0.message.contains("Command PhaseScriptExecution failed") }
        XCTAssertNotNil(phaseError, "Should have PhaseScriptExecution error")

        if let phaseError = phaseError {
            XCTAssertTrue(
                phaseError.message.contains("Script execution failed"),
                "Error message should include preceding context"
            )
        }
    }

    func testPhaseScriptExecutionWithSingleLineContext() {
        let output = """
            Running build phase script...
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure with single context line")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
        XCTAssertTrue(
            error.message.contains("Running build phase script"),
            "Error message should include context line"
        )
    }

    func testPhaseScriptExecutionWithNoContext() {
        let output = """
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure even with no context")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
    }

    func testPhaseScriptExecutionDoesNotDuplicateErrors() {
        let output = """
            /bin/sh -c /path/to/script.sh
            Command PhaseScriptExecution failed with a nonzero exit code
            /bin/sh -c /path/to/script.sh
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        // Should deduplicate identical errors
        XCTAssertLessThanOrEqual(
            result.summary.errors,
            2,
            "Should not duplicate identical PhaseScriptExecution errors"
        )
    }

    func testBuildSucceededDoesNotCreatePhaseError() {
        let output = """
            Running phase script...
            Build succeeded in 5.234 seconds
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 0, "Build succeeded should not create a PhaseScriptExecution error")
    }

    func testPhaseScriptExecutionWithComplexOutput() {
        let output = """
            ** BUILD START **

            Linking Framework/Module

            Running script phase [CP] Copy Pods Resources

            Resources copied...
            warning: Some resources were skipped

            Running script phase custom build script

            Processing configuration...
            /bin/sh -c /path/to/complex/script.sh
            Error: Configuration file not found at /expected/path
            Command PhaseScriptExecution failed with a nonzero exit code

            Build failed after 10.234 seconds
            """

        let result = parser.parse(input: output)

        // Should detect the PhaseScriptExecution failure
        let phaseError = result.errors.first { $0.message.contains("Command PhaseScriptExecution failed") }
        XCTAssertNotNil(phaseError, "Should detect PhaseScriptExecution failure in complex output")

        if let phaseError = phaseError {
            XCTAssertTrue(
                phaseError.message.contains("Error: Configuration file not found"),
                "Should include relevant context from preceding lines"
            )
        }
    }

    func testPhaseScriptExecutionFiltersUnrelatedWarnings() {
        // Test case based on user's real project scenario
        let output = """
            Warning: unknown environment variable SWIFT_DEBUG_INFORMATION_FORMAT
            bash: /Users/roman/Developer/SpaceTime/build_id.sh: No such file or directory
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        XCTAssertEqual(result.summary.errors, 1, "Should detect PhaseScriptExecution failure")
        XCTAssertFalse(result.errors.isEmpty, "Should have at least one error")

        let error = result.errors[0]
        XCTAssertTrue(
            error.message.contains("Command PhaseScriptExecution failed"),
            "Error message should contain failure indicator"
        )
        XCTAssertTrue(
            error.message.contains("bash:"),
            "Error message should include bash error context"
        )
        XCTAssertTrue(
            error.message.contains("No such file or directory"),
            "Error message should include error details"
        )
        XCTAssertFalse(
            error.message.contains("Warning: unknown environment variable"),
            "Should filter out unrelated Warning: lines"
        )
    }
}
