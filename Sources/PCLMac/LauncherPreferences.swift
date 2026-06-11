import Foundation

enum LauncherThemePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case pclBlue = "PCL 蓝"
    case grass = "草方块绿"
    case amethyst = "紫水晶紫"
    case redstone = "红石红"
    case copper = "铜锭橙"

    var id: String { rawValue }
}

enum LauncherAppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }
}

enum LauncherHomeCard: String, CaseIterable, Identifiable, Codable, Sendable {
    case status
    case java
    case launchConfig
    case dependency
    case command
    case launchLog
    case versions

    var id: String { rawValue }
}

enum LocalVersionFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "全部"
    case favorites = "收藏"
    case vanilla = "原版"
    case fabric = "Fabric"
    case forge = "Forge"
    case quilt = "Quilt"
    case neoForge = "NeoForge"

    var id: String { rawValue }
}

enum GameWindowSizePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case minecraftDefault = "854 × 480"
    case hd = "1280 × 720"
    case hdPlus = "1600 × 900"
    case fullHD = "1920 × 1080"
    case qhd = "2560 × 1440"

    var id: String { rawValue }

    var width: Double {
        switch self {
        case .minecraftDefault: 854
        case .hd: 1280
        case .hdPlus: 1600
        case .fullHD: 1920
        case .qhd: 2560
        }
    }

    var height: Double {
        switch self {
        case .minecraftDefault: 480
        case .hd: 720
        case .hdPlus: 900
        case .fullHD: 1080
        case .qhd: 1440
        }
    }

    var displayName: String {
        switch self {
        case .minecraftDefault: "Minecraft 默认 · \(rawValue)"
        case .hd: "720p · \(rawValue)"
        case .hdPlus: "900p · \(rawValue)"
        case .fullHD: "1080p · \(rawValue)"
        case .qhd: "2K · \(rawValue)"
        }
    }
}

enum GameMemoryPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneGB = "1 GB"
    case twoGB = "2 GB"
    case fourGB = "4 GB"
    case sixGB = "6 GB"
    case eightGB = "8 GB"
    case twelveGB = "12 GB"
    case sixteenGB = "16 GB"

    var id: String { rawValue }

    var megabytes: Double {
        switch self {
        case .oneGB: 1024
        case .twoGB: 2048
        case .fourGB: 4096
        case .sixGB: 6144
        case .eightGB: 8192
        case .twelveGB: 12288
        case .sixteenGB: 16384
        }
    }

    var displayName: String {
        switch self {
        case .oneGB: "低配/远古版本 · 1 GB"
        case .twoGB: "轻量原版 · 2 GB"
        case .fourGB: "常规整合包 · 4 GB"
        case .sixGB: "中型整合包 · 6 GB"
        case .eightGB: "大型整合包 · 8 GB"
        case .twelveGB: "重度整合包 · 12 GB"
        case .sixteenGB: "上限 · 16 GB"
        }
    }
}

struct LauncherServerFavorite: Codable, Equatable, Hashable, Identifiable, Sendable {
    var name: String
    var address: String
    var port: String?

    var id: String {
        "\(address.lowercased())|\(port ?? "")"
    }

    var displayName: String {
        name.trimmed.isEmpty ? address : name
    }

    var addressText: String {
        if let port, !port.isEmpty {
            return "\(address):\(port)"
        }
        return address
    }

    var normalized: LauncherServerFavorite? {
        let normalizedAddress = address.trimmed
        guard !normalizedAddress.isEmpty else { return nil }
        let normalizedPort = Self.normalizedPort(port)
        let normalizedName = name.trimmed.nonEmpty ?? normalizedAddress
        return LauncherServerFavorite(
            name: normalizedName,
            address: normalizedAddress,
            port: normalizedPort
        )
    }

    static func normalizedPort(_ port: String?) -> String? {
        guard let text = port?.trimmed, !text.isEmpty, let value = Int(text), (1...65535).contains(value) else {
            return nil
        }
        return "\(value)"
    }
}

