import CryptoKit
import Foundation

struct MojangJavaRuntimeInstallProgress: Sendable {
    let finished: Int
    let total: Int
    let currentName: String
    let downloaded: Int
    let skipped: Int

    var fraction: Double {
        guard total > 0 else { return 1 }
        return Double(finished) / Double(total)
    }
}

struct MojangJavaRuntimeInstallResult: Sendable {
    let component: String
    let versionName: String
    let runtimeDirectory: URL
    let javaExecutable: URL
    let installedFiles: Int
    let skippedFiles: Int
}

enum MojangJavaRuntimeInstallerError: LocalizedError {
    case missingPlatform(String)
    case missingRuntime(platform: String, component: String)
    case missingManifestDownload(component: String)
    case missingRawDownload(path: String)
    case unsafeManifestPath(String)
    case unsafeLinkTarget(path: String, target: String)
    case checksumMismatch(path: String)
    case missingJavaExecutable(URL)

    var errorDescription: String? {
        switch self {
        case .missingPlatform(let platform):
            "Mojang Java Runtime 清单中没有 \(platform) 平台"
        case .missingRuntime(let platform, let component):
            "Mojang Java Runtime 清单中没有 \(platform) / \(component)"
        case .missingManifestDownload(let component):
            "\(component) 缺少 runtime manifest 下载地址"
        case .missingRawDownload(let path):
            "\(path) 缺少原始文件下载地址"
        case .unsafeManifestPath(let path):
            "Runtime 清单包含不安全路径：\(path)"
        case .unsafeLinkTarget(let path, let target):
            "Runtime 清单包含不安全链接：\(path) -> \(target)"
        case .checksumMismatch(let path):
            "\(path) 校验失败"
        case .missingJavaExecutable(let url):
            "安装完成但没有找到 Java 可执行文件：\(url.path)"
        }
    }
}

struct MojangJavaRuntimeInstaller {
    typealias DataLoader = @Sendable (URL) async throws -> Data
    typealias ProgressHandler = @Sendable (MojangJavaRuntimeInstallProgress) async -> Void

    static let runtimeIndexURL = URL(
        string: "https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json"
    )!

    let downloadSource: MinecraftDownloadSource
    let platformID: String
    let dataLoader: DataLoader
    private let fileManager: FileManager

    init(
        downloadSource: MinecraftDownloadSource = .defaultValue,
        platformID: String = MojangJavaRuntimeInstaller.currentPlatformID,
        fileManager: FileManager = .default,
        dataLoader: @escaping DataLoader = MinecraftDownloadSource.defaultDataLoader
    ) {
        self.downloadSource = downloadSource
        self.platformID = platformID
        self.fileManager = fileManager
        self.dataLoader = dataLoader
    }

    func install(
        component: String,
        appSupportDirectory: URL,
        progress: ProgressHandler? = nil
    ) async throws -> MojangJavaRuntimeInstallResult {
        let indexData = try await downloadSource.loadData(from: Self.runtimeIndexURL, loader: dataLoader)
        let index = try JSONDecoder().decode([String: [String: [MojangJavaRuntimeMetadata]]].self, from: indexData)
        guard let platformRuntimes = index[platformID] else {
            throw MojangJavaRuntimeInstallerError.missingPlatform(platformID)
        }
        guard let runtimes = platformRuntimes[component], !runtimes.isEmpty else {
            throw MojangJavaRuntimeInstallerError.missingRuntime(platform: platformID, component: component)
        }
        let runtime = newestRuntime(from: runtimes)
        guard let manifestURL = runtime.manifest.url else {
            throw MojangJavaRuntimeInstallerError.missingManifestDownload(component: component)
        }

        let manifestData = try await downloadSource.loadData(from: manifestURL, loader: dataLoader)
        let manifest = try JSONDecoder().decode(MojangJavaRuntimeFileManifest.self, from: manifestData)
        let versionName = sanitizePathComponent(runtime.version.name)
        let runtimeDirectory = appSupportDirectory
            .appendingPathComponent("JavaRuntimes", isDirectory: true)
            .appendingPathComponent(platformID, isDirectory: true)
            .appendingPathComponent(component, isDirectory: true)
            .appendingPathComponent(versionName, isDirectory: true)

        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)

