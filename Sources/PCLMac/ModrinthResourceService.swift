import CryptoKit
import Foundation

enum ModrinthResourceError: LocalizedError, Sendable {
    case noCompatibleVersion(String)
    case noInstallableFile(String)
    case unsafeFileName(String)
    case checksumMismatch(URL)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .noCompatibleVersion(let projectID):
            "没有找到兼容当前版本的资源：\(projectID)"
        case .noInstallableFile(let projectID):
            "该资源没有可安装文件：\(projectID)"
        case .unsafeFileName(let fileName):
            "资源文件名不安全：\(fileName)"
        case .checksumMismatch(let url):
            "资源文件校验失败：\(url.path)"
        case .httpStatus(let status, let body):
            "Modrinth 返回 HTTP \(status)：\(body)"
        }
    }
}

enum ModrinthProjectType: String, CaseIterable, Identifiable, Sendable {
    case mod
    case modpack
    case datapack
    case resourcepack
    case shader

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mod: "Mod"
        case .modpack: "整合包"
        case .datapack: "数据包"
        case .resourcepack: "资源包"
        case .shader: "光影包"
        }
    }

    var installableExtension: String {
        switch self {
        case .mod: ".jar"
        case .modpack: ".mrpack"
        case .datapack, .resourcepack, .shader: ".zip"
        }
    }

    var supportsLoaderFiltering: Bool {
        switch self {
        case .mod, .modpack: true
        case .datapack, .resourcepack, .shader: false
        }
    }

    var defaultSearchQuery: String {
        switch self {
        case .mod: "fabric api"
        case .modpack: "adventure"
        case .datapack: "terralith"
        case .resourcepack: "faithful"
        case .shader: "complementary"
        }
    }

    var installActionTitle: String {
        switch self {
        case .mod: "安装到当前实例"
        case .modpack: "导入整合包"
        case .datapack: "下载数据包文件"
        case .resourcepack: "安装到资源包目录"
        case .shader: "安装到光影包目录"
        }
    }

    var destinationDescription: String {
        switch self {
        case .mod: "当前实例 mods"
        case .modpack: "独立 Minecraft 实例"
        case .datapack: "PCL 数据包暂存目录"
        case .resourcepack: "Minecraft resourcepacks"
        case .shader: "Minecraft shaderpacks"
        }
    }
}

struct ModrinthSearchRequest: Sendable {
    var projectType: ModrinthProjectType
    var query: String
    var minecraftVersion: String?
    var loader: String?
    var limit: Int

    init(
        projectType: ModrinthProjectType = .mod,
        query: String,
        minecraftVersion: String? = nil,
        loader: String? = nil,
        limit: Int = 30
    ) {
        self.projectType = projectType
        self.query = query.trimmed
        self.minecraftVersion = minecraftVersion?.trimmed
        self.loader = projectType.supportsLoaderFiltering ? loader?.trimmed.lowercased() : nil
        self.limit = min(max(limit, 1), 100)
    }
}

struct ModrinthSearchResponse: Decodable, Sendable {
    let hits: [ModrinthProject]
    let totalHits: Int

    enum CodingKeys: String, CodingKey {
        case hits
        case totalHits = "total_hits"
    }
}

struct ModrinthProject: Decodable, Identifiable, Hashable, Sendable {
    let projectID: String
    let slug: String
    let title: String
    let description: String
    let projectType: String
    let downloads: Int
    let follows: Int
    let author: String?
    let iconURL: URL?
    let latestVersion: String?
    let versions: [String]
    let categories: [String]

    var id: String { projectID }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case slug
        case title
        case description
        case projectType = "project_type"
        case downloads
        case follows
        case author
        case iconURL = "icon_url"
        case latestVersion = "latest_version"
        case versions
        case categories
    }
}

extension ModrinthProject {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try container.decode(String.self, forKey: .projectID)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        projectType = try container.decode(String.self, forKey: .projectType)
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads) ?? 0
        follows = try container.decodeIfPresent(Int.self, forKey: .follows) ?? 0
        author = try container.decodeIfPresent(String.self, forKey: .author)
        latestVersion = try container.decodeIfPresent(String.self, forKey: .latestVersion)
        versions = try container.decodeIfPresent([String].self, forKey: .versions) ?? []
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []

        if let iconString = try container.decodeIfPresent(String.self, forKey: .iconURL)?.trimmed,
           !iconString.isEmpty {
            iconURL = URL(string: iconString)
        } else {
            iconURL = nil
        }
    }
}

