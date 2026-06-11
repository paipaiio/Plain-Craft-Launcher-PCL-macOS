import Foundation

enum LocalModStatus: String, Sendable {
    case enabled = "已启用"
    case disabled = "已禁用"
    case archived = "旧文件"
}

struct LocalModMetadata: Hashable, Sendable {
    let displayName: String?
    let version: String?
    let loader: String?
    let description: String?
}

struct LocalModFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let displayName: String
    let status: LocalModStatus
    let size: Int64
    let modifiedAt: Date?
    let metadata: LocalModMetadata?

    var canToggle: Bool {
        true
    }
}

enum LocalModManagerError: LocalizedError {
    case missingModsDirectory
    case unsupportedModFile(String)
    case targetAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .missingModsDirectory:
            "当前实例还没有 mods 文件夹"
        case .unsupportedModFile(let name):
            "不支持的 Mod 文件：\(name)"
        case .targetAlreadyExists(let name):
            "目标文件已存在：\(name)"
        }
    }
}

struct LocalModManager {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func modsDirectory(for instanceDirectory: URL) -> URL {
        instanceDirectory.appendingPathComponent("mods", isDirectory: true)
    }

    func scan(instanceDirectory: URL) throws -> [LocalModFile] {
        let modsDirectory = modsDirectory(for: instanceDirectory)
        guard fileManager.fileExists(atPath: modsDirectory.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: modsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            guard try isRegularFile(url) else { return nil }
            guard let status = status(for: url) else { return nil }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let metadata = loadMetadata(from: url)
            return LocalModFile(
                url: url,
                displayName: metadata?.displayName ?? displayName(for: url),
                status: status,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                metadata: metadata
            )
        }
        .sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status.sortOrder < rhs.status.sortOrder
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    func importFiles(_ files: [URL], instanceDirectory: URL) throws -> [LocalModFile] {
        let modsDirectory = modsDirectory(for: instanceDirectory)
        try fileManager.createDirectory(at: modsDirectory, withIntermediateDirectories: true)

        var importedNames: [String] = []
        for file in files {
            let fileName = try safeImportFileName(file.lastPathComponent)
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw LocalModManagerError.unsupportedModFile(fileName)
            }
            let destination = modsDirectory.appendingPathComponent(fileName)
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw LocalModManagerError.targetAlreadyExists(fileName)
            }
            try fileManager.copyItem(at: file, to: destination)
            importedNames.append(fileName)
        }

