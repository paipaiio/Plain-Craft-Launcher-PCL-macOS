import CryptoKit
import Foundation

enum AuthlibInjectorError: LocalizedError, Sendable {
    case missingDownloadURL
    case checksumMismatch(URL)
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .missingDownloadURL:
            "Authlib-Injector 缺少下载地址"
        case .checksumMismatch(let url):
            "Authlib-Injector 文件校验失败：\(url.path)"
        case .invalidMetadata:
            "Authlib-Injector 下载信息无效"
        }
    }
}

struct AuthlibInjectorManager: Sendable {
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

    func prepare(authserverURL: URL, appSupportDirectory: URL) async throws -> AuthlibInjectorConfiguration {
        let serverURL = yggdrasilRootURL(from: authserverURL)
        let toolsDirectory = appSupportDirectory.appendingPathComponent("tools", isDirectory: true)
        let jarURL = toolsDirectory.appendingPathComponent("authlib-injector.jar")

        let metadata = try await fetchLatestMetadata()
        guard let downloadURL = metadata.downloadURL else { throw AuthlibInjectorError.missingDownloadURL }

        if try !isSatisfied(jarURL: jarURL, sha256: metadata.sha256) {
            try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
            let data = try await dataLoader(downloadURL)
            try data.write(to: jarURL, options: [.atomic])
            if try sha256Hex(for: jarURL) != metadata.sha256.lowercased() {
                try? FileManager.default.removeItem(at: jarURL)
                throw AuthlibInjectorError.checksumMismatch(jarURL)
            }
        }

        let prefetched = try await dataLoader(serverURL)
        return AuthlibInjectorConfiguration(
            jarURL: jarURL,
            serverURL: serverURL,
            prefetchedMetadata: String(data: prefetched, encoding: .utf8) ?? "{}"
        )
    }

    func yggdrasilRootURL(from authserverURL: URL) -> URL {
        var absolute = authserverURL.absoluteString
        if absolute.hasSuffix("/") {
            absolute.removeLast()
        }
        if absolute.hasSuffix("/authserver") {
            absolute.removeLast("/authserver".count)
        }
        return URL(string: absolute) ?? authserverURL
    }

    private func fetchLatestMetadata() async throws -> AuthlibInjectorMetadata {
        let urls = [
            URL(string: "https://authlib-injector.yushi.moe/artifact/latest.json")!,
            URL(string: "https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/latest.json")!
        ]
        var lastError: Error?
        for url in urls {
            do {
                let data = try await dataLoader(url)
                return try JSONDecoder().decode(AuthlibInjectorMetadata.self, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? AuthlibInjectorError.invalidMetadata
    }

    private func isSatisfied(jarURL: URL, sha256: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: jarURL.path) else { return false }
        return try sha256Hex(for: jarURL) == sha256.lowercased()
    }

    private func sha256Hex(for file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct AuthlibInjectorMetadata: Decodable, Sendable {
    let downloadURL: URL?
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case checksums
    }

    enum ChecksumKeys: String, CodingKey {
        case sha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
        let checksums = try container.nestedContainer(keyedBy: ChecksumKeys.self, forKey: .checksums)
        sha256 = try checksums.decode(String.self, forKey: .sha256)
    }
}