struct LauncherPreferences: Codable, Equatable, Sendable {
    var loginMode: String
    var offlineUsername: String
    var selectedAccountID: String?
    var microsoftClientID: String?
    var nideServerID: String?
    var nideUsername: String?
    var authlibServerURL: String?
    var authlibUsername: String?
    var selectedInstanceName: String?
    var selectedJavaPath: String?
    var customMinecraftDirectoryPath: String?
    var localVersionQuery: String
    var localVersionFilter: String
    var favoriteInstanceNames: [String]
    var hiddenInstanceNames: [String]
    var showsHiddenInstances: Bool
    var downloadSource: String
    var resourceProvider: String?
    var curseForgeAPIKey: String?
    var selectedInstallLoader: String?
    var maxDownloadThreads: Double
    var memoryLimit: Double
    var gameWindowWidth: Double
    var gameWindowHeight: Double
    var launchFullscreen: Bool
    var useVersionIsolation: Bool
    var launchServerAddress: String?
    var launchServerPort: String?
    var serverFavorites: [LauncherServerFavorite]
    var extraJvmArguments: String
    var extraGameArguments: String
    var hideLauncherOnGameStart: Bool
    var showLauncherOnGameExit: Bool
    var showNativeNotifications: Bool
    var showDockBadge: Bool
    var useHighPerformanceMode: Bool
    var autoSelectJava: Bool
    var remoteVersionFilter: String
    var themePreset: String
    var appearanceMode: String
    var showsHomeHint: Bool
    var hiddenHomeCardIDs: [String]
    var backgroundImagePath: String?
    var backgroundImageOpacity: Double

    init(
        loginMode: String,
        offlineUsername: String,
        selectedAccountID: String?,
        microsoftClientID: String?,
        nideServerID: String?,
        nideUsername: String?,
        authlibServerURL: String?,
        authlibUsername: String?,
        selectedInstanceName: String?,
        selectedJavaPath: String?,
        customMinecraftDirectoryPath: String? = nil,
        localVersionQuery: String = "",
        localVersionFilter: String = LocalVersionFilter.all.rawValue,
        favoriteInstanceNames: [String] = [],
        hiddenInstanceNames: [String] = [],
        showsHiddenInstances: Bool = false,
        downloadSource: String,
        resourceProvider: String?,
        curseForgeAPIKey: String?,
        selectedInstallLoader: String?,
        maxDownloadThreads: Double,
        memoryLimit: Double,
        gameWindowWidth: Double = Self.defaultGameWindowWidth,
        gameWindowHeight: Double = Self.defaultGameWindowHeight,
        launchFullscreen: Bool = false,
        useVersionIsolation: Bool = true,
        launchServerAddress: String? = nil,
        launchServerPort: String? = nil,
        serverFavorites: [LauncherServerFavorite] = [],
        extraJvmArguments: String = "",
        extraGameArguments: String = "",
        hideLauncherOnGameStart: Bool = false,
        showLauncherOnGameExit: Bool = true,
        showNativeNotifications: Bool = false,
        showDockBadge: Bool = true,
        useHighPerformanceMode: Bool,
        autoSelectJava: Bool,
        remoteVersionFilter: String,
        themePreset: String = LauncherThemePreset.pclBlue.rawValue,
        appearanceMode: String = LauncherAppearanceMode.system.rawValue,
        showsHomeHint: Bool = true,
        hiddenHomeCardIDs: [String] = [],
        backgroundImagePath: String? = nil,
        backgroundImageOpacity: Double = 0.28
    ) {
        self.loginMode = loginMode
        self.offlineUsername = offlineUsername
        self.selectedAccountID = selectedAccountID
        self.microsoftClientID = microsoftClientID
        self.nideServerID = nideServerID
        self.nideUsername = nideUsername
        self.authlibServerURL = authlibServerURL
        self.authlibUsername = authlibUsername
        self.selectedInstanceName = selectedInstanceName
        self.selectedJavaPath = selectedJavaPath
        self.customMinecraftDirectoryPath = customMinecraftDirectoryPath
        self.localVersionQuery = localVersionQuery
        self.localVersionFilter = localVersionFilter
        self.favoriteInstanceNames = favoriteInstanceNames
        self.hiddenInstanceNames = hiddenInstanceNames
        self.showsHiddenInstances = showsHiddenInstances
        self.downloadSource = downloadSource
        self.resourceProvider = resourceProvider
        self.curseForgeAPIKey = curseForgeAPIKey
        self.selectedInstallLoader = selectedInstallLoader
        self.maxDownloadThreads = maxDownloadThreads
        self.memoryLimit = memoryLimit
        self.gameWindowWidth = gameWindowWidth
        self.gameWindowHeight = gameWindowHeight
        self.launchFullscreen = launchFullscreen
        self.useVersionIsolation = useVersionIsolation
        self.launchServerAddress = launchServerAddress
        self.launchServerPort = launchServerPort
        self.serverFavorites = serverFavorites
        self.extraJvmArguments = extraJvmArguments
        self.extraGameArguments = extraGameArguments
        self.hideLauncherOnGameStart = hideLauncherOnGameStart
        self.showLauncherOnGameExit = showLauncherOnGameExit
        self.showNativeNotifications = showNativeNotifications
        self.showDockBadge = showDockBadge
        self.useHighPerformanceMode = useHighPerformanceMode
        self.autoSelectJava = autoSelectJava
        self.remoteVersionFilter = remoteVersionFilter
        self.themePreset = themePreset
        self.appearanceMode = appearanceMode
        self.showsHomeHint = showsHomeHint
        self.hiddenHomeCardIDs = hiddenHomeCardIDs
        self.backgroundImagePath = backgroundImagePath
        self.backgroundImageOpacity = backgroundImageOpacity
    }

