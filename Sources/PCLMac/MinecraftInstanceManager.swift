import Foundation

enum MinecraftInstanceManagerError: LocalizedError, Equatable, Sendable {
    case missingInstance
    case unsafeInstancePath(URL)
    case unsafeImportPath(String)
    case missingVersionJSON(URL)
    case invalidVersionJSON(URL)
    case duplicateTargetExists(URL)
    case invalidImportArchive(String)
    case unsafeExportDestination(URL)
    case exportProcessFailed(String)
    case importProcessFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingInstance:
            "请先选择 Minecraft 实例"
        case .unsafeInstancePath(let url):
            "实例路径不在 versions 目录内：\(url.path)"
        case .unsafeImportPath(let path):
            "实例压缩包包含不安全路径：\(path)"
        case .missingVersionJSON(let url):
            "实例缺少版本 JSON：\(url.path)"
        case .invalidVersionJSON(let url):
            "实例版本 JSON 无法更新：\(url.path)"
        case .duplicateTargetExists(let url):
            "目标实例已存在：\(url.path)"
        case .invalidImportArchive(let message):
            message.isEmpty ? "实例压缩包格式无效" : "实例压缩包格式无效：\(message)"
        case .unsafeExportDestination(let url):
            "导出目标不能放在实例目录内：\(url.path)"
        case .exportProcessFailed(let message):
            message.isEmpty ? "实例导出失败" : "实例导出失败：\(message)"
        case .importProcessFailed(let message):
            message.isEmpty ? "实例导入失败" : "实例导入失败：\(message)"
        }
    }
}

struct MinecraftInstanceOperationResult: Sendable {
    let name: String
    let directory: URL
    let jsonURL: URL
}

struct MinecraftInstanceExportResult: Sendable {
    let name: String
    let archiveURL: URL
    let byteCount: Int64
}

struct MinecraftInstanceImportResult: Sendable {
    let name: String
    let directory: URL
    let jsonURL: URL
    let originalName: String
}

struct MinecraftInstanceManager {
    var fileManager: FileManager = .default

    func duplicate(_ instance: MinecraftInstance, minecraftDirectory: URL) throws -> MinecraftInstanceOperationResult {
        let versionsDirectory = minecraftDirectory.appendingPathComponent("versions", isDirectory: true)
        try validate(instance: instance, versionsDirectory: versionsDirectory)

        let copyName = uniqueCopyName(baseName: "\(instance.name)-副本", versionsDirectory: versionsDirectory)
        let destination = versionsDirectory.appendingPathComponent(copyName, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw MinecraftInstanceManagerError.duplicateTargetExists(destination)
        }

        try fileManager.copyItem(at: instance.path, to: destination)

        let copiedJSON = destination.appendingPathComponent(instance.jsonURL.lastPathComponent)
        guard fileManager.fileExists(atPath: copiedJSON.path) else {
            throw MinecraftInstanceManagerError.missingVersionJSON(copiedJSON)
        }

        let newJSON = destination.appendingPathComponent("\(copyName).json")
        if copiedJSON.lastPathComponent != newJSON.lastPathComponent {
            if fileManager.fileExists(atPath: newJSON.path) {
                try fileManager.removeItem(at: newJSON)
            }
            try fileManager.moveItem(at: copiedJSON, to: newJSON)
        }
        try updateVersionID(in: newJSON, id: copyName)

        let copiedJar = destination.appendingPathComponent("\(instance.name).jar")
        let newJar = destination.appendingPathComponent("\(copyName).jar")
        if fileManager.fileExists(atPath: copiedJar.path), copiedJar.lastPathComponent != newJar.lastPathComponent {
            if fileManager.fileExists(atPath: newJar.path) {
                try fileManager.removeItem(at: newJar)
            }
            try fileManager.moveItem(at: copiedJar, to: newJar)
        }

        return MinecraftInstanceOperationResult(name: copyName, directory: destination, jsonURL: newJSON)
    }

    func remove(_ instance: MinecraftInstance, minecraftDirectory: URL) throws {
        let versionsDirectory = minecraftDirectory.appendingPathComponent("versions", isDirectory: true)
        try validate(instance: instance, versionsDirectory: versionsDirectory)
        try fileManager.removeItem(at: instance.path)
    }

    func exportArchive(_ instance: MinecraftInstance, minecraftDirectory: URL, destination: URL) throws -> MinecraftInstanceExportResult {
        let versionsDirectory = minecraftDirectory.appendingPathComponent("versions", isDirectory: true)
        try validate(instance: instance, versionsDirectory: versionsDirectory)

        let archiveURL = destination.pathExtension.lowercased() == "zip"
            ? destination
            : destination.appendingPathExtension("zip")
        let archivePath = archiveURL.standardizedFileURL.path
        let instancePath = instance.path.standardizedFileURL.path
        guard archivePath != instancePath, !archivePath.hasPrefix(instancePath + "/") else {
            throw MinecraftInstanceManagerError.unsafeExportDestination(archiveURL)
        }

        let parent = archiveURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", instance.path.path, archiveURL.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MinecraftInstanceManagerError.exportProcessFailed(message)
        }

