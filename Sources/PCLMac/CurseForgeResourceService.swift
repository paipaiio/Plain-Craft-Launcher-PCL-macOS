import CryptoKit
import Foundation

enum CurseForgeResourceError: LocalizedError, Sendable {
    case missingAPIKey
    case noCompatibleFile(String)
    case missingDownloadURL(String)
    case unsafeFileName(String)
    case checksumMismatch(URL)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "请先配置 CurseForge API Key"
        case .noCompatibleFile(let name):
            "没有找到兼容当前条件的 CurseForge 文件：\(name)"
        case .missingDownloadURL(let name):
            "CurseForge 没有返回可下载地址：\(name)"
        case .unsafeFileName(let fileName):
            "资源文件名不安全：\(fileName)"
        case .checksumMismatch(let url):
            "资源文件校验失败：\(url.path)"
        case .httpStatus(let status, let body):
            "CurseForge 返回 HTTP \(status)：\(body)"
        }
    }
}

enum CurseForgeResourceType: Int, CaseIterable, Identifiable, Sendable {
    case mod = 6
    case modpack = 4471
    case resourcePack = 12

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .mod: "Mod"
        case .modpack: "整合包"
        case .resourcePack: "资源包"
        }
    }

    var defaultSearchQuery: String {
        switch self {
        case .mod: "fabric api"
        case .modpack: "adventure"
        case .resourcePack: "faithful"
        }
    }

    var installActionTitle: String {
        switch self {
        case .mod: "安装到当前实例"
        case .modpack: "导入整合包"
        case .resourcePack: "安装到资源包目录"
        }
    }

    var destinationDescription: String {
        switch self {
        case .mod: "当前实例 mods"
        case .modpack: "独立 Minecraft 实例"
        case .resourcePack: "Minecraft resourcepacks"
        }
    }

    var installableExtensions: [String] {
        switch self {
        case .mod: [".jar"]
        case .modpack, .resourcePack: [".zip"]
        }
    }

    var supportsLoaderFiltering: Bool {
        switch self {
        case .mod, .modpack: true
        case .resourcePack: false
        }
    }
}

struct CurseForgeSearchRequest: Sendable {
    var apiKey: String
    var resourceType: CurseForgeResourceType
    var query: String
    var minecraftVersion: String?
    var loader: String?
    var pageSize: Int

    init(
        apiKey: String,
        resourceType: CurseForgeResourceType,
        query: String,
        minecraftVersion: String? = nil,
        loader: String? = nil,
        pageSize: Int = 30
    ) {
        self.apiKey = apiKey.trimmed
        self.resourceType = resourceType
        self.query = query.trimmed
        self.minecraftVersion = minecraftVersion?.trimmed
        self.loader = resourceType.supportsLoaderFiltering ? loader?.trimmed.lowercased() : nil
        self.pageSize = min(max(pageSize, 1), 50)
    }
}

struct CurseForgeSearchResponse: Decodable, Sendable {
    let data: [CurseForgeProject]
    let pagination: CurseForgePagination
}

struct CurseForgeFilesResponse: Decodable, Sendable {
    let data: [CurseForgeFile]
    let pagination: CurseForgePagination
}

struct CurseForgeFileResponse: Decodable, Sendable {
    let data: CurseForgeFile
}

struct CurseForgeStringResponse: Decodable, Sendable {
    let data: String
}

struct CurseForgePagination: Decodable, Hashable, Sendable {
    let index: Int
    let pageSize: Int
    let resultCount: Int
    let totalCount: Int
}

struct CurseForgeProject: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let gameID: Int?
    let name: String
    let slug: String?
    let summary: String
    let downloadCount: Int
    let classID: Int?
    let authors: [CurseForgeAuthor]
    let logo: CurseForgeAsset?

    enum CodingKeys: String, CodingKey {
        case id
        case gameID = "gameId"
        case name
        case slug
        case summary
        case downloadCount
        case classID = "classId"
        case authors
        case logo
    }
}

extension CurseForgeResourceType {
    var websitePathComponent: String {
        switch self {
        case .mod: "mc-mods"
        case .modpack: "modpacks"
        case .resourcePack: "texture-packs"
        }
    }
}

extension CurseForgeProject {
    func websiteURL(resourceType: CurseForgeResourceType) -> URL? {
        guard let slug, !slug.trimmed.isEmpty else { return nil }
        return URL(string: "https://www.curseforge.com/minecraft/\(resourceType.websitePathComponent)/\(slug)")
    }

    var authorSummary: String {
        let names = authors.map(\.name).filter { !$0.trimmed.isEmpty }
        return names.isEmpty ? "-" : names.prefix(3).joined(separator: ", ")
    }