    enum CodingKeys: String, CodingKey {
        case loginMode
        case offlineUsername
        case selectedAccountID
        case microsoftClientID
        case nideServerID
        case nideUsername
        case authlibServerURL
        case authlibUsername
        case selectedInstanceName
        case selectedJavaPath
        case customMinecraftDirectoryPath
        case localVersionQuery
        case localVersionFilter
        case favoriteInstanceNames
        case hiddenInstanceNames
        case showsHiddenInstances
        case downloadSource
        case resourceProvider
        case curseForgeAPIKey
        case selectedInstallLoader
        case maxDownloadThreads
        case memoryLimit
        case gameWindowWidth
        case gameWindowHeight
        case launchFullscreen
        case useVersionIsolation
        case launchServerAddress
        case launchServerPort
        case serverFavorites
        case extraJvmArguments
        case extraGameArguments
        case hideLauncherOnGameStart
        case showLauncherOnGameExit
        case showNativeNotifications
        case showDockBadge
        case useHighPerformanceMode
        case autoSelectJava
        case remoteVersionFilter
        case themePreset
        case appearanceMode
        case showsHomeHint
        case hiddenHomeCardIDs
        case backgroundImagePath
        case backgroundImageOpacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            loginMode: try container.decodeIfPresent(String.self, forKey: .loginMode) ?? Self.defaults.loginMode,
            offlineUsername: try container.decodeIfPresent(String.self, forKey: .offlineUsername) ?? Self.defaults.offlineUsername,
            selectedAccountID: try container.decodeIfPresent(String.self, forKey: .selectedAccountID),
            microsoftClientID: try container.decodeIfPresent(String.self, forKey: .microsoftClientID),
            nideServerID: try container.decodeIfPresent(String.self, forKey: .nideServerID),
            nideUsername: try container.decodeIfPresent(String.self, forKey: .nideUsername),
            authlibServerURL: try container.decodeIfPresent(String.self, forKey: .authlibServerURL),
            authlibUsername: try container.decodeIfPresent(String.self, forKey: .authlibUsername),
            selectedInstanceName: try container.decodeIfPresent(String.self, forKey: .selectedInstanceName),
            selectedJavaPath: try container.decodeIfPresent(String.self, forKey: .selectedJavaPath),
            customMinecraftDirectoryPath: try container.decodeIfPresent(String.self, forKey: .customMinecraftDirectoryPath),
            localVersionQuery: try container.decodeIfPresent(String.self, forKey: .localVersionQuery) ?? Self.defaults.localVersionQuery,
            localVersionFilter: try container.decodeIfPresent(String.self, forKey: .localVersionFilter) ?? Self.defaults.localVersionFilter,
            favoriteInstanceNames: try container.decodeIfPresent([String].self, forKey: .favoriteInstanceNames) ?? Self.defaults.favoriteInstanceNames,
            hiddenInstanceNames: try container.decodeIfPresent([String].self, forKey: .hiddenInstanceNames) ?? Self.defaults.hiddenInstanceNames,
            showsHiddenInstances: try container.decodeIfPresent(Bool.self, forKey: .showsHiddenInstances) ?? Self.defaults.showsHiddenInstances,
            downloadSource: try container.decodeIfPresent(String.self, forKey: .downloadSource) ?? Self.defaults.downloadSource,
            resourceProvider: try container.decodeIfPresent(String.self, forKey: .resourceProvider),
            curseForgeAPIKey: try container.decodeIfPresent(String.self, forKey: .curseForgeAPIKey),
            selectedInstallLoader: try container.decodeIfPresent(String.self, forKey: .selectedInstallLoader),
            maxDownloadThreads: try container.decodeIfPresent(Double.self, forKey: .maxDownloadThreads) ?? Self.defaults.maxDownloadThreads,
            memoryLimit: try container.decodeIfPresent(Double.self, forKey: .memoryLimit) ?? Self.defaults.memoryLimit,
            gameWindowWidth: try container.decodeIfPresent(Double.self, forKey: .gameWindowWidth) ?? Self.defaults.gameWindowWidth,
            gameWindowHeight: try container.decodeIfPresent(Double.self, forKey: .gameWindowHeight) ?? Self.defaults.gameWindowHeight,
            launchFullscreen: try container.decodeIfPresent(Bool.self, forKey: .launchFullscreen) ?? Self.defaults.launchFullscreen,
            useVersionIsolation: try container.decodeIfPresent(Bool.self, forKey: .useVersionIsolation) ?? Self.defaults.useVersionIsolation,
            launchServerAddress: try container.decodeIfPresent(String.self, forKey: .launchServerAddress),
            launchServerPort: try container.decodeIfPresent(String.self, forKey: .launchServerPort),
            serverFavorites: try container.decodeIfPresent([LauncherServerFavorite].self, forKey: .serverFavorites) ?? Self.defaults.serverFavorites,
            extraJvmArguments: try container.decodeIfPresent(String.self, forKey: .extraJvmArguments) ?? Self.defaults.extraJvmArguments,
            extraGameArguments: try container.decodeIfPresent(String.self, forKey: .extraGameArguments) ?? Self.defaults.extraGameArguments,
            hideLauncherOnGameStart: try container.decodeIfPresent(Bool.self, forKey: .hideLauncherOnGameStart) ?? Self.defaults.hideLauncherOnGameStart,
            showLauncherOnGameExit: try container.decodeIfPresent(Bool.self, forKey: .showLauncherOnGameExit) ?? Self.defaults.showLauncherOnGameExit,
            showNativeNotifications: try container.decodeIfPresent(Bool.self, forKey: .showNativeNotifications) ?? Self.defaults.showNativeNotifications,
            showDockBadge: try container.decodeIfPresent(Bool.self, forKey: .showDockBadge) ?? Self.defaults.showDockBadge,
            useHighPerformanceMode: try container.decodeIfPresent(Bool.self, forKey: .useHighPerformanceMode) ?? Self.defaults.useHighPerformanceMode,
            autoSelectJava: try container.decodeIfPresent(Bool.self, forKey: .autoSelectJava) ?? Self.defaults.autoSelectJava,
            remoteVersionFilter: try container.decodeIfPresent(String.self, forKey: .remoteVersionFilter) ?? Self.defaults.remoteVersionFilter,
            themePreset: try container.decodeIfPresent(String.self, forKey: .themePreset) ?? Self.defaults.themePreset,
            appearanceMode: try container.decodeIfPresent(String.self, forKey: .appearanceMode) ?? Self.defaults.appearanceMode,
            showsHomeHint: try container.decodeIfPresent(Bool.self, forKey: .showsHomeHint) ?? Self.defaults.showsHomeHint,
            hiddenHomeCardIDs: try container.decodeIfPresent([String].self, forKey: .hiddenHomeCardIDs) ?? Self.defaults.hiddenHomeCardIDs,
            backgroundImagePath: try container.decodeIfPresent(String.self, forKey: .backgroundImagePath),
            backgroundImageOpacity: try container.decodeIfPresent(Double.self, forKey: .backgroundImageOpacity) ?? Self.defaults.backgroundImageOpacity
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(loginMode, forKey: .loginMode)
        try container.encode(offlineUsername, forKey: .offlineUsername)
        try container.encodeIfPresent(selectedAccountID, forKey: .selectedAccountID)
        try container.encodeIfPresent(microsoftClientID, forKey: .microsoftClientID)
        try container.encodeIfPresent(nideServerID, forKey: .nideServerID)
        try container.encodeIfPresent(nideUsername, forKey: .nideUsername)
        try container.encodeIfPresent(authlibServerURL, forKey: .authlibServerURL)
        try container.encodeIfPresent(authlibUsername, forKey: .authlibUsername)
        try container.encodeIfPresent(selectedInstanceName, forKey: .selectedInstanceName)
        try container.encodeIfPresent(selectedJavaPath, forKey: .selectedJavaPath)
        try container.encodeIfPresent(customMinecraftDirectoryPath, forKey: .customMinecraftDirectoryPath)
        try container.encode(localVersionQuery, forKey: .localVersionQuery)
        try container.encode(localVersionFilter, forKey: .localVersionFilter)
        try container.encode(favoriteInstanceNames, forKey: .favoriteInstanceNames)
        try container.encode(hiddenInstanceNames, forKey: .hiddenInstanceNames)
        try container.encode(showsHiddenInstances, forKey: .showsHiddenInstances)
        try container.encode(downloadSource, forKey: .downloadSource)
        try container.encodeIfPresent(resourceProvider, forKey: .resourceProvider)
        try container.encodeIfPresent(curseForgeAPIKey, forKey: .curseForgeAPIKey)
        try container.encodeIfPresent(selectedInstallLoader, forKey: .selectedInstallLoader)
        try container.encode(maxDownloadThreads, forKey: .maxDownloadThreads)
        try container.encode(memoryLimit, forKey: .memoryLimit)
        try container.encode(gameWindowWidth, forKey: .gameWindowWidth)
        try container.encode(gameWindowHeight, forKey: .gameWindowHeight)
        try container.encode(launchFullscreen, forKey: .launchFullscreen)
        try container.encode(useVersionIsolation, forKey: .useVersionIsolation)
        try container.encodeIfPresent(launchServerAddress, forKey: .launchServerAddress)
        try container.encodeIfPresent(launchServerPort, forKey: .launchServerPort)
        try container.encode(serverFavorites, forKey: .serverFavorites)
        try container.encode(extraJvmArguments, forKey: .extraJvmArguments)
        try container.encode(extraGameArguments, forKey: .extraGameArguments)
        try container.encode(hideLauncherOnGameStart, forKey: .hideLauncherOnGameStart)
        try container.encode(showLauncherOnGameExit, forKey: .showLauncherOnGameExit)
        try container.encode(showNativeNotifications, forKey: .showNativeNotifications)
        try container.encode(showDockBadge, forKey: .showDockBadge)
        try container.encode(useHighPerformanceMode, forKey: .useHighPerformanceMode)
        try container.encode(autoSelectJava, forKey: .autoSelectJava)
        try container.encode(remoteVersionFilter, forKey: .remoteVersionFilter)
        try container.encode(themePreset, forKey: .themePreset)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(showsHomeHint, forKey: .showsHomeHint)
        try container.encode(hiddenHomeCardIDs, forKey: .hiddenHomeCardIDs)
        try container.encodeIfPresent(backgroundImagePath, forKey: .backgroundImagePath)
        try container.encode(backgroundImageOpacity, forKey: .backgroundImageOpacity)
    }

