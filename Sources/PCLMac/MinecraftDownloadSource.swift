import Foundation

enum MinecraftDownloadSource: String, CaseIterable, Identifiable, Sendable {
    case official = "官方"
    case bmclapi = "BMCLAPI"
    case officialAndBMCLAPI = "官方 + BMCLAPI"

    static let defaultValue = MinecraftDownloadSource.officialAndBMCLAPI

    var id: String { rawValue }

    init(preference: String) {
        let normalized = preference.trimmed
        self = Self.allCases.first { $0.rawValue == normalized } ?? Self.defaultValue
    }

    var versionManifestURL: URL {
        switch self {
        case .official:
            URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
        case .bmclapi, .officialAndBMCLAPI:
            URL(string: "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json")!
        }
    }

    func candidates(for originalURL: URL) -> [URL] {
        switch self {
        case .official:
            return [originalURL]
        case .bmclapi:
            return [mirrorURL(for: originalURL) ?? originalURL]
        case .officialAndBMCLAPI:
            guard let mirror = mirrorURL(for: originalURL), mirror != originalURL else {
                return [originalURL]
            }
            return [mirror, originalURL]
        }
    }

    func primaryURL(for originalURL: URL) -> URL {
        candidates(for: originalURL).first ?? originalURL
    }

    func loadData(
        from originalURL: URL,
        loader: @escaping @Sendable (URL) async throws -> Data = MinecraftDownloadSource.defaultDataLoader
    ) async throws -> Data {
        var lastError: Error?
        for url in candidates(for: originalURL) {
            do {
                return try await loader(url)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.badURL)
    }

    private func mirrorURL(for originalURL: URL) -> URL? {
        guard let host = originalURL.host?.lowercased() else { return nil }
        let path = originalURL.path

        switch host {
        case "piston-meta.mojang.com", "launchermeta.mojang.com", "launcher.mojang.com":
            return bmclURL(path: path)
        case "piston-data.mojang.com":
            return bmclURL(path: path)
        case "libraries.minecraft.net", "maven.minecraftforge.net", "maven.neoforged.net":
            return bmclURL(path: "/maven\(path)")
        case "resources.download.minecraft.net":
            return bmclURL(path: "/assets\(path)")
        default:
            return nil
        }
    }

    private func bmclURL(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bmclapi2.bangbang93.com"
        components.path = path
        return components.url
    }

    static func defaultDataLoader(_ url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
