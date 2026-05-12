import Foundation

/// Error types for Codex installation
enum CodexInstallerError: Error, CustomStringConvertible {
    case alreadyExists(path: String)
    case createDirectoryFailed(path: String, underlying: Error)
    case writeFileFailed(path: String, underlying: Error)
    case deleteFileFailed(path: String, underlying: Error)
    case notInstalled(path: String)

    var description: String {
        switch self {
        case .alreadyExists(let path):
            return "Skill already exists at \(path). Use --force to overwrite."
        case .createDirectoryFailed(let path, let error):
            return "Failed to create directory at \(path): \(error.localizedDescription)"
        case .writeFileFailed(let path, let error):
            return "Failed to write file at \(path): \(error.localizedDescription)"
        case .deleteFileFailed(let path, let error):
            return "Failed to delete file at \(path): \(error.localizedDescription)"
        case .notInstalled(let path):
            return "xcsift skill not installed at \(path)"
        }
    }
}

/// Handles Codex skill installation
struct CodexInstaller {
    private let fileManager: FileManager

    /// The target directory for Codex skills
    static var skillDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/skills/xcsift"
    }

    /// The target path for the SKILL.md file
    static var skillFilePath: String {
        return "\(skillDirectory)/SKILL.md"
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Install the Codex skill
    /// - Parameter force: If true, overwrite existing installation
    func install(force: Bool = false) throws {
        let skillDir = Self.skillDirectory
        let skillFile = Self.skillFilePath

        // Check if already installed
        if fileManager.fileExists(atPath: skillFile) && !force {
            throw CodexInstallerError.alreadyExists(path: skillFile)
        }

        // Create directory if needed
        if !fileManager.fileExists(atPath: skillDir) {
            do {
                try fileManager.createDirectory(
                    atPath: skillDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw CodexInstallerError.createDirectoryFailed(path: skillDir, underlying: error)
            }
        }

        // Write SKILL.md
        do {
            try CodexTemplates.skillMarkdown.write(
                toFile: skillFile,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw CodexInstallerError.writeFileFailed(path: skillFile, underlying: error)
        }
    }

    /// Uninstall the Codex skill
    func uninstall() throws {
        let skillDir = Self.skillDirectory
        let skillFile = Self.skillFilePath

        // Check if installed
        guard fileManager.fileExists(atPath: skillFile) else {
            throw CodexInstallerError.notInstalled(path: skillFile)
        }

        // Remove the skill directory and contents
        do {
            try fileManager.removeItem(atPath: skillDir)
        } catch {
            throw CodexInstallerError.deleteFileFailed(path: skillDir, underlying: error)
        }
    }
}