    static let defaultGameWindowWidth = 854.0
    static let defaultGameWindowHeight = 480.0

    static let defaults = LauncherPreferences(
        loginMode: "离线",
        offlineUsername: "Player",
        selectedAccountID: nil,
        microsoftClientID: nil,
        nideServerID: nil,
        nideUsername: nil,
        authlibServerURL: nil,
        authlibUsername: nil,
        selectedInstanceName: nil,
        selectedJavaPath: nil,
        customMinecraftDirectoryPath: nil,
        localVersionQuery: "",
        localVersionFilter: LocalVersionFilter.all.rawValue,
        favoriteInstanceNames: [],
        hiddenInstanceNames: [],
        showsHiddenInstances: false,
        downloadSource: "官方 + BMCLAPI",
        resourceProvider: "Modrinth",
        curseForgeAPIKey: ProcessInfo.processInfo.environment["PCL_CURSEFORGE_API_KEY"],
        selectedInstallLoader: "原版",
        maxDownloadThreads: 32,
        memoryLimit: 4096,
        gameWindowWidth: defaultGameWindowWidth,
        gameWindowHeight: defaultGameWindowHeight,
        launchFullscreen: false,
        useVersionIsolation: true,
        launchServerAddress: nil,
        launchServerPort: nil,
        serverFavorites: [],
        extraJvmArguments: "",
        extraGameArguments: "",
        hideLauncherOnGameStart: false,
        showLauncherOnGameExit: true,
        showNativeNotifications: false,
        showDockBadge: true,
        useHighPerformanceMode: true,
        autoSelectJava: true,
        remoteVersionFilter: "release",
        themePreset: LauncherThemePreset.pclBlue.rawValue,
        appearanceMode: LauncherAppearanceMode.system.rawValue,
        showsHomeHint: true,
        hiddenHomeCardIDs: [],
        backgroundImagePath: nil,
        backgroundImageOpacity: 0.28
    )

