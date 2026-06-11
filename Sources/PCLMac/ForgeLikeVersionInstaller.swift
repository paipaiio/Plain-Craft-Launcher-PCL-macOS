import Foundation

enum ForgeLikeProvider: String, Sendable {
    case forge = "Forge"
    case neoForge = "NeoForge"

    var metadataURL: URL {
        switch self {
        case .forge:
            URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml")!
        case .neoForge:
            URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml")!
        }
    }

    func installerURL(version: String) -> URL {
        switch self {
        case .forge:
            URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/\(version)/forge-\(version)-installer.jar")!
        case .neoForge:
            URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/\(version)/neoforge-\(version)-installer.jar")!
        }
    }

    func installerFileName(version: String) -> String {
        switch self {
        case .forge: "forge-\(version)-installer.jar"
        case .neoForge: "neoforge-\(version)-installer.jar"
        }
    }

    var installerArguments: [String] {
        switch self {
        case .forge: ["--installClient"]
        case .neoForge: ["--install-client"]
        }
    }

    func matches(gameVersion: String, loaderVersion: String) -> Bool {
        switch self {
        case .forge:
            loaderVersion.hasPrefix("\(gameVersion)-")
        case .neoForge:
            loaderVersion.hasPrefix(neoForgeVersionPrefix(for: gameVersion))
        }
    }

    func displayLoaderVersion(from version: String, gameVersion: String) -> String {
        switch self {
        case .forge:
            version.replacingOccurrences(of: "\(gameVersion)-", with: "")
        case .neoForge:
            version
        }
    }

    func fallbackProfileID(gameVersion: String, loaderVersion: String) -> String {
        switch self {
        case .forge:
            "\(gameVersion)-forge-\(displayLoaderVersion(from: loaderVersion, gameVersion: gameVersion))"
        case .neoForge:
            "neoforge-\(loaderVersion)"
        }
    }

    private func neoForgeVersionPrefix(for gameVersion: String) -> String {
        let parts = gameVersion.split(separator: ".").map(String.init)
        guard parts.count >= 2, parts[0] == "1" else {
            return "\(gameVersion)."
        }
        let minor = parts[1]
        let patch = parts.count >= 3 ? parts[2] : "0"
        return "\(minor).\(patch)."
    }
}

enum ForgeLikeInstallError: LocalizedError, Sendable {
    case noCompatibleVersion(String, ForgeLikeProvider)
    case invalidMetadata(ForgeLikeProvider)
    case installerFailed(ForgeLikeProvider, Int32, URL)

    var errorDescription: String? {
        switch self {
        case .noCompatibleVersion(let gameVersion, let provider):
            "没有找到适用于 \(gameVersion) 的 \(provider.rawValue) 版本"
        case .invalidMetadata(let provider):
            "\(provider.rawValue) Maven 元数据无效"
        case .installerFailed(let provider, let status, let logURL):
            "\(provider.rawValue) 安装器返回 \(status)，日志：\(logURL.path)"
        }
    }
}

struct ForgeLikeInstallResult: Sendable {
    let baseVersion: MinecraftVersionInstallResult
    let provider: ForgeLikeProvider
    let loaderVersion: String
    let displayLoaderVersion: String
    let installerURL: URL
    let installerJarURL: URL
    let profileID: String
}

struct ForgeLikeInstallerRunRequest: Sendable {
    let provider: ForgeLikeProvider
    let javaExecutable: URL
    let installerJarURL: URL
    let minecraftDirectory: URL
    let arguments: [String]
}

struct ForgeLikeInstallerRunResult: Sendable {
    let terminationStatus: Int32
    let logURL: URL
}

struct ForgeLikeVersionInstaller: Sendable {
    typealias DataLoader = @Sendable (URL) async throws -> Data
    typealias ProcessRunner = @Sendable (ForgeLikeInstallerRunRequest) async throws -> ForgeLikeInstallerRunResult

    let provider: ForgeLikeProvider
    var downloadSource: MinecraftDownloadSource
    var dataLoader: DataLoader
    var processRunner: ProcessRunner