extension ModrinthProjectType {
    var websitePathComponent: String {
        switch self {
        case .mod: "mod"
        case .modpack: "modpack"
        case .datapack: "datapack"
        case .resourcepack: "resourcepack"
        case .shader: "shader"
        }
    }
}

extension ModrinthProject {
    func websiteURL(projectType: ModrinthProjectType) -> URL? {
        URL(string: "https://modrinth.com/\(projectType.websitePathComponent)/\(slug)")
    }

    var categorySummary: String {
        categories.isEmpty ? "-" : categories.prefix(5).joined(separator: ", ")
    }

    var versionSummary: String {
        versions.isEmpty ? "-" : versions.prefix(5).joined(separator: ", ")
    }

    func detailSummary(projectType: ModrinthProjectType) -> String {
        [
            title,
            "来源：Modrinth \(projectType.displayName)",
            "作者：\(author ?? "-")",
            "下载：\(downloads.formatted())",
            "关注：\(follows.formatted())",
            "版本：\(versionSummary)",
            "分类：\(categorySummary)",
            "链接：\(websiteURL(projectType: projectType)?.absoluteString ?? "-")",
            description
        ].joined(separator: "\n")
    }
}

struct ModrinthVersion: Decodable, Sendable {
    let id: String
    let name: String
    let versionNumber: String
    let versionType: String?
    let gameVersions: [String]
    let loaders: [String]
    let files: [ModrinthFile]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case versionNumber = "version_number"
        case versionType = "version_type"
        case gameVersions = "game_versions"
        case loaders
        case files
    }
}

struct ModrinthFile: Decodable, Sendable {
    let hashes: ModrinthFileHashes
    let url: URL
    let filename: String
    let primary: Bool
    let size: Int?
}

struct ModrinthFileHashes: Decodable, Sendable {
    let sha1: String?
}

struct ModrinthInstallResult: Sendable {
    let project: ModrinthProject?
    let version: ModrinthVersion
    let file: ModrinthFile
    let destination: URL
}

struct ModrinthResourceService: Sendable {
    typealias HTTPClient = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    var baseURL: URL
    var httpClient: HTTPClient