    var normalized: LauncherPreferences {
        var value = self
        if !["正版", "离线", "统一通行证", "Authlib"].contains(value.loginMode) {
            value.loginMode = LauncherPreferences.defaults.loginMode
        }
        if value.offlineUsername.trimmed.isEmpty {
            value.offlineUsername = LauncherPreferences.defaults.offlineUsername
        }
        if !["release", "snapshot", "all"].contains(value.remoteVersionFilter) {
            value.remoteVersionFilter = LauncherPreferences.defaults.remoteVersionFilter
        }
        if !LauncherThemePreset.allCases.map(\.rawValue).contains(value.themePreset) {
            value.themePreset = LauncherPreferences.defaults.themePreset
        }
        if !LauncherAppearanceMode.allCases.map(\.rawValue).contains(value.appearanceMode) {
            value.appearanceMode = LauncherPreferences.defaults.appearanceMode
        }
        value.downloadSource = value.downloadSource.trimmed
        if !MinecraftDownloadSource.allCases.map(\.rawValue).contains(value.downloadSource) {
            value.downloadSource = LauncherPreferences.defaults.downloadSource
        }
        value.resourceProvider = value.resourceProvider?.trimmed ?? LauncherPreferences.defaults.resourceProvider
        if !["Modrinth", "CurseForge"].contains(value.resourceProvider ?? "Modrinth") {
            value.resourceProvider = LauncherPreferences.defaults.resourceProvider
        }
        value.microsoftClientID = value.microsoftClientID?.trimmed
        if value.microsoftClientID?.isEmpty == true {
            value.microsoftClientID = nil
        }
        value.curseForgeAPIKey = value.curseForgeAPIKey?.trimmed
        if value.curseForgeAPIKey?.isEmpty == true {
            value.curseForgeAPIKey = ProcessInfo.processInfo.environment["PCL_CURSEFORGE_API_KEY"]
        }
        value.nideServerID = value.nideServerID?.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.nideServerID?.isEmpty == true {
            value.nideServerID = nil
        }
        value.nideUsername = value.nideUsername?.trimmed
        if value.nideUsername?.isEmpty == true {
            value.nideUsername = nil
        }
        value.authlibServerURL = value.authlibServerURL?.trimmed
        if value.authlibServerURL?.isEmpty == true {
            value.authlibServerURL = nil
        }
        value.authlibUsername = value.authlibUsername?.trimmed
        if value.authlibUsername?.isEmpty == true {
            value.authlibUsername = nil
        }
        value.selectedInstallLoader = value.selectedInstallLoader?.trimmed ?? LauncherPreferences.defaults.selectedInstallLoader
        if !["原版", "Fabric", "Quilt", "Forge", "NeoForge"].contains(value.selectedInstallLoader ?? "原版") {
            value.selectedInstallLoader = LauncherPreferences.defaults.selectedInstallLoader
        }
        value.maxDownloadThreads = min(max(value.maxDownloadThreads, 1), 64)
        value.memoryLimit = min(max(value.memoryLimit, 1024), 16384)
        value.gameWindowWidth = min(max(value.gameWindowWidth, 320), 7680)
        value.gameWindowHeight = min(max(value.gameWindowHeight, 240), 4320)
        value.launchServerAddress = value.launchServerAddress?.trimmed
        if value.launchServerAddress?.isEmpty == true {
            value.launchServerAddress = nil
        }
        value.launchServerPort = Self.normalizedServerPort(value.launchServerPort)
        value.serverFavorites = Self.normalizedServerFavorites(value.serverFavorites)
        value.extraJvmArguments = value.extraJvmArguments.trimmed
        value.extraGameArguments = value.extraGameArguments.trimmed
        value.customMinecraftDirectoryPath = Self.normalizedDirectoryPath(value.customMinecraftDirectoryPath)
        value.localVersionQuery = value.localVersionQuery.trimmed
        if !LocalVersionFilter.allCases.map(\.rawValue).contains(value.localVersionFilter) {
            value.localVersionFilter = LauncherPreferences.defaults.localVersionFilter
        }
        value.favoriteInstanceNames = Self.normalizedInstanceNames(value.favoriteInstanceNames)
        let favoriteNames = Set(value.favoriteInstanceNames)
        value.hiddenInstanceNames = Self.normalizedInstanceNames(value.hiddenInstanceNames).filter { !favoriteNames.contains($0) }
        value.hiddenHomeCardIDs = Self.normalizedHomeCardIDs(value.hiddenHomeCardIDs)
        value.backgroundImagePath = value.backgroundImagePath?.trimmed
        if value.backgroundImagePath?.isEmpty == true {
            value.backgroundImagePath = nil
        }
        value.backgroundImageOpacity = min(max(value.backgroundImageOpacity, 0.08), 0.65)
        return value
    }

