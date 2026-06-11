import CryptoKit
import Foundation

enum CurseForgePackInspectionError: LocalizedError, Equatable, Sendable {
    case missingManifest
    case unsupportedManifestType(String)
    case unsupportedManifestVersion(Int)
    case missingMinecraftVersion
    case missingFileIdentifiers
    case unsafePath(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            "整合包缺少 manifest.json"
        case .unsupportedManifestType(let type):
            "暂不支持 CurseForge 整合包类型：\(type)"
        case .unsupportedManifestVersion(let version):
            "暂不支持 CurseForge 整合包格式版本：\(version)"
        case .missingMinecraftVersion:
            "整合包缺少 Minecraft 版本信息"
        case .missingFileIdentifiers:
            "整合包文件缺少 projectID 或 fileID"
        case .unsafePath(let path):
            "整合包包含不安全路径：\(path)"
        case .unzipFailed(let message):
            "无法读取整合包：\(message)"
        }
    }
}

enum CurseForgePackImportError: LocalizedError, Sendable {
    case invalidPackExtension(String)
    case missingAPIKey
    case checksumMismatch(String)
    case invalidProfileID(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackExtension(let name):
            "请选择 CurseForge .zip 整合包文件：\(name)"
        case .missingAPIKey:
            "导入 CurseForge 整合包需要 API Key"
        case .checksumMismatch(let name):
            "整合包文件校验失败：\(name)"
        case .invalidProfileID(let id):
            "整合包实例名无效：\(id)"
        case .unzipFailed(let message):
            "解压 CurseForge 整合包失败：\(message)"
        }
    }
}

struct CurseForgePackPlan: Equatable, Sendable {
    let name: String
    let versionID: String
    let minecraftVersion: String
    let loaderSummary: String
    let fileCount: Int
    let requiredFileCount: Int
    let overrideEntryCount: Int
}

struct CurseForgePackManifest: Decodable, Sendable {
    let minecraft: CurseForgePackMinecraft
    let manifestType: String?
    let manifestVersion: Int
    let name: String
    let version: String?
    let author: String?
    let files: [CurseForgePackFile]
    let overrides: String?
}

struct CurseForgePackMinecraft: Decodable, Sendable {
    let version: String
    let modLoaders: [CurseForgePackModLoader]?
}

struct CurseForgePackModLoader: Decodable, Equatable, Sendable {
    let id: String
    let primary: Bool?
}

struct CurseForgePackFile: Decodable, Equatable, Sendable {
    let projectID: Int
    let fileID: Int
    let required: Bool?

    var isRequired: Bool {
        required ?? true
    }
}

struct CurseForgePackImportResult: Sendable {
    let plan: CurseForgePackPlan
    let instanceName: String
    let instanceDirectory: URL
    let profileID: String
    let downloadedFiles: Int
    let skippedFiles: Int
    let copiedOverrides: Int
}

func isCurseForgePackFileURL(_ url: URL) -> Bool {
    url.pathExtension.caseInsensitiveCompare("zip") == .orderedSame
}

struct CurseForgePackInspector: Sendable {
    func inspect(_ packURL: URL, importRoot: URL? = nil) throws -> CurseForgePackPlan {
        let manifest = try loadManifest(packURL, importRoot: importRoot)
        let entries = try zipEntries(packURL)
        let manifestEntry = try manifestEntry(in: entries)
        let overrideRoot = normalizedOverrideRoot(manifest.overrides, basePrefix: basePrefix(for: manifestEntry))
        let overrideEntryCount = try entries
            .filter { !$0.hasSuffix("/") }
            .filter { entry in
                guard let overrideRoot else { return false }
                return entry.hasPrefix(overrideRoot) && entry != manifestEntry
            }
            .reduce(0) { count, entry in
                guard let overrideRoot else { return count }
                let relative = String(entry.dropFirst(overrideRoot.count))
                guard !relative.isEmpty else { return count }
                try validateRelativePath(relative, importRoot: importRoot)
                return count + 1
            }

        return CurseForgePackPlan(
            name: manifest.name,
            versionID: manifest.version?.trimmed.nonEmpty ?? manifest.minecraft.version,
            minecraftVersion: manifest.minecraft.version,
            loaderSummary: loaderSummary(from: manifest.minecraft.modLoaders ?? []),
            fileCount: manifest.files.count,
            requiredFileCount: manifest.files.filter(\.isRequired).count,
            overrideEntryCount: overrideEntryCount
        )
    }

