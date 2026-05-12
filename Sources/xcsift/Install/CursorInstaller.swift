import Foundation

/// Error types for Cursor installation
enum CursorInstallerError: Error, CustomStringConvertible {
    case alreadyExists(path: String)
    case createDirectoryFailed(path: String, underlying: Error)
    case writeFileFailed(path: String, underlying: Error)
    case deleteFileFailed(path: String, underlying: Error)
    case notInstalled(path: String)
    case setPermissionsFailed(path: String, underlying: Error)

    var description: String {
        switch self {
        case .alreadyExists(let path):
            return "Cursor hooks already exist at \(path). Use --force to overwrite."
        case .createDirectoryFailed(let path, let error):
            return "Failed to create directory at \(path): \(error.localizedDescription)"
        case .writeFileFailed(let path, let error):
            return "Failed to write file at \(path): \(error.localizedDescription)"
        case .deleteFileFailed(let path, let error):
            return "Failed to delete file at \(path): \(error.localizedDescription)"
        case .notInstalled(let path):
            return "xcsift hooks not installed at \(path)"
        case .setPermissionsFailed(let path, let error):
            return "Failed to set executable permissions on \(path): \(error.localizedDescription)"
        }
    }
}

/// Handles Cursor hook installation
struct CursorInstaller {
    private let fileManager: FileManager

    /// Whether to install globally (~/.cursor) or locally (.cursor)
    let global: Bool

    /// The base directory for Cursor configuration
    var baseDirectory: String {
        if global {
            let home = fileManager.homeDirectoryForCurrentUser.path
            return "\(home)/.cursor"
        } else {
            return ".cursor"
        }
    }

    /// The hooks directory path
    var hooksDirectory: String {
        return "\(baseDirectory)/hooks"
    }

    /// The hooks.json file path
    var hooksJSONPath: String {
        return "\(baseDirectory)/hooks.json"
    }

    /// The hook script path
    var hookScriptPath: String {
        return "\(hooksDirectory)/pre-xcsift.sh"
    }

    /// The skills directory path
    var skillsDirectory: String {
        return "\(baseDirectory)/skills/xcsift"
    }

    /// The skill file path
    var skillFilePath: String {
        return "\(skillsDirectory)/SKILL.md"
    }

    init(global: Bool, fileManager: FileManager = .default) {
        self.global = global
        self.fileManager = fileManager
    }

    /// Install Cursor hooks
    /// - Parameter force: If true, overwrite existing installation
    func install(force: Bool = false) throws {
        // Check if already installed
        if fileManager.fileExists(atPath: hooksJSONPath) && !force {
            throw CursorInstallerError.alreadyExists(path: hooksJSONPath)
        }

        // Create hooks directory if needed
        if !fileManager.fileExists(atPath: hooksDirectory) {
            do {
                try fileManager.createDirectory(
                    atPath: hooksDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw CursorInstallerError.createDirectoryFailed(
                    path: hooksDirectory,
                    underlying: error
                )
            }
        }

        // Write hooks.json
        let hooksJSON = global ? CursorTemplates.globalHooksJSON : CursorTemplates.projectHooksJSON
        do {
            try hooksJSON.write(
                toFile: hooksJSONPath,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw CursorInstallerError.writeFileFailed(path: hooksJSONPath, underlying: error)
        }

        // Write hook script
        do {
            try CursorTemplates.hookScript.write(
                toFile: hookScriptPath,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw CursorInstallerError.writeFileFailed(path: hookScriptPath, underlying: error)
        }

        // Make script executable
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: hookScriptPath
            )
        } catch {
            throw CursorInstallerError.setPermissionsFailed(path: hookScriptPath, underlying: error)
        }

        // Create skills directory if needed
        if !fileManager.fileExists(atPath: skillsDirectory) {
            do {
                try fileManager.createDirectory(
                    atPath: skillsDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw CursorInstallerError.createDirectoryFailed(
                    path: skillsDirectory,
                    underlying: error
                )
            }
        }

        // Write skill file
        do {
            try CursorTemplates.skillMarkdown.write(
                toFile: skillFilePath,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw CursorInstallerError.writeFileFailed(path: skillFilePath, underlying: error)
        }
    }

    /// Uninstall Cursor hooks
    func uninstall() throws {
        // Check if installed
        guard fileManager.fileExists(atPath: hooksJSONPath) else {
            throw CursorInstallerError.notInstalled(path: hooksJSONPath)
        }

        // Remove hooks.json
        do {
            try fileManager.removeItem(atPath: hooksJSONPath)
        } catch {
            throw CursorInstallerError.deleteFileFailed(path: hooksJSONPath, underlying: error)
        }

        // Remove hook script if it exists
        if fileManager.fileExists(atPath: hookScriptPath) {
            do {
                try fileManager.removeItem(atPath: hookScriptPath)
            } catch {
                throw CursorInstallerError.deleteFileFailed(path: hookScriptPath, underlying: error)
            }
        }

        // Try to remove hooks directory if empty
        let hooksDir = hooksDirectory
        if let contents = try? fileManager.contentsOfDirectory(atPath: hooksDir),
            contents.isEmpty
        {
            do {
                try fileManager.removeItem(atPath: hooksDir)
            } catch {
                // Log cleanup failure but don't throw - this is best-effort
                FileHandle.standardError.write(
                    Data(
                        "Warning: Failed to remove empty hooks directory at \(hooksDir): \(error.localizedDescription)\n"
                            .utf8
                    )
                )
            }
        }

        // Remove skill file if it exists
        if fileManager.fileExists(atPath: skillFilePath) {
            do {
                try fileManager.removeItem(atPath: skillFilePath)
            } catch {
                throw CursorInstallerError.deleteFileFailed(path: skillFilePath, underlying: error)
            }
        }

        // Try to remove skills/xcsift directory if empty
        let skillsDir = skillsDirectory
        if let contents = try? fileManager.contentsOfDirectory(atPath: skillsDir),
            contents.isEmpty
        {
            do {
                try fileManager.removeItem(atPath: skillsDir)
            } catch {
                // Log cleanup failure but don't throw - this is best-effort
                FileHandle.standardError.write(
                    Data(
                        "Warning: Failed to remove empty skills/xcsift directory at \(skillsDir): \(error.localizedDescription)\n"
                            .utf8
                    )
                )
            }
        }

        // Try to remove skills directory if empty
        let parentSkillsDir = "\(baseDirectory)/skills"
        if let contents = try? fileManager.contentsOfDirectory(atPath: parentSkillsDir),
            contents.isEmpty
        {
            do {
                try fileManager.removeItem(atPath: parentSkillsDir)
            } catch {
                // Log cleanup failure but don't throw - this is best-effort
                FileHandle.standardError.write(
                    Data(
                        "Warning: Failed to remove empty skills directory at \(parentSkillsDir): \(error.localizedDescription)\n"
                            .utf8
                    )
                )
            }
        }
    }
}