    init(
        provider: ForgeLikeProvider,
        downloadSource: MinecraftDownloadSource = .official,
        dataLoader: @escaping DataLoader = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        },
        processRunner: @escaping ProcessRunner = ForgeLikeVersionInstaller.runInstallerProcess
    ) {
        self.provider = provider
        self.downloadSource = downloadSource
        self.dataLoader = dataLoader
        self.processRunner = processRunner
    }

    func install(
        _ version: MinecraftRemoteVersion,
        minecraftDirectory: URL,
        javaExecutable: URL,
        appSupportDirectory: URL,
        loaderVersion requestedLoaderVersion: String? = nil
    ) async throws -> ForgeLikeInstallResult {
        let baseVersion = try await MinecraftVersionInstaller(downloadSource: downloadSource, dataLoader: dataLoader)
            .install(version, minecraftDirectory: minecraftDirectory)
        let selectedVersion = try await normalizedLoaderVersion(requestedLoaderVersion, gameVersion: version.id)
        let installerURL = provider.installerURL(version: selectedVersion)
        let installerJarURL = try await downloadInstaller(
            version: selectedVersion,
            installerURL: installerURL,
            appSupportDirectory: appSupportDirectory
        )
        let runResult = try await processRunner(
            ForgeLikeInstallerRunRequest(
                provider: provider,
                javaExecutable: javaExecutable,
                installerJarURL: installerJarURL,
                minecraftDirectory: minecraftDirectory,
                arguments: provider.installerArguments
            )
        )
        guard runResult.terminationStatus == 0 else {
            throw ForgeLikeInstallError.installerFailed(provider, runResult.terminationStatus, runResult.logURL)
        }
        let profileID = detectInstalledProfile(
            minecraftDirectory: minecraftDirectory,
            gameVersion: version.id,
            loaderVersion: selectedVersion
        ) ?? provider.fallbackProfileID(gameVersion: version.id, loaderVersion: selectedVersion)
        return ForgeLikeInstallResult(
            baseVersion: baseVersion,
            provider: provider,
            loaderVersion: selectedVersion,
            displayLoaderVersion: provider.displayLoaderVersion(from: selectedVersion, gameVersion: version.id),
            installerURL: installerURL,
            installerJarURL: installerJarURL,
            profileID: profileID
        )
    }

    func latestLoaderVersion(gameVersion: String) async throws -> String {
        let versions = try parseVersions(from: try await downloadSource.loadData(from: provider.metadataURL, loader: dataLoader))
            .filter { provider.matches(gameVersion: gameVersion, loaderVersion: $0) }
        guard let selected = versions
            .sorted(by: compareVersionDescending)
            .first(where: { !$0.localizedCaseInsensitiveContains("beta") })
            ?? versions.sorted(by: compareVersionDescending).first else {
            throw ForgeLikeInstallError.noCompatibleVersion(gameVersion, provider)
        }
        return selected
    }

    private func normalizedLoaderVersion(_ requestedLoaderVersion: String?, gameVersion: String) async throws -> String {
        guard let requested = requestedLoaderVersion?.trimmed.nonEmpty else {
            return try await latestLoaderVersion(gameVersion: gameVersion)
        }
        let normalized: String
        switch provider {
        case .forge:
            normalized = requested.hasPrefix("\(gameVersion)-") ? requested : "\(gameVersion)-\(requested)"
        case .neoForge:
            normalized = requested
        }
        guard provider.matches(gameVersion: gameVersion, loaderVersion: normalized) else {
            throw ForgeLikeInstallError.noCompatibleVersion(gameVersion, provider)
        }
        return normalized
    }

    private func parseVersions(from data: Data) throws -> [String] {
        let document = try XMLDocument(data: data)
        let nodes = try document.nodes(forXPath: "/metadata/versioning/versions/version")
        let versions = nodes.compactMap { node -> String? in
            guard let element = node as? XMLElement else { return nil }
            return element.stringValue?.trimmed
        }
        guard !versions.isEmpty else {
            throw ForgeLikeInstallError.invalidMetadata(provider)
        }
        return versions
    }

    private func downloadInstaller(version: String, installerURL: URL, appSupportDirectory: URL) async throws -> URL {
        let directory = appSupportDirectory
            .appendingPathComponent("installers", isDirectory: true)
            .appendingPathComponent(provider.rawValue, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        let destination = directory.appendingPathComponent(provider.installerFileName(version: version))
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await downloadSource.loadData(from: installerURL, loader: dataLoader).write(to: destination, options: [.atomic])
        return destination
    }

    private func detectInstalledProfile(minecraftDirectory: URL, gameVersion: String, loaderVersion: String) -> String? {
        let versionsDirectory = minecraftDirectory.appendingPathComponent("versions", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(at: versionsDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }
        let providerNeedle = provider == .forge ? "forge" : "neoforge"
        return folders
            .compactMap { folder -> (id: String, timestamp: Date)? in
                let id = folder.lastPathComponent
                let jsonURL = folder.appendingPathComponent("\(id).json")
                guard let data = try? Data(contentsOf: jsonURL),
                      let raw = String(data: data, encoding: .utf8),
                      raw.localizedCaseInsensitiveContains(providerNeedle),
                      raw.contains(loaderVersion) || id.contains(loaderVersion) else {
                    return nil
                }
                let timestamp = (try? FileManager.default.attributesOfItem(atPath: jsonURL.path)[.modificationDate] as? Date) ?? .distantPast
                return (id, timestamp)
            }
            .sorted { $0.timestamp > $1.timestamp }
            .first?
            .id
    }

    private func compareVersionDescending(_ lhs: String, _ rhs: String) -> Bool {
        let left = ForgeLikeParsedVersion(lhs)
        let right = ForgeLikeParsedVersion(rhs)
        if left.numbers != right.numbers {
            return left.numbers.lexicographicallyPrecedes(right.numbers) == false
        }
        if left.isPrerelease != right.isPrerelease {
            return !left.isPrerelease && right.isPrerelease
        }
        return lhs > rhs
    }

    static func runInstallerProcess(_ request: ForgeLikeInstallerRunRequest) async throws -> ForgeLikeInstallerRunResult {
        let logsDirectory = request.minecraftDirectory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appendingPathComponent("\(request.provider.rawValue.lowercased())-installer.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = request.javaExecutable
        process.arguments = ["-jar", request.installerJarURL.path] + request.arguments
        process.currentDirectoryURL = request.minecraftDirectory
        process.standardOutput = logHandle
        process.standardError = logHandle

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                try? logHandle.close()
                continuation.resume(returning: ForgeLikeInstallerRunResult(
                    terminationStatus: process.terminationStatus,
                    logURL: logURL
                ))
            }
            do {
                try process.run()
            } catch {
                try? logHandle.close()
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct ForgeLikeParsedVersion: Sendable {
    let numbers: [Int]
    let isPrerelease: Bool

    init(_ value: String) {
        let cleaned = value.replacingOccurrences(of: "-", with: ".")
        numbers = cleaned
            .split(separator: ".")
            .compactMap { Int($0.filter(\.isNumber)) }
        isPrerelease = value.localizedCaseInsensitiveContains("beta") ||
            value.localizedCaseInsensitiveContains("alpha")
    }
}