    func loadManifest(_ packURL: URL, importRoot: URL? = nil) throws -> CurseForgePackManifest {
        let entries = try zipEntries(packURL)
        let manifestEntry = try manifestEntry(in: entries)
        let data = try zipData(packURL, entry: manifestEntry)
        let manifest = try JSONDecoder().decode(CurseForgePackManifest.self, from: data)
        try validate(manifest, importRoot: importRoot)
        return manifest
    }

    func validate(_ manifest: CurseForgePackManifest, importRoot: URL?) throws {
        if let manifestType = manifest.manifestType?.trimmed,
           !manifestType.isEmpty,
           manifestType != "minecraftModpack" {
            throw CurseForgePackInspectionError.unsupportedManifestType(manifestType)
        }
        guard manifest.manifestVersion == 1 else {
            throw CurseForgePackInspectionError.unsupportedManifestVersion(manifest.manifestVersion)
        }
        guard !manifest.minecraft.version.trimmed.isEmpty else {
            throw CurseForgePackInspectionError.missingMinecraftVersion
        }
        for file in manifest.files {
            guard file.projectID > 0, file.fileID > 0 else {
                throw CurseForgePackInspectionError.missingFileIdentifiers
            }
        }
        if let overrides = manifest.overrides?.trimmed,
           !overrides.isEmpty,
           overrides != ".",
           overrides != "./" {
            try validateRelativePath(overrides.trimmingCharacters(in: CharacterSet(charactersIn: "/")), importRoot: importRoot)
        }
    }

    func validateRelativePath(_ path: String, importRoot: URL?) throws {
        let trimmedPath = path.trimmed
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/"),
              !trimmedPath.contains("\\") else {
            throw CurseForgePackInspectionError.unsafePath(path)
        }

        let components = trimmedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains(".") else {
            throw CurseForgePackInspectionError.unsafePath(path)
        }

        if let importRoot {
            let root = importRoot.standardizedFileURL
            let destination = root.appendingPathComponent(trimmedPath).standardizedFileURL
            guard destination.path.hasPrefix(root.path + "/") else {
                throw CurseForgePackInspectionError.unsafePath(path)
            }
        }
    }

    func manifestEntry(in entries: [String]) throws -> String {
        if entries.contains("manifest.json") {
            return "manifest.json"
        }
        if let nested = entries.first(where: { $0.hasSuffix("/manifest.json") }) {
            return nested
        }
        throw CurseForgePackInspectionError.missingManifest
    }

    func basePrefix(for manifestEntry: String) -> String {
        guard let slash = manifestEntry.lastIndex(of: "/") else { return "" }
        return String(manifestEntry[..<manifestEntry.index(after: slash)])
    }