        let attributes = try fileManager.attributesOfItem(atPath: archiveURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return MinecraftInstanceExportResult(name: instance.name, archiveURL: archiveURL, byteCount: byteCount)
    }

    func importArchive(_ archiveURL: URL, minecraftDirectory: URL) throws -> MinecraftInstanceImportResult {
        guard archiveURL.pathExtension.caseInsensitiveCompare("zip") == .orderedSame else {
            throw MinecraftInstanceManagerError.invalidImportArchive("请选择 .zip 实例备份")
        }

        let entries = try zipEntries(archiveURL)
        guard !entries.isEmpty else {
            throw MinecraftInstanceManagerError.invalidImportArchive("压缩包为空")
        }
        try entries.forEach(validateArchiveRelativePath)

        let importName = try importedInstanceName(from: entries, archiveURL: archiveURL)
        let versionsDirectory = minecraftDirectory.appendingPathComponent("versions", isDirectory: true)
        try fileManager.createDirectory(at: versionsDirectory, withIntermediateDirectories: true)
        let destinationName = uniqueCopyName(baseName: importName, versionsDirectory: versionsDirectory)
        let destination = versionsDirectory.appendingPathComponent(destinationName, isDirectory: true)

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PCLMacInstanceImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try extractArchive(archiveURL, to: temporaryRoot)

        let source = try extractedInstanceSource(in: temporaryRoot, preferredName: importName)
        try copyExtractedInstance(from: source, to: destination, temporaryRoot: temporaryRoot)
        let jsonURL = try normalizeImportedInstance(at: destination, name: destinationName, originalName: source.lastPathComponent)
        return MinecraftInstanceImportResult(
            name: destinationName,
            directory: destination,
            jsonURL: jsonURL,
            originalName: importName
        )
    }

    func validate(instance: MinecraftInstance, versionsDirectory: URL) throws {
        let root = versionsDirectory.standardizedFileURL
        let instancePath = instance.path.standardizedFileURL
        let jsonPath = instance.jsonURL.standardizedFileURL
        guard instancePath.path.hasPrefix(root.path + "/"),
              jsonPath.path.hasPrefix(instancePath.path + "/") else {
            throw MinecraftInstanceManagerError.unsafeInstancePath(instance.path)
        }
        guard fileManager.fileExists(atPath: instance.jsonURL.path) else {
            throw MinecraftInstanceManagerError.missingVersionJSON(instance.jsonURL)
        }
    }

    func uniqueCopyName(baseName: String, versionsDirectory: URL) -> String {
        let sanitized = sanitizeInstanceName(baseName)
        var candidate = sanitized
        var counter = 2
        while fileManager.fileExists(atPath: versionsDirectory.appendingPathComponent(candidate, isDirectory: true).path) {
            candidate = "\(sanitized)-\(counter)"
            counter += 1
        }
        return candidate
    }

