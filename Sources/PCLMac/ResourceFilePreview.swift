import Foundation

struct ResourceVersionFilePreview: Identifiable, Hashable, Sendable {
    let id: String
    let versionName: String
    let releaseType: String
    let fileName: String
    let gameVersions: [String]
    let loaders: [String]
    let size: Int?
    let isPrimary: Bool

    var versionSummary: String {
        gameVersions.isEmpty ? "-" : gameVersions.prefix(4).joined(separator: ", ")
    }

    var loaderSummary: String {
        loaders.isEmpty ? "-" : loaders.prefix(4).joined(separator: ", ")
    }

    static func modrinth(
        versions: [ModrinthVersion],
        projectType: ModrinthProjectType,
        limit: Int = 8
    ) -> [ResourceVersionFilePreview] {
        var previews: [ResourceVersionFilePreview] = []
        for version in versions {
            let files = version.files
                .filter { $0.filename.lowercased().hasSuffix(projectType.installableExtension) }
                .sorted { lhs, rhs in
                    if lhs.primary != rhs.primary { return lhs.primary && !rhs.primary }
                    return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
                }
            for file in files {
                previews.append(
                    ResourceVersionFilePreview(
                        id: "modrinth:\(version.id):\(file.filename)",
                        versionName: version.versionNumber.isEmpty ? version.name : version.versionNumber,
                        releaseType: version.versionType?.displayReleaseType ?? "Release",
                        fileName: file.filename,
                        gameVersions: version.gameVersions,
                        loaders: version.loaders,
                        size: file.size,
                        isPrimary: file.primary
                    )
                )
                if previews.count >= limit { return previews }
            }
        }
        return previews
    }

    static func curseForge(
        files: [CurseForgeFile],
        resourceType: CurseForgeResourceType,
        limit: Int = 8
    ) -> [ResourceVersionFilePreview] {
        files
            .filter { file in
                let lowercased = file.fileName.lowercased()
                return resourceType.installableExtensions.contains { lowercased.hasSuffix($0) }
            }
            .prefix(limit)
            .map { file in
                ResourceVersionFilePreview(
                    id: "curseforge:\(file.id)",
                    versionName: file.displayName.isEmpty ? file.fileName : file.displayName,
                    releaseType: file.releaseTypeDisplay,
                    fileName: file.fileName,
                    gameVersions: file.gameVersions,
                    loaders: file.loaderSummaryItems,
                    size: file.fileLength,
                    isPrimary: true
                )
            }
    }
}

private extension String {
    var displayReleaseType: String {
        switch lowercased() {
        case "release": "Release"
        case "beta": "Beta"
        case "alpha": "Alpha"
        default: isEmpty ? "-" : self
        }
    }
}

private extension CurseForgeFile {
    var releaseTypeDisplay: String {
        switch releaseType {
        case 1: "Release"
        case 2: "Beta"
        case 3: "Alpha"
        default: "-"
        }
    }

    var loaderSummaryItems: [String] {
        let knownLoaders = ["Forge", "Fabric", "Quilt", "NeoForge"]
        return gameVersions.filter { version in
            knownLoaders.contains { loader in
                version.localizedCaseInsensitiveContains(loader)
            }
        }
    }
}