    func detailSummary(resourceType: CurseForgeResourceType) -> String {
        [
            name,
            "来源：CurseForge \(resourceType.displayName)",
            "作者：\(authorSummary)",
            "下载：\(downloadCount.formatted())",
            "链接：\(websiteURL(resourceType: resourceType)?.absoluteString ?? "-")",
            summary
        ].joined(separator: "\n")
    }
}

struct CurseForgeAuthor: Decodable, Hashable, Sendable {
    let id: Int?
    let name: String
    let url: URL?
}

struct CurseForgeAsset: Decodable, Hashable, Sendable {
    let thumbnailURL: URL?
    let url: URL?

    enum CodingKeys: String, CodingKey {
        case thumbnailURL = "thumbnailUrl"
        case url
    }
}

struct CurseForgeFile: Decodable, Hashable, Sendable {
    let id: Int
    let modID: Int
    let displayName: String
    let fileName: String
    let fileLength: Int?
    let downloadURLString: String?
    let hashes: [CurseForgeFileHash]
    let gameVersions: [String]
    let releaseType: Int?
    let modules: [CurseForgeFileModule]?

    var downloadURL: URL? {
        guard let downloadURLString, !downloadURLString.trimmed.isEmpty else { return nil }
        return URL(string: downloadURLString)
    }

    var sha1: String? {
        hashes.first { $0.algo == 1 }?.value.lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case modID = "modId"
        case displayName
        case fileName
        case fileLength
        case downloadURLString = "downloadUrl"
        case hashes
        case gameVersions
        case releaseType
        case modules
    }
}

struct CurseForgeFileHash: Decodable, Hashable, Sendable {
    let value: String
    let algo: Int
}

struct CurseForgeFileModule: Decodable, Hashable, Sendable {
    let name: String
    let fingerprint: Int?
}

struct CurseForgeInstallResult: Sendable {
    let project: CurseForgeProject
    let file: CurseForgeFile
    let destination: URL
}

struct CurseForgeResourceService: Sendable {
    typealias HTTPClient = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let minecraftGameID = 432

    var baseURL: URL
    var httpClient: HTTPClient

