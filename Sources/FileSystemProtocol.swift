import Foundation

/// Protocol for file system operations, enabling dependency injection for testing
protocol FileSystemProtocol {
    func fileExists(atPath path: String) -> Bool
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func enumerator(atPath path: String) -> FileManager.DirectoryEnumerator?
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    var homeDirectoryForCurrentUser: URL { get }
}

extension FileManager: FileSystemProtocol {}
