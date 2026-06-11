import Foundation

enum FabricVersionInstallError: LocalizedError, Sendable {
    case noCompatibleLoader(String)
    case invalidProfile(String)

    var errorDescription: String? {
        switch self {
        case .noCompatibleLoader(let version):
            "没有找到适用于 \(version) 的 Fabric Loader"
        case .invalidProfile(let version):
            "Fabric \(version) 的 Profile JSON 无效"
        }
    }
}

struct FabricInstallResult: Sendable {
    let baseVersion: MinecraftVersionInstallResult
    let loaderVersion: String
    let profileID: String
    let jsonURL: URL
}

struct FabricVersionInstaller: Sendable {
    var metaBaseURL: URL
    var downloadSource: MinecraftDownloadSource
    var dataLoader: @Sendable (URL) async throws -> Data

    init(
        metaBaseURL: URL = URL(string: "https://meta.fabricmc.net/v2")!,
        downloadSource: MinecraftDownloadSource = .official,
        dataLoader: @escaping @Sendable (URL) async throws -> Data = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.metaBaseURL = metaBaseURL
        self.downloadSource = downloadSource
        self.dataLoader = dataLoader
    }

    func install(
        _ version: MinecraftRemoteVersion,
        loaderVersion requestedLoaderVersion: String? = nil,
        minecraftDirectory: URL
    ) async throws -> FabricInstallResult {
        let baseVersion = try await MinecraftVersionInstaller(downloadSource: downloadSource, dataLoader: dataLoader)
            .install(version, minecraftDirectory: minecraftDirectory)
        let loaderVersion: String
        if let requested = requestedLoaderVersion?.trimmed.nonEmpty {
            loaderVersion = requested
        } else {
            loaderVersion = try await latestLoader(gameVersion: version.id).loader.version
        }
        let profileData = try await dataLoader(profileURL(gameVersion: version.id, loaderVersion: loaderVersion))
        guard let profile = try? JSONDecoder().decode(MinecraftVersionFile.self, from: profileData),
              !profile.id.isEmpty,
              profile.inheritsFrom == version.id else {
            throw FabricVersionInstallError.invalidProfile(version.id)
        }

        let profileDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(profile.id, isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let jsonURL = profileDirectory.appendingPathComponent("\(profile.id).json")
        try profileData.write(to: jsonURL, options: [.atomic])
        return FabricInstallResult(
            baseVersion: baseVersion,
            loaderVersion: loaderVersion,
            profileID: profile.id,
            jsonURL: jsonURL
        )
    }

    func latestLoader(gameVersion: String) async throws -> FabricLoaderEntry {
        let loaders = try JSONDecoder().decode([FabricLoaderEntry].self, from: try await dataLoader(loaderListURL(gameVersion: gameVersion)))
        guard let loader = loaders.first(where: { $0.loader.stable }) ?? loaders.first else {
            throw FabricVersionInstallError.noCompatibleLoader(gameVersion)
        }
        return loader
    }

    private func loaderListURL(gameVersion: String) -> URL {
        metaBaseURL
            .appendingPathComponent("versions")
            .appendingPathComponent("loader")
            .appendingPathComponent(gameVersion)
    }

    private func profileURL(gameVersion: String, loaderVersion: String) -> URL {
        loaderListURL(gameVersion: gameVersion)
            .appendingPathComponent(loaderVersion)
            .appendingPathComponent("profile")
            .appendingPathComponent("json")
    }
}

struct FabricLoaderEntry: Decodable, Sendable {
    let loader: FabricLoader
}

struct FabricLoader: Decodable, Sendable {
    let version: String
    let stable: Bool
}
