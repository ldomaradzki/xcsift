import Foundation

struct CoverageParser {
    let fileSystem: FileSystemProtocol
    let shellRunner: ShellRunnerProtocol

    init(
        fileSystem: FileSystemProtocol = FileManager.default,
        shellRunner: ShellRunnerProtocol = DefaultShellRunner()
    ) {
        self.fileSystem = fileSystem
        self.shellRunner = shellRunner
    }

    // MARK: - Main Entry Point

    func parseCoverageFromPath(_ path: String, targetFilter: String? = nil) -> CodeCoverage? {
        let coveragePath: String

        // If explicit path provided and exists, use it
        if !path.isEmpty && fileSystem.fileExists(atPath: path) {
            coveragePath = path
        } else {
            // Auto-detect: try xcodebuild first (DerivedData), then SPM paths
            if let latestXCResult = findLatestXCResultInDerivedData(projectHint: targetFilter) {
                return convertXCResultToJSON(xcresultPath: latestXCResult, targetFilter: targetFilter)
            }

            let defaultPaths = [
                ".build/debug/codecov",
                ".build/arm64-apple-macosx/debug/codecov",
                ".build/x86_64-apple-macosx/debug/codecov",
                ".build/arm64-unknown-linux-gnu/debug/codecov",
                ".build/x86_64-unknown-linux-gnu/debug/codecov",
                "DerivedData",
                ".",
            ]

            var foundPath: String?
            for defaultPath in defaultPaths {
                if fileSystem.fileExists(atPath: defaultPath) {
                    foundPath = defaultPath
                    break
                }
            }

            guard let found = foundPath else {
                return nil
            }
            coveragePath = found
        }

        guard fileSystem.fileExists(atPath: coveragePath) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        _ = fileSystem.fileExists(atPath: coveragePath, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            guard let files = try? fileSystem.contentsOfDirectory(atPath: coveragePath) else {
                return nil
            }

            let jsonFiles = files.filter { $0.hasSuffix(".json") }
            if let firstJsonFile = jsonFiles.first {
                let jsonPath = (coveragePath as NSString).appendingPathComponent(firstJsonFile)
                return parseCoverageJSON(at: jsonPath, targetFilter: targetFilter)
            }

            let profrawFiles = findProfrawFiles(in: coveragePath)
            if !profrawFiles.isEmpty {
                return convertProfrawToJSON(profrawFiles: profrawFiles)
            }

            let xcresultBundles = findXCResultBundles(in: coveragePath)
            if let firstXCResult = xcresultBundles.first {
                return convertXCResultToJSON(xcresultPath: firstXCResult, targetFilter: targetFilter)
            }

            if let latestXCResult = findLatestXCResultInDerivedData() {
                return convertXCResultToJSON(xcresultPath: latestXCResult, targetFilter: targetFilter)
            }

            return nil
        } else {
            if coveragePath.hasSuffix(".xcresult") {
                return convertXCResultToJSON(xcresultPath: coveragePath, targetFilter: targetFilter)
            } else {
                return parseCoverageJSON(at: coveragePath, targetFilter: targetFilter)
            }
        }
    }

    // MARK: - Auto-Detection Helpers

    /// Finds all .profraw files in a directory (recursively)
    private func findProfrawFiles(in directory: String) -> [String] {
        guard let enumerator = fileSystem.enumerator(atPath: directory) else {
            return []
        }

        var profrawFiles: [String] = []
        for case let file as String in enumerator {
            if file.hasSuffix(".profraw") {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                profrawFiles.append(fullPath)
            }
        }
        return profrawFiles
    }

    /// Finds .xcresult bundles (created by xcodebuild)
    private func findXCResultBundles(in directory: String) -> [String] {
        guard let enumerator = fileSystem.enumerator(atPath: directory) else {
            return []
        }

        var xcresultPaths: [String] = []
        for case let file as String in enumerator {
            if file.hasSuffix(".xcresult") {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                xcresultPaths.append(fullPath)
            }
        }
        return xcresultPaths
    }

