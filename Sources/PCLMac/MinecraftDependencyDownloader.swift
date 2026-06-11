import CryptoKit
import Foundation

enum MinecraftDownloadError: LocalizedError, Sendable {
    case missingURL(String)
    case invalidURL(String)
    case checksumMismatch(URL)
    case assetIndexUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingURL(let name):
            "缺少下载地址：\(name)"
        case .invalidURL(let url):
            "下载地址无效：\(url)"
        case .checksumMismatch(let url):
            "文件校验失败：\(url.path)"
        case .assetIndexUnavailable(let id):
            "无法读取资源索引：\(id)"
        }
    }
}

struct MinecraftDownloadProgress: Sendable {
    enum Action: Sendable, Equatable {
        case skipped
        case downloaded
    }

    let finished: Int
    let total: Int
    let currentName: String
    let downloaded: Int
    let skipped: Int
    let action: Action

    var fraction: Double {
        guard total > 0 else { return 1 }
        return Double(finished) / Double(total)
    }
}

struct MinecraftDependencySummary: Sendable {
    let downloaded: Int
    let skipped: Int
    let total: Int
}

struct MinecraftDownloadItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let fallbackURLs: [URL]
    let destination: URL
    let sha1: String?
    let size: Int?
}

struct MinecraftDependencyDownloader: Sendable {
    var session: URLSession = .shared
    var maximumConcurrentDownloads = 16
    var validateExistingFileHashes = false
    var downloadSource: MinecraftDownloadSource = .official
    var itemDownloader: @Sendable (MinecraftDownloadItem, URLSession) async throws -> Void = MinecraftDependencyDownloader.downloadItem

    func prepareDependencies(
        request: MinecraftLaunchRequest,
        progress: (@Sendable (MinecraftDownloadProgress) async -> Void)? = nil
    ) async throws -> MinecraftDependencySummary {
        let chain = try MinecraftVersionRepository().loadVersionChain(instance: request.instance, minecraftDirectory: request.minecraftDirectory)
        let initialItems = try dependencyItems(from: chain, request: request)
        var downloaded = 0
        var skipped = 0
        var completed = 0

        try await download(items: initialItems, completed: &completed, downloaded: &downloaded, skipped: &skipped, total: initialItems.count, progress: progress)

        let assetItems = try assetItems(from: chain, request: request)
        let total = initialItems.count + assetItems.count
        try await download(items: assetItems, completed: &completed, downloaded: &downloaded, skipped: &skipped, total: total, progress: progress)

        return MinecraftDependencySummary(downloaded: downloaded, skipped: skipped, total: total)
    }

    func dependencyItems(from chain: [MinecraftVersionFile], request: MinecraftLaunchRequest) throws -> [MinecraftDownloadItem] {
        var items: [MinecraftDownloadItem] = []
        let libraries = MinecraftLibraryResolver().collectLibraries(from: chain, minecraftDirectory: request.minecraftDirectory)

        for library in libraries {
            guard let artifact = library.artifact else { continue }
            guard let urlString = artifact.url, !urlString.isEmpty else {
                throw MinecraftDownloadError.missingURL(library.name)
            }
            items.append(try item(
                name: library.name,
                urlString: urlString,
                destination: library.localPath,
                sha1: artifact.sha1,
                size: artifact.size
            ))
        }

        items.append(contentsOf: try clientDownloadItems(from: chain, request: request))

        if let assetIndex = chain.reversed().compactMap(\.assetIndex).first,
           let id = assetIndex.id,
           let urlString = assetIndex.url {
            let destination = request.minecraftDirectory
                .appendingPathComponent("assets/indexes", isDirectory: true)
                .appendingPathComponent("\(id).json")
            items.append(try item(name: "assets-index-\(id)", urlString: urlString, destination: destination, sha1: assetIndex.sha1, size: assetIndex.size))
        }

        return items.uniquedByDestination()
    }

    func assetItems(from chain: [MinecraftVersionFile], request: MinecraftLaunchRequest) throws -> [MinecraftDownloadItem] {
        guard let assetIndex = chain.reversed().compactMap(\.assetIndex).first,
              let id = assetIndex.id else {
            return []
        }
        let indexURL = request.minecraftDirectory
            .appendingPathComponent("assets/indexes", isDirectory: true)
            .appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(MinecraftAssetObjectIndex.self, from: data) else {
            throw MinecraftDownloadError.assetIndexUnavailable(id)
        }

        return index.objects.map { name, object in
            let prefix = String(object.hash.prefix(2))
            let destination = request.minecraftDirectory
                .appendingPathComponent("assets/objects", isDirectory: true)
                .appendingPathComponent(prefix, isDirectory: true)
                .appendingPathComponent(object.hash)
            let originalURL = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(object.hash)")!
            return item(name: name, originalURL: originalURL, destination: destination, sha1: object.hash, size: object.size)
        }
        .uniquedByDestination()
    }

