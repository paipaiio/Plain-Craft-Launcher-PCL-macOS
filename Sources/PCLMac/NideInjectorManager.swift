import CryptoKit
import Foundation

enum NideInjectorError: LocalizedError, Sendable {
    case missingServerID
    case invalidMetadata
    case checksumMismatch(URL)

    var errorDescription: String? {
        switch self {
        case .missingServerID:
            "请填写统一通行证服务器 ID"
        case .invalidMetadata:
            "统一通行证下载信息无效"
        case .checksumMismatch(let url):
            "统一通行证 nide8auth.jar 校验失败：\(url.path)"
        }
    }
}

struct NideInjectorManager: Sendable {
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

    func prepare(serverID: String, appSupportDirectory: URL) async throws -> NideInjectorConfiguration {
        let normalizedServerID = normalized(serverID: serverID)
        guard !normalizedServerID.isEmpty else { throw NideInjectorError.missingServerID }

        let toolsDirectory = appSupportDirectory.appendingPathComponent("tools", isDirectory: true)
        let jarURL = toolsDirectory.appendingPathComponent("nide8auth.jar")
        let metadataURL = URL(string: "https://auth.mc-user.com:233/\(normalizedServerID)")!

        do {
            let metadata = try JSONDecoder().decode(NideInjectorMetadata.self, from: try await dataLoader(metadataURL))
            if try !isSatisfied(jarURL: jarURL, hash: metadata.jarHash) {
                try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
                let jarData = try await dataLoader(URL(string: "https://login.mc-user.com:233/index/jar")!)
                try jarData.write(to: jarURL, options: [.atomic])
                if try fileHash(jarURL, matching: metadata.jarHash) != metadata.jarHash.lowercased() {
                    try? FileManager.default.removeItem(at: jarURL)
                    throw NideInjectorError.checksumMismatch(jarURL)
                }
            }
        } catch {
            if FileManager.default.fileExists(atPath: jarURL.path) {
                return NideInjectorConfiguration(jarURL: jarURL, serverID: normalizedServerID)
            }
            throw error
        }

        return NideInjectorConfiguration(jarURL: jarURL, serverID: normalizedServerID)
    }

    func authserverURL(serverID: String) throws -> URL {
        let normalizedServerID = normalized(serverID: serverID)
        guard !normalizedServerID.isEmpty else { throw NideInjectorError.missingServerID }
        return URL(string: "https://auth.mc-user.com:233/\(normalizedServerID)/authserver")!
    }

    func serverID(from authserverURL: URL) -> String? {
        let components = authserverURL.pathComponents.filter { $0 != "/" }
        guard let authserverIndex = components.firstIndex(of: "authserver"),
              authserverIndex > 0 else {
            return nil
        }
        return components[authserverIndex - 1]
    }

    private func normalized(serverID: String) -> String {
        serverID.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func isSatisfied(jarURL: URL, hash: String) throws -> Bool {
        guard FileManager.default.fileExists(atPath: jarURL.path) else { return false }
        return try fileHash(jarURL, matching: hash) == hash.lowercased()
    }

    private func fileHash(_ file: URL, matching expectedHash: String) throws -> String {
        let data = try Data(contentsOf: file)
        let expected = expectedHash.lowercased()
        let digest: any Sequence<UInt8>
        if expected.count < 35 {
            digest = Insecure.MD5.hash(data: data)
        } else if expected.count == 64 {
            digest = SHA256.hash(data: data)
        } else {
            digest = Insecure.SHA1.hash(data: data)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct NideInjectorMetadata: Decodable, Sendable {
    let jarHash: String
}