        let directories = manifest.files
            .filter { $0.value.type == .directory }
            .map(\.key)
            .sorted()
        for path in directories {
            let destination = try destinationURL(for: path, in: runtimeDirectory)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        let fileEntries = manifest.files
            .filter { $0.value.type == .file }
            .sorted { $0.key < $1.key }
        let total = fileEntries.count
        var finished = 0
        var downloaded = 0
        var skipped = 0

        for (path, entry) in fileEntries {
            try Task.checkCancellation()
            let destination = try destinationURL(for: path, in: runtimeDirectory)
            guard let artifact = entry.downloads?.raw else {
                throw MojangJavaRuntimeInstallerError.missingRawDownload(path: path)
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if try existingFileMatches(destination, artifact: artifact) {
                skipped += 1
            } else {
                guard let fileURL = artifact.url else {
                    throw MojangJavaRuntimeInstallerError.missingRawDownload(path: path)
                }
                let data = try await downloadSource.loadData(from: fileURL, loader: dataLoader)
                guard Self.sha1Hex(data) == artifact.sha1.lowercased() else {
                    throw MojangJavaRuntimeInstallerError.checksumMismatch(path: path)
                }
                try removeItemIfPresent(destination)
                try data.write(to: destination, options: [.atomic])
                try fileManager.setAttributes(
                    [.posixPermissions: entry.executable == true ? 0o755 : 0o644],
                    ofItemAtPath: destination.path
                )
                downloaded += 1
            }

            finished += 1
            await progress?(MojangJavaRuntimeInstallProgress(
                finished: finished,
                total: total,
                currentName: path,
                downloaded: downloaded,
                skipped: skipped
            ))
        }

        let linkEntries = manifest.files
            .filter { $0.value.type == .link }
            .sorted { $0.key < $1.key }
        for (path, entry) in linkEntries {
            try Task.checkCancellation()
            guard let target = entry.target, !target.isEmpty, !target.hasPrefix("/") else {
                throw MojangJavaRuntimeInstallerError.unsafeLinkTarget(path: path, target: entry.target ?? "")
            }
            let destination = try destinationURL(for: path, in: runtimeDirectory)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try removeItemIfPresent(destination)
            try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
        }

        let javaExecutable = runtimeDirectory.appendingPathComponent("jre.bundle/Contents/Home/bin/java")
        guard fileManager.isExecutableFile(atPath: javaExecutable.path) else {
            throw MojangJavaRuntimeInstallerError.missingJavaExecutable(javaExecutable)
        }

        return MojangJavaRuntimeInstallResult(
            component: component,
            versionName: runtime.version.name,
            runtimeDirectory: runtimeDirectory,
            javaExecutable: javaExecutable,
            installedFiles: downloaded,
            skippedFiles: skipped
        )
    }

    static func component(forMajorVersion majorVersion: Int) -> String {
        if majorVersion >= 25 { return "java-runtime-epsilon" }
        if majorVersion >= 21 { return "java-runtime-delta" }
        if majorVersion >= 17 { return "java-runtime-gamma" }
        if majorVersion >= 16 { return "java-runtime-alpha" }
        return "jre-legacy"
    }

    static var currentPlatformID: String {
        #if arch(arm64)
        "mac-os-arm64"
        #else
        "mac-os"
        #endif
    }

    static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func newestRuntime(from runtimes: [MojangJavaRuntimeMetadata]) -> MojangJavaRuntimeMetadata {
        runtimes.max { lhs, rhs in
            lhs.version.released < rhs.version.released
        } ?? runtimes[0]
    }

    private func existingFileMatches(_ url: URL, artifact: MojangJavaRuntimeFileArtifact) throws -> Bool {
        guard fileManager.isReadableFile(atPath: url.path),
              let data = try? Data(contentsOf: url),
              data.count == artifact.size else {
            return false
        }
        return Self.sha1Hex(data) == artifact.sha1.lowercased()
    }

    private func destinationURL(for manifestPath: String, in root: URL) throws -> URL {
        guard !manifestPath.isEmpty, !manifestPath.hasPrefix("/") else {
            throw MojangJavaRuntimeInstallerError.unsafeManifestPath(manifestPath)
        }
        let components = manifestPath.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MojangJavaRuntimeInstallerError.unsafeManifestPath(manifestPath)
        }
        let destination = components.reduce(root) { partial, component in
            partial.appendingPathComponent(component)
        }
        let rootPath = root.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard destinationPath == rootPath || destinationPath.hasPrefix(rootPath + "/") else {
            throw MojangJavaRuntimeInstallerError.unsafeManifestPath(manifestPath)
        }
        return destination
    }

    private func removeItemIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            try fileManager.removeItem(at: url)
        }
    }

    private func sanitizePathComponent(_ component: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = component.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let value = String(sanitized).trimmed
        return value.isEmpty ? "runtime" : value
    }
}

private struct MojangJavaRuntimeMetadata: Decodable {
    let manifest: MojangJavaRuntimeManifestDownload
    let version: MojangJavaRuntimeVersion
}

private struct MojangJavaRuntimeManifestDownload: Decodable {
    let url: URL?
}

private struct MojangJavaRuntimeVersion: Decodable {
    let name: String
    let released: String
}

private struct MojangJavaRuntimeFileManifest: Decodable {
    let files: [String: MojangJavaRuntimeFileEntry]
}

private struct MojangJavaRuntimeFileEntry: Decodable {
    let type: MojangJavaRuntimeFileType
    let executable: Bool?
    let downloads: MojangJavaRuntimeFileDownloads?
    let target: String?
}

private enum MojangJavaRuntimeFileType: String, Decodable {
    case directory
    case file
    case link
}

private struct MojangJavaRuntimeFileDownloads: Decodable {
    let raw: MojangJavaRuntimeFileArtifact?
}

private struct MojangJavaRuntimeFileArtifact: Decodable {
    let sha1: String
    let size: Int
    let url: URL?
}