    func normalizedOverrideRoot(_ overrideRoot: String?, basePrefix: String) -> String? {
        guard let overrideRoot = overrideRoot?.trimmed, !overrideRoot.isEmpty else {
            return nil
        }
        if overrideRoot == "." || overrideRoot == "./" {
            return basePrefix
        }
        let trimmed = overrideRoot.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return basePrefix }
        return "\(basePrefix)\(trimmed)/"
    }

    private func loaderSummary(from loaders: [CurseForgePackModLoader]) -> String {
        let summaries = loaders
            .map(\.id)
            .map(loaderDisplayName)
            .filter { !$0.isEmpty }
        return summaries.isEmpty ? "原版" : summaries.joined(separator: " / ")
    }

    private func loaderDisplayName(_ id: String) -> String {
        let lowercased = id.lowercased()
        if lowercased.hasPrefix("forge-") {
            return "Forge \(String(id.dropFirst("forge-".count)))"
        }
        if lowercased.hasPrefix("neoforge-") {
            return "NeoForge \(String(id.dropFirst("neoforge-".count)))"
        }
        if lowercased.hasPrefix("fabric-") {
            return "Fabric \(String(id.dropFirst("fabric-".count)))"
        }
        if lowercased.hasPrefix("quilt-") {
            return "Quilt \(String(id.dropFirst("quilt-".count)))"
        }
        return id
    }

    private func zipEntries(_ packURL: URL) throws -> [String] {
        let data = try runUnzip(arguments: ["-Z1", packURL.path])
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty } ?? []
    }

    private func zipData(_ packURL: URL, entry: String) throws -> Data {
        try runUnzip(arguments: ["-p", packURL.path, entry])
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
            throw CurseForgePackInspectionError.unzipFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmed
            throw CurseForgePackInspectionError.unzipFailed(message?.isEmpty == false ? message! : "unzip exited \(process.terminationStatus)")
        }
        return data
    }
}

struct CurseForgePackImporter: Sendable {
    typealias DataLoader = @Sendable (URL) async throws -> Data

    var resourceService: CurseForgeResourceService
    var dataLoader: DataLoader

    init(
        resourceService: CurseForgeResourceService = CurseForgeResourceService(),
        dataLoader: @escaping DataLoader = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.resourceService = resourceService
        self.dataLoader = dataLoader
    }

    func importPack(
        _ packURL: URL,
        apiKey: String,
        minecraftDirectory: URL,
        inheritedProfileID: String,
        progress: (@Sendable (String) async -> Void)? = nil
    ) async throws -> CurseForgePackImportResult {
        guard isCurseForgePackFileURL(packURL) else {
            throw CurseForgePackImportError.invalidPackExtension(packURL.lastPathComponent)
        }
        guard !apiKey.trimmed.isEmpty else {
            throw CurseForgePackImportError.missingAPIKey
        }

        let inspector = CurseForgePackInspector()
        let plan = try inspector.inspect(packURL)
        let manifest = try inspector.loadManifest(packURL)
        let instanceName = safeInstanceName(packName: manifest.name, versionID: plan.versionID)
        guard !instanceName.isEmpty else {
            throw CurseForgePackImportError.invalidProfileID(manifest.name)
        }

        let instanceDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(instanceName, isDirectory: true)
        try inspector.validate(manifest, importRoot: instanceDirectory)
        try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        try writeChildProfile(instanceName: instanceName, inheritedProfileID: inheritedProfileID, to: instanceDirectory)

        var downloaded = 0
        var skipped = 0
        let requiredFiles = manifest.files.filter(\.isRequired)
        var seenFileIDs = Set<Int>()

        for (offset, packFile) in requiredFiles.enumerated() where seenFileIDs.insert(packFile.fileID).inserted {
            await progress?("下载 CurseForge 文件 \(offset + 1)/\(requiredFiles.count)：\(packFile.fileID)")
            let file = try await resourceService.file(projectID: packFile.projectID, fileID: packFile.fileID, apiKey: apiKey)
            let destination = instanceDirectory
                .appendingPathComponent(targetFolder(for: file), isDirectory: true)
                .appendingPathComponent(try safeFileName(file.fileName))
            if try isSatisfied(file, at: destination) {
                skipped += 1
            } else {
                let url = try await resourceService.downloadURL(for: file, projectID: packFile.projectID, apiKey: apiKey)
                try await download(file, from: url, to: destination)
                downloaded += 1
            }
        }

        await progress?("正在复制 overrides")
        let copiedOverrides = try extractOverrides(packURL, manifest: manifest, to: instanceDirectory, inspector: inspector)
        return CurseForgePackImportResult(
            plan: plan,
            instanceName: instanceName,
            instanceDirectory: instanceDirectory,
            profileID: inheritedProfileID,
            downloadedFiles: downloaded,
            skippedFiles: skipped,
            copiedOverrides: copiedOverrides
        )
    }

