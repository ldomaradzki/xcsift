import Foundation

@testable import xcsift

/// Mock implementation of FileSystemProtocol for testing
final class MockFileSystem: FileSystemProtocol {
    var existingPaths: Set<String> = []
    var directories: [String: [String]] = [:]
    var directoryFlags: Set<String> = []
    var fileAttributes: [String: [FileAttributeKey: Any]] = [:]
    var mockHomeDirectory = URL(fileURLWithPath: "/mock/home")

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let exists = existingPaths.contains(path)
        if exists, let isDir = isDirectory {
            isDir.pointee = ObjCBool(directoryFlags.contains(path))
        }
        return exists
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        guard let contents = directories[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        return contents
    }

    func enumerator(atPath path: String) -> FileManager.DirectoryEnumerator? {
        // Return nil for mock - tests don't need directory enumeration
        nil
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        guard let attrs = fileAttributes[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        return attrs
    }

    var homeDirectoryForCurrentUser: URL {
        mockHomeDirectory
    }
}

/// Mock implementation of ShellRunnerProtocol for testing
final class MockShellRunner: ShellRunnerProtocol {
    var commandResults: [String: String] = [:]
    var executedCommands: [(command: String, args: [String])] = []

    func run(_ command: String, args: [String]) -> String? {
        executedCommands.append((command, args))
        // Return nil by default - no shell commands succeed in tests
        let key = ([command] + args).joined(separator: " ")
        return commandResults[key]
    }
}