    /// Finds the most recent .xcresult bundle in Xcode DerivedData using shell find
    private func findLatestXCResultInDerivedData(projectHint: String? = nil) -> String? {
        let homeDir = fileSystem.homeDirectoryForCurrentUser.path
        let derivedDataPath = (homeDir as NSString).appendingPathComponent(
            "Library/Developer/Xcode/DerivedData"
        )

        guard fileSystem.fileExists(atPath: derivedDataPath) else {
            return nil
        }

        // If we have a project hint, search only in matching project directories
        let searchPaths: [String]
        if let hint = projectHint {
            // Find project directories matching the hint (e.g., "MyProject-abcdef123")
            let projectDirs = (try? fileSystem.contentsOfDirectory(atPath: derivedDataPath))?
                .filter { $0.hasPrefix("\(hint)-") || $0.hasPrefix("\(hint)Tests-") }
                .map { (derivedDataPath as NSString).appendingPathComponent($0) }
                .filter { fileSystem.fileExists(atPath: $0) }

            guard let dirs = projectDirs, !dirs.isEmpty else {
                // Project hint provided but no matching directory found
                // Return nil to allow fallback to SPM paths
                return nil
            }
            searchPaths = dirs
        } else {
            searchPaths = [derivedDataPath]
        }

        let findArgs = ["find"] + searchPaths + ["-name", "*.xcresult", "-type", "d", "-mtime", "-7"]
        guard let output = shellRunner.run("/usr/bin/env", args: findArgs) else {
            return nil
        }

        let paths = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            return nil
        }

        var newestBundle: String?
        var newestDate: Date?

        for path in paths {
            if let attrs = try? fileSystem.attributesOfItem(atPath: path),
                let modDate = attrs[.modificationDate] as? Date
            {
                if newestDate == nil || modDate > newestDate! {
                    newestDate = modDate
                    newestBundle = path
                }
            }
        }