        let importedSet = Set(importedNames)
        return try scan(instanceDirectory: instanceDirectory)
            .filter { importedSet.contains($0.url.lastPathComponent) }
    }

    func toggle(_ file: LocalModFile) throws -> LocalModFile {
        let destination = try toggledURL(for: file)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw LocalModManagerError.targetAlreadyExists(destination.lastPathComponent)
        }
        try fileManager.moveItem(at: file.url, to: destination)
        guard let updated = try scan(instanceDirectory: destination.deletingLastPathComponent().deletingLastPathComponent())
            .first(where: { $0.url == destination }) else {
            throw LocalModManagerError.unsupportedModFile(destination.lastPathComponent)
        }
        return updated
    }

    func toggledURL(for file: LocalModFile) throws -> URL {
        switch file.status {
        case .enabled:
            return file.url.appendingPathExtension("disabled")
        case .disabled:
            return file.url.deletingPathExtension()
        case .archived:
            return file.url.deletingPathExtension()
        }
    }

    private func safeImportFileName(_ fileName: String) throws -> String {
        let lowercased = fileName.lowercased()
        guard !fileName.isEmpty,
              !fileName.contains("/") &&
              !fileName.contains("\\") &&
              !fileName.contains(".."),
              Self.enabledExtensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased()) else {
            throw LocalModManagerError.unsupportedModFile(fileName)
        }
        guard !Self.disabledSuffixes.contains(where: { lowercased.hasSuffix($0) }),
              !Self.archivedSuffixes.contains(where: { lowercased.hasSuffix($0) }) else {
            throw LocalModManagerError.unsupportedModFile(fileName)
        }
        return fileName
    }

    private func isRegularFile(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        return values.isRegularFile == true
    }

    private func status(for url: URL) -> LocalModStatus? {
        let lowercasedName = url.lastPathComponent.lowercased()
        if Self.enabledExtensions.contains(url.pathExtension.lowercased()) {
            return .enabled
        }
        if Self.disabledSuffixes.contains(where: { lowercasedName.hasSuffix($0) }) {
            return .disabled
        }
        if Self.archivedSuffixes.contains(where: { lowercasedName.hasSuffix($0) }) {
            return .archived
        }
        return nil
    }

    private func displayName(for url: URL) -> String {
        var name = url.lastPathComponent
        for suffix in Self.disabledSuffixes + Self.archivedSuffixes where name.lowercased().hasSuffix(suffix) {
            name.removeLast(suffix.count)
            return name
        }
        if Self.enabledExtensions.contains(url.pathExtension.lowercased()) {
            return url.deletingPathExtension().lastPathComponent
        }
        return name
    }

    private func loadMetadata(from url: URL) -> LocalModMetadata? {
        if let metadata = fabricMetadata(from: url) {
            return metadata
        }
        if let metadata = quiltMetadata(from: url) {
            return metadata
        }
        if let metadata = forgeMetadata(from: url, entry: "META-INF/mods.toml", loader: "Forge") {
            return metadata
        }
        if let metadata = forgeMetadata(from: url, entry: "META-INF/neoforge.mods.toml", loader: "NeoForge") {
            return metadata
        }
        if let metadata = legacyForgeMetadata(from: url) {
            return metadata
        }
        return nil
    }

    private func fabricMetadata(from url: URL) -> LocalModMetadata? {
        guard let data = zipEntryData("fabric.mod.json", from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return LocalModMetadata(
            displayName: cleanString(object["name"] as? String),
            version: cleanVersion(object["version"] as? String, archiveURL: url),
            loader: "Fabric",
            description: cleanString(object["description"] as? String)
        )
    }

    private func quiltMetadata(from url: URL) -> LocalModMetadata? {
        guard let data = zipEntryData("quilt.mod.json", from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loader = object["quilt_loader"] as? [String: Any] else {
            return nil
        }
        let metadata = loader["metadata"] as? [String: Any]
        return LocalModMetadata(
            displayName: cleanString(metadata?["name"] as? String),
            version: cleanVersion(loader["version"] as? String, archiveURL: url),
            loader: "Quilt",
            description: cleanString(metadata?["description"] as? String)
        )
    }

    private func forgeMetadata(from url: URL, entry: String, loader: String) -> LocalModMetadata? {
        guard let data = zipEntryData(entry, from: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let values = parseFirstModTOMLBlock(text)
        guard !values.isEmpty else { return nil }
        return LocalModMetadata(
            displayName: cleanString(values["displayName"]),
            version: cleanVersion(values["version"], archiveURL: url),
            loader: loader,
            description: cleanString(values["description"])
        )
    }

    private func legacyForgeMetadata(from url: URL) -> LocalModMetadata? {
        guard let data = zipEntryData("mcmod.info", from: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let info: [String: Any]?
        if let array = object as? [[String: Any]] {
            info = array.first
        } else if let dictionary = object as? [String: Any],
                  let modList = dictionary["modList"] as? [[String: Any]] {
            info = modList.first
        } else {
            info = nil
        }
        guard let info else { return nil }

        return LocalModMetadata(
            displayName: cleanString(info["name"] as? String),
            version: cleanVersion(info["version"] as? String, archiveURL: url),
            loader: "Forge",
            description: cleanString(info["description"] as? String)
        )
    }

    private func parseFirstModTOMLBlock(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        var insideModBlock = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripTOMLComment(rawLine).trimmed
            guard !line.isEmpty else { continue }
            if line == "[[mods]]" || line == "[mods]" {
                if insideModBlock, !values.isEmpty {
                    break
                }
                insideModBlock = true
                continue
            }
            if insideModBlock, line.hasPrefix("[") {
                break
            }
            guard insideModBlock, let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmed
            let rawValue = String(line[line.index(after: separator)...]).trimmed
            values[key] = parseTOMLString(rawValue)
        }

        return values
    }

    private func parseTOMLString(_ value: String) -> String {
        var text = value.trimmed
        if text.hasPrefix(#""""#), text.hasSuffix(#""""#), text.count >= 6 {
            text.removeFirst(3)
            text.removeLast(3)
            return text.trimmed
        }
        if text.hasPrefix("'''"), text.hasSuffix("'''"), text.count >= 6 {
            text.removeFirst(3)
            text.removeLast(3)
            return text.trimmed
        }
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text.removeFirst()
            text.removeLast()
            return text.trimmed
        }
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 {
            text.removeFirst()
            text.removeLast()
            return text.trimmed
        }
        return text
    }

    private func stripTOMLComment(_ line: String) -> String {
        var isInsideQuote = false
        var quoteCharacter: Character?
        for (index, character) in line.enumerated() {
            if character == "\"" || character == "'" {
                if isInsideQuote, quoteCharacter == character {
                    isInsideQuote = false
                    quoteCharacter = nil
                } else if !isInsideQuote {
                    isInsideQuote = true
                    quoteCharacter = character
                }
            }
            if character == "#", !isInsideQuote {
                let end = line.index(line.startIndex, offsetBy: index)
                return String(line[..<end])
            }
        }
        return line
    }

    private func cleanString(_ value: String?) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        let lowercased = value.lowercased()
        if lowercased == "name" || lowercased.contains("modname") {
            return nil
        }
        return value
    }

    private func cleanVersion(_ value: String?, archiveURL: URL) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        if value.localizedCaseInsensitiveContains("version") || value.contains("${") {
            return manifestImplementationVersion(from: archiveURL)
        }
        return value
    }

    private func manifestImplementationVersion(from url: URL) -> String? {
        guard let data = zipEntryData("META-INF/MANIFEST.MF", from: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        for line in text.components(separatedBy: .newlines) {
            let normalized = line.replacingOccurrences(of: " :", with: ":")
            if normalized.hasPrefix("Implementation-Version:") {
                return cleanString(String(normalized.dropFirst("Implementation-Version:".count)))
            }
        }
        return nil
    }

    private func zipEntryData(_ entry: String, from archiveURL: URL) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archiveURL.path, entry]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    private static let enabledExtensions: Set<String> = ["jar", "zip", "litemod"]
    private static let disabledSuffixes = [".jar.disabled", ".zip.disabled", ".litemod.disabled"]
    private static let archivedSuffixes = [".jar.old", ".zip.old", ".litemod.old"]
}

private extension LocalModStatus {
    var sortOrder: Int {
        switch self {
        case .enabled:
            0
        case .disabled:
            1
        case .archived:
            2
        }
    }
}
