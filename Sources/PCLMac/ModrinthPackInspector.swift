import Foundation

enum ModrinthPackInspectionError: LocalizedError, Equatable, Sendable {
    case missingIndex
    case unsupportedFormat(Int)
    case unsupportedGame(String)
    case missingMinecraftVersion
    case unsafePath(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingIndex:
            "整合包缺少 modrinth.index.json"
        case .unsupportedFormat(let version):
            "暂不支持 Modrinth Pack 格式版本：\(version)"
        case .unsupportedGame(let game):
            "该整合包不是 Minecraft：\(game)"
        case .missingMinecraftVersion:
            "整合包缺少 Minecraft 版本依赖"
        case .unsafePath(let path):
            "整合包包含不安全路径：\(path)"
        case .unzipFailed(let message):
            "无法读取整合包：\(message)"
        }
    }
}

struct ModrinthPackPlan: Equatable, Sendable {
    let name: String
    let versionID: String
    let minecraftVersion: String
    let loaderSummary: String
    let fileCount: Int
    let overrideEntryCount: Int
}

struct ModrinthPackIndex: Decodable, Sendable {
    let formatVersion: Int
    let game: String
    let versionId: String
    let name: String
    let summary: String?
    let files: [ModrinthPackFile]
    let dependencies: [String: String]
}

struct ModrinthPackFile: Decodable, Sendable {
    let path: String
    let hashes: [String: String]
    let downloads: [URL]
    let fileSize: Int?
    let env: ModrinthPackFileEnvironment?

    enum CodingKeys: String, CodingKey {
        case path
        case hashes
        case downloads
        case fileSize
        case env
    }
}

struct ModrinthPackFileEnvironment: Decodable, Sendable {
    let client: String?
    let server: String?
}

struct ModrinthPackInspector: Sendable {
    func inspect(_ packURL: URL, importRoot: URL? = nil) throws -> ModrinthPackPlan {
        let index = try loadIndex(packURL, importRoot: importRoot)
        let entries = try unzipEntries(packURL: packURL)
        let overrideEntryCount = try entries
            .filter { !$0.hasSuffix("/") }
            .filter { $0.hasPrefix("overrides/") || $0.hasPrefix("client-overrides/") }
            .reduce(0) { count, entry in
                let relative = entry
                    .replacingOccurrences(of: "client-overrides/", with: "")
                    .replacingOccurrences(of: "overrides/", with: "")
                try validateRelativePath(relative, importRoot: importRoot)
                return count + 1
            }

        guard let minecraftVersion = index.dependencies["minecraft"]?.trimmed,
              !minecraftVersion.isEmpty else {
            throw ModrinthPackInspectionError.missingMinecraftVersion
        }

        return ModrinthPackPlan(
            name: index.name,
            versionID: index.versionId,
            minecraftVersion: minecraftVersion,
            loaderSummary: loaderSummary(from: index.dependencies),
            fileCount: index.files.count,
            overrideEntryCount: overrideEntryCount
        )
    }

    func loadIndex(_ packURL: URL, importRoot: URL? = nil) throws -> ModrinthPackIndex {
        let indexData = try unzipData(packURL: packURL, entry: "modrinth.index.json")
        guard !indexData.isEmpty else {
            throw ModrinthPackInspectionError.missingIndex
        }

        let index = try JSONDecoder().decode(ModrinthPackIndex.self, from: indexData)
        try validate(index, importRoot: importRoot)
        return index
    }

    func validate(_ index: ModrinthPackIndex, importRoot: URL?) throws {
        guard index.formatVersion == 1 else {
            throw ModrinthPackInspectionError.unsupportedFormat(index.formatVersion)
        }
        guard index.game.lowercased() == "minecraft" else {
            throw ModrinthPackInspectionError.unsupportedGame(index.game)
        }
        guard index.dependencies["minecraft"]?.trimmed.isEmpty == false else {
            throw ModrinthPackInspectionError.missingMinecraftVersion
        }
        for file in index.files {
            try validateRelativePath(file.path, importRoot: importRoot)
        }
    }

    private func loaderSummary(from dependencies: [String: String]) -> String {
        let knownLoaders: [(key: String, title: String)] = [
            ("fabric-loader", "Fabric"),
            ("quilt-loader", "Quilt"),
            ("forge", "Forge"),
            ("neoforge", "NeoForge")
        ]
        for loader in knownLoaders {
            if let version = dependencies[loader.key]?.trimmed, !version.isEmpty {
                return "\(loader.title) \(version)"
            }
        }

        let extraDependencies = dependencies
            .filter { $0.key != "minecraft" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
        return extraDependencies.isEmpty ? "原版" : extraDependencies.joined(separator: " / ")
    }

    func validateRelativePath(_ path: String, importRoot: URL?) throws {
        let trimmedPath = path.trimmed
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/"),
              !trimmedPath.contains("\\") else {
            throw ModrinthPackInspectionError.unsafePath(path)
        }

        let components = trimmedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains(".") else {
            throw ModrinthPackInspectionError.unsafePath(path)
        }

        if let importRoot {
            let root = importRoot.standardizedFileURL
            let destination = root.appendingPathComponent(trimmedPath).standardizedFileURL
            guard destination.path.hasPrefix(root.path + "/") else {
                throw ModrinthPackInspectionError.unsafePath(path)
            }
        }
    }

    private func unzipData(packURL: URL, entry: String) throws -> Data {
        let output = try runUnzip(arguments: ["-p", packURL.path, entry])
        guard !output.isEmpty else {
            throw ModrinthPackInspectionError.missingIndex
        }
        return output
    }

    private func unzipEntries(packURL: URL) throws -> [String] {
        let output = try runUnzip(arguments: ["-Z1", packURL.path])
        return String(data: output, encoding: .utf8)?
            .split(separator: "\n")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty } ?? []
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
            throw ModrinthPackInspectionError.unzipFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmed
            throw ModrinthPackInspectionError.unzipFailed(message?.isEmpty == false ? message! : "unzip exited \(process.terminationStatus)")
        }
        return data
    }
}