    init(
        baseURL: URL = URL(string: "https://api.curseforge.com/v1")!,
        httpClient: @escaping HTTPClient = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CurseForgeResourceError.httpStatus(0, "Invalid response")
            }
            return (data, http)
        }
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
    }

    func searchResources(_ request: CurseForgeSearchRequest) async throws -> CurseForgeSearchResponse {
        try await send(searchURL(request), apiKey: request.apiKey, response: CurseForgeSearchResponse.self)
    }

    func files(
        modID: Int,
        apiKey: String,
        minecraftVersion: String?,
        loader: String?,
        pageSize: Int = 20
    ) async throws -> [CurseForgeFile] {
        let url = filesURL(
            modID: modID,
            minecraftVersion: minecraftVersion,
            loader: loader,
            pageSize: pageSize
        )
        return try await send(url, apiKey: apiKey, response: CurseForgeFilesResponse.self).data
    }

    func file(projectID: Int, fileID: Int, apiKey: String) async throws -> CurseForgeFile {
        try await send(
            fileURL(projectID: projectID, fileID: fileID),
            apiKey: apiKey,
            response: CurseForgeFileResponse.self
        ).data
    }

    func installLatestResource(
        project: CurseForgeProject,
        resourceType: CurseForgeResourceType,
        apiKey: String,
        minecraftVersion: String?,
        loader: String?,
        destinationDirectory: URL
    ) async throws -> CurseForgeInstallResult {
        let projectFiles = try await files(
            modID: project.id,
            apiKey: apiKey,
            minecraftVersion: minecraftVersion,
            loader: resourceType.supportsLoaderFiltering ? loader : nil
        )
        guard let file = installableFile(from: projectFiles, resourceType: resourceType) else {
            throw CurseForgeResourceError.noCompatibleFile(project.name)
        }

        let downloadURL = try await downloadURL(for: file, projectID: project.id, apiKey: apiKey)
        let destination = destinationDirectory
            .appendingPathComponent(try safeFileName(file.fileName, expectedExtensions: resourceType.installableExtensions))
        try await download(file, from: downloadURL, to: destination)
        return CurseForgeInstallResult(project: project, file: file, destination: destination)
    }

    func installResourceFile(
        project: CurseForgeProject,
        file: CurseForgeFile,
        resourceType: CurseForgeResourceType,
        apiKey: String,
        destinationDirectory: URL
    ) async throws -> CurseForgeInstallResult {
        let lowercased = file.fileName.lowercased()
        guard resourceType.installableExtensions.contains(where: { lowercased.hasSuffix($0) }) else {
            throw CurseForgeResourceError.noCompatibleFile(project.name)
        }
        let downloadURL = try await downloadURL(for: file, projectID: project.id, apiKey: apiKey)
        let destination = destinationDirectory
            .appendingPathComponent(try safeFileName(file.fileName, expectedExtensions: resourceType.installableExtensions))
        try await download(file, from: downloadURL, to: destination)
        return CurseForgeInstallResult(project: project, file: file, destination: destination)
    }

    func searchURL(_ request: CurseForgeSearchRequest) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("mods/search"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "gameId", value: "\(Self.minecraftGameID)"),
            URLQueryItem(name: "classId", value: "\(request.resourceType.rawValue)"),
            URLQueryItem(name: "searchFilter", value: request.query),
            URLQueryItem(name: "sortField", value: "6"),
            URLQueryItem(name: "sortOrder", value: "desc"),
            URLQueryItem(name: "pageSize", value: "\(request.pageSize)")
        ]
        if let minecraftVersion = request.minecraftVersion, !minecraftVersion.isEmpty {
            queryItems.append(URLQueryItem(name: "gameVersion", value: minecraftVersion))
            if let loaderType = curseForgeLoaderType(from: request.loader) {
                queryItems.append(URLQueryItem(name: "modLoaderType", value: "\(loaderType)"))
            }
        }
        components.queryItems = queryItems
        return components.url!
    }

    func filesURL(
        modID: Int,
        minecraftVersion: String?,
        loader: String?,
        pageSize: Int
    ) -> URL {
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("mods")
                .appendingPathComponent("\(modID)")
                .appendingPathComponent("files"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "pageSize", value: "\(min(max(pageSize, 1), 50))")
        ]
        if let minecraftVersion, !minecraftVersion.trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "gameVersion", value: minecraftVersion.trimmed))
            if let loaderType = curseForgeLoaderType(from: loader) {
                queryItems.append(URLQueryItem(name: "modLoaderType", value: "\(loaderType)"))
            }
        }
        components.queryItems = queryItems
        return components.url!
    }

    func downloadURLURL(projectID: Int, fileID: Int) -> URL {
        baseURL
            .appendingPathComponent("mods")
            .appendingPathComponent("\(projectID)")
            .appendingPathComponent("files")
            .appendingPathComponent("\(fileID)")
            .appendingPathComponent("download-url")
    }

    func fileURL(projectID: Int, fileID: Int) -> URL {
        baseURL
            .appendingPathComponent("mods")
            .appendingPathComponent("\(projectID)")
            .appendingPathComponent("files")
            .appendingPathComponent("\(fileID)")
    }

    func curseForgeLoaderType(from loader: String?) -> Int? {
        switch loader?.trimmed.lowercased() {
        case "forge": 1
        case "fabric": 4
        case "quilt": 5
        case "neoforge": 6
        default: nil
        }
    }

    private func installableFile(from files: [CurseForgeFile], resourceType: CurseForgeResourceType) -> CurseForgeFile? {
        files.first { file in
            let lowercased = file.fileName.lowercased()
            return resourceType.installableExtensions.contains { lowercased.hasSuffix($0) }
        }
    }

    func downloadURL(for file: CurseForgeFile, projectID: Int, apiKey: String) async throws -> URL {
        if let url = file.downloadURL {
            return url
        }
        let response = try await send(
            downloadURLURL(projectID: projectID, fileID: file.id),
            apiKey: apiKey,
            response: CurseForgeStringResponse.self
        )
        guard let url = URL(string: response.data) else {
            throw CurseForgeResourceError.missingDownloadURL(file.fileName)
        }
        return url
    }

    private func safeFileName(_ fileName: String, expectedExtensions: [String]) throws -> String {
        let lastPathComponent = URL(fileURLWithPath: fileName).lastPathComponent
        guard lastPathComponent == fileName,
              !lastPathComponent.isEmpty,
              expectedExtensions.contains(where: { lastPathComponent.lowercased().hasSuffix($0) }),
              !lastPathComponent.contains("/") &&
              !lastPathComponent.contains("\\") &&
              !lastPathComponent.contains("..") else {
            throw CurseForgeResourceError.unsafeFileName(fileName)
        }
        return lastPathComponent
    }

    private func download(_ file: CurseForgeFile, from url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("PCLMac/0.1 (macOS native preview)", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await httpClient(request)
        guard (200..<300).contains(http.statusCode) else {
            throw CurseForgeResourceError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let sha1 = file.sha1, !sha1.isEmpty {
            let digest = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == sha1 else {
                throw CurseForgeResourceError.checksumMismatch(destination)
            }
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic])
    }

    private func send<T: Decodable>(_ url: URL, apiKey: String, response: T.Type) async throws -> T {
        let trimmedKey = apiKey.trimmed
        guard !trimmedKey.isEmpty else { throw CurseForgeResourceError.missingAPIKey }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("PCLMac/0.1 (macOS native preview)", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await httpClient(request)
        guard (200..<300).contains(http.statusCode) else {
            throw CurseForgeResourceError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
