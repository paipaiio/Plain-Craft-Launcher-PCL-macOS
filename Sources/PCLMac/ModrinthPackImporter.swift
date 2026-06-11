import CryptoKit
import Foundation

enum ModrinthPackImportError: LocalizedError, Sendable {
    case invalidPackExtension(String)
    case missingDownload(String)
    case checksumMismatch(String)
    case unsupportedPackLoader(String)
    case missingJavaForForge(String)
    case missingMinecraftVersionInManifest(String)
    case invalidProfileID(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackExtension(let name):
            "请选择 .mrpack 整合包文件：\(name)"
        case .missingDownload(let path):
            "整合包文件缺少下载地址：\(path)"
        case .checksumMismatch(let path):
            "整合包文件校验失败：\(path)"
        case .unsupportedPackLoader(let loader):
            "暂不支持导入该整合包加载器：\(loader)"
        case .missingJavaForForge(let loader):
            "导入 \(loader) 整合包需要先选择可用 Java"
        case .missingMinecraftVersionInManifest(let version):
            "Mojang 版本清单中没有找到 Minecraft \(version)"
        case .invalidProfileID(let id):
            "整合包实例名无效：\(id)"
        case .unzipFailed(let message):
            "解压整合包失败：\(message)"
        }
    }
}

struct ModrinthPackImportResult: Sendable {
    let plan: ModrinthPackPlan
    let instanceName: String
    let instanceDirectory: URL
    let profileID: String
    let downloadedFiles: Int
    let skippedFiles: Int
    let copiedOverrides: Int
}

func isModrinthPackFileURL(_ url: URL) -> Bool {
    url.pathExtension.caseInsensitiveCompare("mrpack") == .orderedSame
}

struct ModrinthPackImporter: Sendable {
    typealias DataLoader = @Sendable (URL) async throws -> Data

    var dataLoader: DataLoader

    init(
        dataLoader: @escaping DataLoader = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.dataLoader = dataLoader
    }

    func importPack(
        _ packURL: URL,
        minecraftDirectory: URL,
        inheritedProfileID: String,
        progress: (@Sendable (String) async -> Void)? = nil
    ) async throws -> ModrinthPackImportResult {
        guard isModrinthPackFileURL(packURL) else {
            throw ModrinthPackImportError.invalidPackExtension(packURL.lastPathComponent)
        }
        let inspector = ModrinthPackInspector()
        let plan = try inspector.inspect(packURL)
        let index = try inspector.loadIndex(packURL)
        let instanceName = safeInstanceName(packName: index.name, versionID: index.versionId)
        guard !instanceName.isEmpty else {
            throw ModrinthPackImportError.invalidProfileID(index.name)
        }

        let instanceDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(instanceName, isDirectory: true)
        try inspector.validate(index, importRoot: instanceDirectory)
        try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        try writeChildProfile(instanceName: instanceName, inheritedProfileID: inheritedProfileID, to: instanceDirectory)

        var downloaded = 0
        var skipped = 0
        let clientFiles = index.files.filter(\.isNeededByClient)
        for (offset, file) in clientFiles.enumerated() {
            await progress?("下载整合包文件 \(offset + 1)/\(clientFiles.count)：\(file.path)")
            let destination = instanceDirectory.appendingPathComponent(file.path)
            if try isSatisfied(file, at: destination) {
                skipped += 1
            } else {
                try await download(file, to: destination)
                downloaded += 1
            }
        }

        await progress?("正在复制 overrides")
        let copiedOverrides = try extractOverrides(packURL, to: instanceDirectory, inspector: inspector)
        return ModrinthPackImportResult(
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
        return collapsed.isEmpty ? "Modrinth-Pack" : String(collapsed.prefix(80))
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

    private func isSatisfied(_ file: ModrinthPackFile, at destination: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        let data = try Data(contentsOf: destination)
        if let fileSize = file.fileSize, data.count != fileSize {
            return false
        }
        return hashMatches(data, hashes: file.hashes)
    }

    private func download(_ file: ModrinthPackFile, to destination: URL) async throws {
        guard !file.downloads.isEmpty else {
            throw ModrinthPackImportError.missingDownload(file.path)
        }

        var lastError: Error?
        for url in file.downloads {
            do {
                let data = try await dataLoader(url)
                guard hashMatches(data, hashes: file.hashes) else {
                    throw ModrinthPackImportError.checksumMismatch(file.path)
                }
                if let fileSize = file.fileSize, data.count != fileSize {
                    throw ModrinthPackImportError.checksumMismatch(file.path)
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: [.atomic])
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ModrinthPackImportError.missingDownload(file.path)
    }

    private func hashMatches(_ data: Data, hashes: [String: String]) -> Bool {
        if let sha512 = hashes["sha512"]?.lowercased(), !sha512.isEmpty {
            let digest = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return digest == sha512
        }
        if let sha1 = hashes["sha1"]?.lowercased(), !sha1.isEmpty {
            let digest = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return digest == sha1
        }
        return true
    }

    private func extractOverrides(_ packURL: URL, to instanceDirectory: URL, inspector: ModrinthPackInspector) throws -> Int {
        let entries = try zipEntries(packURL)
        var copied = 0
        for entry in entries where !entry.hasSuffix("/") {
            guard let relativePath = overrideRelativePath(entry) else { continue }
            try inspector.validateRelativePath(relativePath, importRoot: instanceDirectory)
            let data = try zipData(packURL, entry: entry)
            let destination = instanceDirectory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: [.atomic])
            copied += 1
        }
        return copied
    }

    private func overrideRelativePath(_ entry: String) -> String? {
        if entry.hasPrefix("client-overrides/") {
            return String(entry.dropFirst("client-overrides/".count))
        }
        if entry.hasPrefix("overrides/") {
            return String(entry.dropFirst("overrides/".count))
        }
        return nil
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
            throw ModrinthPackImportError.unzipFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmed
            throw ModrinthPackImportError.unzipFailed(message?.isEmpty == false ? message! : "unzip exited \(process.terminationStatus)")
        }
        return data
    }
}

private extension ModrinthPackFile {
    var isNeededByClient: Bool {
        guard let env else { return true }
        return env.client?.lowercased() != "unsupported"
    }
}