    func safeInstanceName(packName: String, versionID: String) -> String {
        let combined = "\(packName)-\(versionID)"
        let sanitized = combined.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                return character
            }
            return "-"
        }
        let collapsed = String(sanitized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return collapsed.isEmpty ? "CurseForge-Pack" : String(collapsed.prefix(80))
    }

    private func writeChildProfile(instanceName: String, inheritedProfileID: String, to instanceDirectory: URL) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let profile: [String: Any] = [
            "id": instanceName,
            "type": "release",
            "time": now,
            "releaseTime": now,
            "inheritsFrom": inheritedProfileID,
            "libraries": []
        ]
        let data = try JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: instanceDirectory.appendingPathComponent("\(instanceName).json"), options: [.atomic])
    }

    private func targetFolder(for file: CurseForgeFile) -> String {
        let fileName = file.fileName.lowercased()
        let moduleNames = Set((file.modules ?? []).map { $0.name.lowercased() })
        if moduleNames.contains("meta-inf") || moduleNames.contains("mcmod.info") || fileName.hasSuffix(".jar") {
            return "mods"
        }
        if moduleNames.contains("pack.mcmeta") {
            return "resourcepacks"
        }
        return fileName.hasSuffix(".zip") ? "shaderpacks" : "mods"
    }

    private func safeFileName(_ fileName: String) throws -> String {
        let lastPathComponent = URL(fileURLWithPath: fileName).lastPathComponent
        guard lastPathComponent == fileName,
              !lastPathComponent.isEmpty,
              !lastPathComponent.contains("/") &&
              !lastPathComponent.contains("\\") &&
              !lastPathComponent.contains("..") else {
            throw CurseForgeResourceError.unsafeFileName(fileName)
        }
        return lastPathComponent
    }

    private func isSatisfied(_ file: CurseForgeFile, at destination: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        let data = try Data(contentsOf: destination)
        if let fileLength = file.fileLength, data.count != fileLength {
            return false
        }
        return hashMatches(data, file: file)
    }

    private func download(_ file: CurseForgeFile, from url: URL, to destination: URL) async throws {
        let data = try await dataLoader(url)
        if let fileLength = file.fileLength, data.count != fileLength {
            throw CurseForgePackImportError.checksumMismatch(file.fileName)
        }
        guard hashMatches(data, file: file) else {
            throw CurseForgePackImportError.checksumMismatch(file.fileName)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic])
    }

    private func hashMatches(_ data: Data, file: CurseForgeFile) -> Bool {
        if let sha1 = file.sha1, !sha1.isEmpty {
            let digest = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return digest == sha1
        }
        return true
    }

    private func extractOverrides(
        _ packURL: URL,
        manifest: CurseForgePackManifest,
        to instanceDirectory: URL,
        inspector: CurseForgePackInspector
    ) throws -> Int {
        let entries = try zipEntries(packURL)
        let manifestEntry = try inspector.manifestEntry(in: entries)
        guard let overrideRoot = inspector.normalizedOverrideRoot(manifest.overrides, basePrefix: inspector.basePrefix(for: manifestEntry)) else {
            return 0
        }

        var copied = 0
        for entry in entries where !entry.hasSuffix("/") && entry.hasPrefix(overrideRoot) && entry != manifestEntry {
            let relativePath = String(entry.dropFirst(overrideRoot.count))
            guard !relativePath.isEmpty else { continue }
            try inspector.validateRelativePath(relativePath, importRoot: instanceDirectory)
            let data = try zipData(packURL, entry: entry)
            let destination = instanceDirectory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: [.atomic])
            copied += 1
        }
        return copied
    }

    private func zipEntries(_ packURL: URL) throws -> [String] {
        let data = try runUnzip(arguments: ["-Z1", packURL.path])
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty } ?? []
    }

    private func zipData(_ packURL: URL, entry: String) throws -> Data {
        try runUnzip(arguments: ["-p", packURL.path, entry])
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
            throw CurseForgePackImportError.unzipFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmed
            throw CurseForgePackImportError.unzipFailed(message?.isEmpty == false ? message! : "unzip exited \(process.terminationStatus)")
        }
        return data
    }
}
