import Foundation

enum QuiltVersionInstallError: LocalizedError, Sendable {
    case noCompatibleLoader(String)
    case invalidProfile(String)

    var errorDescription: String? {
        switch self {
        case .noCompatibleLoader(let version):
            "没有找到适用于 \(version) 的 Quilt Loader"
        case .invalidProfile(let version):
            "Quilt \(version) 的 Profile JSON 无效"
        }
    }
}

struct QuiltInstallResult: Sendable {
    let baseVersion: MinecraftVersionInstallResult
    let loaderVersion: String
    let profileID: String
    let jsonURL: URL
}

struct QuiltVersionInstaller: Sendable {
    var metaBaseURL: URL
    var downloadSource: MinecraftDownloadSource
    var dataLoader: @Sendable (URL) async throws -> Data

    init(
        metaBaseURL: URL = URL(string: "https://meta.quiltmc.org/v3")!,
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
    ) async throws -> QuiltInstallResult {
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
            throw QuiltVersionInstallError.invalidProfile(version.id)
        }

        let profileDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(profile.id, isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)

        let jsonURL = profileDirectory.appendingPathComponent("\(profile.id).json")
        try profileData.write(to: jsonURL, options: [.atomic])
        return QuiltInstallResult(
            baseVersion: baseVersion,
            loaderVersion: loaderVersion,
            profileID: profile.id,
            jsonURL: jsonURL
        )
    }

    func latestLoader(gameVersion: String) async throws -> QuiltLoaderEntry {
        let loaders = try JSONDecoder().decode([QuiltLoaderEntry].self, from: try await dataLoader(loaderListURL(gameVersion: gameVersion)))
        guard let loader = loaders
            .sorted(by: { compareVersion($0.loader.version, $1.loader.version) })
            .first(where: { !$0.loader.version.localizedCaseInsensitiveContains("beta") })
            ?? loaders.sorted(by: { compareVersion($0.loader.version, $1.loader.version) }).first else {
            throw QuiltVersionInstallError.noCompatibleLoader(gameVersion)
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

    private func compareVersion(_ lhs: String, _ rhs: String) -> Bool {
        let left = ParsedVersion(lhs)
        let right = ParsedVersion(rhs)
        if left.numbers != right.numbers {
            return left.numbers.lexicographicallyPrecedes(right.numbers) == false
        }
        return left.isPrerelease == false && right.isPrerelease
    }
}

struct QuiltLoaderEntry: Decodable, Sendable {
    let loader: QuiltLoader
}

struct QuiltLoader: Decodable, Sendable {
    let version: String
}

private struct ParsedVersion: Sendable {
    let numbers: [Int]
    let isPrerelease: Bool

    init(_ value: String) {
        let main = value.split(separator: "-", maxSplits: 1).first.map(String.init) ?? value
        numbers = main.split(separator: ".").map { Int($0) ?? 0 }
        isPrerelease = value.contains("-")
    }
}