    private static func normalizedServerPort(_ port: String?) -> String? {
        guard let text = port?.trimmed, !text.isEmpty, let value = Int(text), (1...65535).contains(value) else {
            return nil
        }
        return "\(value)"
    }

    private static func normalizedInstanceNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for name in names {
            let trimmed = name.trimmed
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func normalizedHomeCardIDs(_ ids: [String]) -> [String] {
        let validIDs = Set(LauncherHomeCard.allCases.map(\.rawValue))
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids {
            let trimmed = id.trimmed
            guard validIDs.contains(trimmed), seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func normalizedServerFavorites(_ favorites: [LauncherServerFavorite]) -> [LauncherServerFavorite] {
        var seen: Set<LauncherServerFavorite.ID> = []
        var result: [LauncherServerFavorite] = []
        for favorite in favorites {
            guard let normalized = favorite.normalized, seen.insert(normalized.id).inserted else { continue }
            result.append(normalized)
        }
        return Array(result.prefix(50))
    }

    private static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmed, !trimmed.isEmpty else { return nil }
        let expanded: String
        if trimmed == "~" || trimmed.hasPrefix("~/") {
            expanded = NSString(string: trimmed).expandingTildeInPath
        } else {
            expanded = trimmed
        }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }
}

struct LauncherPreferencesStore: @unchecked Sendable {
    static let live = LauncherPreferencesStore()

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "pcl.mac.launcher.preferences"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> LauncherPreferences {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LauncherPreferences.self, from: data) else {
            return .defaults
        }
        return decoded.normalized
    }

    func save(_ preferences: LauncherPreferences) {
        guard let data = try? JSONEncoder().encode(preferences.normalized) else { return }
        userDefaults.set(data, forKey: key)
    }
}
