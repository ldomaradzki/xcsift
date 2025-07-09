import Testing
@testable import xcsift

@Suite("Swift Testing Output Parser Tests")
struct SwiftTestingOutputParserTests {
    
    @Test("Parse successful build")
    func parseSuccessfulBuild() {
        let parser = OutputParser()
        let input = """
        Building for debugging...
        Build complete!
        """
        
        let result = parser.parse(input: input)
        
        #expect(result.status == "success")
        #expect(result.summary.errors == 0)
        #expect(result.summary.warnings == 0)
        #expect(result.summary.failedTests == 0)
    }
    
    @Test("Parse error with file and line")
    func parseErrorWithFileAndLine() {
        let parser = OutputParser()
        let input = """
        main.swift:15:5: error: use of undeclared identifier 'unknown'
        unknown = 5
        ^
        """
        
        let result = parser.parse(input: input)
        
        #expect(result.status == "failed")
        #expect(result.summary.errors == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].file == "main.swift")
        #expect(result.errors[0].line == 15)
        #expect(result.errors[0].message == "use of undeclared identifier 'unknown'")
    }
    
    @Test("Parse warning message")
    func parseWarningMessage() {
        let parser = OutputParser()
        let input = """
        ViewController.swift:23:9: warning: variable 'temp' was never used
        let temp = "test"
        ^
        """
        
        let result = parser.parse(input: input)
        
        #expect(result.status == "success")
        #expect(result.summary.warnings == 1)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].file == "ViewController.swift")
        #expect(result.warnings[0].line == 23)
        #expect(result.warnings[0].message == "variable 'temp' was never used")
    }
    
    @Test("Parse multiple errors and warnings")
    func parseMultipleErrorsAndWarnings() {
        let parser = OutputParser()
        let input = """
        UserService.swift:45:12: error: cannot find 'invalidFunction' in scope
        NetworkManager.swift:23:5: error: use of undeclared identifier 'unknownVariable'
        AppDelegate.swift:67:8: warning: unused variable 'config'
        """
        
        let result = parser.parse(input: input)
        
        #expect(result.status == "failed")
        #expect(result.summary.errors == 2)
        #expect(result.summary.warnings == 1)
        #expect(result.errors.count == 2)
        #expect(result.warnings.count == 1)
    }
    
    @Test("Parse fatal error")
    func parseFatalError() {
        let parser = OutputParser()
        let input = """
        Swift/ContiguousArrayBuffer.swift:690: Fatal error: Index out of range
        """
        
        let result = parser.parse(input: input)
        
        #expect(result.status == "failed")
        #expect(result.summary.errors == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].file == "Swift/ContiguousArrayBuffer.swift")
        #expect(result.errors[0].line == 690)
        #expect(result.errors[0].message == "Index out of range")
    }
    
    @Test("This test should fail intentionally")
    func intentionalFailure() {
        let parser = OutputParser()
        let result = parser.parse(input: "test")
        
        // This will fail intentionally
        #expect(result.status == "failed")
        #expect(result.summary.errors == 5) // Wrong expectation
    }
    
    @Test("Another failing test")
    func anotherFailingTest() {
        let value = 42
        let expected = 100
        
        // This will fail
        #expect(value == expected)
    }
    
    @Test("Successful test with complex logic")
    func successfulComplexTest() {
        let parser = OutputParser()
        let input = """
        main.swift:10:5: error: syntax error
        test.swift:5:1: warning: unused import
        """
        
        let result = parser.parse(input: input)
        
        #expect(result.status == "failed")
        #expect(result.errors.count == 1)
        #expect(result.warnings.count == 1)
        #expect(result.errors[0].file == "main.swift")
        #expect(result.warnings[0].file == "test.swift")
    }
}