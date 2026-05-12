import Foundation
import XCSiftCore

public final class MockFileSystem: FileSystemProtocol {
    public var existingPaths: Set<String> = []
    public var directories: [String: [String]] = [:]
    public var directoryFlags: Set<String> = []
    public var fileAttributes: [String: [FileAttributeKey: Any]] = [:]
    public var fileContents: [String: String] = [:]
    public var mockHomeDirectory = URL(fileURLWithPath: "/mock/home")
    public var mockCurrentDirectory = "/mock/cwd"

    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    public func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let exists = existingPaths.contains(path)
        if exists, let isDir = isDirectory {
            isDir.pointee = ObjCBool(directoryFlags.contains(path))
        }
        return exists
    }

    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        guard let contents = directories[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        return contents
    }

    public func enumerator(atPath path: String) -> FileManager.DirectoryEnumerator? {
        nil
    }

    public func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        guard let attrs = fileAttributes[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        return attrs
    }

    public var homeDirectoryForCurrentUser: URL {
        mockHomeDirectory
    }

    public var currentDirectoryPath: String {
        mockCurrentDirectory
    }

    public func contentsOfFile(atPath path: String) throws -> String {
        guard let contents = fileContents[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        return contents
    }
}

public final class MockShellRunner: ShellRunnerProtocol {
    public var commandResults: [String: String] = [:]
    public var executedCommands: [(command: String, args: [String])] = []

    public init() {}

    public func run(_ command: String, args: [String]) -> String? {
        executedCommands.append((command, args))
        let key = ([command] + args).joined(separator: " ")
        return commandResults[key]
    }
}