    init(
        baseURL: URL = URL(string: "https://api.modrinth.com/v2")!,
        httpClient: @escaping HTTPClient = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ModrinthResourceError.httpStatus(0, "Invalid response")
            }
            return (data, http)
        }
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    func searchMods(_ request: ModrinthSearchRequest) async throws -> ModrinthSearchResponse {
        try await searchResources(request)
    }

    func searchResources(_ request: ModrinthSearchRequest) async throws -> ModrinthSearchResponse {
        try await send(searchURL(request), response: ModrinthSearchResponse.self)
    }

    func versions(projectID: String, minecraftVersion: String?, loader: String?) async throws -> [ModrinthVersion] {
        try await send(versionsURL(projectID: projectID, minecraftVersion: minecraftVersion, loader: loader), response: [ModrinthVersion].self)
    }

    func installLatestMod(
        project: ModrinthProject?,
        projectID: String,
        minecraftVersion: String?,
        loader: String?,
        instanceDirectory: URL
    ) async throws -> ModrinthInstallResult {
        try await installLatestResource(
            project: project,
            projectID: projectID,
            projectType: .mod,
            minecraftVersion: minecraftVersion,
            loader: loader,
            destinationDirectory: instanceDirectory.appendingPathComponent("mods", isDirectory: true)
        )
    }

    func installLatestResource(
        project: ModrinthProject?,
        projectID: String,
        projectType: ModrinthProjectType,
        minecraftVersion: String?,
        loader: String?,
        destinationDirectory: URL
    ) async throws -> ModrinthInstallResult {
        let versionLoader = projectType.supportsLoaderFiltering ? loader : nil
        let allVersions = try await versions(projectID: projectID, minecraftVersion: minecraftVersion, loader: versionLoader)
        guard let version = allVersions.first else {
            throw ModrinthResourceError.noCompatibleVersion(projectID)
        }
        guard let file = installableFile(from: version, projectType: projectType) else {
            throw ModrinthResourceError.noInstallableFile(projectID)
        }
        let destination = destinationDirectory
            .appendingPathComponent(try safeFileName(file.filename, expectedExtension: projectType.installableExtension))
        try await download(file, to: destination)
        return ModrinthInstallResult(project: project, version: version, file: file, destination: destination)
    }

    func installResourceFile(
        project: ModrinthProject?,
        version: ModrinthVersion,
        file: ModrinthFile,
        projectType: ModrinthProjectType,
        destinationDirectory: URL
    ) async throws -> ModrinthInstallResult {
        guard file.filename.lowercased().hasSuffix(projectType.installableExtension) else {
            throw ModrinthResourceError.noInstallableFile(project?.projectID ?? version.id)
        }
        let destination = destinationDirectory
            .appendingPathComponent(try safeFileName(file.filename, expectedExtension: projectType.installableExtension))
        try await download(file, to: destination)
        return ModrinthInstallResult(project: project, version: version, file: file, destination: destination)
    }

    func searchURL(_ request: ModrinthSearchRequest) throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "query", value: request.query),
            URLQueryItem(name: "index", value: "downloads"),
            URLQueryItem(name: "limit", value: "\(request.limit)")
        ]

        var facets = [["project_type:\(request.projectType.rawValue)"]]
        if let minecraftVersion = request.minecraftVersion, !minecraftVersion.isEmpty {
            facets.append(["versions:\(minecraftVersion)"])
        }
        if let loader = request.loader, !loader.isEmpty {
            facets.append(["categories:\(loader)"])
        }
        let facetsData = try JSONEncoder().encode(facets)
        queryItems.append(URLQueryItem(name: "facets", value: String(data: facetsData, encoding: .utf8)))
        components.queryItems = queryItems
        return components.url!
    }

    func versionsURL(projectID: String, minecraftVersion: String?, loader: String?) throws -> URL {
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("project")
                .appendingPathComponent(projectID)
                .appendingPathComponent("version"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems: [URLQueryItem] = []
        if let minecraftVersion, !minecraftVersion.trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "game_versions", value: try jsonArray([minecraftVersion.trimmed])))
        }
        if let loader, !loader.trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "loaders", value: try jsonArray([loader.trimmed.lowercased()])))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private func installableFile(from version: ModrinthVersion, projectType: ModrinthProjectType) -> ModrinthFile? {
        let candidates = version.files.filter { $0.filename.lowercased().hasSuffix(projectType.installableExtension) }
        return candidates.first(where: \.primary) ?? candidates.first
    }

    private func safeFileName(_ fileName: String, expectedExtension: String) throws -> String {
        let lastPathComponent = URL(fileURLWithPath: fileName).lastPathComponent
        guard lastPathComponent == fileName,
              !lastPathComponent.isEmpty,
              lastPathComponent.lowercased().hasSuffix(expectedExtension),
              !lastPathComponent.contains("/") &&
              !lastPathComponent.contains("\\") &&
              !lastPathComponent.contains("..") else {
            throw ModrinthResourceError.unsafeFileName(fileName)
        }
        return lastPathComponent
    }

    private func download(_ file: ModrinthFile, to destination: URL) async throws {
        var request = URLRequest(url: file.url)
        request.setValue("PCLMac/0.1 (macOS native preview)", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await httpClient(request)
        guard (200..<300).contains(http.statusCode) else {
            throw ModrinthResourceError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let sha1 = file.hashes.sha1, !sha1.isEmpty {
            let digest = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == sha1.lowercased() else {
                throw ModrinthResourceError.checksumMismatch(destination)
            }
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic])
    }

    private func send<T: Decodable>(_ url: URL, response: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("PCLMac/0.1 (macOS native preview)", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await httpClient(request)
        guard (200..<300).contains(http.statusCode) else {
            throw ModrinthResourceError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func jsonArray(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