    private func clientDownloadItems(from chain: [MinecraftVersionFile], request: MinecraftLaunchRequest) throws -> [MinecraftDownloadItem] {
        try minecraftClientJarOwners(from: chain, fallback: request.instance.name).compactMap { jarOwner in
            guard let version = chain.first(where: { $0.id == jarOwner }) ?? chain.reversed().first(where: { $0.id == jarOwner }) else {
                return nil
            }
            guard let artifact = version.downloads?.client else { return nil }
            guard let urlString = artifact.url, !urlString.isEmpty else {
                throw MinecraftDownloadError.missingURL("\(jarOwner).jar")
            }
            let destination = request.minecraftDirectory
                .appendingPathComponent("versions", isDirectory: true)
                .appendingPathComponent(jarOwner, isDirectory: true)
                .appendingPathComponent("\(jarOwner).jar")
            return try item(name: "\(jarOwner).jar", urlString: urlString, destination: destination, sha1: artifact.sha1, size: artifact.size)
        }
    }

    private func item(name: String, urlString: String, destination: URL, sha1: String?, size: Int?) throws -> MinecraftDownloadItem {
        guard let url = URL(string: urlString) else { throw MinecraftDownloadError.invalidURL(urlString) }
        return item(name: name, originalURL: url, destination: destination, sha1: sha1, size: size)
    }

    private func item(name: String, originalURL: URL, destination: URL, sha1: String?, size: Int?) -> MinecraftDownloadItem {
        let candidates = downloadSource.candidates(for: originalURL)
        return MinecraftDownloadItem(
            id: destination.path,
            name: name,
            url: candidates.first ?? originalURL,
            fallbackURLs: Array(candidates.dropFirst()),
            destination: destination,
            sha1: sha1,
            size: size
        )
    }

    private func download(
        items: [MinecraftDownloadItem],
        completed: inout Int,
        downloaded: inout Int,
        skipped: inout Int,
        total: Int,
        progress: (@Sendable (MinecraftDownloadProgress) async -> Void)?
    ) async throws {
        var pending: [MinecraftDownloadItem] = []
        let limit = max(1, min(maximumConcurrentDownloads, 64))

        try await withThrowingTaskGroup(of: (MinecraftDownloadItem, Bool).self) { group in
            var nextIndex = 0

            func enqueueNextCheck() {
                guard nextIndex < items.count else { return }
                let item = items[nextIndex]
                nextIndex += 1
                group.addTask {
                    try Task.checkCancellation()
                    return (item, try await isSatisfied(item))
                }
            }

            for _ in 0..<min(limit, items.count) {
                enqueueNextCheck()
            }

            while let (item, satisfied) = try await group.next() {
                if satisfied {
                    skipped += 1
                    completed += 1
                    await progress?(
                        MinecraftDownloadProgress(
                            finished: completed,
                            total: total,
                            currentName: item.name,
                            downloaded: downloaded,
                            skipped: skipped,
                            action: .skipped
                        )
                    )
                } else {
                    pending.append(item)
                }
                enqueueNextCheck()
            }
        }

        guard !pending.isEmpty else { return }

        var nextIndex = 0

        try await withThrowingTaskGroup(of: MinecraftDownloadItem.self) { group in
            func enqueueNext() {
                guard nextIndex < pending.count else { return }
                let item = pending[nextIndex]
                nextIndex += 1
                group.addTask {
                    try await download(item)
                    return item
                }
            }

            for _ in 0..<min(limit, pending.count) {
                enqueueNext()
            }

            while let item = try await group.next() {
                downloaded += 1
                completed += 1
                await progress?(
                    MinecraftDownloadProgress(
                        finished: completed,
                        total: total,
                        currentName: item.name,
                        downloaded: downloaded,
                        skipped: skipped,
                        action: .downloaded
                    )
                )
                enqueueNext()
            }
        }
    }

    func isSatisfied(_ item: MinecraftDownloadItem) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: item.destination.path) else { return false }
        if let size = item.size,
           let attributes = try? FileManager.default.attributesOfItem(atPath: item.destination.path),
           let actualSize = attributes[.size] as? NSNumber,
           actualSize.intValue != size {
            return false
        }
        if validateExistingFileHashes, let sha1 = item.sha1, !sha1.isEmpty {
            return try Self.sha1Hex(for: item.destination) == sha1.lowercased()
        }
        return true
    }

    private func download(_ item: MinecraftDownloadItem) async throws {
        try await itemDownloader(item, session)
    }

    private static func downloadItem(_ item: MinecraftDownloadItem, session: URLSession) async throws {
        try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempURL = try await downloadCandidate(for: item, session: session)
        if FileManager.default.fileExists(atPath: item.destination.path) {
            try FileManager.default.removeItem(at: item.destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: item.destination)
        if let sha1 = item.sha1, !sha1.isEmpty, try sha1Hex(for: item.destination) != sha1.lowercased() {
            try? FileManager.default.removeItem(at: item.destination)
            throw MinecraftDownloadError.checksumMismatch(item.destination)
        }
    }

    private static func downloadCandidate(for item: MinecraftDownloadItem, session: URLSession) async throws -> URL {
        var lastError: Error?
        for url in [item.url] + item.fallbackURLs {
            do {
                let (tempURL, _) = try await session.download(from: url)
                return tempURL
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MinecraftDownloadError.invalidURL(item.url.absoluteString)
    }

    private static func sha1Hex(for file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct MinecraftAssetObjectIndex: Decodable, Sendable {
    let objects: [String: MinecraftAssetObject]
}

private struct MinecraftAssetObject: Decodable, Sendable {
    let hash: String
    let size: Int
}

private extension Array where Element == MinecraftDownloadItem {
    func uniquedByDestination() -> [MinecraftDownloadItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.destination.path).inserted }
    }
}