    func sanitizeInstanceName(_ value: String) -> String {
        let mapped = value.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                return character
            }
            return "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return collapsed.isEmpty ? "Minecraft-Instance" : String(collapsed.prefix(80))
    }

    private func updateVersionID(in jsonURL: URL, id: String) throws {
        let data = try Data(contentsOf: jsonURL)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MinecraftInstanceManagerError.invalidVersionJSON(jsonURL)
        }
        object["id"] = id
        let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: jsonURL, options: [.atomic])
    }

    private func validateArchiveRelativePath(_ path: String) throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/"),
              !trimmedPath.contains("\\"),
              !trimmedPath.contains("//") else {
            throw MinecraftInstanceManagerError.unsafeImportPath(path)
        }

        let components = trimmedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              !components.contains(".."),
              !components.contains(".") else {
            throw MinecraftInstanceManagerError.unsafeImportPath(path)
        }
    }

    private func importedInstanceName(from entries: [String], archiveURL: URL) throws -> String {
        let usefulEntries = entries.filter { entry in
            let normalized = entry.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return !normalized.isEmpty &&
                !normalized.hasPrefix("__MACOSX/") &&
                !normalized.split(separator: "/").contains { $0.hasPrefix("._") } &&
                normalized != ".DS_Store"
        }
        guard !usefulEntries.isEmpty else {
            throw MinecraftInstanceManagerError.invalidImportArchive("没有可导入的实例文件")
        }

        let topLevelNames = Set(usefulEntries.compactMap { $0.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) })
        if topLevelNames.count == 1, let topLevelName = topLevelNames.first {
            let expectedJSON = "\(topLevelName)/\(topLevelName).json"
            if usefulEntries.contains(where: { $0 == expectedJSON }) {
                return sanitizeInstanceName(topLevelName)
            }

            let topLevelJSONs = usefulEntries.compactMap { entry -> String? in
                let components = entry.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard components.count == 2,
                      components[0] == topLevelName,
                      components[1].hasSuffix(".json") else {
                    return nil
                }
                return URL(fileURLWithPath: components[1]).deletingPathExtension().lastPathComponent
            }
            if let jsonName = topLevelJSONs.sorted().first {
                return sanitizeInstanceName(jsonName)
            }
        }

        let rootJSONs = usefulEntries.compactMap { entry -> String? in
            let components = entry.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard components.count == 1, components[0].hasSuffix(".json") else { return nil }
            return URL(fileURLWithPath: components[0]).deletingPathExtension().lastPathComponent
        }
        if let jsonName = rootJSONs.sorted().first {
            return sanitizeInstanceName(jsonName)
        }

        let archiveName = archiveURL.deletingPathExtension().lastPathComponent
        let fallbackName = sanitizeInstanceName(archiveName)
        guard !fallbackName.isEmpty else {
            throw MinecraftInstanceManagerError.invalidImportArchive("没有找到实例版本 JSON")
        }
        return fallbackName
    }

    private func extractedInstanceSource(in temporaryRoot: URL, preferredName: String) throws -> URL {
        let preferredDirectory = temporaryRoot.appendingPathComponent(preferredName, isDirectory: true)
        if isDirectory(preferredDirectory), try topLevelJSON(in: preferredDirectory) != nil {
            return preferredDirectory
        }

        let items = try fileManager.contentsOfDirectory(
            at: temporaryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let directories = items.filter { isDirectory($0) && $0.lastPathComponent != "__MACOSX" }
        if directories.count == 1, try topLevelJSON(in: directories[0]) != nil {
            return directories[0]
        }

        if try topLevelJSON(in: temporaryRoot) != nil {
            return temporaryRoot
        }

        throw MinecraftInstanceManagerError.invalidImportArchive("没有找到实例版本 JSON")
    }

    private func copyExtractedInstance(from source: URL, to destination: URL, temporaryRoot: URL) throws {
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw MinecraftInstanceManagerError.duplicateTargetExists(destination)
        }

        if source.standardizedFileURL == temporaryRoot.standardizedFileURL {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let items = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for item in items where item.lastPathComponent != "__MACOSX" {
                try fileManager.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
            }
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func normalizeImportedInstance(at directory: URL, name: String, originalName: String) throws -> URL {
        guard let importedJSON = try topLevelJSON(in: directory) else {
            throw MinecraftInstanceManagerError.missingVersionJSON(directory.appendingPathComponent("\(name).json"))
        }

        let importedJSONName = importedJSON.deletingPathExtension().lastPathComponent
        let normalizedJSON = directory.appendingPathComponent("\(name).json")
        if importedJSON.standardizedFileURL != normalizedJSON.standardizedFileURL {
            if fileManager.fileExists(atPath: normalizedJSON.path) {
                try fileManager.removeItem(at: normalizedJSON)
            }
            try fileManager.moveItem(at: importedJSON, to: normalizedJSON)
        }
        try updateVersionID(in: normalizedJSON, id: name)

        let normalizedJar = directory.appendingPathComponent("\(name).jar")
        var jarCandidates: [String] = []
        for candidate in [importedJSONName, originalName] where !jarCandidates.contains(candidate) {
            jarCandidates.append(candidate)
        }
        for candidate in jarCandidates {
            let jar = directory.appendingPathComponent("\(candidate).jar")
            guard fileManager.fileExists(atPath: jar.path),
                  jar.standardizedFileURL != normalizedJar.standardizedFileURL else {
                continue
            }
            if fileManager.fileExists(atPath: normalizedJar.path) {
                try fileManager.removeItem(at: normalizedJar)
            }
            try fileManager.moveItem(at: jar, to: normalizedJar)
            break
        }

        return normalizedJSON
    }

    private func topLevelJSON(in directory: URL) throws -> URL? {
        let items = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return items
            .filter { $0.pathExtension.caseInsensitiveCompare("json") == .orderedSame }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func zipEntries(_ archiveURL: URL) throws -> [String] {
        let data = try runUnzip(arguments: ["-Z1", archiveURL.path])
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func extractArchive(_ archiveURL: URL, to destination: URL) throws {
        _ = try runDitto(arguments: ["-x", "-k", archiveURL.path, destination.path])
    }

    private func runUnzip(arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw MinecraftInstanceManagerError.importProcessFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MinecraftInstanceManagerError.importProcessFailed(message.isEmpty ? "unzip exited \(process.terminationStatus)" : message)
        }
        return data
    }

    private func runDitto(arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw MinecraftInstanceManagerError.importProcessFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MinecraftInstanceManagerError.importProcessFailed(message.isEmpty ? "ditto exited \(process.terminationStatus)" : message)
        }
        return data
    }
}