        return newestBundle
    }

    /// Finds the test binary (.xctest bundle) in .build directory
    private func findTestBinary() -> String? {
        let buildDir = ".build"

        guard fileSystem.fileExists(atPath: buildDir),
            let enumerator = fileSystem.enumerator(atPath: buildDir)
        else {
            return nil
        }

        for case let file as String in enumerator {
            if file.hasSuffix(".xctest") {
                let xctestPath = (buildDir as NSString).appendingPathComponent(file)
                let macosPath = (xctestPath as NSString).appendingPathComponent("Contents/MacOS")

                guard let macosContents = try? fileSystem.contentsOfDirectory(atPath: macosPath)
                else {
                    continue
                }

                for item in macosContents {
                    let itemPath = (macosPath as NSString).appendingPathComponent(item)
                    var isDirectory: ObjCBool = false

                    if fileSystem.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                        !isDirectory.boolValue,
                        !item.hasSuffix(".dSYM")
                    {
                        return itemPath
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Conversion Helpers

    /// Converts .profraw files to JSON coverage data
    private func convertProfrawToJSON(profrawFiles: [String]) -> CodeCoverage? {
        guard !profrawFiles.isEmpty else {
            return nil
        }

        guard let testBinary = findTestBinary() else {
            return nil
        }

        let tempDir = NSTemporaryDirectory()
        let profdataPath = (tempDir as NSString).appendingPathComponent("xcsift-coverage.profdata")
        let jsonPath = (tempDir as NSString).appendingPathComponent("xcsift-coverage.json")

        let mergeArgs = ["llvm-profdata", "merge", "-sparse"] + profrawFiles + ["-o", profdataPath]
        guard shellRunner.run("xcrun", args: mergeArgs) != nil else {
            return nil
        }

        let exportArgs = [
            "llvm-cov", "export", testBinary, "-instr-profile=\(profdataPath)", "-format=text",
        ]
        guard let jsonOutput = shellRunner.run("xcrun", args: exportArgs) else {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }

        guard let jsonData = jsonOutput.data(using: .utf8) else {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }

        do {
            try jsonData.write(to: URL(fileURLWithPath: jsonPath))
            let coverage = parseCoverageJSON(at: jsonPath)
            try? FileManager.default.removeItem(atPath: profdataPath)
            try? FileManager.default.removeItem(atPath: jsonPath)
            return coverage
        } catch {
            try? FileManager.default.removeItem(atPath: profdataPath)
            return nil
        }
    }

    /// Converts .xcresult bundle to JSON coverage data
    private func convertXCResultToJSON(xcresultPath: String, targetFilter: String? = nil)
        -> CodeCoverage?
    {
        let args = ["xccov", "view", "--report", "--json", xcresultPath]
        guard let jsonOutput = shellRunner.run("xcrun", args: args) else {
            return nil
        }

        guard let jsonData = jsonOutput.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return nil
        }

        return Self.parseXcodebuildFormat(json: json, targetFilter: targetFilter)
    }

    // MARK: - JSON Parsing

    private func parseCoverageJSON(at path: String, targetFilter: String? = nil) -> CodeCoverage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let coverage = Self.parseXcodebuildFormat(json: json, targetFilter: targetFilter) {
            return coverage
        }

        if let coverage = Self.parseSPMFormat(json: json) {
            return coverage
        }

        return nil
    }

    private static func parseXcodebuildFormat(json: [String: Any], targetFilter: String? = nil)
        -> CodeCoverage?
    {
        guard let targets = json["targets"] as? [[String: Any]] else {
            return nil
        }

        var fileCoverages: [FileCoverage] = []
        var totalCovered = 0
        var totalExecutable = 0

        for target in targets {
            // Get target name if available
            let targetName = target["name"] as? String

            // Skip test bundles - we want coverage of tested code, not tests themselves
            if let name = targetName, name.hasSuffix(".xctest") {
                continue
            }

            // Apply target filter if specified
            if let filter = targetFilter, let name = targetName {
                if !name.contains(filter) && !filter.contains(name) {
                    continue
                }
            }

            guard let filesArray = target["files"] as? [[String: Any]] else {
                continue
            }

            for fileData in filesArray {
                guard let filename = fileData["path"] as? String else {
                    continue
                }

                let lineCoverage: Double
                let covered: Int
                let executable: Int

                if let coverage = fileData["lineCoverage"] as? Double {
                    lineCoverage = coverage > 1.0 ? coverage : coverage * 100.0
                    covered = fileData["coveredLines"] as? Int ?? 0
                    executable = fileData["executableLines"] as? Int ?? 0
                } else {
                    continue
                }

                let name = (filename as NSString).lastPathComponent

                fileCoverages.append(
                    FileCoverage(
                        path: filename,
                        name: name,
                        lineCoverage: lineCoverage,
                        coveredLines: covered,
                        executableLines: executable
                    )
                )

                totalCovered += covered
                totalExecutable += executable
            }
        }

        guard !fileCoverages.isEmpty else {
            return nil
        }

        let overallCoverage =
            totalExecutable > 0 ? (Double(totalCovered) / Double(totalExecutable)) * 100.0 : 0.0

        return CodeCoverage(lineCoverage: overallCoverage, files: fileCoverages)
    }

    private static func parseSPMFormat(json: [String: Any]) -> CodeCoverage? {
        guard let dataArray = json["data"] as? [[String: Any]],
            let firstData = dataArray.first,
            let filesArray = firstData["files"] as? [[String: Any]]
        else {
            return nil
        }

        var fileCoverages: [FileCoverage] = []
        var totalCovered = 0
        var totalExecutable = 0

        for fileData in filesArray {
            guard let filename = fileData["filename"] as? String,
                let summary = fileData["summary"] as? [String: Any],
                let lines = summary["lines"] as? [String: Any],
                let covered = lines["covered"] as? Int,
                let count = lines["count"] as? Int
            else {
                continue
            }

            let coverage = count > 0 ? (Double(covered) / Double(count)) * 100.0 : 0.0
            let name = (filename as NSString).lastPathComponent

            fileCoverages.append(
                FileCoverage(
                    path: filename,
                    name: name,
                    lineCoverage: coverage,
                    coveredLines: covered,
                    executableLines: count
                )
            )

            totalCovered += covered
            totalExecutable += count
        }

        guard !fileCoverages.isEmpty else {
            return nil
        }

        let overallCoverage =
            totalExecutable > 0 ? (Double(totalCovered) / Double(totalExecutable)) * 100.0 : 0.0

        return CodeCoverage(lineCoverage: overallCoverage, files: fileCoverages)
    }
}

// MARK: - Static API for backward compatibility

extension CoverageParser {
    static func parseCoverageFromPath(_ path: String, targetFilter: String? = nil) -> CodeCoverage? {
        CoverageParser().parseCoverageFromPath(path, targetFilter: targetFilter)
    }
}
