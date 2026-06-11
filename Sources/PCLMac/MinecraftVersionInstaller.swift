import Foundation

enum MinecraftVersionInstallError: LocalizedError, Sendable {
    case invalidVersionPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidVersionPayload(let version):
            "版本 \(version) 的 JSON 无效"
        }
    }
}

struct MinecraftVersionManifest: Decodable, Sendable {
    let latest: LatestVersions
    let versions: [MinecraftRemoteVersion]

    struct LatestVersions: Decodable, Sendable {
        let release: String
        let snapshot: String
    }
}

struct MinecraftRemoteVersion: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let type: String
    let url: URL
    let time: String
    let releaseTime: String

    var displayType: String {
        switch type {
        case "release": "正式版"
        case "snapshot": "快照版"
        case "old_beta": "远古 Beta"
        case "old_alpha": "远古 Alpha"
        default: type
        }
    }
}

struct MinecraftVersionInstallResult: Sendable {
    let version: MinecraftRemoteVersion
    let jsonURL: URL
}

struct MinecraftVersionInstaller: Sendable {
    var manifestURL: URL
    var dataLoader: @Sendable (URL) async throws -> Data
    var downloadSource: MinecraftDownloadSource

    init(
        downloadSource: MinecraftDownloadSource = .official,
        manifestURL: URL? = nil,
        dataLoader: @escaping @Sendable (URL) async throws -> Data = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    ) {
        self.downloadSource = downloadSource
        self.manifestURL = manifestURL ?? downloadSource.versionManifestURL
        self.dataLoader = dataLoader
    }

    func fetchManifest() async throws -> MinecraftVersionManifest {
        let data = try await downloadSource.loadData(from: manifestURL, loader: dataLoader)
        return try JSONDecoder().decode(MinecraftVersionManifest.self, from: data)
    }

    func install(_ version: MinecraftRemoteVersion, minecraftDirectory: URL) async throws -> MinecraftVersionInstallResult {
        let data = try await downloadSource.loadData(from: version.url, loader: dataLoader)
        guard let parsed = try? JSONDecoder().decode(MinecraftVersionFile.self, from: data),
              parsed.id == version.id else {
            throw MinecraftVersionInstallError.invalidVersionPayload(version.id)
        }

        let versionDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(version.id, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)

        let jsonURL = versionDirectory.appendingPathComponent("\(version.id).json")
        try data.write(to: jsonURL, options: [.atomic])
        return MinecraftVersionInstallResult(version: version, jsonURL: jsonURL)
    }
}
