import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct PCLMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = LauncherModel(
        dockBadgeController: .live,
        notificationCenter: .live,
        preferenceSaveDelayNanoseconds: PCLMotion.preferenceSaveDelayNanoseconds
    )

    var body: some Scene {
        WindowGroup("Plain Craft Launcher (PCL) macOS") {
            LauncherRootView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
                .background(WindowConfigurator())
                .task {
                    await model.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase != .active else { return }
                    model.flushPendingPreferences()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("PCL") {
                Button("启动当前实例") {
                    Task { await model.launchSelectedInstance() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canLaunchSelectedInstance)

                Button("停止 Minecraft") {
                    model.stopGame()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.isLaunching)

                Divider()

                Button("刷新环境") {
                    Task { await model.refreshEnvironment() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("打开 Minecraft 文件夹") {
                    model.openMinecraftFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("打开当前实例文件夹") {
                    model.openSelectedInstanceFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(model.selectedInstance == nil)

                Divider()

                Button("导入实例备份...") {
                    model.chooseAndImportLocalInstanceArchive()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.isManagingInstance)

                Button("导出当前实例...") {
                    model.chooseAndExportSelectedInstance()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.selectedInstance == nil || model.isManagingInstance)

                Divider()

                Button("任务中心") {
                    model.showDownloadTasks()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("帮助文档") {
                    model.selectedMoreSection = .help
                    model.selectedPage = .more
                    model.openHelpDocument()
                }
                .keyboardShortcut("/", modifiers: [.command])
            }

            CommandMenu("页面") {
                Button("启动") {
                    model.selectedPage = .launch
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("下载") {
                    model.selectedPage = .download
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("联机") {
                    model.selectedPage = .link
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("设置") {
                    model.selectedPage = .settings
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("更多") {
                    model.selectedPage = .more
                }
                .keyboardShortcut("5", modifiers: [.command])

                Divider()

                Button("原版游戏下载") {
                    model.selectedDownloadSection = .vanilla
                    model.selectedPage = .download
                }

                Button("Mod 下载") {
                    model.selectedDownloadSection = .mods
                    model.selectedPage = .download
                }

                Button("整合包下载") {
                    model.selectedDownloadSection = .modpacks
                    model.selectedPage = .download
                }
            }
        }
    }
}

enum LauncherPage: String, CaseIterable, Identifiable {
    case launch
    case download
    case link
    case settings
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: "启动"
        case .download: "下载"
        case .link: "联机"
        case .settings: "设置"
        case .more: "更多"
        }
    }

    var systemImage: String {
        switch self {
        case .launch: "play.fill"
        case .download: "arrow.down.circle.fill"
        case .link: "wifi"
        case .settings: "gearshape.fill"
        case .more: "square.grid.2x2.fill"
        }
    }
}

private extension LauncherPage {
    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

private enum PageTransitionDirection {
    case forward
    case backward

    var insertionOffset: CGFloat {
        self == .forward ? 28 : -28
    }

    var removalOffset: CGFloat {
        self == .forward ? -14 : 14
    }
}

struct JavaInstallation: Identifiable, Hashable, Sendable {
    let id = UUID()
    let executable: URL
    let versionSummary: String
    let source: String
}

struct MinecraftInstance: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let path: URL
    let jsonURL: URL
    let type: String
    let releaseTime: String
}

private struct LocalVersionListCacheKey: Equatable {
    let instanceIDs: [MinecraftInstance.ID]
    let favoriteNames: [String]
    let hiddenNames: [String]
    let showsHiddenInstances: Bool
    let query: String
    let filter: LocalVersionFilter
}

private struct LocalVersionListSnapshot {
    let visibleInstances: [MinecraftInstance]
    let hiddenCount: Int
    let favoriteCount: Int
}

private struct RemoteVersionFilterCacheKey: Equatable {
    let versionIDs: [MinecraftRemoteVersion.ID]
    let filter: String
    let query: String
}

struct LaunchStatus: Sendable {
    var title: String
    var detail: String
    var progress: Double
}

struct LaunchReadiness: Equatable, Sendable {
    var isReady: Bool
    var title: String
    var detail: String
    var systemImage: String
}

struct DependencyProgressEntry: Identifiable, Hashable {
    enum State: String {
        case skipped = "已存在"
        case downloaded = "已下载"
    }

    let id = UUID()
    let state: State
    let name: String
    let finished: Int
    let total: Int
    let downloaded: Int
    let skipped: Int

    init(progress: MinecraftDownloadProgress) {
        state = progress.action == .downloaded ? .downloaded : .skipped
        name = progress.currentName
        finished = progress.finished
        total = progress.total
        downloaded = progress.downloaded
        skipped = progress.skipped
    }
}

enum DownloadSection: String, CaseIterable, Identifiable {
    case tasks = "任务"
    case vanilla = "原版游戏"
    case mods = "Mod"
    case modpacks = "整合包"
    case datapacks = "数据包"
    case resourcepacks = "资源包"
    case shaders = "光影包"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .tasks: "list.bullet.rectangle"
        case .vanilla: "cube.box.fill"
        case .mods: "puzzlepiece.extension.fill"
        case .modpacks: "shippingbox.fill"
        case .datapacks: "square.grid.3x3.fill"
        case .resourcepacks: "photo.fill"
        case .shaders: "sun.max.fill"
        }
    }

    var modrinthProjectType: ModrinthProjectType? {
        switch self {
        case .mods: .mod
        case .modpacks: .modpack
        case .datapacks: .datapack
        case .resourcepacks: .resourcepack
        case .shaders: .shader
        case .tasks, .vanilla: nil
        }
    }

    var curseForgeResourceType: CurseForgeResourceType? {
        switch self {
        case .mods: .mod
        case .modpacks: .modpack
        case .resourcepacks: .resourcePack
        case .tasks, .vanilla, .datapacks, .shaders: nil
        }
    }
}

enum DownloadTaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case running = "进行中"
    case succeeded = "已完成"
    case failed = "失败"
    case paused = "已暂停"
    case cancelled = "已取消"

    var id: String { rawValue }
}

enum DownloadTaskRetryAction: Hashable, Codable, Sendable {
    case installVersion(versionID: String, loader: String, downloadSource: String)
    case installJavaRuntime(component: String, downloadSource: String)
}

struct DownloadTaskRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var category: String
    var detail: String
    var status: DownloadTaskStatus
    var progress: Double?
    var destinationPath: String?
    var retryAction: DownloadTaskRetryAction?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        detail: String,
        status: DownloadTaskStatus = .running,
        progress: Double? = nil,
        destinationPath: String? = nil,
        retryAction: DownloadTaskRetryAction? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.detail = detail
        self.status = status
        self.progress = progress
        self.destinationPath = destinationPath
        self.retryAction = retryAction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isRetryable: Bool {
        retryAction != nil
    }

    var summaryText: String {
        var lines = [
            "名称：\(title)",
            "类型：\(category)",
            "状态：\(status.rawValue)",
            "进度：\(progress.map { "\(Int($0 * 100))%" } ?? "-")",
            "详情：\(detail)",
            "创建：\(createdAt.formatted(date: .numeric, time: .shortened))",
            "更新：\(updatedAt.formatted(date: .numeric, time: .shortened))"
        ]
        if let destinationPath {
            lines.append("位置：\(destinationPath)")
        }
        if let retryAction {
            lines.append("\(status == .paused ? "继续" : "重试")：\(retryAction.summaryText)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension DownloadTaskRetryAction {
    var summaryText: String {
        switch self {
        case .installVersion(let versionID, let loader, let downloadSource):
            "安装 \(loader) \(versionID)（\(downloadSource)）"
        case .installJavaRuntime(let component, let downloadSource):
            "安装 Java Runtime \(component)（\(downloadSource)）"
        }
    }
}

enum LinkSection: String, CaseIterable, Identifiable {
    case rooms = "房间"
    case connection = "连接"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .rooms: "person.2.fill"
        case .connection: "link"
        case .settings: "slider.horizontal.3"
        }
    }
}

private extension CurseForgeResourceType {
    var modrinthProjectType: ModrinthProjectType {
        switch self {
        case .mod: .mod
        case .modpack: .modpack
        case .resourcePack: .resourcepack
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case launch = "启动"
    case version = "版本"
    case system = "系统"
    case appearance = "界面"
    case download = "下载"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .launch: "play"
        case .version: "cube.box"
        case .system: "macwindow"
        case .appearance: "paintpalette"
        case .download: "arrow.down"
        }
    }
}

enum MoreSection: String, CaseIterable, Identifiable {
    case help = "帮助"
    case about = "关于"
    case logs = "日志"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .help: "questionmark.circle"
        case .about: "info.circle"
        case .logs: "doc.text"
        }
    }
}

enum LauncherAuthError: LocalizedError {
    case missingAccount
    case missingSecret
    case expiredMicrosoftSecretWithoutRefresh

    var errorDescription: String? {
        switch self {
        case .missingAccount:
            "请先登录账户"
        case .missingSecret:
            "Keychain 中没有找到该账户的登录凭据"
        case .expiredMicrosoftSecretWithoutRefresh:
            "Microsoft 登录已过期，请重新登录"
        }
    }
}

enum LauncherPreparationError: LocalizedError {
    case missingInstance
    case missingJava
    case incompatibleJava(required: Int, actual: Int, summary: String)

    var errorDescription: String? {
        switch self {
        case .missingInstance:
            "请先选择一个 Minecraft 实例"
        case .missingJava:
            "未找到可用 Java"
        case .incompatibleJava(let required, let actual, let summary):
            "当前版本需要 Java \(required)+，但将使用 \(summary)（Java \(actual)）。请安装更高版本 Java，或在版本设置中指定兼容 Java。"
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var selectedPage: LauncherPage = .launch
    @Published var selectedDownloadSection: DownloadSection = .vanilla {
        didSet { scheduleDownloadResourcePreparation() }
    }
    @Published var selectedLinkSection: LinkSection = .rooms
    @Published var selectedSettingsSection: SettingsSection = .launch
    @Published var selectedMoreSection: MoreSection = .about
    @Published var loginMode = "离线" { didSet { savePreferences() } }
    @Published var offlineUsername = "Player" { didSet { savePreferences() } }
    @Published var selectedAccountID: LauncherAccountProfile.ID? { didSet { savePreferences() } }
    @Published var accounts: [LauncherAccountProfile] = []
    @Published var accountVaultMessage = "账户保险箱未初始化"
    @Published var microsoftClientID = "" { didSet { savePreferences() } }
    @Published var microsoftDeviceCode: MicrosoftDeviceCode?
    @Published var isMicrosoftLoginInProgress = false
    @Published var nideServerID = "" { didSet { savePreferences() } }
    @Published var nideUsername = "" { didSet { savePreferences() } }
    @Published var nidePassword = ""
    @Published var isNideLoginInProgress = false
    @Published var authlibServerURL = "" { didSet { savePreferences() } }
    @Published var authlibUsername = "" { didSet { savePreferences() } }
    @Published var authlibPassword = ""
    @Published var isAuthlibLoginInProgress = false
    @Published var selectedInstanceID: MinecraftInstance.ID? {
        didSet {
            selectedInstanceLookupCache = nil
            selectedInstanceNamePreference = selectedInstance?.name ?? selectedInstanceNamePreference
            savePreferences()
            localModFiles = []
            selectedLocalModFileID = nil
            if selectedDownloadSection == .mods {
                Task { await refreshLocalMods() }
            }
            loadSelectedVersionSettings()
        }
    }
    @Published var selectedJavaID: JavaInstallation.ID? {
        didSet {
            selectedJavaPathPreference = selectedJava?.executable.path ?? selectedJavaPathPreference
            savePreferences()
        }
    }
    @Published var javaInstallations: [JavaInstallation] = []
    @Published var minecraftInstances: [MinecraftInstance] = [] {
        didSet { selectedInstanceLookupCache = nil }
    }
    @Published var favoriteInstanceNames: [String] = [] { didSet { savePreferences() } }
    @Published var hiddenInstanceNames: [String] = [] { didSet { savePreferences() } }
    @Published var showsHiddenInstances = false {
        didSet {
            savePreferences()
            restoreSelectedInstance()
        }
    }
    @Published var localVersionQuery = "" {
        didSet {
            savePreferences()
            restoreSelectedInstance()
        }
    }
    @Published var localVersionFilter = LocalVersionFilter.all.rawValue {
        didSet {
            savePreferences()
            restoreSelectedInstance()
        }
    }
    @Published var launchStatus = LaunchStatus(title: "正在加载", detail: "准备扫描本机环境", progress: 0.08)
    @Published var isScanning = false
    @Published var isPreparingLaunch = false
    @Published var isLaunching = false {
        didSet { updateDockBadge() }
    }
    @Published var isManagingInstance = false
    @Published var isInstallingJavaRuntime = false
    @Published var lastEvent = "启动器初始化中"
    @Published var launchCommandPreview = ""
    @Published var dependencyProgressEntries: [DependencyProgressEntry] = []
    @Published var versionSettings = VersionLaunchSettings.defaults {
        didSet { saveSelectedVersionSettingsIfNeeded() }
    }
    @Published var versionSettingsMessage = "选择版本后可调整版本级启动设置"
    @Published var downloadSource = "官方 + BMCLAPI" { didSet { savePreferences() } }
    @Published var selectedInstallLoader = "原版" { didSet { savePreferences() } }
    @Published var maxDownloadThreads = 32.0 { didSet { savePreferences() } }
    @Published var memoryLimit = 4096.0 { didSet { savePreferences() } }
    @Published var customMinecraftDirectoryPath: String? = nil { didSet { savePreferences() } }
    @Published var gameWindowWidth = LauncherPreferences.defaultGameWindowWidth { didSet { savePreferences() } }
    @Published var gameWindowHeight = LauncherPreferences.defaultGameWindowHeight { didSet { savePreferences() } }
    @Published var launchFullscreen = false { didSet { savePreferences() } }
    @Published var useVersionIsolation = true { didSet { savePreferences() } }
    @Published var launchServerAddress = "" { didSet { savePreferences() } }
    @Published var launchServerPort = "" { didSet { savePreferences() } }
    @Published var extraJvmArguments = "" { didSet { savePreferences() } }
    @Published var extraGameArguments = "" { didSet { savePreferences() } }
    @Published var serverFavorites: [LauncherServerFavorite] = [] { didSet { savePreferences() } }
    @Published var selectedServerFavoriteID: LauncherServerFavorite.ID?
    @Published var serverFavoriteDraftName = ""
    @Published var serverFavoriteDraftAddress = ""
    @Published var serverFavoriteDraftPort = ""
    @Published var hideLauncherOnGameStart = false { didSet { savePreferences() } }
    @Published var showLauncherOnGameExit = true { didSet { savePreferences() } }
    @Published var showNativeNotifications = false {
        didSet {
            savePreferences()
            if showNativeNotifications {
                Task { await requestNativeNotificationAuthorizationIfNeeded() }
            }
        }
    }
    @Published var showDockBadge = true {
        didSet {
            savePreferences()
            updateDockBadge()
        }
    }
    @Published var useHighPerformanceMode = true { didSet { savePreferences() } }
    @Published var autoSelectJava = true { didSet { savePreferences() } }
    @Published var themePreset = LauncherThemePreset.pclBlue.rawValue { didSet { savePreferences() } }
    @Published var appearanceMode = LauncherAppearanceMode.system.rawValue { didSet { savePreferences() } }
    @Published var showsHomeHint = true { didSet { savePreferences() } }
    @Published var hiddenHomeCardIDs: [String] = [] { didSet { savePreferences() } }
    @Published var backgroundImagePath: String? = nil { didSet { savePreferences() } }
    @Published var backgroundImageOpacity = 0.28 { didSet { savePreferences() } }
    @Published var remoteVersions: [MinecraftRemoteVersion] = []
    @Published var selectedRemoteVersionID: MinecraftRemoteVersion.ID?
    @Published var remoteVersionFilter = "release" { didSet { savePreferences() } }
    @Published var remoteVersionQuery = ""
    @Published var isLoadingRemoteVersions = false
    @Published var isInstallingVersion = false
    @Published var installMessage = "尚未加载版本列表"
    @Published var downloadTaskRecords: [DownloadTaskRecord] = [] {
        didSet { refreshDownloadTaskSummaryState() }
    }
    @Published var selectedDownloadTaskID: DownloadTaskRecord.ID?
    @Published private(set) var cancellableDownloadTaskIDs: Set<DownloadTaskRecord.ID> = []
    private(set) var activeDownloadTaskCount = 0
    private(set) var failedDownloadTaskCount = 0
    @Published var resourceProvider = "Modrinth" {
        didSet {
            savePreferences()
            scheduleDownloadResourcePreparation()
        }
    }
    @Published var modrinthQuery = "fabric api"
    @Published var modrinthResults: [ModrinthProject] = []
    @Published var selectedModrinthProjectID: ModrinthProject.ID? {
        didSet {
            if oldValue != selectedModrinthProjectID {
                resetModrinthVersionFilePreview()
            }
        }
    }
    @Published var isSearchingModrinth = false
    @Published var isInstallingModrinthMod = false
    @Published var modrinthMessage = "选择一个 Minecraft 实例后搜索 Modrinth"
    @Published var modrinthVersionFilePreviews: [ResourceVersionFilePreview] = []
    @Published var selectedModrinthVersionFileID: ResourceVersionFilePreview.ID?
    @Published var isLoadingModrinthVersionFiles = false
    @Published var modrinthVersionFilesMessage = "选择项目后查看版本文件"
    @Published var lastModrinthFileURL: URL?
    @Published var lastModrinthProjectTitle = ""
    @Published var lastModrinthPackPlan: ModrinthPackPlan?
    @Published var lastModrinthPackImportResult: ModrinthPackImportResult?
    @Published var curseForgeAPIKey = "" { didSet { savePreferences() } }
    @Published var curseForgeQuery = "fabric api"
    @Published var curseForgeResults: [CurseForgeProject] = []
    @Published var selectedCurseForgeProjectID: CurseForgeProject.ID? {
        didSet {
            if oldValue != selectedCurseForgeProjectID {
                resetCurseForgeFilePreview()
            }
        }
    }
    @Published var isSearchingCurseForge = false
    @Published var isInstallingCurseForgeResource = false
    @Published var curseForgeMessage = "配置 API Key 后搜索 CurseForge"
    @Published var curseForgeFilePreviews: [ResourceVersionFilePreview] = []
    @Published var selectedCurseForgeFileID: ResourceVersionFilePreview.ID?
    @Published var isLoadingCurseForgeFiles = false
    @Published var curseForgeFilesMessage = "选择项目后查看版本文件"
    @Published var lastCurseForgeFileURL: URL?
    @Published var lastCurseForgeProjectTitle = ""
    @Published var lastCurseForgePackPlan: CurseForgePackPlan?
    @Published var lastCurseForgePackImportResult: CurseForgePackImportResult?
    @Published var aboutMessage = "当前应用身份信息已准备好。"
    @Published var helpMessage = "帮助文档会随应用打包，也可以从这里直接打开。"
    @Published var linkMessage = "局域网联机助手已准备好；在游戏内开启局域网世界后，可把本机地址发给同伴。"
    @Published var localNetworkAddresses: [String] = []
    @Published var lanWorlds: [MinecraftLANWorld] = []
    @Published var selectedLANWorldID: MinecraftLANWorld.ID?
    @Published var isScanningLANWorlds = false
    @Published var localModFiles: [LocalModFile] = []
    @Published var selectedLocalModFileID: LocalModFile.ID?
    @Published var isLoadingLocalMods = false
    @Published var localModMessage = "选择实例后刷新本地 Mod"
    @Published var minecraftLogEntries: [MinecraftLogEntry] = []
    @Published var selectedMinecraftLogID: MinecraftLogEntry.ID? {
        didSet { updateSelectedMinecraftLogPreview() }
    }
    @Published var selectedMinecraftLogPreview = ""
    @Published var selectedMinecraftLogDiagnoses: [MinecraftLogDiagnosis] = []
    @Published var minecraftLogMessage = "刷新后可查看 Minecraft 日志和崩溃报告"
    @Published var isLoadingMinecraftLogs = false

    let paths = MacPlatformPaths()
    private let preferencesStore: LauncherPreferencesStore
    private let accountStore: LauncherAccountStore
    private let downloadTaskHistoryStore: DownloadTaskHistoryStore
    private let dockBadgeController: LauncherDockBadgeController
    private let notificationCenter: LauncherNotificationCenter
    private let launchCommandPreviewLimit = 2_400
    private var activeModrinthProjectType: ModrinthProjectType = .mod
    private var activeCurseForgeResourceType: CurseForgeResourceType = .mod
    private var selectedInstanceNamePreference: String?
    private var selectedJavaPathPreference: String?
    private var gameProcess: Process?
    private var gameLaunchStartedAt: Date?
    private var gameLaunchInstanceName = ""
    private var didRequestGameStop = false
    private var didHideLauncherForGame = false
    private var loadedModrinthVersionFilesKey: String?
    private var loadedCurseForgeFilesKey: String?
    private var loadedModrinthVersions: [ModrinthVersion] = []
    private var loadedCurseForgeFiles: [CurseForgeFile] = []
    private var activeDownloadTaskOperations: [DownloadTaskRecord.ID: Task<Void, Never>] = [:]
    private var downloadResourcePreparationTask: Task<Void, Never>?
    private var preferenceSaveTask: Task<Void, Never>?
    private var didRequestNativeNotificationAuthorization = false
    private let preferenceSaveDelayNanoseconds: UInt64?
    private let versionSettingsStore = VersionLaunchSettingsStore()
    private var isLoadingVersionSettings = false
    private var versionSettingsCache: [String: VersionLaunchSettings] = [:]
    private var requiredJavaMajorVersionCache: [String: Int] = [:]
    private var noRequiredJavaMajorVersionCache: Set<String> = []
    private var selectedInstanceLookupCache: (id: MinecraftInstance.ID?, count: Int, instance: MinecraftInstance?)?
    private var localVersionListCache: (key: LocalVersionListCacheKey, snapshot: LocalVersionListSnapshot)?
    private var filteredRemoteVersionsCache: (key: RemoteVersionFilterCacheKey, versions: [MinecraftRemoteVersion])?

    init(
        preferencesStore: LauncherPreferencesStore = .live,
        accountStore: LauncherAccountStore = .live,
        downloadTaskHistoryStore: DownloadTaskHistoryStore = .live,
        dockBadgeController: LauncherDockBadgeController = .disabled,
        notificationCenter: LauncherNotificationCenter = .disabled,
        preferenceSaveDelayNanoseconds: UInt64? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.accountStore = accountStore
        self.downloadTaskHistoryStore = downloadTaskHistoryStore
        self.dockBadgeController = dockBadgeController
        self.notificationCenter = notificationCenter
        self.preferenceSaveDelayNanoseconds = preferenceSaveDelayNanoseconds
        let preferences = preferencesStore.load()
        loginMode = preferences.loginMode
        offlineUsername = preferences.offlineUsername
        selectedAccountID = preferences.selectedAccountID
        microsoftClientID = preferences.microsoftClientID ?? ""
        nideServerID = preferences.nideServerID ?? ""
        nideUsername = preferences.nideUsername ?? ""
        authlibServerURL = preferences.authlibServerURL ?? ""
        authlibUsername = preferences.authlibUsername ?? ""
        selectedInstanceNamePreference = preferences.selectedInstanceName
        selectedJavaPathPreference = preferences.selectedJavaPath
        localVersionQuery = preferences.localVersionQuery
        localVersionFilter = preferences.localVersionFilter
        favoriteInstanceNames = preferences.favoriteInstanceNames
        hiddenInstanceNames = preferences.hiddenInstanceNames
        showsHiddenInstances = preferences.showsHiddenInstances
        downloadSource = preferences.downloadSource
        resourceProvider = preferences.resourceProvider ?? "Modrinth"
        curseForgeAPIKey = preferences.curseForgeAPIKey ?? ""
        selectedInstallLoader = preferences.selectedInstallLoader ?? "原版"
        maxDownloadThreads = preferences.maxDownloadThreads
        memoryLimit = preferences.memoryLimit
        customMinecraftDirectoryPath = preferences.customMinecraftDirectoryPath
        gameWindowWidth = preferences.gameWindowWidth
        gameWindowHeight = preferences.gameWindowHeight
        launchFullscreen = preferences.launchFullscreen
        useVersionIsolation = preferences.useVersionIsolation
        launchServerAddress = preferences.launchServerAddress ?? ""
        launchServerPort = preferences.launchServerPort ?? ""
        extraJvmArguments = preferences.extraJvmArguments
        extraGameArguments = preferences.extraGameArguments
        serverFavorites = preferences.serverFavorites
        selectedServerFavoriteID = preferences.serverFavorites.first?.id
        hideLauncherOnGameStart = preferences.hideLauncherOnGameStart
        showLauncherOnGameExit = preferences.showLauncherOnGameExit
        showNativeNotifications = preferences.showNativeNotifications
        showDockBadge = preferences.showDockBadge
        useHighPerformanceMode = preferences.useHighPerformanceMode
        autoSelectJava = preferences.autoSelectJava
        remoteVersionFilter = preferences.remoteVersionFilter
        themePreset = preferences.themePreset
        appearanceMode = preferences.appearanceMode
        showsHomeHint = preferences.showsHomeHint
        hiddenHomeCardIDs = preferences.hiddenHomeCardIDs
        backgroundImagePath = preferences.backgroundImagePath
        backgroundImageOpacity = preferences.backgroundImageOpacity
        downloadTaskRecords = downloadTaskHistoryStore.load()
        selectedDownloadTaskID = downloadTaskRecords.first?.id
        refreshDownloadTaskSummaryState()
    }

    var selectedInstance: MinecraftInstance? {
        if let cached = selectedInstanceLookupCache,
           cached.id == selectedInstanceID,
           cached.count == minecraftInstances.count {
            return cached.instance
        }
        let instance = minecraftInstances.first { $0.id == selectedInstanceID }
        selectedInstanceLookupCache = (selectedInstanceID, minecraftInstances.count, instance)
        return instance
    }

    var minecraftDirectory: URL {
        if let path = customMinecraftDirectoryPath?.trimmed.nonEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return paths.minecraftDirectory
    }

    var isUsingCustomMinecraftDirectory: Bool {
        customMinecraftDirectoryPath?.trimmed.nonEmpty != nil
    }

    var visibleMinecraftInstances: [MinecraftInstance] {
        localVersionListSnapshot.visibleInstances
    }

    var hiddenMinecraftInstanceCount: Int {
        localVersionListSnapshot.hiddenCount
    }

    var favoriteMinecraftInstanceCount: Int {
        localVersionListSnapshot.favoriteCount
    }

    var selectedInstanceIsFavorite: Bool {
        selectedInstance.map(isFavoriteInstance) ?? false
    }

    var selectedInstanceIsHidden: Bool {
        selectedInstance.map(isHiddenInstance) ?? false
    }

    var selectedLocalVersionFilter: LocalVersionFilter {
        LocalVersionFilter(rawValue: localVersionFilter) ?? .all
    }

    var localVersionFilterBadgeTitle: String? {
        let filter = selectedLocalVersionFilter
        guard filter != .all else { return nil }
        return filter.rawValue
    }

    private var localVersionListSnapshot: LocalVersionListSnapshot {
        let key = LocalVersionListCacheKey(
            instanceIDs: minecraftInstances.map(\.id),
            favoriteNames: favoriteInstanceNames,
            hiddenNames: hiddenInstanceNames,
            showsHiddenInstances: showsHiddenInstances,
            query: localVersionQuery.trimmed,
            filter: selectedLocalVersionFilter
        )
        if let cached = localVersionListCache, cached.key == key {
            return cached.snapshot
        }

        let favoriteRanks = Dictionary(uniqueKeysWithValues: favoriteInstanceNames.enumerated().map { ($0.element, $0.offset) })
        let favoriteNames = Set(favoriteInstanceNames)
        let hiddenNames = Set(hiddenInstanceNames)
        let sortedInstances = minecraftInstances.sorted { left, right in
            let leftFavoriteRank = favoriteRanks[left.name] ?? Int.max
            let rightFavoriteRank = favoriteRanks[right.name] ?? Int.max
            if leftFavoriteRank != rightFavoriteRank {
                return leftFavoriteRank < rightFavoriteRank
            }

            let leftHidden = hiddenNames.contains(left.name)
            let rightHidden = hiddenNames.contains(right.name)
            if leftHidden != rightHidden {
                return !leftHidden && rightHidden
            }

            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
        let visibleInstances = sortedInstances.filter { instance in
            guard key.showsHiddenInstances || !hiddenNames.contains(instance.name) else { return false }
            guard matchesLocalVersionFilter(instance, filter: key.filter, favoriteNames: favoriteNames) else { return false }
            guard !key.query.isEmpty else { return true }
            return instance.name.localizedCaseInsensitiveContains(key.query)
                || instance.type.localizedCaseInsensitiveContains(key.query)
                || localVersionLoaderDisplay(for: instance).localizedCaseInsensitiveContains(key.query)
                || localVersionMetadataTypeDisplay(for: instance).localizedCaseInsensitiveContains(key.query)
                || localVersionKindDisplay(for: instance).localizedCaseInsensitiveContains(key.query)
                || instance.path.path.localizedCaseInsensitiveContains(key.query)
        }
        let snapshot = LocalVersionListSnapshot(
            visibleInstances: visibleInstances,
            hiddenCount: minecraftInstances.filter { hiddenNames.contains($0.name) }.count,
            favoriteCount: minecraftInstances.filter { favoriteNames.contains($0.name) }.count
        )
        localVersionListCache = (key, snapshot)
        return snapshot
    }

    private func matchesLocalVersionFilter(_ instance: MinecraftInstance) -> Bool {
        matchesLocalVersionFilter(instance, filter: selectedLocalVersionFilter, favoriteNames: Set(favoriteInstanceNames))
    }

    private func matchesLocalVersionFilter(
        _ instance: MinecraftInstance,
        filter: LocalVersionFilter,
        favoriteNames: Set<String>
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .favorites:
            return favoriteNames.contains(instance.name)
        case .vanilla:
            return inferredLocalLoader(for: instance) == nil
        case .fabric:
            return inferredLocalLoader(for: instance) == "fabric"
        case .forge:
            return inferredLocalLoader(for: instance) == "forge"
        case .quilt:
            return inferredLocalLoader(for: instance) == "quilt"
        case .neoForge:
            return inferredLocalLoader(for: instance) == "neoforge"
        }
    }

    private func inferredLocalLoader(for instance: MinecraftInstance) -> String? {
        inferLoader(from: instance.name)
    }

    func localVersionLoaderDisplay(for instance: MinecraftInstance) -> String {
        switch inferredLocalLoader(for: instance) {
        case "fabric":
            return "Fabric"
        case "forge":
            return "Forge"
        case "quilt":
            return "Quilt"
        case "neoforge":
            return "NeoForge"
        default:
            return "原版"
        }
    }

    func localVersionMetadataTypeDisplay(for instance: MinecraftInstance) -> String {
        switch instance.type {
        case "release":
            return "正式版"
        case "snapshot":
            return "快照版"
        case "old_alpha":
            return "远古 Alpha"
        case "old_beta":
            return "远古 Beta"
        case "":
            return "未知"
        default:
            return instance.type
        }
    }

    func localVersionKindDisplay(for instance: MinecraftInstance) -> String {
        "\(localVersionLoaderDisplay(for: instance)) · \(localVersionMetadataTypeDisplay(for: instance))"
    }

    func localVersionLoaderSystemImage(for instance: MinecraftInstance) -> String {
        switch inferredLocalLoader(for: instance) {
        case "fabric", "quilt":
            return "puzzlepiece.extension"
        case "forge", "neoforge":
            return "hammer"
        default:
            return "cube.box"
        }
    }

    var selectedInstanceGameDirectoryText: String {
        guard let selectedInstance else { return "未选择版本" }
        return effectiveVersionIsolation ? selectedInstance.path.path : minecraftDirectory.path
    }

    var selectedInstanceWindowText: String {
        let size = "\(Int(effectiveVersionWindowWidth)) × \(Int(effectiveVersionWindowHeight))"
        return effectiveVersionFullscreen ? "\(size)，全屏" : size
    }

    var selectedInstanceSummaryText: String {
        guard let selectedInstance else { return "未选择 Minecraft 实例" }
        return [
            "名称：\(selectedInstance.name)",
            "类型：\(localVersionKindDisplay(for: selectedInstance))",
            "版本目录：\(selectedInstance.path.path)",
            "版本 JSON：\(selectedInstance.jsonURL.path)",
            "游戏目录：\(selectedInstanceGameDirectoryText)",
            "Java 要求：\(selectedInstanceJavaRequirementText)",
            "启动 Java：\(effectiveJavaSummary)",
            "Java 路径：\(effectiveJavaDetail)",
            "内存：\(Int(effectiveVersionMemory)) MB",
            "窗口：\(selectedInstanceWindowText)",
            "自动进服：\(launchServerTargetText)（\(launchServerTargetScopeText)）"
        ].joined(separator: "\n")
    }

    var launchAccountSummaryText: String {
        switch loginMode {
        case "离线":
            return "离线：\(offlineUsername.trimmed.nonEmpty ?? "Player")"
        case "正版":
            return accountSummary(for: .microsoft, missingText: "未选择 Microsoft 账户")
        case "统一通行证":
            return accountSummary(for: .nide, missingText: "未选择统一通行证账户")
        case "Authlib":
            return accountSummary(for: .authlib, missingText: "未选择 Authlib 账户")
        default:
            return selectedAccount.map { "\($0.kind.displayName)：\($0.displayName)" } ?? "未保存账户"
        }
    }

    var launchReadiness: LaunchReadiness {
        if isScanning {
            return LaunchReadiness(isReady: false, title: "正在扫描", detail: "正在扫描版本和 Java 环境", systemImage: "arrow.clockwise")
        }
        if isPreparingLaunch {
            return LaunchReadiness(isReady: false, title: "正在准备", detail: "依赖补全或启动命令正在生成", systemImage: "bolt.horizontal")
        }
        if isLaunching {
            return LaunchReadiness(isReady: false, title: "游戏运行中", detail: "当前已有 Minecraft 进程在运行", systemImage: "play.circle")
        }
        guard let selectedInstance else {
            return LaunchReadiness(isReady: false, title: "未选择版本", detail: "请先选择一个 Minecraft 版本", systemImage: "cube.transparent")
        }
        guard let javaURL = effectiveJavaURL(for: selectedInstance) else {
            return LaunchReadiness(isReady: false, title: "缺少 Java", detail: "请安装 Java 或在版本设置中指定 Java", systemImage: "cup.and.saucer")
        }
        guard FileManager.default.isExecutableFile(atPath: javaURL.path) else {
            return LaunchReadiness(isReady: false, title: "Java 不可执行", detail: javaURL.path, systemImage: "exclamationmark.triangle")
        }
        if let javaCompatibilityError = javaCompatibilityError(for: selectedInstance, javaExecutable: javaURL) {
            return LaunchReadiness(
                isReady: false,
                title: "Java 版本过低",
                detail: javaCompatibilityError.localizedDescription,
                systemImage: "exclamationmark.triangle"
            )
        }
        if let expectedKind = expectedLaunchAccountKind, selectedLaunchAccount == nil {
            return LaunchReadiness(isReady: false, title: "需要登录", detail: "请先登录或选择 \(expectedKind.displayName) 账户", systemImage: "person.crop.circle.badge.exclamationmark")
        }
        return LaunchReadiness(isReady: true, title: "可以启动", detail: "配置完整，点击启动游戏", systemImage: "checkmark.circle.fill")
    }

    var canLaunchSelectedInstance: Bool {
        launchReadiness.isReady
    }

    var dependencyPreparationReadiness: LaunchReadiness {
        if isScanning {
            return LaunchReadiness(isReady: false, title: "正在扫描", detail: "正在扫描版本和 Java 环境", systemImage: "arrow.clockwise")
        }
        if isPreparingLaunch {
            return LaunchReadiness(isReady: false, title: "正在准备", detail: "依赖补全正在进行", systemImage: "bolt.horizontal")
        }
        if isLaunching {
            return LaunchReadiness(isReady: false, title: "游戏运行中", detail: "当前已有 Minecraft 进程在运行", systemImage: "play.circle")
        }
        guard let selectedInstance else {
            return LaunchReadiness(isReady: false, title: "未选择版本", detail: "请先选择一个 Minecraft 版本", systemImage: "cube.transparent")
        }
        guard let javaURL = effectiveJavaURL(for: selectedInstance) else {
            return LaunchReadiness(isReady: false, title: "缺少 Java", detail: "请安装 Java 或在版本设置中指定 Java", systemImage: "cup.and.saucer")
        }
        guard FileManager.default.isExecutableFile(atPath: javaURL.path) else {
            return LaunchReadiness(isReady: false, title: "Java 不可执行", detail: javaURL.path, systemImage: "exclamationmark.triangle")
        }
        return LaunchReadiness(isReady: true, title: "可以预补全", detail: "可提前下载 client、libraries、natives 和 assets", systemImage: "arrow.down.doc.fill")
    }

    var canPrepareSelectedInstanceDependencies: Bool {
        dependencyPreparationReadiness.isReady
    }

    var selectedLaunchConfigurationSummaryText: String {
        guard let selectedInstance else { return "未选择 Minecraft 实例" }
        let extraJvmArguments = effectiveExtraJvmArgumentList(for: selectedInstance).joined(separator: " ").nonEmpty ?? "无"
        let extraGameArguments = effectiveExtraGameArgumentList(for: selectedInstance).joined(separator: " ").nonEmpty ?? "无"
        return [
            "版本：\(selectedInstance.name)",
            "就绪检查：\(launchReadiness.detail)",
            "登录：\(launchAccountSummaryText)",
            "Java 要求：\(selectedInstanceJavaRequirementText)",
            "启动 Java：\(effectiveJavaSummary)",
            "Java 路径：\(effectiveJavaDetail)",
            "内存：\(Int(effectiveVersionMemory)) MB",
            "窗口：\(selectedInstanceWindowText)",
            "游戏目录：\(selectedInstanceGameDirectoryText)",
            "版本隔离：\(effectiveVersionIsolation ? "版本目录" : "Minecraft 根目录")",
            "自动进服：\(launchServerTargetText)（\(launchServerTargetScopeText)）",
            "额外 JVM 参数：\(extraJvmArguments)",
            "额外游戏参数：\(extraGameArguments)"
        ].joined(separator: "\n")
    }

    var selectedJava: JavaInstallation? {
        if let selectedJavaID,
           let java = javaInstallations.first(where: { $0.id == selectedJavaID }) {
            return java
        }
        return javaInstallations.first
    }

    var selectedAccount: LauncherAccountProfile? {
        if let selectedAccountID,
           let account = accounts.first(where: { $0.id == selectedAccountID }) {
            return account
        }
        return accounts.first
    }

    var selectedLaunchAccount: LauncherAccountProfile? {
        guard let expectedLaunchAccountKind else { return nil }
        if let account = selectedAccount, account.kind == expectedLaunchAccountKind {
            return account
        }
        return accounts.first { $0.kind == expectedLaunchAccountKind }
    }

    var launchModeAccounts: [LauncherAccountProfile] {
        guard let accountKind = launchModeAccountKind else { return accounts }
        return accounts.filter { $0.kind == accountKind }
    }

    var selectedLaunchModeAccount: LauncherAccountProfile? {
        guard let accountKind = launchModeAccountKind else { return selectedAccount }
        if let account = selectedAccount, account.kind == accountKind {
            return account
        }
        return accounts.first { $0.kind == accountKind }
    }

    var selectedLaunchModeAccountID: LauncherAccountProfile.ID? {
        get { selectedLaunchModeAccount?.id }
        set { selectedAccountID = newValue }
    }

    private var expectedLaunchAccountKind: LauncherAccountKind? {
        switch loginMode {
        case "正版":
            return .microsoft
        case "统一通行证":
            return .nide
        case "Authlib":
            return .authlib
        default:
            return nil
        }
    }

    private var launchModeAccountKind: LauncherAccountKind? {
        if loginMode == "离线" {
            return .offline
        }
        return expectedLaunchAccountKind
    }

    private func accountSummary(for kind: LauncherAccountKind, missingText: String) -> String {
        let account = selectedLaunchAccount ?? accounts.first { $0.kind == kind }
        guard let account, account.kind == kind else {
            return missingText
        }
        return "\(kind.displayName)：\(account.displayName)"
    }

    var filteredRemoteVersions: [MinecraftRemoteVersion] {
        let query = remoteVersionQuery.trimmed
        let key = RemoteVersionFilterCacheKey(
            versionIDs: remoteVersions.map(\.id),
            filter: remoteVersionFilter,
            query: query
        )
        if let cached = filteredRemoteVersionsCache, cached.key == key {
            return cached.versions
        }
        let versions = remoteVersions.filter { version in
            let typeMatches = remoteVersionFilter == "all" || version.type == remoteVersionFilter
            let queryMatches = query.isEmpty || version.id.localizedCaseInsensitiveContains(query)
            return typeMatches && queryMatches
        }
        filteredRemoteVersionsCache = (key, versions)
        return versions
    }

    var selectedRemoteVersion: MinecraftRemoteVersion? {
        if let selectedRemoteVersionID,
           let version = remoteVersions.first(where: { $0.id == selectedRemoteVersionID }) {
            return version
        }
        return filteredRemoteVersions.first
    }

    var selectedModrinthProject: ModrinthProject? {
        if let selectedModrinthProjectID,
           let project = modrinthResults.first(where: { $0.id == selectedModrinthProjectID }) {
            return project
        }
        return modrinthResults.first
    }

    var selectedCurseForgeProject: CurseForgeProject? {
        if let selectedCurseForgeProjectID,
           let project = curseForgeResults.first(where: { $0.id == selectedCurseForgeProjectID }) {
            return project
        }
        return curseForgeResults.first
    }

    var selectedLocalModFile: LocalModFile? {
        if let selectedLocalModFileID,
           let file = localModFiles.first(where: { $0.id == selectedLocalModFileID }) {
            return file
        }
        return localModFiles.first
    }

    var selectedMinecraftLogEntry: MinecraftLogEntry? {
        if let selectedMinecraftLogID,
           let entry = minecraftLogEntries.first(where: { $0.id == selectedMinecraftLogID }) {
            return entry
        }
        return minecraftLogEntries.first
    }

    var selectedLANWorld: MinecraftLANWorld? {
        if let selectedLANWorldID,
           let world = lanWorlds.first(where: { $0.id == selectedLANWorldID }) {
            return world
        }
        return lanWorlds.first
    }

    var selectedServerFavorite: LauncherServerFavorite? {
        if let selectedServerFavoriteID,
           let favorite = serverFavorites.first(where: { $0.id == selectedServerFavoriteID }) {
            return favorite
        }
        return serverFavorites.first
    }

    var versionSettingsJavaPath: String? {
        versionSettings.javaExecutablePath ?? selectedJava?.executable.path
    }

    var selectedInstanceJavaRequirementText: String {
        guard let selectedInstance else { return "未选择版本" }
        guard let major = requiredJavaMajorVersion(for: selectedInstance) else { return "未声明" }
        return "Java \(major)+"
    }

    var effectiveJavaSummary: String {
        guard let selectedInstance else { return "未选择版本" }
        let settings = activeVersionSettings(for: selectedInstance)
        if !settings.usesGlobalJava,
           let path = settings.javaExecutablePath?.trimmed.nonEmpty {
            let javaURL = URL(fileURLWithPath: path)
            if let java = javaInstallation(matching: javaURL) {
                return "版本指定：\(java.versionSummary)"
            }
            return "版本指定：\(javaURL.lastPathComponent)"
        }
        guard let java = effectiveJavaInstallation(for: selectedInstance, settings: settings) else {
            return "未找到可用 Java"
        }
        if autoSelectJava {
            return "自动：\(java.versionSummary)"
        }
        return "手动：\(java.versionSummary)"
    }

    var effectiveJavaDetail: String {
        guard let selectedInstance else { return "先选择一个 Minecraft 版本" }
        let settings = activeVersionSettings(for: selectedInstance)
        if !settings.usesGlobalJava,
           let path = settings.javaExecutablePath?.trimmed.nonEmpty {
            return path
        }
        guard let java = effectiveJavaInstallation(for: selectedInstance, settings: settings) else {
            return "当前没有可用于启动的 Java"
        }
        return "\(java.source) · \(java.executable.path)"
    }

    var effectiveJavaCompatibilityMessage: String? {
        guard let selectedInstance,
              let javaURL = effectiveJavaURL(for: selectedInstance),
              let error = javaCompatibilityError(for: selectedInstance, javaExecutable: javaURL) else {
            return nil
        }
        return error.localizedDescription
    }

    var recommendedCompatibleJava: JavaInstallation? {
        guard let selectedInstance,
              let requiredMajorVersion = requiredJavaMajorVersion(for: selectedInstance) else {
            return nil
        }
        return compatibleJavaInstallation(requiredMajorVersion: requiredMajorVersion)
    }

    var recommendedJavaRuntimeMajorVersion: Int? {
        guard let selectedInstance else { return nil }
        return requiredJavaMajorVersion(for: selectedInstance)
    }

    var recommendedJavaRuntimeComponent: String? {
        guard let selectedInstance else { return nil }
        return requiredJavaRuntimeComponent(for: selectedInstance)
    }

    var canInstallRecommendedJavaRuntime: Bool {
        effectiveJavaCompatibilityMessage != nil
            && recommendedCompatibleJava == nil
            && recommendedJavaRuntimeComponent != nil
            && !isInstallingJavaRuntime
    }

    var recommendedJavaRuntimeInstallButtonTitle: String {
        guard let major = recommendedJavaRuntimeMajorVersion else { return "安装兼容 Java" }
        return "安装 Java \(major)+"
    }

    var selectedJavaDiagnosticSummaryText: String {
        [
            "版本：\(selectedInstance?.name ?? "未选择")",
            "Java 要求：\(selectedInstanceJavaRequirementText)",
            "启动将使用：\(effectiveJavaSummary)",
            "Java 路径：\(effectiveJavaDetail)",
            "就绪状态：\(launchReadiness.title)",
            "详情：\(launchReadiness.detail)",
            "可用 Java：",
            javaInstallations.isEmpty
                ? "  - 未发现"
                : javaInstallations.map { "  - \($0.versionSummary) · \($0.source) · \($0.executable.path)" }.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    var microsoftClientIDResolution: MicrosoftOAuthClientIDResolution {
        MicrosoftOAuthClientIDResolver(settingsClientID: microsoftClientID).resolve()
    }

    var effectiveMicrosoftClientID: String {
        microsoftClientIDResolution.clientID
    }

    var microsoftClientIDStatusText: String {
        let resolution = microsoftClientIDResolution
        guard let source = resolution.source else {
            return "未配置"
        }
        return "使用\(source.displayName)"
    }

    var microsoftClientIDDetailText: String {
        let resolution = microsoftClientIDResolution
        guard let source = resolution.source else {
            return "正式包可内置 Microsoft 授权；开发构建可设置 PCL_MS_CLIENT_ID，或在这里填写高级覆盖。"
        }
        switch source {
        case .settings:
            return "当前使用设置页填写的高级覆盖值。"
        case .environment:
            return "当前使用运行环境中的 PCL_MS_CLIENT_ID。"
        case .bundle:
            return "当前使用 app 包内置的正版登录授权。"
        }
    }

    var effectiveVersionMemory: Double {
        guard !versionSettings.usesGlobalMemory else { return memoryLimit }
        return versionSettings.memoryMegabytes ?? memoryLimit
    }

    var effectiveVersionWindowWidth: Double {
        guard !versionSettings.usesGlobalWindow else { return gameWindowWidth }
        return versionSettings.windowWidth ?? gameWindowWidth
    }

    var effectiveVersionWindowHeight: Double {
        guard !versionSettings.usesGlobalWindow else { return gameWindowHeight }
        return versionSettings.windowHeight ?? gameWindowHeight
    }

    var effectiveVersionFullscreen: Bool {
        guard !versionSettings.usesGlobalWindow else { return launchFullscreen }
        return versionSettings.fullscreen ?? launchFullscreen
    }

    var effectiveVersionIsolation: Bool {
        guard !versionSettings.usesGlobalGameDirectory else { return useVersionIsolation }
        return versionSettings.usesIsolatedGameDirectory ?? useVersionIsolation
    }

    var effectiveVersionServerAddress: String {
        guard !versionSettings.usesGlobalServer else { return launchServerAddress }
        return versionSettings.serverAddress ?? ""
    }

    var effectiveVersionServerPort: String {
        guard !versionSettings.usesGlobalServer else { return launchServerPort }
        return versionSettings.serverPort ?? ""
    }

    var launchServerTargetText: String {
        let address = effectiveVersionServerAddress.trimmed
        guard !address.isEmpty else { return "未设置" }
        let port = effectiveVersionServerPort.trimmed
        if port.isEmpty {
            return address
        }
        return "\(address):\(port)"
    }

    var launchServerTargetScopeText: String {
        versionSettings.usesGlobalServer ? "使用全局自动进服" : "当前版本覆盖"
    }

    var globalExtraJvmArgumentList: [String] {
        VersionLaunchSettings.splitArguments(extraJvmArguments)
    }

    var globalExtraGameArgumentList: [String] {
        VersionLaunchSettings.splitArguments(extraGameArguments)
    }

    var selectedEffectiveExtraJvmArgumentList: [String] {
        guard let selectedInstance else {
            return effectiveExtraJvmArgumentList(settings: versionSettings)
        }
        return effectiveExtraJvmArgumentList(for: selectedInstance)
    }

    var selectedEffectiveExtraGameArgumentList: [String] {
        guard let selectedInstance else {
            return effectiveExtraGameArgumentList(settings: versionSettings)
        }
        return effectiveExtraGameArgumentList(for: selectedInstance)
    }

    var selectedEffectiveExtraArgumentsSummaryText: String {
        let jvmCount = selectedEffectiveExtraJvmArgumentList.count
        let gameCount = selectedEffectiveExtraGameArgumentList.count
        guard jvmCount > 0 || gameCount > 0 else { return "无" }
        return "JVM \(jvmCount) 项，游戏 \(gameCount) 项"
    }

    var effectiveCurseForgeAPIKey: String {
        curseForgeAPIKey.trimmed.nonEmpty ?? ProcessInfo.processInfo.environment["PCL_CURSEFORGE_API_KEY"]?.trimmed.nonEmpty ?? ""
    }

    var hasCurseForgeAPIKey: Bool {
        !effectiveCurseForgeAPIKey.isEmpty
    }

    var launchCommandPreviewDisplay: String {
        guard let cutoff = launchCommandPreview.index(
            launchCommandPreview.startIndex,
            offsetBy: launchCommandPreviewLimit,
            limitedBy: launchCommandPreview.endIndex
        ), cutoff < launchCommandPreview.endIndex else {
            return launchCommandPreview
        }
        return "\(launchCommandPreview[..<cutoff])\n..."
    }

    var isLaunchCommandPreviewTruncated: Bool {
        guard let cutoff = launchCommandPreview.index(
            launchCommandPreview.startIndex,
            offsetBy: launchCommandPreviewLimit,
            limitedBy: launchCommandPreview.endIndex
        ) else {
            return false
        }
        return cutoff < launchCommandPreview.endIndex
    }

    var currentLaunchReadinessStatus: LaunchStatus {
        if isScanning || isPreparingLaunch || isLaunching {
            return launchStatus
        }
        let readiness = launchReadiness
        return LaunchStatus(
            title: readiness.title,
            detail: readiness.detail,
            progress: readiness.isReady ? 1 : 0
        )
    }

    var latestDependencyProgress: DependencyProgressEntry? {
        dependencyProgressEntries.first
    }

    var selectedDownloadTask: DownloadTaskRecord? {
        if let selectedDownloadTaskID,
           let record = downloadTaskRecords.first(where: { $0.id == selectedDownloadTaskID }) {
            return record
        }
        return downloadTaskRecords.first
    }

    var canRetrySelectedDownloadTask: Bool {
        guard let task = selectedDownloadTask else { return false }
        return task.status.isRecoverable && task.isRetryable && !isInstallingVersion && !isInstallingJavaRuntime
    }

    var canPauseSelectedDownloadTask: Bool {
        guard let task = selectedDownloadTask else { return false }
        return task.status == .running && cancellableDownloadTaskIDs.contains(task.id)
    }

    var canCancelSelectedDownloadTask: Bool {
        canPauseSelectedDownloadTask
    }

    var selectedDownloadTaskResumeButtonTitle: String {
        selectedDownloadTask?.status == .paused ? "继续" : "重试"
    }

    var selectedDownloadTaskResumeButtonSystemImage: String {
        selectedDownloadTask?.status == .paused ? "play.circle" : "arrow.clockwise"
    }

    var dependencyProgressSummary: String {
        guard let latestDependencyProgress else {
            return isPreparingLaunch ? "正在准备依赖检查" : "尚未开始依赖检查"
        }
        return "\(latestDependencyProgress.finished)/\(latestDependencyProgress.total) · 下载 \(latestDependencyProgress.downloaded) · 跳过 \(latestDependencyProgress.skipped)"
    }

    var selectedThemePreset: LauncherThemePreset {
        LauncherThemePreset(rawValue: themePreset) ?? .pclBlue
    }

    var selectedAppearanceMode: LauncherAppearanceMode {
        LauncherAppearanceMode(rawValue: appearanceMode) ?? .system
    }

    var appNameText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Plain Craft Launcher (PCL) macOS"
    }

    var appBundleIdentifierText: String {
        Bundle.main.bundleIdentifier ?? "com.paipaiio.pcl"
    }

    var appVersionSummaryText: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.trimmed.nonEmpty ?? "开发构建"
        guard let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?.trimmed.nonEmpty else {
            return version
        }
        return "\(version) (\(build))"
    }

    var appBundlePathText: String {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    var appInstallLocationText: String {
        let path = appBundlePathText
        if path.hasPrefix("/Applications/") {
            return "Applications 正式安装"
        }
        if path.contains("/PCLMac/dist/") {
            return "本地 dist 构建"
        }
        if path.contains("/.build/") || !path.hasSuffix(".app") {
            return "SwiftPM 调试运行"
        }
        return "自定义位置"
    }

    var appBundleSummaryText: String {
        [
            "应用：\(appNameText)",
            "版本：\(appVersionSummaryText)",
            "Bundle ID：\(appBundleIdentifierText)",
            "位置：\(appInstallLocationText)",
            "路径：\(appBundlePathText)"
        ].joined(separator: "\n")
    }

    func openOriginalPCLSponsorPage() {
        guard let url = URL(string: "https://meloong.com/afd/a/LTCat") else { return }
        NSWorkspace.shared.open(url)
    }

    func openOriginalPCLRepository() {
        guard let url = URL(string: "https://github.com/Meloong-Git/PCL") else { return }
        NSWorkspace.shared.open(url)
    }

    var effectiveDownloadSource: MinecraftDownloadSource {
        MinecraftDownloadSource(preference: downloadSource)
    }

    func isHomeCardVisible(_ card: LauncherHomeCard) -> Bool {
        !hiddenHomeCardIDs.contains(card.rawValue)
    }

    func setHomeCard(_ card: LauncherHomeCard, visible: Bool) {
        var hidden = hiddenHomeCardIDs
        if visible {
            hidden.removeAll { $0 == card.rawValue }
        } else if !hidden.contains(card.rawValue) {
            hidden.append(card.rawValue)
        }
        hiddenHomeCardIDs = hidden.filter { id in
            LauncherHomeCard.allCases.contains { $0.rawValue == id }
        }
    }

    func resetHomeCards() {
        hiddenHomeCardIDs = []
    }

    func copyLaunchCommandPreview() {
        guard !launchCommandPreview.isEmpty else { return }
        copyToPasteboard(launchCommandPreview)
        lastEvent = "已复制完整启动命令"
    }

    func copySelectedInstanceSummary() {
        guard selectedInstance != nil else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        copyToPasteboard(selectedInstanceSummaryText)
        lastEvent = "已复制版本详情"
    }

    func copySelectedLaunchConfigurationSummary() {
        guard selectedInstance != nil else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        copyToPasteboard(selectedLaunchConfigurationSummaryText)
        lastEvent = "已复制启动配置摘要"
    }

    func copySelectedJavaDiagnostics() {
        guard selectedInstance != nil else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        copyToPasteboard(selectedJavaDiagnosticSummaryText)
        lastEvent = "已复制 Java 诊断"
    }

    func copyAppBundlePath() {
        copyToPasteboard(appBundlePathText)
        aboutMessage = "已复制当前应用路径"
    }

    func copyAppBundleSummary() {
        copyToPasteboard(appBundleSummaryText)
        aboutMessage = "已复制应用身份摘要"
    }

    func revealAppBundleInFinder() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
        aboutMessage = "已在 Finder 中显示当前应用"
    }

    func scheduleDownloadResourcePreparation() {
        downloadResourcePreparationTask?.cancel()
        downloadResourcePreparationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: PCLMotion.deferredWorkDelayNanoseconds)
            guard !Task.isCancelled else { return }
            prepareDownloadResourceSectionIfNeeded()
        }
    }

    func prepareDownloadResourceSectionIfNeeded() {
        prepareModrinthSectionIfNeeded()
        prepareCurseForgeSectionIfNeeded()
    }

    func prepareModrinthSectionIfNeeded() {
        guard let projectType = selectedDownloadSection.modrinthProjectType else { return }
        guard activeModrinthProjectType != projectType else { return }

        let previousDefaultQuery = activeModrinthProjectType.defaultSearchQuery
        activeModrinthProjectType = projectType
        modrinthResults = []
        selectedModrinthProjectID = nil
        resetModrinthVersionFilePreview()
        lastModrinthFileURL = nil
        lastModrinthProjectTitle = ""
        lastModrinthPackPlan = nil
        lastModrinthPackImportResult = nil
        if modrinthQuery.trimmed.isEmpty || modrinthQuery.trimmed == previousDefaultQuery {
            modrinthQuery = projectType.defaultSearchQuery
        }
        modrinthMessage = "选择条件后搜索 Modrinth \(projectType.displayName)"
    }

    func prepareCurseForgeSectionIfNeeded() {
        guard let resourceType = selectedDownloadSection.curseForgeResourceType else { return }
        guard activeCurseForgeResourceType != resourceType else { return }

        let previousDefaultQuery = activeCurseForgeResourceType.defaultSearchQuery
        activeCurseForgeResourceType = resourceType
        curseForgeResults = []
        selectedCurseForgeProjectID = nil
        resetCurseForgeFilePreview()
        lastCurseForgeFileURL = nil
        lastCurseForgeProjectTitle = ""
        lastCurseForgePackPlan = nil
        lastCurseForgePackImportResult = nil
        if curseForgeQuery.trimmed.isEmpty || curseForgeQuery.trimmed == previousDefaultQuery {
            curseForgeQuery = resourceType.defaultSearchQuery
        }
        curseForgeMessage = hasCurseForgeAPIKey
            ? "选择条件后搜索 CurseForge \(resourceType.displayName)"
            : "请先在下载设置中配置 CurseForge API Key"
    }

    private func resetModrinthVersionFilePreview() {
        modrinthVersionFilePreviews = []
        selectedModrinthVersionFileID = nil
        loadedModrinthVersions = []
        loadedModrinthVersionFilesKey = nil
        modrinthVersionFilesMessage = "选择项目后查看版本文件"
    }

    private func resetCurseForgeFilePreview() {
        curseForgeFilePreviews = []
        selectedCurseForgeFileID = nil
        loadedCurseForgeFiles = []
        loadedCurseForgeFilesKey = nil
        curseForgeFilesMessage = "选择项目后查看版本文件"
    }

    func bootstrap() async {
        paths.prepare()
        await requestNativeNotificationAuthorizationIfNeeded()
        loadAccounts()
        refreshLocalNetworkInfo()
        await refreshEnvironment()
    }

    private func requestNativeNotificationAuthorizationIfNeeded() async {
        guard showNativeNotifications, !didRequestNativeNotificationAuthorization else { return }
        didRequestNativeNotificationAuthorization = true
        let granted = await notificationCenter.requestAuthorization()
        if !granted {
            lastEvent = "系统通知未授权，结果提示将只显示在启动器内"
        }
    }

    private func sendNativeNotification(title: String, body: String) {
        guard showNativeNotifications else { return }
        notificationCenter.deliver(LauncherNotification(title: title, body: body))
    }

    func loadAccounts() {
        accounts = accountStore.loadProfiles()
        if let selectedAccountID,
           accounts.contains(where: { $0.id == selectedAccountID }) {
            accountVaultMessage = "已加载 \(accounts.count) 个账户"
            return
        }
        selectedAccountID = accounts.first?.id
        accountVaultMessage = accounts.isEmpty ? "尚未保存账户，正版凭据将写入 Keychain" : "已加载 \(accounts.count) 个账户"
    }

    func saveCurrentOfflineAccount() {
        do {
            let profile = LauncherAccountProfile.offline(username: offlineUsername)
            try accountStore.upsert(profile)
            accounts = accountStore.loadProfiles()
            selectedAccountID = profile.id
            loginMode = "离线"
            accountVaultMessage = "已保存离线账户：\(profile.displayName)"
        } catch {
            accountVaultMessage = "账户保存失败：\(error.localizedDescription)"
        }
    }

    func startMicrosoftLogin() async {
        let clientID = effectiveMicrosoftClientID
        guard !clientID.isEmpty else {
            accountVaultMessage = "当前应用未内置 Microsoft 授权，请在设置中填写高级覆盖或使用 PCL_MS_CLIENT_ID"
            selectedPage = .settings
            selectedSettingsSection = .launch
            return
        }
        if isMicrosoftLoginInProgress { return }
        isMicrosoftLoginInProgress = true
        accountVaultMessage = "正在向 Microsoft 获取设备验证码（\(microsoftClientIDStatusText)）"

        do {
            let service = MicrosoftMinecraftLoginService(clientID: clientID)
            let code = try await service.requestDeviceCode()
            microsoftDeviceCode = code
            accountVaultMessage = "请在浏览器输入验证码：\(code.userCode)"
            copyToPasteboard(code.userCode)
            NSWorkspace.shared.open(code.verificationURI)

            let result = try await service.loginWithDeviceCode(code)
            try accountStore.upsert(result.profile, secret: result.secret)
            accounts = accountStore.loadProfiles()
            selectedAccountID = result.profile.id
            loginMode = "正版"
            accountVaultMessage = "Microsoft 登录成功：\(result.profile.displayName)"
            microsoftDeviceCode = nil
        } catch {
            accountVaultMessage = "Microsoft 登录失败：\(error.localizedDescription)"
        }
        isMicrosoftLoginInProgress = false
    }

    func startAuthlibLogin() async {
        guard let serverURL = normalizedAuthlibServerURL() else {
            accountVaultMessage = "请填写 Authlib 认证服务器地址"
            loginMode = "Authlib"
            return
        }
        guard !authlibUsername.trimmed.isEmpty else {
            accountVaultMessage = "请填写 Authlib 账号"
            loginMode = "Authlib"
            return
        }
        guard !authlibPassword.isEmpty else {
            accountVaultMessage = "请填写 Authlib 密码"
            loginMode = "Authlib"
            return
        }
        if isAuthlibLoginInProgress { return }
        isAuthlibLoginInProgress = true
        accountVaultMessage = "正在登录 Authlib"

        do {
            let result = try await AuthlibLoginService().login(
                AuthlibLoginRequest(
                    serverURL: serverURL,
                    username: authlibUsername,
                    password: authlibPassword,
                    preferredProfileID: selectedLaunchAccount?.playerUUID
                )
            )
            try accountStore.upsert(result.profile, secret: result.secret)
            accounts = accountStore.loadProfiles()
            selectedAccountID = result.profile.id
            loginMode = "Authlib"
            accountVaultMessage = "Authlib 登录成功：\(result.profile.displayName)"
        } catch {
            accountVaultMessage = "Authlib 登录失败：\(error.localizedDescription)"
        }
        isAuthlibLoginInProgress = false
    }

    func startNideLogin() async {
        let manager = NideInjectorManager()
        let normalizedServerID = nideServerID.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedServerID.isEmpty else {
            accountVaultMessage = "请填写统一通行证服务器 ID"
            loginMode = "统一通行证"
            return
        }
        guard !nideUsername.trimmed.isEmpty else {
            accountVaultMessage = "请填写统一通行证账号"
            loginMode = "统一通行证"
            return
        }
        guard !nidePassword.isEmpty else {
            accountVaultMessage = "请填写统一通行证密码"
            loginMode = "统一通行证"
            return
        }
        if isNideLoginInProgress { return }
        isNideLoginInProgress = true
        accountVaultMessage = "正在登录统一通行证"

        do {
            let serverURL = try manager.authserverURL(serverID: normalizedServerID)
            let result = try await AuthlibLoginService().login(
                AuthlibLoginRequest(
                    serverURL: serverURL,
                    username: nideUsername,
                    password: nidePassword,
                    preferredProfileID: selectedAccount?.kind == .nide ? selectedAccount?.playerUUID : nil,
                    accountKind: .nide
                )
            )
            try accountStore.upsert(result.profile, secret: result.secret)
            accounts = accountStore.loadProfiles()
            selectedAccountID = result.profile.id
            nideServerID = normalizedServerID
            loginMode = "统一通行证"
            accountVaultMessage = "统一通行证登录成功：\(result.profile.displayName)"
        } catch {
            accountVaultMessage = "统一通行证登录失败：\(error.localizedDescription)"
        }
        isNideLoginInProgress = false
    }

    private func normalizedAuthlibServerURL() -> URL? {
        var raw = authlibServerURL.trimmed
        if raw.isEmpty { return nil }
        if !raw.contains("://") {
            raw = "https://\(raw)"
        }
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !raw.hasSuffix("/authserver") {
            raw += "/authserver"
        }
        return URL(string: raw)
    }

    private func launchIdentity() async throws -> MinecraftLaunchRequest.Identity {
        if loginMode == "离线" {
            return .offline(username: offlineUsername)
        }

        guard var account = selectedLaunchAccount else {
            throw LauncherAuthError.missingAccount
        }
        guard var secret = try accountStore.loadSecret(for: account.id) else {
            throw LauncherAuthError.missingSecret
        }

        if account.kind == .authlib || account.kind == .nide {
            if let refreshed = try await refreshYggdrasilAccountIfNeeded(account: account, secret: secret) {
                account = refreshed.profile
                secret = refreshed.secret
            }
            return MinecraftLaunchRequest.Identity(
                username: account.displayName,
                uuid: account.playerUUID ?? account.id,
                accessToken: secret.accessToken,
                userType: "msa",
                clientToken: secret.clientToken
            )
        }

        guard account.kind == .microsoft else {
            throw LauncherAuthError.missingAccount
        }

        if let expiresAt = secret.expiresAt, expiresAt <= Date() {
            guard let refreshToken = secret.refreshToken else {
                throw LauncherAuthError.expiredMicrosoftSecretWithoutRefresh
            }
            let clientID = effectiveMicrosoftClientID
            guard !clientID.isEmpty else {
                throw MicrosoftMinecraftLoginError.missingClientID
            }
            let result = try await MicrosoftMinecraftLoginService(clientID: clientID).loginWithRefreshToken(refreshToken)
            try accountStore.upsert(result.profile, secret: result.secret)
            accounts = accountStore.loadProfiles()
            selectedAccountID = result.profile.id
            account = result.profile
            secret = result.secret
        }

        return MinecraftLaunchRequest.Identity(
            username: account.displayName,
            uuid: account.playerUUID ?? account.id.replacingOccurrences(of: "microsoft:", with: ""),
            accessToken: secret.accessToken,
            userType: "msa"
        )
    }

    private func refreshYggdrasilAccountIfNeeded(
        account: LauncherAccountProfile,
        secret: LauncherAccountSecret
    ) async throws -> AuthlibLoginResult? {
        guard let serverURL = account.serverURL else {
            throw AuthlibLoginError.missingServerURL
        }
        let service = AuthlibLoginService()
        do {
            try await service.validate(serverURL: serverURL, secret: secret)
            return nil
        } catch {
            do {
                let result = try await service.refresh(serverURL: serverURL, profile: account, secret: secret)
                try accountStore.upsert(result.profile, secret: result.secret)
                accounts = accountStore.loadProfiles()
                selectedAccountID = result.profile.id
                return result
            } catch {
                guard let password = secret.password else { throw error }
                let savedUsername = secret.username ?? (account.kind == .nide ? nideUsername : authlibUsername)
                let result = try await service.login(
                    AuthlibLoginRequest(
                        serverURL: serverURL,
                        username: savedUsername.isEmpty ? account.displayName : savedUsername,
                        password: password,
                        preferredProfileID: account.playerUUID,
                        accountKind: account.kind
                    )
                )
                try accountStore.upsert(result.profile, secret: result.secret)
                accounts = accountStore.loadProfiles()
                selectedAccountID = result.profile.id
                return result
            }
        }
    }

    private func authlibInjectorConfigurationIfNeeded() async throws -> AuthlibInjectorConfiguration? {
        guard loginMode == "Authlib",
              let serverURL = selectedLaunchAccount?.serverURL else {
            return nil
        }
        launchStatus = LaunchStatus(title: "准备 Authlib", detail: "正在准备 Authlib-Injector", progress: 0.04)
        return try await AuthlibInjectorManager().prepare(
            authserverURL: serverURL,
            appSupportDirectory: paths.appSupportDirectory
        )
    }

    private func nideInjectorConfigurationIfNeeded() async throws -> NideInjectorConfiguration? {
        guard loginMode == "统一通行证",
              let account = selectedAccount,
              account.kind == .nide else {
            return nil
        }
        let manager = NideInjectorManager()
        let serverID = account.serverURL.flatMap { manager.serverID(from: $0) } ?? nideServerID
        launchStatus = LaunchStatus(title: "准备统一通行证", detail: "正在准备 nide8auth.jar", progress: 0.04)
        return try await manager.prepare(
            serverID: serverID,
            appSupportDirectory: paths.appSupportDirectory
        )
    }

    func removeSelectedAccount() {
        guard let account = selectedAccount else {
            accountVaultMessage = "请先选择账户"
            return
        }
        do {
            try accountStore.delete(accountID: account.id)
            accounts = accountStore.loadProfiles()
            selectedAccountID = accounts.first?.id
            accountVaultMessage = "已移除账户：\(account.displayName)"
        } catch {
            accountVaultMessage = "账户移除失败：\(error.localizedDescription)"
        }
    }

    func refreshEnvironment() async {
        isScanning = true
        launchStatus = LaunchStatus(title: "正在扫描", detail: "查找 Minecraft 实例与 Java", progress: 0.18)

        async let java = JavaDiscoveryService().discover(appSupportDirectory: paths.appSupportDirectory)
        async let instances = MinecraftInstanceScanner().scan(minecraftDirectory: minecraftDirectory)
        let result = await (java, instances)

        versionSettingsCache.removeAll(keepingCapacity: true)
        requiredJavaMajorVersionCache.removeAll(keepingCapacity: true)
        noRequiredJavaMajorVersionCache.removeAll(keepingCapacity: true)
        javaInstallations = result.0
        minecraftInstances = result.1
        restoreSelectedInstance()
        restoreSelectedJava()

        let instanceText = minecraftInstances.isEmpty ? "未发现实例" : "发现 \(minecraftInstances.count) 个实例"
        let javaText = javaInstallations.isEmpty ? "未发现 Java" : "发现 \(javaInstallations.count) 个 Java"
        launchStatus = LaunchStatus(title: "准备就绪", detail: "\(instanceText)，\(javaText)", progress: 1)
        lastEvent = "环境刷新完成"
        isScanning = false
    }

    private func restoreSelectedInstance() {
        let candidates = visibleMinecraftInstances
        if let selectedInstanceNamePreference,
           let instance = candidates.first(where: { $0.name == selectedInstanceNamePreference }) {
            selectedInstanceID = instance.id
            return
        }
        if let selectedInstanceID,
           candidates.contains(where: { $0.id == selectedInstanceID }) {
            return
        }
        selectedInstanceID = candidates.first?.id
    }

    private func restoreSelectedJava() {
        if let selectedJavaPathPreference,
           let java = javaInstallations.first(where: { $0.executable.path == selectedJavaPathPreference }) {
            selectedJavaID = java.id
            return
        }
        if let selectedJavaID,
           javaInstallations.contains(where: { $0.id == selectedJavaID }) {
            return
        }
        selectedJavaID = autoSelectJava ? javaInstallations.first?.id : nil
    }

    private func savePreferences() {
        let preferences = currentPreferencesSnapshot()
        guard let preferenceSaveDelayNanoseconds else {
            preferencesStore.save(preferences)
            return
        }

        preferenceSaveTask?.cancel()
        preferenceSaveTask = Task { [preferencesStore, preferences] in
            try? await Task.sleep(nanoseconds: preferenceSaveDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                preferencesStore.save(preferences)
            }.value
        }
    }

    func flushPendingPreferences() {
        preferenceSaveTask?.cancel()
        preferenceSaveTask = nil
        preferencesStore.save(currentPreferencesSnapshot())
    }

    private func currentPreferencesSnapshot() -> LauncherPreferences {
        LauncherPreferences(
            loginMode: loginMode,
            offlineUsername: offlineUsername,
            selectedAccountID: selectedAccountID,
            microsoftClientID: microsoftClientID,
            nideServerID: nideServerID,
            nideUsername: nideUsername,
            authlibServerURL: authlibServerURL,
            authlibUsername: authlibUsername,
            selectedInstanceName: selectedInstance?.name ?? selectedInstanceNamePreference,
            selectedJavaPath: selectedJava?.executable.path ?? selectedJavaPathPreference,
            customMinecraftDirectoryPath: customMinecraftDirectoryPath,
            localVersionQuery: localVersionQuery,
            localVersionFilter: localVersionFilter,
            favoriteInstanceNames: favoriteInstanceNames,
            hiddenInstanceNames: hiddenInstanceNames,
            showsHiddenInstances: showsHiddenInstances,
            downloadSource: downloadSource,
            resourceProvider: resourceProvider,
            curseForgeAPIKey: curseForgeAPIKey,
            selectedInstallLoader: selectedInstallLoader,
            maxDownloadThreads: maxDownloadThreads,
            memoryLimit: memoryLimit,
            gameWindowWidth: gameWindowWidth,
            gameWindowHeight: gameWindowHeight,
            launchFullscreen: launchFullscreen,
            useVersionIsolation: useVersionIsolation,
            launchServerAddress: launchServerAddress,
            launchServerPort: launchServerPort,
            serverFavorites: serverFavorites,
            extraJvmArguments: extraJvmArguments,
            extraGameArguments: extraGameArguments,
            hideLauncherOnGameStart: hideLauncherOnGameStart,
            showLauncherOnGameExit: showLauncherOnGameExit,
            showNativeNotifications: showNativeNotifications,
            showDockBadge: showDockBadge,
            useHighPerformanceMode: useHighPerformanceMode,
            autoSelectJava: autoSelectJava,
            remoteVersionFilter: remoteVersionFilter,
            themePreset: themePreset,
            appearanceMode: appearanceMode,
            showsHomeHint: showsHomeHint,
            hiddenHomeCardIDs: hiddenHomeCardIDs,
            backgroundImagePath: backgroundImagePath,
            backgroundImageOpacity: backgroundImageOpacity
        )
    }

    @discardableResult
    func beginDownloadTask(
        title: String,
        category: String,
        detail: String,
        progress: Double? = nil,
        destinationPath: String? = nil,
        retryAction: DownloadTaskRetryAction? = nil
    ) -> DownloadTaskRecord.ID {
        let task = DownloadTaskRecord(
            title: title,
            category: category,
            detail: detail,
            progress: progress,
            destinationPath: destinationPath,
            retryAction: retryAction
        )
        downloadTaskRecords.insert(task, at: 0)
        selectedDownloadTaskID = task.id
        trimDownloadTasks()
        persistDownloadTaskRecords()
        return task.id
    }

    func updateDownloadTask(
        _ id: DownloadTaskRecord.ID,
        status: DownloadTaskStatus? = nil,
        detail: String? = nil,
        progress: Double? = nil,
        destinationPath: String? = nil
    ) {
        guard let index = downloadTaskRecords.firstIndex(where: { $0.id == id }) else { return }
        let previousStatus = downloadTaskRecords[index].status
        if let status {
            downloadTaskRecords[index].status = status
        }
        if let detail {
            downloadTaskRecords[index].detail = detail
        }
        if let progress {
            downloadTaskRecords[index].progress = progress
        }
        if let destinationPath {
            downloadTaskRecords[index].destinationPath = destinationPath
        }
        downloadTaskRecords[index].updatedAt = Date()
        notifyDownloadTaskStatusChangeIfNeeded(downloadTaskRecords[index], previousStatus: previousStatus, requestedStatus: status)
        persistDownloadTaskRecords()
    }

    private func notifyDownloadTaskStatusChangeIfNeeded(
        _ task: DownloadTaskRecord,
        previousStatus: DownloadTaskStatus,
        requestedStatus: DownloadTaskStatus?
    ) {
        guard let requestedStatus, requestedStatus != previousStatus else { return }
        switch requestedStatus {
        case .succeeded:
            sendNativeNotification(title: "任务已完成", body: "\(task.title)：\(task.detail)")
        case .failed:
            sendNativeNotification(title: "任务失败", body: "\(task.title)：\(task.detail)")
        case .paused, .cancelled:
            sendNativeNotification(title: "任务已暂停", body: "\(task.title)：\(task.detail)")
        case .running:
            break
        }
    }

    func clearFinishedDownloadTasks() {
        downloadTaskRecords.removeAll { $0.status == .succeeded }
        normalizeSelectedDownloadTask()
        persistDownloadTaskRecords()
    }

    func clearFailedDownloadTasks() {
        downloadTaskRecords.removeAll { $0.status.isRecoverable }
        normalizeSelectedDownloadTask()
        persistDownloadTaskRecords()
    }

    func clearDownloadTaskHistory() {
        downloadTaskRecords.removeAll { $0.status != .running }
        normalizeSelectedDownloadTask()
        persistDownloadTaskRecords()
    }

    func copySelectedDownloadTaskSummary() {
        guard let task = selectedDownloadTask else {
            lastEvent = "请选择一条下载任务"
            return
        }
        copyToPasteboard(task.summaryText)
        lastEvent = "已复制任务摘要：\(task.title)"
    }

    func registerDownloadTaskOperation(_ id: DownloadTaskRecord.ID, operation: Task<Void, Never>) {
        activeDownloadTaskOperations[id] = operation
        cancellableDownloadTaskIDs.insert(id)
    }

    func finishDownloadTaskOperation(_ id: DownloadTaskRecord.ID) {
        activeDownloadTaskOperations[id] = nil
        cancellableDownloadTaskIDs.remove(id)
    }

    func pauseSelectedDownloadTask() {
        guard let task = selectedDownloadTask else {
            lastEvent = "请选择一条下载任务"
            return
        }
        guard task.status == .running, let operation = activeDownloadTaskOperations[task.id] else {
            lastEvent = "当前任务不支持暂停"
            return
        }
        operation.cancel()
        updateDownloadTask(
            task.id,
            status: .paused,
            detail: "正在暂停；已完成的文件会保留，点击继续会跳过已完成部分",
            progress: task.progress
        )
        lastEvent = "已请求暂停：\(task.title)"
    }

    func cancelSelectedDownloadTask() {
        pauseSelectedDownloadTask()
    }

    func retrySelectedDownloadTask() async {
        guard !isInstallingVersion else {
            lastEvent = "当前已有版本安装任务正在进行"
            return
        }
        guard let task = selectedDownloadTask else {
            lastEvent = "请选择一条下载任务"
            return
        }
        guard task.status.isRecoverable, let retryAction = task.retryAction else {
            lastEvent = "当前任务没有可继续操作"
            return
        }

        switch retryAction {
        case .installVersion(let versionID, let loader, let sourcePreference):
            let source = MinecraftDownloadSource(preference: sourcePreference)
            downloadSource = source.rawValue
            selectedInstallLoader = loader
            do {
                let version = try await remoteMinecraftVersion(id: versionID)
                selectedRemoteVersionID = version.id
                selectedDownloadSection = .tasks
                selectedPage = .download
                startRemoteVersionInstall(version: version, loader: loader, downloadSource: source)
            } catch {
                installMessage = "重试失败：\(error.localizedDescription)"
                lastEvent = installMessage
            }
        case .installJavaRuntime(let component, let sourcePreference):
            let source = MinecraftDownloadSource(preference: sourcePreference)
            downloadSource = source.rawValue
            startJavaRuntimeInstall(component: component, downloadSource: source)
        }
    }

    func showDownloadTasks() {
        selectedDownloadSection = .tasks
        selectedPage = .download
    }

    func openSelectedModrinthProjectPage(_ projectType: ModrinthProjectType) {
        guard let url = selectedModrinthProject?.websiteURL(projectType: projectType) else {
            modrinthMessage = "没有可打开的 Modrinth 页面"
            return
        }
        NSWorkspace.shared.open(url)
        modrinthMessage = "已打开 Modrinth 页面"
    }

    func copySelectedModrinthProjectSummary(_ projectType: ModrinthProjectType) {
        guard let project = selectedModrinthProject else {
            modrinthMessage = "请先选择一个\(projectType.displayName)"
            return
        }
        copyToPasteboard(project.detailSummary(projectType: projectType))
        modrinthMessage = "已复制 \(project.title) 的详情"
    }

    func modrinthVersionFilesRequestKey(_ projectType: ModrinthProjectType) -> String {
        [
            selectedModrinthProject?.projectID ?? "-",
            projectType.rawValue,
            resourceMinecraftVersion() ?? "*",
            projectType.supportsLoaderFiltering ? (resourceLoaderFilter(for: projectType) ?? "*") : "*"
        ].joined(separator: "|")
    }

    func modrinthInstallButtonTitle(_ projectType: ModrinthProjectType) -> String {
        guard selectedModrinthVersionFile(projectType: projectType) != nil else {
            return projectType.installActionTitle
        }
        switch projectType {
        case .mod:
            return "安装所选 Mod"
        case .modpack:
            return "导入所选整合包"
        case .datapack:
            return "下载所选数据包"
        case .resourcepack:
            return "安装所选资源包"
        case .shader:
            return "安装所选光影包"
        }
    }

    func loadSelectedModrinthVersionFiles(_ projectType: ModrinthProjectType, force: Bool = false) async {
        guard let project = selectedModrinthProject else {
            resetModrinthVersionFilePreview()
            modrinthVersionFilesMessage = "选择项目后查看版本文件"
            return
        }
        let key = modrinthVersionFilesRequestKey(projectType)
        guard force || loadedModrinthVersionFilesKey != key else { return }
        if isLoadingModrinthVersionFiles { return }

        isLoadingModrinthVersionFiles = true
        modrinthVersionFilesMessage = "正在加载版本文件"
        do {
            let versions = try await ModrinthResourceService().versions(
                projectID: project.projectID,
                minecraftVersion: resourceMinecraftVersion(),
                loader: projectType.supportsLoaderFiltering ? resourceLoaderFilter(for: projectType) : nil
            )
            let previews = ResourceVersionFilePreview.modrinth(versions: versions, projectType: projectType)
            loadedModrinthVersions = versions
            modrinthVersionFilePreviews = previews
            selectedModrinthVersionFileID = previews.first?.id
            loadedModrinthVersionFilesKey = key
            modrinthVersionFilesMessage = modrinthVersionFilePreviews.isEmpty
                ? "没有找到可安装文件"
                : "已加载 \(modrinthVersionFilePreviews.count) 个版本文件"
        } catch {
            modrinthVersionFilePreviews = []
            selectedModrinthVersionFileID = nil
            loadedModrinthVersions = []
            loadedModrinthVersionFilesKey = nil
            modrinthVersionFilesMessage = "版本文件加载失败：\(error.localizedDescription)"
        }
        isLoadingModrinthVersionFiles = false
    }

    private func selectedModrinthVersionFile(projectType: ModrinthProjectType) -> (version: ModrinthVersion, file: ModrinthFile)? {
        guard let selectedModrinthVersionFileID else { return nil }
        for version in loadedModrinthVersions {
            for file in version.files where file.filename.lowercased().hasSuffix(projectType.installableExtension) {
                if "modrinth:\(version.id):\(file.filename)" == selectedModrinthVersionFileID {
                    return (version, file)
                }
            }
        }
        return nil
    }

    func openSelectedCurseForgeProjectPage(_ resourceType: CurseForgeResourceType) {
        guard let url = selectedCurseForgeProject?.websiteURL(resourceType: resourceType) else {
            curseForgeMessage = "没有可打开的 CurseForge 页面"
            return
        }
        NSWorkspace.shared.open(url)
        curseForgeMessage = "已打开 CurseForge 页面"
    }

    func copySelectedCurseForgeProjectSummary(_ resourceType: CurseForgeResourceType) {
        guard let project = selectedCurseForgeProject else {
            curseForgeMessage = "请先选择一个\(resourceType.displayName)"
            return
        }
        copyToPasteboard(project.detailSummary(resourceType: resourceType))
        curseForgeMessage = "已复制 \(project.name) 的详情"
    }

    func curseForgeFilesRequestKey(_ resourceType: CurseForgeResourceType) -> String {
        [
            selectedCurseForgeProject.map { "\($0.id)" } ?? "-",
            "\(resourceType.rawValue)",
            resourceMinecraftVersion() ?? "*",
            resourceType.supportsLoaderFiltering ? (resourceLoaderFilter(for: resourceType.modrinthProjectType) ?? "*") : "*",
            hasCurseForgeAPIKey ? "key" : "no-key"
        ].joined(separator: "|")
    }

    func curseForgeInstallButtonTitle(_ resourceType: CurseForgeResourceType) -> String {
        guard selectedCurseForgeFile(resourceType: resourceType) != nil else {
            return resourceType.installActionTitle
        }
        switch resourceType {
        case .mod:
            return "安装所选 Mod"
        case .modpack:
            return "导入所选整合包"
        case .resourcePack:
            return "安装所选资源包"
        }
    }

    func loadSelectedCurseForgeFiles(_ resourceType: CurseForgeResourceType, force: Bool = false) async {
        guard hasCurseForgeAPIKey else {
            resetCurseForgeFilePreview()
            curseForgeFilesMessage = "需要先配置 CurseForge API Key"
            return
        }
        guard let project = selectedCurseForgeProject else {
            resetCurseForgeFilePreview()
            curseForgeFilesMessage = "选择项目后查看版本文件"
            return
        }
        let key = curseForgeFilesRequestKey(resourceType)
        guard force || loadedCurseForgeFilesKey != key else { return }
        if isLoadingCurseForgeFiles { return }

        isLoadingCurseForgeFiles = true
        curseForgeFilesMessage = "正在加载版本文件"
        do {
            let files = try await CurseForgeResourceService().files(
                modID: project.id,
                apiKey: effectiveCurseForgeAPIKey,
                minecraftVersion: resourceMinecraftVersion(),
                loader: resourceType.supportsLoaderFiltering ? resourceLoaderFilter(for: resourceType.modrinthProjectType) : nil,
                pageSize: 20
            )
            let previews = ResourceVersionFilePreview.curseForge(files: files, resourceType: resourceType)
            loadedCurseForgeFiles = files
            curseForgeFilePreviews = previews
            selectedCurseForgeFileID = previews.first?.id
            loadedCurseForgeFilesKey = key
            curseForgeFilesMessage = curseForgeFilePreviews.isEmpty
                ? "没有找到可安装文件"
                : "已加载 \(curseForgeFilePreviews.count) 个版本文件"
        } catch {
            curseForgeFilePreviews = []
            selectedCurseForgeFileID = nil
            loadedCurseForgeFiles = []
            loadedCurseForgeFilesKey = nil
            curseForgeFilesMessage = "版本文件加载失败：\(error.localizedDescription)"
        }
        isLoadingCurseForgeFiles = false
    }

    private func selectedCurseForgeFile(resourceType: CurseForgeResourceType) -> CurseForgeFile? {
        guard let selectedCurseForgeFileID else { return nil }
        return loadedCurseForgeFiles.first { file in
            let lowercased = file.fileName.lowercased()
            let isInstallable = resourceType.installableExtensions.contains { lowercased.hasSuffix($0) }
            return isInstallable && "curseforge:\(file.id)" == selectedCurseForgeFileID
        }
    }

    func revealSelectedDownloadTaskInFinder() {
        guard let path = selectedDownloadTask?.destinationPath else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func trimDownloadTasks() {
        if downloadTaskRecords.count > 50 {
            downloadTaskRecords.removeLast(downloadTaskRecords.count - 50)
        }
    }

    private func normalizeSelectedDownloadTask() {
        if let selectedDownloadTaskID,
           !downloadTaskRecords.contains(where: { $0.id == selectedDownloadTaskID }) {
            self.selectedDownloadTaskID = downloadTaskRecords.first?.id
        } else if selectedDownloadTaskID == nil {
            selectedDownloadTaskID = downloadTaskRecords.first?.id
        }
    }

    private func persistDownloadTaskRecords() {
        downloadTaskHistoryStore.save(downloadTaskRecords)
    }

    private func refreshDownloadTaskSummaryState() {
        var runningCount = 0
        var recoverableCount = 0
        for record in downloadTaskRecords {
            if record.status == .running {
                runningCount += 1
            }
            if record.status.isRecoverable {
                recoverableCount += 1
            }
        }
        activeDownloadTaskCount = runningCount
        failedDownloadTaskCount = recoverableCount
        updateDockBadge()
    }

    private var dockBadgeText: String? {
        guard showDockBadge else { return nil }
        if activeDownloadTaskCount > 0 {
            return isLaunching ? "\(activeDownloadTaskCount)+" : "\(activeDownloadTaskCount)"
        }
        if isLaunching {
            return "MC"
        }
        return nil
    }

    private func updateDockBadge() {
        dockBadgeController.setBadge(dockBadgeText)
    }

    func loadRemoteVersions() async {
        if isLoadingRemoteVersions { return }
        isLoadingRemoteVersions = true
        installMessage = "正在通过 \(effectiveDownloadSource.rawValue) 获取 Mojang 版本列表"
        do {
            let manifest = try await MinecraftVersionInstaller(downloadSource: effectiveDownloadSource).fetchManifest()
            remoteVersions = manifest.versions
            selectedRemoteVersionID = manifest.versions.first(where: { $0.id == manifest.latest.release })?.id ?? manifest.versions.first?.id
            installMessage = "最新正式版：\(manifest.latest.release)，最新快照：\(manifest.latest.snapshot)"
        } catch {
            installMessage = "版本列表加载失败：\(error.localizedDescription)"
        }
        isLoadingRemoteVersions = false
    }

    func startSelectedRemoteVersionInstall() {
        guard let version = selectedRemoteVersion else {
            installMessage = "请先选择要安装的版本"
            return
        }
        startRemoteVersionInstall(
            version: version,
            loader: selectedInstallLoader,
            downloadSource: effectiveDownloadSource
        )
    }

    func installSelectedRemoteVersion() async {
        guard let version = selectedRemoteVersion else {
            installMessage = "请先选择要安装的版本"
            return
        }
        let loader = selectedInstallLoader
        let source = effectiveDownloadSource
        let taskID = beginVersionInstallTask(version: version, loader: loader, downloadSource: source)
        isInstallingVersion = true
        await performRemoteVersionInstall(version: version, loader: loader, downloadSource: source, taskID: taskID)
    }

    @discardableResult
    private func startRemoteVersionInstall(
        version: MinecraftRemoteVersion,
        loader: String,
        downloadSource: MinecraftDownloadSource
    ) -> DownloadTaskRecord.ID? {
        guard !isInstallingVersion else {
            installMessage = "已有版本安装任务正在进行"
            return nil
        }
        let taskID = beginVersionInstallTask(version: version, loader: loader, downloadSource: downloadSource)
        isInstallingVersion = true
        let operation = Task { [weak self] in
            guard let self else { return }
            await self.performRemoteVersionInstall(
                version: version,
                loader: loader,
                downloadSource: downloadSource,
                taskID: taskID
            )
        }
        registerDownloadTaskOperation(taskID, operation: operation)
        return taskID
    }

    private func beginVersionInstallTask(
        version: MinecraftRemoteVersion,
        loader: String,
        downloadSource: MinecraftDownloadSource
    ) -> DownloadTaskRecord.ID {
        let taskID = beginDownloadTask(
            title: loader == "原版" ? version.id : "\(loader) \(version.id)",
            category: "版本安装",
            detail: "正在通过 \(downloadSource.rawValue) 准备安装 \(version.id)",
            progress: 0.05,
            retryAction: .installVersion(
                versionID: version.id,
                loader: loader,
                downloadSource: downloadSource.rawValue
            )
        )
        installMessage = loader == "原版" ? "正在安装 \(version.id)" : "正在安装 \(loader) \(version.id)"
        return taskID
    }

    private func performRemoteVersionInstall(
        version: MinecraftRemoteVersion,
        loader: String,
        downloadSource: MinecraftDownloadSource,
        taskID: DownloadTaskRecord.ID
    ) async {
        defer {
            isInstallingVersion = false
            finishDownloadTaskOperation(taskID)
        }

        do {
            try Task.checkCancellation()
            let installedInstanceName: String
            if loader == "Fabric" {
                updateDownloadTask(taskID, detail: "正在安装 Fabric Loader", progress: 0.35)
                try Task.checkCancellation()
                let result = try await FabricVersionInstaller(downloadSource: downloadSource).install(version, minecraftDirectory: minecraftDirectory)
                installedInstanceName = result.profileID
                installMessage = "已安装 Fabric \(version.id) / Loader \(result.loaderVersion)"
            } else if loader == "Quilt" {
                updateDownloadTask(taskID, detail: "正在安装 Quilt Loader", progress: 0.35)
                try Task.checkCancellation()
                let result = try await QuiltVersionInstaller(downloadSource: downloadSource).install(version, minecraftDirectory: minecraftDirectory)
                installedInstanceName = result.profileID
                installMessage = "已安装 Quilt \(version.id) / Loader \(result.loaderVersion)"
            } else if loader == "Forge" || loader == "NeoForge" {
                guard let java = selectedJava else {
                    installMessage = "安装失败：未找到可用 Java"
                    updateDownloadTask(taskID, status: .failed, detail: "安装失败：未找到可用 Java", progress: 1)
                    return
                }
                let provider: ForgeLikeProvider = loader == "Forge" ? .forge : .neoForge
                updateDownloadTask(taskID, detail: "正在下载并执行 \(provider.rawValue) installer", progress: 0.35)
                try Task.checkCancellation()
                let result = try await ForgeLikeVersionInstaller(provider: provider, downloadSource: downloadSource).install(
                    version,
                    minecraftDirectory: minecraftDirectory,
                    javaExecutable: java.executable,
                    appSupportDirectory: paths.appSupportDirectory
                )
                installedInstanceName = result.profileID
                installMessage = "已安装 \(provider.rawValue) \(version.id) / \(result.displayLoaderVersion)"
            } else {
                updateDownloadTask(taskID, detail: "正在写入原版版本 JSON", progress: 0.35)
                try Task.checkCancellation()
                let result = try await MinecraftVersionInstaller(downloadSource: downloadSource).install(version, minecraftDirectory: minecraftDirectory)
                installedInstanceName = result.version.id
                installMessage = "已安装 \(result.version.id)"
            }
            try Task.checkCancellation()
            await refreshEnvironment()
            selectedInstanceID = minecraftInstances.first(where: { $0.name == installedInstanceName })?.id ?? selectedInstanceID
            selectedPage = .launch
            updateDownloadTask(
                taskID,
                status: .succeeded,
                detail: "已安装 \(installedInstanceName)",
                progress: 1,
                destinationPath: minecraftDirectory.appendingPathComponent("versions/\(installedInstanceName)").path
            )
        } catch is CancellationError {
            installMessage = "已暂停安装：\(loader == "原版" ? version.id : "\(loader) \(version.id)")"
            updateDownloadTask(
                taskID,
                status: .paused,
                detail: "已暂停；已完成的文件会保留，点击继续会跳过已完成部分"
            )
        } catch {
            installMessage = "安装失败：\(error.localizedDescription)"
            updateDownloadTask(taskID, status: .failed, detail: installMessage, progress: 1)
        }
    }

    func searchModrinthMods() async {
        await searchModrinthResources(.mod)
    }

    func searchModrinthResources(_ projectType: ModrinthProjectType) async {
        if isSearchingModrinth { return }
        isSearchingModrinth = true
        let query = modrinthQuery.trimmed.isEmpty ? projectType.defaultSearchQuery : modrinthQuery.trimmed
        modrinthQuery = query
        modrinthMessage = "正在搜索 Modrinth \(projectType.displayName)"
        do {
            let service = ModrinthResourceService()
            let request = ModrinthSearchRequest(
                projectType: projectType,
                query: query,
                minecraftVersion: resourceMinecraftVersion(),
                loader: resourceLoaderFilter(for: projectType),
                limit: 30
            )
            let response = try await service.searchResources(request)
            modrinthResults = response.hits
            selectedModrinthProjectID = response.hits.first?.id
            let versionText = resourceMinecraftVersion() ?? "全部版本"
            if let loaderText = resourceLoaderFilter(for: projectType) {
                modrinthMessage = "找到 \(response.hits.count)/\(response.totalHits) 个\(projectType.displayName)：\(versionText)，\(loaderText)"
            } else {
                modrinthMessage = "找到 \(response.hits.count)/\(response.totalHits) 个\(projectType.displayName)：\(versionText)"
            }
        } catch {
            modrinthMessage = "Modrinth 搜索失败：\(error.localizedDescription)"
        }
        isSearchingModrinth = false
    }

    func installSelectedModrinthMod() async {
        await installSelectedModrinthResource(.mod)
    }

    func chooseAndImportLocalModrinthPack() {
        guard !isInstallingModrinthMod else { return }
        let panel = NSOpenPanel()
        panel.title = "选择 Modrinth 整合包"
        panel.message = "选择一个 .mrpack 文件导入为独立 Minecraft 实例"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let mrpackType = UTType(filenameExtension: "mrpack") {
            panel.allowedContentTypes = [mrpackType]
        }

        guard panel.runModal() == .OK, let packURL = panel.url else {
            modrinthMessage = "已取消本地整合包导入"
            return
        }

        Task { await importLocalModrinthPack(from: packURL) }
    }

    func importLocalModrinthPack(from packURL: URL) async {
        if isInstallingModrinthMod { return }
        guard isModrinthPackFileURL(packURL) else {
            modrinthMessage = "请选择 .mrpack 整合包文件"
            return
        }
        let taskID = beginDownloadTask(
            title: packURL.lastPathComponent,
            category: "本地整合包",
            detail: "正在读取 Modrinth 整合包",
            progress: 0.10,
            destinationPath: packURL.path
        )
        isInstallingModrinthMod = true
        lastModrinthFileURL = packURL
        lastModrinthProjectTitle = packURL.deletingPathExtension().lastPathComponent
        lastModrinthPackPlan = nil
        lastModrinthPackImportResult = nil
        modrinthMessage = "正在读取本地整合包：\(packURL.lastPathComponent)"

        do {
            let plan = try ModrinthPackInspector().inspect(packURL, importRoot: minecraftDirectory)
            lastModrinthPackPlan = plan
            modrinthMessage = "已通过预检，正在导入：\(plan.name)"
            updateDownloadTask(taskID, detail: "正在导入 \(plan.name)", progress: 0.35)
            let importResult = try await importDownloadedModrinthPack(packURL)
            lastModrinthPackImportResult = importResult
            lastModrinthPackPlan = importResult.plan
            await refreshEnvironment()
            selectedInstanceID = minecraftInstances.first(where: { $0.name == importResult.instanceName })?.id ?? selectedInstanceID
            lastEvent = "已导入本地整合包实例：\(importResult.instanceName)"
            modrinthMessage = "已导入 \(importResult.plan.name)：下载 \(importResult.downloadedFiles)，跳过 \(importResult.skippedFiles)，覆盖 \(importResult.copiedOverrides)"
            updateDownloadTask(
                taskID,
                status: .succeeded,
                detail: modrinthMessage,
                progress: 1,
                destinationPath: minecraftDirectory.appendingPathComponent("versions/\(importResult.instanceName)").path
            )
        } catch {
            modrinthMessage = "本地整合包导入失败：\(error.localizedDescription)"
            updateDownloadTask(taskID, status: .failed, detail: modrinthMessage, progress: 1)
        }
        isInstallingModrinthMod = false
    }

    func chooseAndImportLocalCurseForgePack() {
        guard !isInstallingCurseForgeResource else { return }
        let panel = NSOpenPanel()
        panel.title = "选择 CurseForge 整合包"
        panel.message = "选择一个 CurseForge .zip 整合包导入为独立 Minecraft 实例"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let zipType = UTType(filenameExtension: "zip") {
            panel.allowedContentTypes = [zipType]
        }

        guard panel.runModal() == .OK, let packURL = panel.url else {
            curseForgeMessage = "已取消本地 CurseForge 整合包导入"
            return
        }

        Task { await importLocalCurseForgePack(from: packURL) }
    }

    func importLocalCurseForgePack(from packURL: URL) async {
        guard hasCurseForgeAPIKey else {
            curseForgeMessage = "请先在下载设置中配置 CurseForge API Key"
            selectedSettingsSection = .download
            selectedPage = .settings
            return
        }
        if isInstallingCurseForgeResource { return }
        guard isCurseForgePackFileURL(packURL) else {
            curseForgeMessage = "请选择 CurseForge .zip 整合包文件"
            return
        }

        let taskID = beginDownloadTask(
            title: packURL.lastPathComponent,
            category: "本地 CurseForge 整合包",
            detail: "正在读取 CurseForge 整合包",
            progress: 0.10,
            destinationPath: packURL.path
        )
        isInstallingCurseForgeResource = true
        lastCurseForgeFileURL = packURL
        lastCurseForgeProjectTitle = packURL.deletingPathExtension().lastPathComponent
        lastCurseForgePackPlan = nil
        lastCurseForgePackImportResult = nil
        curseForgeMessage = "正在读取本地 CurseForge 整合包：\(packURL.lastPathComponent)"

        do {
            let plan = try CurseForgePackInspector().inspect(packURL, importRoot: minecraftDirectory)
            lastCurseForgePackPlan = plan
            curseForgeMessage = "已通过预检，正在导入：\(plan.name)"
            updateDownloadTask(taskID, detail: "正在导入 \(plan.name)", progress: 0.35)
            let importResult = try await importDownloadedCurseForgePack(packURL)
            lastCurseForgePackImportResult = importResult
            lastCurseForgePackPlan = importResult.plan
            await refreshEnvironment()
            selectedInstanceID = minecraftInstances.first(where: { $0.name == importResult.instanceName })?.id ?? selectedInstanceID
            lastEvent = "已导入本地 CurseForge 整合包实例：\(importResult.instanceName)"
            curseForgeMessage = "已导入 \(importResult.plan.name)：下载 \(importResult.downloadedFiles)，跳过 \(importResult.skippedFiles)，覆盖 \(importResult.copiedOverrides)"
            updateDownloadTask(
                taskID,
                status: .succeeded,
                detail: curseForgeMessage,
                progress: 1,
                destinationPath: minecraftDirectory.appendingPathComponent("versions/\(importResult.instanceName)").path
            )
        } catch {
            curseForgeMessage = "本地 CurseForge 整合包导入失败：\(error.localizedDescription)"
            updateDownloadTask(taskID, status: .failed, detail: curseForgeMessage, progress: 1)
        }
        isInstallingCurseForgeResource = false
    }

    func installSelectedModrinthResource(_ projectType: ModrinthProjectType) async {
        guard let project = selectedModrinthProject else {
            modrinthMessage = "请先选择一个\(projectType.displayName)"
            return
        }
        guard let destinationDirectory = modrinthDestinationDirectory(for: projectType) else {
            modrinthMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        if isInstallingModrinthMod { return }
        let taskID = beginDownloadTask(
            title: project.title,
            category: "Modrinth \(projectType.displayName)",
            detail: "正在处理 \(project.title)",
            progress: 0.10
        )
        isInstallingModrinthMod = true
        modrinthMessage = "正在处理 \(project.title)"
        do {
            let service = ModrinthResourceService()
            let selectedFile = selectedModrinthVersionFile(projectType: projectType)
            updateDownloadTask(
                taskID,
                detail: selectedFile == nil ? "正在下载最新文件" : "正在下载所选文件",
                progress: 0.35
            )
            let result: ModrinthInstallResult
            if let selectedFile {
                result = try await service.installResourceFile(
                    project: project,
                    version: selectedFile.version,
                    file: selectedFile.file,
                    projectType: projectType,
                    destinationDirectory: destinationDirectory
                )
            } else {
                result = try await service.installLatestResource(
                    project: project,
                    projectID: project.projectID,
                    projectType: projectType,
                    minecraftVersion: resourceMinecraftVersion(),
                    loader: resourceLoaderFilter(for: projectType),
                    destinationDirectory: destinationDirectory
                )
            }
            lastModrinthFileURL = result.destination
            lastModrinthProjectTitle = project.title
            lastModrinthPackPlan = nil
            lastModrinthPackImportResult = nil
            if projectType == .modpack {
                do {
                    let plan = try ModrinthPackInspector().inspect(result.destination, importRoot: minecraftDirectory)
                    lastModrinthPackPlan = plan
                    modrinthMessage = "已保存并通过预检，正在导入：\(plan.name)"
                    updateDownloadTask(taskID, detail: "正在导入整合包：\(plan.name)", progress: 0.60, destinationPath: result.destination.path)
                    let importResult = try await importDownloadedModrinthPack(result.destination)
                    lastModrinthPackImportResult = importResult
                    lastModrinthPackPlan = importResult.plan
                    await refreshEnvironment()
                    selectedInstanceID = minecraftInstances.first(where: { $0.name == importResult.instanceName })?.id ?? selectedInstanceID
                    lastEvent = "已导入整合包实例：\(importResult.instanceName)"
                    modrinthMessage = "已导入 \(importResult.plan.name)：下载 \(importResult.downloadedFiles)，跳过 \(importResult.skippedFiles)，覆盖 \(importResult.copiedOverrides)"
                    updateDownloadTask(
                        taskID,
                        status: .succeeded,
                        detail: modrinthMessage,
                        progress: 1,
                        destinationPath: minecraftDirectory.appendingPathComponent("versions/\(importResult.instanceName)").path
                    )
                } catch {
                    modrinthMessage = "已保存 \(project.title)：\(result.file.filename)，但整合包导入失败：\(error.localizedDescription)"
                    updateDownloadTask(taskID, status: .failed, detail: modrinthMessage, progress: 1, destinationPath: result.destination.path)
                }
            } else {
                modrinthMessage = "已保存 \(project.title)：\(result.file.filename)"
                updateDownloadTask(taskID, status: .succeeded, detail: modrinthMessage, progress: 1, destinationPath: result.destination.path)
                if projectType == .mod {
                    await refreshLocalMods()
                }
            }
        } catch {
            modrinthMessage = "\(projectType.displayName) 处理失败：\(error.localizedDescription)"
            updateDownloadTask(taskID, status: .failed, detail: modrinthMessage, progress: 1)
        }
        isInstallingModrinthMod = false
    }

    func searchCurseForgeResources(_ resourceType: CurseForgeResourceType) async {
        guard hasCurseForgeAPIKey else {
            curseForgeMessage = "请先在下载设置中配置 CurseForge API Key"
            selectedSettingsSection = .download
            return
        }
        if isSearchingCurseForge { return }
        isSearchingCurseForge = true
        let query = curseForgeQuery.trimmed.isEmpty ? resourceType.defaultSearchQuery : curseForgeQuery.trimmed
        curseForgeQuery = query
        curseForgeMessage = "正在搜索 CurseForge \(resourceType.displayName)"
        do {
            let service = CurseForgeResourceService()
            let request = CurseForgeSearchRequest(
                apiKey: effectiveCurseForgeAPIKey,
                resourceType: resourceType,
                query: query,
                minecraftVersion: resourceMinecraftVersion(),
                loader: resourceLoaderFilter(for: resourceType.modrinthProjectType),
                pageSize: 30
            )
            let response = try await service.searchResources(request)
            curseForgeResults = response.data
            selectedCurseForgeProjectID = response.data.first?.id
            let versionText = resourceMinecraftVersion() ?? "全部版本"
            if let loaderText = resourceLoaderFilter(for: resourceType.modrinthProjectType), resourceType.supportsLoaderFiltering {
                curseForgeMessage = "找到 \(response.pagination.resultCount)/\(response.pagination.totalCount) 个\(resourceType.displayName)：\(versionText)，\(loaderText)"
            } else {
                curseForgeMessage = "找到 \(response.pagination.resultCount)/\(response.pagination.totalCount) 个\(resourceType.displayName)：\(versionText)"
            }
        } catch {
            curseForgeMessage = "CurseForge 搜索失败：\(error.localizedDescription)"
        }
        isSearchingCurseForge = false
    }

    func installSelectedCurseForgeResource(_ resourceType: CurseForgeResourceType) async {
        guard hasCurseForgeAPIKey else {
            curseForgeMessage = "请先在下载设置中配置 CurseForge API Key"
            selectedSettingsSection = .download
            return
        }
        guard let project = selectedCurseForgeProject else {
            curseForgeMessage = "请先选择一个\(resourceType.displayName)"
            return
        }
        guard let destinationDirectory = curseForgeDestinationDirectory(for: resourceType) else {
            curseForgeMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        if isInstallingCurseForgeResource { return }
        let taskID = beginDownloadTask(
            title: project.name,
            category: "CurseForge \(resourceType.displayName)",
            detail: "正在处理 \(project.name)",
            progress: 0.10
        )
        isInstallingCurseForgeResource = true
        curseForgeMessage = "正在处理 \(project.name)"
        do {
            let service = CurseForgeResourceService()
            let selectedFile = selectedCurseForgeFile(resourceType: resourceType)
            updateDownloadTask(
                taskID,
                detail: selectedFile == nil ? "正在下载最新文件" : "正在下载所选文件",
                progress: 0.35
            )
            let result: CurseForgeInstallResult
            if let selectedFile {
                result = try await service.installResourceFile(
                    project: project,
                    file: selectedFile,
                    resourceType: resourceType,
                    apiKey: effectiveCurseForgeAPIKey,
                    destinationDirectory: destinationDirectory
                )
            } else {
                result = try await service.installLatestResource(
                    project: project,
                    resourceType: resourceType,
                    apiKey: effectiveCurseForgeAPIKey,
                    minecraftVersion: resourceMinecraftVersion(),
                    loader: resourceLoaderFilter(for: resourceType.modrinthProjectType),
                    destinationDirectory: destinationDirectory
                )
            }
            lastCurseForgeFileURL = result.destination
            lastCurseForgeProjectTitle = project.name
            lastCurseForgePackPlan = nil
            lastCurseForgePackImportResult = nil
            if resourceType == .modpack {
                do {
                    let plan = try CurseForgePackInspector().inspect(result.destination, importRoot: minecraftDirectory)
                    lastCurseForgePackPlan = plan
                    curseForgeMessage = "已保存并通过预检，正在导入：\(plan.name)"
                    updateDownloadTask(taskID, detail: "正在导入整合包：\(plan.name)", progress: 0.60, destinationPath: result.destination.path)
                    let importResult = try await importDownloadedCurseForgePack(result.destination)
                    lastCurseForgePackImportResult = importResult
                    lastCurseForgePackPlan = importResult.plan
                    await refreshEnvironment()
                    selectedInstanceID = minecraftInstances.first(where: { $0.name == importResult.instanceName })?.id ?? selectedInstanceID
                    lastEvent = "已导入 CurseForge 整合包实例：\(importResult.instanceName)"
                    curseForgeMessage = "已导入 \(importResult.plan.name)：下载 \(importResult.downloadedFiles)，跳过 \(importResult.skippedFiles)，覆盖 \(importResult.copiedOverrides)"
                    updateDownloadTask(
                        taskID,
                        status: .succeeded,
                        detail: curseForgeMessage,
                        progress: 1,
                        destinationPath: minecraftDirectory.appendingPathComponent("versions/\(importResult.instanceName)").path
                    )
                } catch {
                    curseForgeMessage = "已保存 \(project.name)：\(result.file.fileName)，但整合包导入失败：\(error.localizedDescription)"
                    updateDownloadTask(taskID, status: .failed, detail: curseForgeMessage, progress: 1, destinationPath: result.destination.path)
                }
            } else {
                curseForgeMessage = "已保存 \(project.name)：\(result.file.fileName)"
                updateDownloadTask(taskID, status: .succeeded, detail: curseForgeMessage, progress: 1, destinationPath: result.destination.path)
                if resourceType == .mod {
                    await refreshLocalMods()
                }
            }
        } catch {
            curseForgeMessage = "\(resourceType.displayName) 处理失败：\(error.localizedDescription)"
            updateDownloadTask(taskID, status: .failed, detail: curseForgeMessage, progress: 1)
        }
        isInstallingCurseForgeResource = false
    }

    private func importDownloadedModrinthPack(_ packURL: URL) async throws -> ModrinthPackImportResult {
        let inspector = ModrinthPackInspector()
        let index = try inspector.loadIndex(packURL)
        guard let minecraftVersion = index.dependencies["minecraft"]?.trimmed.nonEmpty else {
            throw ModrinthPackInspectionError.missingMinecraftVersion
        }
        let remoteVersion = try await remoteMinecraftVersion(id: minecraftVersion)
        let profileID = try await installPackProfile(index: index, remoteVersion: remoteVersion)
        return try await ModrinthPackImporter().importPack(
            packURL,
            minecraftDirectory: minecraftDirectory,
            inheritedProfileID: profileID
        ) { [weak self] message in
            await MainActor.run {
                self?.modrinthMessage = message
            }
        }
    }

    private func importDownloadedCurseForgePack(_ packURL: URL) async throws -> CurseForgePackImportResult {
        let inspector = CurseForgePackInspector()
        let manifest = try inspector.loadManifest(packURL)
        let remoteVersion = try await remoteMinecraftVersion(id: manifest.minecraft.version)
        let profileID = try await installPackProfile(manifest: manifest, remoteVersion: remoteVersion)
        return try await CurseForgePackImporter().importPack(
            packURL,
            apiKey: effectiveCurseForgeAPIKey,
            minecraftDirectory: minecraftDirectory,
            inheritedProfileID: profileID
        ) { [weak self] message in
            await MainActor.run {
                self?.curseForgeMessage = message
            }
        }
    }

    private func remoteMinecraftVersion(id: String) async throws -> MinecraftRemoteVersion {
        if let version = remoteVersions.first(where: { $0.id == id }) {
            return version
        }
        let manifest = try await MinecraftVersionInstaller(downloadSource: effectiveDownloadSource).fetchManifest()
        remoteVersions = manifest.versions
        guard let version = manifest.versions.first(where: { $0.id == id }) else {
            throw ModrinthPackImportError.missingMinecraftVersionInManifest(id)
        }
        return version
    }

    private func installPackProfile(index: ModrinthPackIndex, remoteVersion: MinecraftRemoteVersion) async throws -> String {
        if let fabric = index.dependencies["fabric-loader"]?.trimmed.nonEmpty {
            let result = try await FabricVersionInstaller(downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                loaderVersion: fabric,
                minecraftDirectory: minecraftDirectory
            )
            return result.profileID
        }
        if let quilt = index.dependencies["quilt-loader"]?.trimmed.nonEmpty {
            let result = try await QuiltVersionInstaller(downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                loaderVersion: quilt,
                minecraftDirectory: minecraftDirectory
            )
            return result.profileID
        }
        if let forge = index.dependencies["forge"]?.trimmed.nonEmpty {
            guard let java = selectedJava else {
                throw ModrinthPackImportError.missingJavaForForge("Forge")
            }
            let result = try await ForgeLikeVersionInstaller(provider: .forge, downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                minecraftDirectory: minecraftDirectory,
                javaExecutable: java.executable,
                appSupportDirectory: paths.appSupportDirectory,
                loaderVersion: forge
            )
            return result.profileID
        }
        if let neoForge = index.dependencies["neoforge"]?.trimmed.nonEmpty {
            guard let java = selectedJava else {
                throw ModrinthPackImportError.missingJavaForForge("NeoForge")
            }
            let result = try await ForgeLikeVersionInstaller(provider: .neoForge, downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                minecraftDirectory: minecraftDirectory,
                javaExecutable: java.executable,
                appSupportDirectory: paths.appSupportDirectory,
                loaderVersion: neoForge
            )
            return result.profileID
        }

        let result = try await MinecraftVersionInstaller(downloadSource: effectiveDownloadSource).install(remoteVersion, minecraftDirectory: minecraftDirectory)
        return result.version.id
    }

    private func installPackProfile(manifest: CurseForgePackManifest, remoteVersion: MinecraftRemoteVersion) async throws -> String {
        let loaderIDs = manifest.minecraft.modLoaders ?? []
        if let fabric = curseForgeLoaderVersion(loaderIDs, prefix: "fabric-") {
            let result = try await FabricVersionInstaller(downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                loaderVersion: fabric,
                minecraftDirectory: minecraftDirectory
            )
            return result.profileID
        }
        if let quilt = curseForgeLoaderVersion(loaderIDs, prefix: "quilt-") {
            let result = try await QuiltVersionInstaller(downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                loaderVersion: quilt,
                minecraftDirectory: minecraftDirectory
            )
            return result.profileID
        }
        if let forge = curseForgeLoaderVersion(loaderIDs, prefix: "forge-") {
            guard !forge.localizedCaseInsensitiveContains("recommended") else {
                throw ModrinthPackImportError.unsupportedPackLoader("forge-\(forge)")
            }
            guard let java = selectedJava else {
                throw ModrinthPackImportError.missingJavaForForge("Forge")
            }
            let result = try await ForgeLikeVersionInstaller(provider: .forge, downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                minecraftDirectory: minecraftDirectory,
                javaExecutable: java.executable,
                appSupportDirectory: paths.appSupportDirectory,
                loaderVersion: forge
            )
            return result.profileID
        }
        if let neoForge = curseForgeLoaderVersion(loaderIDs, prefix: "neoforge-") {
            guard let java = selectedJava else {
                throw ModrinthPackImportError.missingJavaForForge("NeoForge")
            }
            let result = try await ForgeLikeVersionInstaller(provider: .neoForge, downloadSource: effectiveDownloadSource).install(
                remoteVersion,
                minecraftDirectory: minecraftDirectory,
                javaExecutable: java.executable,
                appSupportDirectory: paths.appSupportDirectory,
                loaderVersion: neoForge
            )
            return result.profileID
        }
        if let unsupported = loaderIDs.first?.id, !unsupported.trimmed.isEmpty {
            throw ModrinthPackImportError.unsupportedPackLoader(unsupported)
        }

        let result = try await MinecraftVersionInstaller(downloadSource: effectiveDownloadSource).install(remoteVersion, minecraftDirectory: minecraftDirectory)
        return result.version.id
    }

    private func curseForgeLoaderVersion(_ loaders: [CurseForgePackModLoader], prefix: String) -> String? {
        let candidates = loaders.sorted { lhs, rhs in
            (lhs.primary ?? false) && !(rhs.primary ?? false)
        }
        guard let loader = candidates.first(where: { $0.id.lowercased().hasPrefix(prefix) }) else {
            return nil
        }
        return String(loader.id.dropFirst(prefix.count)).trimmed.nonEmpty
    }

    func showImportedModrinthPackInstance() {
        guard let result = lastModrinthPackImportResult else {
            modrinthMessage = "还没有导入完成的整合包实例"
            return
        }
        selectedInstanceID = minecraftInstances.first(where: { $0.name == result.instanceName })?.id ?? selectedInstanceID
        selectedPage = .launch
    }

    func showImportedCurseForgePackInstance() {
        guard let result = lastCurseForgePackImportResult else {
            curseForgeMessage = "还没有导入完成的 CurseForge 整合包实例"
            return
        }
        selectedInstanceID = minecraftInstances.first(where: { $0.name == result.instanceName })?.id ?? selectedInstanceID
        selectedPage = .launch
    }

    func openModrinthDestinationFolder(_ projectType: ModrinthProjectType) {
        guard let destinationDirectory = modrinthDestinationDirectory(for: projectType) else {
            modrinthMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(destinationDirectory)
    }

    func revealLastModrinthFileInFinder() {
        guard let fileURL = lastModrinthFileURL else {
            modrinthMessage = "还没有最近保存的 Modrinth 文件"
            return
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return
        }

        let parent = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
            modrinthMessage = "文件已不存在，已打开保存目录"
        } else {
            modrinthMessage = "最近保存的文件和目录都不存在"
        }
    }

    func openCurseForgeDestinationFolder(_ resourceType: CurseForgeResourceType) {
        guard let destinationDirectory = curseForgeDestinationDirectory(for: resourceType) else {
            curseForgeMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(destinationDirectory)
    }

    func revealLastCurseForgeFileInFinder() {
        guard let fileURL = lastCurseForgeFileURL else {
            curseForgeMessage = "还没有最近保存的 CurseForge 文件"
            return
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return
        }

        let parent = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
            curseForgeMessage = "文件已不存在，已打开保存目录"
        } else {
            curseForgeMessage = "最近保存的文件和目录都不存在"
        }
    }

    func refreshLocalMods() async {
        guard let instance = selectedInstance else {
            localModFiles = []
            selectedLocalModFileID = nil
            localModMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        if isLoadingLocalMods { return }
        isLoadingLocalMods = true
        localModMessage = "正在读取 \(instance.name) 的 mods 文件夹"
        do {
            let instanceDirectory = instance.path
            let files = try await Task.detached(priority: .utility) {
                try LocalModManager().scan(instanceDirectory: instanceDirectory)
            }.value
            localModFiles = files
            if let selectedLocalModFileID,
               files.contains(where: { $0.id == selectedLocalModFileID }) {
                self.selectedLocalModFileID = selectedLocalModFileID
            } else {
                selectedLocalModFileID = files.first?.id
            }
            localModMessage = files.isEmpty ? "当前实例没有已安装 Mod" : "发现 \(files.count) 个本地 Mod"
        } catch {
            localModMessage = "读取本地 Mod 失败：\(error.localizedDescription)"
        }
        isLoadingLocalMods = false
    }

    func openLocalModsFolder() {
        guard let instance = selectedInstance else {
            localModMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        let directory = LocalModManager().modsDirectory(for: instance.path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
        localModMessage = "已打开 mods 文件夹：\(instance.name)"
    }

    func chooseAndImportLocalMods() {
        guard let selectedInstance else {
            localModMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "添加本地 Mod"
        panel.message = "选择 .jar、.zip 或 .litemod 文件复制到 \(selectedInstance.name) 的 mods 文件夹"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        let allowedTypes = ["jar", "zip", "litemod"].compactMap { UTType(filenameExtension: $0) }
        if !allowedTypes.isEmpty {
            panel.allowedContentTypes = allowedTypes
        }

        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            localModMessage = "已取消添加本地 Mod"
            return
        }

        Task { await importLocalModFiles(panel.urls) }
    }

    func importLocalModFiles(_ urls: [URL]) async {
        guard let instance = selectedInstance else {
            localModMessage = "请先在启动页选择一个 Minecraft 实例"
            return
        }
        guard !urls.isEmpty else { return }
        isLoadingLocalMods = true
        localModMessage = "正在添加 \(urls.count) 个本地 Mod"
        do {
            let instanceDirectory = instance.path
            let imported = try await Task.detached(priority: .utility) {
                try LocalModManager().importFiles(urls, instanceDirectory: instanceDirectory)
            }.value
            isLoadingLocalMods = false
            await refreshLocalMods()
            selectedLocalModFileID = imported.first?.id ?? selectedLocalModFileID
            localModMessage = imported.isEmpty ? "没有添加新的 Mod" : "已添加 \(imported.count) 个本地 Mod"
        } catch {
            localModMessage = "添加本地 Mod 失败：\(error.localizedDescription)"
        }
        isLoadingLocalMods = false
    }

    func revealSelectedLocalModInFinder() {
        guard let file = selectedLocalModFile else {
            localModMessage = "还没有可显示的本地 Mod"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func toggleSelectedLocalMod() async {
        guard let file = selectedLocalModFile else {
            localModMessage = "请先选择一个本地 Mod"
            return
        }
        do {
            let updated = try await Task.detached(priority: .utility) {
                try LocalModManager().toggle(file)
            }.value
            await refreshLocalMods()
            selectedLocalModFileID = updated.id
            localModMessage = "\(file.displayName) \(updated.status == .enabled ? "已启用" : "已禁用")"
        } catch {
            localModMessage = "切换 Mod 状态失败：\(error.localizedDescription)"
        }
    }

    private func modrinthDestinationDirectory(for projectType: ModrinthProjectType) -> URL? {
        switch projectType {
        case .mod:
            selectedInstance?.path.appendingPathComponent("mods", isDirectory: true)
        case .modpack:
            paths.appSupportDirectory.appendingPathComponent("ModrinthPacks", isDirectory: true)
        case .datapack:
            paths.appSupportDirectory.appendingPathComponent("Datapacks", isDirectory: true)
        case .resourcepack:
            minecraftDirectory.appendingPathComponent("resourcepacks", isDirectory: true)
        case .shader:
            minecraftDirectory.appendingPathComponent("shaderpacks", isDirectory: true)
        }
    }

    private func curseForgeDestinationDirectory(for resourceType: CurseForgeResourceType) -> URL? {
        switch resourceType {
        case .mod:
            selectedInstance?.path.appendingPathComponent("mods", isDirectory: true)
        case .modpack:
            paths.appSupportDirectory.appendingPathComponent("CurseForgePacks", isDirectory: true)
        case .resourcePack:
            minecraftDirectory.appendingPathComponent("resourcepacks", isDirectory: true)
        }
    }

    private func resourceMinecraftVersion() -> String? {
        guard let instance = selectedInstance else {
            return selectedRemoteVersion?.id
        }
        if let chain = try? MinecraftVersionRepository().loadVersionChain(instance: instance, minecraftDirectory: minecraftDirectory),
           let base = chain.first?.id {
            return base
        }
        return instance.name
    }

    private func resourceLoaderFilter(for projectType: ModrinthProjectType = .mod) -> String? {
        guard projectType.supportsLoaderFiltering else { return nil }
        if let inferred = inferLoader(from: selectedInstance?.name) {
            return inferred
        }
        switch selectedInstallLoader {
        case "Forge": return "forge"
        case "Fabric": return "fabric"
        case "Quilt": return "quilt"
        case "NeoForge": return "neoforge"
        default: return nil
        }
    }

    private func inferLoader(from instanceName: String?) -> String? {
        guard let instanceName else { return nil }
        let value = instanceName.lowercased()
        if value.contains("neoforge") { return "neoforge" }
        if value.contains("fabric") { return "fabric" }
        if value.contains("quilt") { return "quilt" }
        if value.contains("forge") { return "forge" }
        return nil
    }

    func openSelectedVersionSettings() {
        selectedSettingsSection = .version
        selectedPage = .settings
        loadSelectedVersionSettings()
    }

    func openSelectedVersionJavaSettings() {
        openSelectedVersionSettings()
        versionSettingsMessage = "已打开当前版本的 Java 覆盖设置"
    }

    func useRecommendedCompatibleJavaForSelectedVersion() {
        guard let java = recommendedCompatibleJava else {
            openSelectedVersionJavaSettings()
            return
        }
        openSelectedVersionSettings()
        versionSettings.usesGlobalJava = false
        versionSettings.javaExecutablePath = java.executable.path
        saveSelectedVersionSettingsIfNeeded()
        lastEvent = "已为当前版本指定 \(java.versionSummary)"
    }

    func applyGlobalGameWindowPreset(_ preset: GameWindowSizePreset) {
        gameWindowWidth = preset.width
        gameWindowHeight = preset.height
        lastEvent = "已应用全局窗口预设：\(preset.rawValue)"
    }

    func applyGlobalMemoryPreset(_ preset: GameMemoryPreset) {
        memoryLimit = preset.megabytes
        lastEvent = "已应用全局内存预设：\(preset.rawValue)"
    }

    func applyVersionGameWindowPreset(_ preset: GameWindowSizePreset) {
        guard let instance = selectedInstance else {
            versionSettingsMessage = "请先选择一个版本"
            return
        }
        if versionSettings.usesGlobalWindow {
            versionSettings.usesGlobalWindow = false
            versionSettings.fullscreen = launchFullscreen
        }
        versionSettings.windowWidth = preset.width
        versionSettings.windowHeight = preset.height
        versionSettingsMessage = "已为 \(instance.name) 应用窗口预设：\(preset.rawValue)"
        lastEvent = versionSettingsMessage
    }

    func applyVersionMemoryPreset(_ preset: GameMemoryPreset) {
        guard let instance = selectedInstance else {
            versionSettingsMessage = "请先选择一个版本"
            return
        }
        if versionSettings.usesGlobalMemory {
            versionSettings.usesGlobalMemory = false
        }
        versionSettings.memoryMegabytes = preset.megabytes
        versionSettingsMessage = "已为 \(instance.name) 应用内存预设：\(preset.rawValue)"
        lastEvent = versionSettingsMessage
    }

    func installRecommendedJavaRuntime() {
        guard let component = recommendedJavaRuntimeComponent else {
            lastEvent = "当前版本没有可安装的 Java Runtime 建议"
            return
        }
        startJavaRuntimeInstall(component: component, downloadSource: effectiveDownloadSource)
    }

    private func startJavaRuntimeInstall(component: String, downloadSource: MinecraftDownloadSource) {
        guard !isInstallingJavaRuntime else {
            lastEvent = "Java Runtime 安装任务已在进行"
            return
        }

        let requiredMajor = recommendedJavaRuntimeMajorVersion
        let title = requiredMajor.map { "安装 Java \($0)+" } ?? "安装 Java Runtime"
        let taskID = beginDownloadTask(
            title: title,
            category: "Java Runtime",
            detail: "正在读取 Mojang Java Runtime 清单",
            progress: 0.02,
            retryAction: .installJavaRuntime(component: component, downloadSource: downloadSource.rawValue)
        )

        isInstallingJavaRuntime = true
        launchStatus = LaunchStatus(title: "正在安装 Java", detail: "准备下载 \(component)", progress: 0.02)
        lastEvent = "开始安装 \(component)"

        let operation = Task { [weak self] in
            guard let self else { return }
            await self.runJavaRuntimeInstall(component: component, downloadSource: downloadSource, taskID: taskID)
        }
        registerDownloadTaskOperation(taskID, operation: operation)
    }

    private func runJavaRuntimeInstall(
        component: String,
        downloadSource: MinecraftDownloadSource,
        taskID: DownloadTaskRecord.ID
    ) async {
        defer {
            isInstallingJavaRuntime = false
            finishDownloadTaskOperation(taskID)
        }

        do {
            let appSupportDirectory = paths.appSupportDirectory
            let javaProgressGate = JavaRuntimeProgressUpdateGate()
            let result = try await Task.detached(priority: .utility) {
                try await MojangJavaRuntimeInstaller(downloadSource: downloadSource).install(
                    component: component,
                    appSupportDirectory: appSupportDirectory
                ) { [weak self] progress in
                    guard await javaProgressGate.shouldEmit(progress) else { return }
                    await MainActor.run {
                        self?.updateDownloadTask(
                            taskID,
                            detail: "\(progress.finished)/\(progress.total) · \(progress.currentName)",
                            progress: max(0.03, min(0.96, progress.fraction))
                        )
                        self?.launchStatus = LaunchStatus(
                            title: "正在安装 Java",
                            detail: progress.currentName,
                            progress: max(0.03, min(0.96, progress.fraction))
                        )
                        self?.lastEvent = "Java Runtime：下载 \(progress.downloaded)，跳过 \(progress.skipped)"
                    }
                }
            }.value

            updateDownloadTask(taskID, detail: "正在刷新 Java 环境", progress: 0.97, destinationPath: result.runtimeDirectory.path)
            await refreshEnvironment()
            applyInstalledJavaRuntime(result)
            updateDownloadTask(
                taskID,
                status: .succeeded,
                detail: "已安装 \(result.versionName)，下载 \(result.installedFiles)，跳过 \(result.skippedFiles)",
                progress: 1,
                destinationPath: result.runtimeDirectory.path
            )
            launchStatus = currentLaunchReadinessStatus
            lastEvent = "已安装 Java \(result.versionName)，并应用到当前版本"
        } catch is CancellationError {
            updateDownloadTask(taskID, status: .paused, detail: "已暂停；点击继续会跳过已完成部分")
            launchStatus = currentLaunchReadinessStatus
            lastEvent = "已暂停 Java Runtime 安装"
        } catch {
            updateDownloadTask(taskID, status: .failed, detail: "安装失败：\(error.localizedDescription)", progress: 1)
            launchStatus = currentLaunchReadinessStatus
            lastEvent = "Java Runtime 安装失败：\(error.localizedDescription)"
        }
    }

    private func applyInstalledJavaRuntime(_ result: MojangJavaRuntimeInstallResult) {
        guard selectedInstance != nil else { return }
        var settings = versionSettings
        settings.usesGlobalJava = false
        settings.javaExecutablePath = result.javaExecutable.path
        versionSettings = settings
        if let java = javaInstallation(matching: result.javaExecutable) {
            selectedJavaPathPreference = java.executable.path
        }
    }

    func selectInstance(_ instance: MinecraftInstance) {
        selectedInstanceID = instance.id
    }

    func isFavoriteInstance(_ instance: MinecraftInstance) -> Bool {
        favoriteInstanceNames.contains(instance.name)
    }

    func isHiddenInstance(_ instance: MinecraftInstance) -> Bool {
        hiddenInstanceNames.contains(instance.name)
    }

    func toggleFavoriteSelectedInstance() {
        guard let instance = selectedInstance else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        if isFavoriteInstance(instance) {
            favoriteInstanceNames.removeAll { $0 == instance.name }
            lastEvent = "已取消收藏：\(instance.name)"
        } else {
            favoriteInstanceNames = Self.appendingUniqueInstanceName(instance.name, to: favoriteInstanceNames)
            hiddenInstanceNames.removeAll { $0 == instance.name }
            lastEvent = "已收藏版本：\(instance.name)"
        }
    }

    func toggleHiddenSelectedInstance() {
        guard let instance = selectedInstance else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        if isHiddenInstance(instance) {
            hiddenInstanceNames.removeAll { $0 == instance.name }
            lastEvent = "已取消隐藏：\(instance.name)"
        } else {
            hiddenInstanceNames = Self.appendingUniqueInstanceName(instance.name, to: hiddenInstanceNames)
            favoriteInstanceNames.removeAll { $0 == instance.name }
            lastEvent = "已隐藏版本：\(instance.name)"
            if !showsHiddenInstances {
                restoreSelectedInstance()
            }
        }
    }

    private static func appendingUniqueInstanceName(_ name: String, to names: [String]) -> [String] {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty, !names.contains(trimmed) else { return names }
        return names + [trimmed]
    }

    private func loadSelectedVersionSettings() {
        isLoadingVersionSettings = true
        defer { isLoadingVersionSettings = false }

        guard let instance = selectedInstance else {
            versionSettings = .defaults
            versionSettingsMessage = "选择版本后可调整版本级启动设置"
            return
        }
        versionSettings = cachedVersionSettings(for: instance)
        versionSettingsMessage = "已加载 \(instance.name) 的版本设置"
    }

    private func saveSelectedVersionSettingsIfNeeded() {
        guard !isLoadingVersionSettings, let instance = selectedInstance else { return }
        do {
            try versionSettingsStore.save(versionSettings, for: instance)
            versionSettingsCache[instanceCacheKey(instance)] = versionSettings.normalized
            versionSettingsMessage = "已保存 \(instance.name) 的版本设置"
        } catch {
            versionSettingsMessage = "保存版本设置失败：\(error.localizedDescription)"
        }
    }

    func resetSelectedVersionSettings() {
        guard let instance = selectedInstance else {
            versionSettingsMessage = "请先选择一个版本"
            return
        }
        do {
            try versionSettingsStore.reset(for: instance)
            versionSettingsCache.removeValue(forKey: instanceCacheKey(instance))
            loadSelectedVersionSettings()
            versionSettingsMessage = "已恢复 \(instance.name) 的全局默认设置"
        } catch {
            versionSettingsMessage = "重置版本设置失败：\(error.localizedDescription)"
        }
    }

    private func effectiveJavaURL(for instance: MinecraftInstance) -> URL? {
        let settings = activeVersionSettings(for: instance)
        if !settings.usesGlobalJava,
           let path = settings.javaExecutablePath?.trimmed.nonEmpty {
            return URL(fileURLWithPath: path)
        }
        return effectiveJavaInstallation(for: instance, settings: settings)?.executable
    }

    private func effectiveJavaInstallation(for instance: MinecraftInstance, settings: VersionLaunchSettings) -> JavaInstallation? {
        if !settings.usesGlobalJava {
            return nil
        }
        guard autoSelectJava else {
            return selectedJava
        }
        let requiredMajorVersion = requiredJavaMajorVersion(for: instance)
        return JavaVersionSelector().select(
            from: javaInstallations,
            requiredMajorVersion: requiredMajorVersion,
            fallback: selectedJava
        )
    }

    private func javaCompatibilityError(for instance: MinecraftInstance, javaExecutable: URL) -> LauncherPreparationError? {
        guard let requiredMajorVersion = requiredJavaMajorVersion(for: instance),
              let java = javaInstallation(matching: javaExecutable),
              let actualMajorVersion = JavaVersionSelector.majorVersion(from: java.versionSummary),
              actualMajorVersion < requiredMajorVersion else {
            return nil
        }
        return .incompatibleJava(
            required: requiredMajorVersion,
            actual: actualMajorVersion,
            summary: java.versionSummary
        )
    }

    private func javaInstallation(matching executable: URL) -> JavaInstallation? {
        let standardizedPath = executable.standardizedFileURL.path
        return javaInstallations.first { $0.executable.standardizedFileURL.path == standardizedPath }
    }

    private func compatibleJavaInstallation(requiredMajorVersion: Int) -> JavaInstallation? {
        javaInstallations
            .compactMap { installation -> (JavaInstallation, Int)? in
                guard let major = JavaVersionSelector.majorVersion(from: installation.versionSummary),
                      major >= requiredMajorVersion else {
                    return nil
                }
                return (installation, major)
            }
            .min { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.versionSummary.localizedStandardCompare(rhs.0.versionSummary) == .orderedAscending
                }
                return lhs.1 < rhs.1
            }?
            .0
    }

    private func requiredJavaMajorVersion(for instance: MinecraftInstance) -> Int? {
        let key = instanceCacheKey(instance)
        if let cached = requiredJavaMajorVersionCache[key] {
            return cached
        }
        if noRequiredJavaMajorVersionCache.contains(key) {
            return nil
        }
        guard let chain = try? MinecraftVersionRepository().loadVersionChain(
            instance: instance,
            minecraftDirectory: minecraftDirectory
        ) else {
            noRequiredJavaMajorVersionCache.insert(key)
            return nil
        }
        guard let majorVersion = requiredMinecraftJavaMajorVersion(from: chain) else {
            noRequiredJavaMajorVersionCache.insert(key)
            return nil
        }
        requiredJavaMajorVersionCache[key] = majorVersion
        return majorVersion
    }

    private func requiredJavaRuntimeComponent(for instance: MinecraftInstance) -> String? {
        if let majorVersion = requiredJavaMajorVersion(for: instance) {
            return MojangJavaRuntimeInstaller.component(forMajorVersion: majorVersion)
        }
        guard let chain = try? MinecraftVersionRepository().loadVersionChain(
            instance: instance,
            minecraftDirectory: minecraftDirectory
        ) else {
            return nil
        }
        return chain.reversed().compactMap(\.javaVersion?.component).first
    }

    private func effectiveMemoryMegabytes(for instance: MinecraftInstance) -> Int {
        let settings = activeVersionSettings(for: instance)
        if !settings.usesGlobalMemory,
           let memory = settings.memoryMegabytes {
            return Int(memory)
        }
        return Int(memoryLimit)
    }

    private func activeVersionSettings(for instance: MinecraftInstance) -> VersionLaunchSettings {
        guard let selectedInstance,
              instanceCacheKey(selectedInstance) == instanceCacheKey(instance) else {
            return cachedVersionSettings(for: instance)
        }
        return versionSettings
    }

    func effectiveExtraJvmArgumentList(for instance: MinecraftInstance) -> [String] {
        effectiveExtraJvmArgumentList(settings: activeVersionSettings(for: instance))
    }

    func effectiveExtraGameArgumentList(for instance: MinecraftInstance) -> [String] {
        effectiveExtraGameArgumentList(settings: activeVersionSettings(for: instance))
    }

    private func effectiveExtraJvmArgumentList(settings: VersionLaunchSettings) -> [String] {
        globalExtraJvmArgumentList + settings.extraJvmArgumentList
    }

    private func effectiveExtraGameArgumentList(settings: VersionLaunchSettings) -> [String] {
        globalExtraGameArgumentList + settings.extraGameArgumentList
    }

    private func cachedVersionSettings(for instance: MinecraftInstance) -> VersionLaunchSettings {
        let key = instanceCacheKey(instance)
        if let settings = versionSettingsCache[key] {
            return settings
        }
        let settings = versionSettingsStore.load(for: instance)
        versionSettingsCache[key] = settings
        return settings
    }

    private func instanceCacheKey(_ instance: MinecraftInstance) -> String {
        instance.path.standardizedFileURL.path
    }

    private func effectiveGameDirectory(for instance: MinecraftInstance, settings: VersionLaunchSettings) -> URL {
        let isolated: Bool
        if !settings.usesGlobalGameDirectory,
           let override = settings.usesIsolatedGameDirectory {
            isolated = override
        } else {
            isolated = useVersionIsolation
        }
        return isolated ? instance.path : minecraftDirectory
    }

    private func effectiveServerAddress(settings: VersionLaunchSettings) -> String? {
        if !settings.usesGlobalServer {
            return settings.serverAddress?.trimmed.nonEmpty
        }
        return launchServerAddress.trimmed.nonEmpty
    }

    private func effectiveServerPort(settings: VersionLaunchSettings) -> Int? {
        let port = !settings.usesGlobalServer ? settings.serverPort?.trimmed : launchServerPort.trimmed
        guard let value = Int(port ?? ""), (1...65535).contains(value) else {
            return nil
        }
        return value
    }

    private func recordDependencyProgress(_ progress: MinecraftDownloadProgress) {
        dependencyProgressEntries.insert(DependencyProgressEntry(progress: progress), at: 0)
        if dependencyProgressEntries.count > 12 {
            dependencyProgressEntries.removeLast(dependencyProgressEntries.count - 12)
        }
    }

    private func buildSelectedLaunchRequest() async throws -> MinecraftLaunchRequest {
        guard let instance = selectedInstance else {
            throw LauncherPreparationError.missingInstance
        }
        let launchSettings = activeVersionSettings(for: instance)
        guard let javaExecutable = effectiveJavaURL(for: instance) else {
            throw LauncherPreparationError.missingJava
        }
        if let javaCompatibilityError = javaCompatibilityError(for: instance, javaExecutable: javaExecutable) {
            throw javaCompatibilityError
        }

        let windowWidth: Int
        let windowHeight: Int
        let fullscreen: Bool
        if !launchSettings.usesGlobalWindow {
            windowWidth = Int(launchSettings.windowWidth ?? gameWindowWidth)
            windowHeight = Int(launchSettings.windowHeight ?? gameWindowHeight)
            fullscreen = launchSettings.fullscreen ?? launchFullscreen
        } else {
            windowWidth = Int(gameWindowWidth)
            windowHeight = Int(gameWindowHeight)
            fullscreen = launchFullscreen
        }

        let identity = try await launchIdentity()
        let authlibInjector = try await authlibInjectorConfigurationIfNeeded()
        let nideInjector = try await nideInjectorConfigurationIfNeeded()

        return MinecraftLaunchRequest(
            instance: instance,
            minecraftDirectory: minecraftDirectory,
            javaExecutable: javaExecutable,
            identity: identity,
            memoryMegabytes: effectiveMemoryMegabytes(for: instance),
            windowWidth: windowWidth,
            windowHeight: windowHeight,
            fullscreen: fullscreen,
            gameDirectory: effectiveGameDirectory(for: instance, settings: launchSettings),
            serverAddress: effectiveServerAddress(settings: launchSettings),
            serverPort: effectiveServerPort(settings: launchSettings),
            authlibInjector: authlibInjector,
            nideInjector: nideInjector,
            extraJvmArguments: effectiveExtraJvmArgumentList(settings: launchSettings),
            extraGameArguments: effectiveExtraGameArgumentList(settings: launchSettings)
        )
    }

    private func buildSelectedDependencyPreparationRequest() throws -> MinecraftLaunchRequest {
        guard let instance = selectedInstance else {
            throw LauncherPreparationError.missingInstance
        }
        let launchSettings = activeVersionSettings(for: instance)
        guard let javaExecutable = effectiveJavaURL(for: instance) else {
            throw LauncherPreparationError.missingJava
        }

        return MinecraftLaunchRequest(
            instance: instance,
            minecraftDirectory: minecraftDirectory,
            javaExecutable: javaExecutable,
            identity: .offline(username: offlineUsername),
            memoryMegabytes: effectiveMemoryMegabytes(for: instance),
            windowWidth: Int(effectiveVersionWindowWidth),
            windowHeight: Int(effectiveVersionWindowHeight),
            fullscreen: effectiveVersionFullscreen,
            gameDirectory: effectiveGameDirectory(for: instance, settings: launchSettings)
        )
    }

    private func prepareDependencies(for request: MinecraftLaunchRequest, title: String) async throws -> MinecraftDependencySummary {
        launchStatus = LaunchStatus(title: title, detail: "正在检查 Minecraft 文件", progress: 0.05)
        let dependencyProgressGate = DependencyProgressUpdateGate()
        return try await MinecraftDependencyDownloader(
            maximumConcurrentDownloads: Int(maxDownloadThreads),
            downloadSource: effectiveDownloadSource
        ).prepareDependencies(request: request) { [weak self] progress in
            guard await dependencyProgressGate.shouldEmit(progress) else { return }
            await MainActor.run {
                self?.recordDependencyProgress(progress)
                self?.launchStatus = LaunchStatus(
                    title: title,
                    detail: progress.currentName,
                    progress: max(0.05, min(0.95, progress.fraction))
                )
                self?.lastEvent = "\(progress.finished)/\(progress.total) · 下载 \(progress.downloaded) · 跳过 \(progress.skipped)"
            }
        }
    }

    func prepareSelectedInstanceDependencies() async {
        let readiness = dependencyPreparationReadiness
        let canBuildLaunchCommand = launchReadiness.isReady
        guard readiness.isReady else {
            launchStatus = LaunchStatus(title: "无法预补全", detail: readiness.detail, progress: 0)
            lastEvent = readiness.title
            return
        }

        isPreparingLaunch = true
        dependencyProgressEntries = []
        defer { isPreparingLaunch = false }

        do {
            let request = canBuildLaunchCommand
                ? try await buildSelectedLaunchRequest()
                : try buildSelectedDependencyPreparationRequest()
            let summary = try await prepareDependencies(for: request, title: "预补全依赖")
            if canBuildLaunchCommand {
                let command = try MinecraftLaunchBuilder().build(request: request)
                launchCommandPreview = command.commandLinePreview
            }
            launchStatus = LaunchStatus(
                title: "依赖已就绪",
                detail: "下载 \(summary.downloaded)，跳过 \(summary.skipped)",
                progress: 1
            )
            lastEvent = "预补全完成：下载 \(summary.downloaded)，跳过 \(summary.skipped)"
        } catch {
            launchStatus = LaunchStatus(title: "预补全失败", detail: error.localizedDescription, progress: 0)
            lastEvent = "依赖预补全返回错误"
        }
    }

    func launchSelectedInstance() async {
        let readiness = launchReadiness
        guard readiness.isReady else {
            launchStatus = LaunchStatus(title: "无法启动", detail: readiness.detail, progress: 0)
            lastEvent = readiness.title
            return
        }

        do {
            isPreparingLaunch = true
            dependencyProgressEntries = []
            let request = try await buildSelectedLaunchRequest()
            let summary = try await prepareDependencies(for: request, title: "补全依赖")
            lastEvent = "依赖检查完成：下载 \(summary.downloaded)，跳过 \(summary.skipped)"
            let command = try MinecraftLaunchBuilder().build(request: request)
            launchCommandPreview = command.commandLinePreview
            let process = try MinecraftLaunchRunner().run(command: command)
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    await self?.handleGameProcessExit(process)
                }
            }
            gameProcess = process
            gameLaunchStartedAt = Date()
            gameLaunchInstanceName = request.instance.name
            didRequestGameStop = false
            isLaunching = true
            launchStatus = LaunchStatus(title: "已启动游戏", detail: request.instance.name, progress: 1)
            lastEvent = "进程 PID：\(gameProcess?.processIdentifier ?? 0)"
            hideLauncherForGameIfNeeded()
        } catch {
            launchStatus = LaunchStatus(title: "启动失败", detail: error.localizedDescription, progress: 0)
            lastEvent = "启动链返回错误"
            sendNativeNotification(title: "启动失败", body: error.localizedDescription)
        }
        isPreparingLaunch = false
    }

    private func handleGameProcessExit(_ process: Process) async {
        let shouldRestoreHiddenLauncher = didHideLauncherForGame
        let summary = GameLaunchExitSummary(
            instanceName: gameLaunchInstanceName.nonEmpty ?? "Minecraft",
            processIdentifier: process.processIdentifier,
            exitCode: process.terminationStatus,
            startedAt: gameLaunchStartedAt ?? Date(),
            endedAt: Date(),
            wasUserRequestedStop: didRequestGameStop
        )
        isLaunching = false
        gameProcess = nil
        gameLaunchStartedAt = nil
        gameLaunchInstanceName = ""
        didRequestGameStop = false
        didHideLauncherForGame = false
        launchStatus = LaunchStatus(
            title: summary.title,
            detail: summary.detail,
            progress: summary.exitCode == 0 ? 1 : 0
        )
        lastEvent = summary.lastEvent
        sendNativeNotification(title: summary.title, body: summary.detail)

        if shouldRestoreHiddenLauncher && (showLauncherOnGameExit || summary.shouldOpenLogDiagnostics) {
            restoreLauncherWindow()
        }

        guard summary.shouldOpenLogDiagnostics else { return }
        selectedPage = .more
        selectedMoreSection = .logs
        selectedMinecraftLogID = nil
        await refreshMinecraftLogs()
    }

    func stopGame() {
        guard let gameProcess, gameProcess.isRunning else {
            isLaunching = false
            launchStatus = LaunchStatus(title: "没有运行中的游戏", detail: "当前没有可关闭的 Minecraft 进程", progress: 0)
            return
        }
        didRequestGameStop = true
        gameProcess.terminate()
        launchStatus = LaunchStatus(title: "已请求关闭", detail: "已向 Minecraft 进程发送终止请求", progress: 0.5)
        lastEvent = "正在等待 Minecraft 退出"
    }

    private func hideLauncherForGameIfNeeded() {
        guard hideLauncherOnGameStart else { return }
        didHideLauncherForGame = true
        NSApp.hide(nil)
    }

    private func restoreLauncherWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.title = "选择启动器背景图"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backgroundImagePath = url.path
        lastEvent = "已设置背景图：\(url.lastPathComponent)"
    }

    func clearBackgroundImage() {
        backgroundImagePath = nil
        lastEvent = "已清除启动器背景图"
    }

    func chooseMinecraftDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 Minecraft 文件夹"
        panel.message = "选择一个 Minecraft 根目录。启动器会在其中读取 versions、libraries 和 assets。"
        panel.prompt = "使用此文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = minecraftDirectory
        guard panel.runModal() == .OK, let url = panel.url else {
            lastEvent = "已取消选择 Minecraft 文件夹"
            return
        }

        Task { await setMinecraftDirectory(url) }
    }

    func resetMinecraftDirectory() {
        Task { await setMinecraftDirectory(nil) }
    }

    func setMinecraftDirectory(_ directory: URL?) async {
        let previousPath = minecraftDirectory.path
        selectedInstanceID = nil
        selectedInstanceNamePreference = nil

        if let directory {
            let url = directory.standardizedFileURL
            customMinecraftDirectoryPath = url.path
            prepareMinecraftDirectory(at: url)
            lastEvent = "已切换 Minecraft 文件夹：\(url.path)"
        } else {
            customMinecraftDirectoryPath = nil
            prepareMinecraftDirectory(at: minecraftDirectory)
            lastEvent = "已恢复默认 Minecraft 文件夹"
        }

        if previousPath != minecraftDirectory.path {
            localModFiles = []
            selectedLocalModFileID = nil
            minecraftLogEntries = []
            selectedMinecraftLogID = nil
            selectedMinecraftLogPreview = ""
            selectedMinecraftLogDiagnoses = []
        }
        await refreshEnvironment()
    }

    private func prepareMinecraftDirectory(at directory: URL) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for child in ["versions", "libraries", "assets", "resourcepacks", "shaderpacks"] {
            try? fileManager.createDirectory(
                at: directory.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    func openMinecraftFolder() {
        prepareMinecraftDirectory(at: minecraftDirectory)
        NSWorkspace.shared.open(minecraftDirectory)
    }

    func openSelectedInstanceFolder() {
        guard let instance = selectedInstance else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        NSWorkspace.shared.open(instance.path)
        lastEvent = "已打开实例目录：\(instance.name)"
    }

    func chooseAndImportLocalInstanceArchive() {
        guard !isManagingInstance else { return }
        let panel = NSOpenPanel()
        panel.title = "导入 Minecraft 实例"
        panel.message = "选择由 PCL Mac 导出的 .zip 实例备份，或包含版本 JSON 的实例目录压缩包。"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let zipType = UTType(filenameExtension: "zip") {
            panel.allowedContentTypes = [zipType]
        }

        guard panel.runModal() == .OK, let archiveURL = panel.url else {
            lastEvent = "已取消导入实例"
            return
        }

        Task { await importLocalInstanceArchive(from: archiveURL) }
    }

    func importLocalInstanceArchive(from archiveURL: URL) async {
        if isManagingInstance { return }
        guard archiveURL.pathExtension.caseInsensitiveCompare("zip") == .orderedSame else {
            lastEvent = "请选择 .zip 实例备份"
            return
        }

        let taskID = beginDownloadTask(
            title: archiveURL.lastPathComponent,
            category: "本地实例",
            detail: "正在读取实例备份",
            progress: 0.10,
            destinationPath: archiveURL.path
        )
        isManagingInstance = true
        defer { isManagingInstance = false }
        lastEvent = "正在导入实例备份：\(archiveURL.lastPathComponent)"

        do {
            let minecraftDirectory = self.minecraftDirectory
            updateDownloadTask(taskID, detail: "正在解压并校验实例", progress: 0.35)
            let result = try await Task.detached(priority: .utility) {
                try MinecraftInstanceManager().importArchive(archiveURL, minecraftDirectory: minecraftDirectory)
            }.value
            updateDownloadTask(taskID, detail: "正在刷新实例列表", progress: 0.75, destinationPath: result.directory.path)
            await refreshEnvironment()
            selectedInstanceID = minecraftInstances.first(where: { $0.name == result.name })?.id ?? selectedInstanceID
            selectedPage = .launch
            lastEvent = result.originalName == result.name
                ? "已导入实例：\(result.name)"
                : "已导入实例：\(result.originalName) → \(result.name)"
            updateDownloadTask(
                taskID,
                status: .succeeded,
                detail: lastEvent,
                progress: 1,
                destinationPath: result.directory.path
            )
        } catch {
            lastEvent = "导入实例失败：\(error.localizedDescription)"
            updateDownloadTask(taskID, status: .failed, detail: lastEvent, progress: 1)
        }
    }

    func chooseAndExportSelectedInstance() {
        guard let instance = selectedInstance else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出 Minecraft 实例"
        panel.message = "把“\(instance.name)”导出为 zip 备份，方便迁移或分享。"
        panel.nameFieldStringValue = "\(instance.name).zip"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .archive]
        guard panel.runModal() == .OK, let destination = panel.url else {
            lastEvent = "已取消导出实例"
            return
        }

        Task { await exportSelectedInstance(to: destination) }
    }

    func exportSelectedInstance(to destination: URL) async {
        guard let instance = selectedInstance else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        if isManagingInstance { return }
        isManagingInstance = true
        lastEvent = "正在导出实例：\(instance.name)"

        do {
            let minecraftDirectory = self.minecraftDirectory
            let result = try await Task.detached(priority: .utility) {
                try MinecraftInstanceManager().exportArchive(
                    instance,
                    minecraftDirectory: minecraftDirectory,
                    destination: destination
                )
            }.value
            let size = ByteCountFormatter.string(fromByteCount: result.byteCount, countStyle: .file)
            lastEvent = "已导出实例：\(result.archiveURL.lastPathComponent)（\(size)）"
            NSWorkspace.shared.activateFileViewerSelecting([result.archiveURL])
        } catch {
            lastEvent = "导出实例失败：\(error.localizedDescription)"
        }

        isManagingInstance = false
    }

    func duplicateSelectedInstance() async {
        guard let instance = selectedInstance else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        if isManagingInstance { return }
        isManagingInstance = true
        do {
            let result = try MinecraftInstanceManager().duplicate(instance, minecraftDirectory: minecraftDirectory)
            await refreshEnvironment()
            selectedInstanceID = minecraftInstances.first(where: { $0.name == result.name })?.id ?? selectedInstanceID
            lastEvent = "已复制实例：\(result.name)"
        } catch {
            lastEvent = "复制实例失败：\(error.localizedDescription)"
        }
        isManagingInstance = false
    }

    func confirmRemoveSelectedInstance() {
        guard let instance = selectedInstance else {
            lastEvent = "请先选择 Minecraft 实例"
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除 Minecraft 实例？"
        alert.informativeText = "实例“\(instance.name)”会移到废纸篓，当前版本目录内的配置、Mod 与存档也会一起移动。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            lastEvent = "已取消删除实例"
            return
        }

        Task { await removeSelectedInstance(instance) }
    }

    private func removeSelectedInstance(_ instance: MinecraftInstance) async {
        if isManagingInstance { return }
        isManagingInstance = true
        do {
            try MinecraftInstanceManager().validate(
                instance: instance,
                versionsDirectory: minecraftDirectory.appendingPathComponent("versions", isDirectory: true)
            )
            try FileManager.default.trashItem(at: instance.path, resultingItemURL: nil)
            if selectedInstanceID == instance.id {
                selectedInstanceID = nil
                selectedInstanceNamePreference = nil
            }
            favoriteInstanceNames.removeAll { $0 == instance.name }
            hiddenInstanceNames.removeAll { $0 == instance.name }
            await refreshEnvironment()
            lastEvent = "已移到废纸篓：\(instance.name)"
        } catch {
            lastEvent = "删除实例失败：\(error.localizedDescription)"
        }
        isManagingInstance = false
    }

    func refreshLocalNetworkInfo() {
        localNetworkAddresses = discoverLocalIPv4Addresses()
        if localNetworkAddresses.isEmpty {
            linkMessage = "未发现可用于局域网联机的 IPv4 地址，请检查 Wi-Fi 或以太网连接。"
        } else {
            linkMessage = "发现 \(localNetworkAddresses.count) 个本机地址，可复制给同一网络下的玩家。"
        }
    }

    func scanLANWorlds() async {
        if isScanningLANWorlds { return }
        isScanningLANWorlds = true
        linkMessage = "正在监听 Minecraft 局域网广播..."
        let worlds = await Task.detached(priority: .utility) {
            MinecraftLANDiscoveryService.scan(timeout: 3)
        }.value
        lanWorlds = worlds
        selectedLANWorldID = worlds.first?.id
        linkMessage = worlds.isEmpty
            ? "未发现局域网房间；请确认对方已在游戏内打开“对局域网开放”。"
            : "发现 \(worlds.count) 个局域网房间。"
        isScanningLANWorlds = false
    }

    func copyPrimaryLocalAddress() {
        guard let address = localNetworkAddresses.first else {
            linkMessage = "没有可复制的局域网地址，请先刷新网络信息。"
            return
        }
        copyToPasteboard(address)
        linkMessage = "已复制局域网地址：\(address)"
    }

    func copySelectedLANWorldAddress() {
        guard let world = selectedLANWorld else {
            linkMessage = "没有可复制的局域网房间，请先扫描。"
            return
        }
        copyToPasteboard(world.address)
        linkMessage = "已复制房间地址：\(world.address)"
    }

    func useSelectedLANWorldForLaunch() {
        guard let world = selectedLANWorld else {
            linkMessage = "没有可配置的局域网房间，请先扫描。"
            return
        }
        launchServerAddress = world.host
        launchServerPort = "\(world.port)"
        linkMessage = "已设为启动后自动进入：\(world.address)"
    }

    func saveSelectedLANWorldAsFavorite() {
        guard let world = selectedLANWorld else {
            linkMessage = "没有可收藏的局域网房间，请先扫描。"
            return
        }
        upsertServerFavorite(
            LauncherServerFavorite(
                name: world.motd,
                address: world.host,
                port: "\(world.port)"
            )
        )
    }

    func saveCurrentLaunchServerAsFavorite() {
        upsertServerFavorite(
            LauncherServerFavorite(
                name: launchServerAddress,
                address: launchServerAddress,
                port: launchServerPort
            )
        )
    }

    func saveServerFavoriteDraft() {
        upsertServerFavorite(
            LauncherServerFavorite(
                name: serverFavoriteDraftName,
                address: serverFavoriteDraftAddress,
                port: serverFavoriteDraftPort
            )
        )
    }

    func useSelectedServerFavoriteForLaunch() {
        guard let favorite = selectedServerFavorite else {
            linkMessage = "请先选择一个常用服务器"
            return
        }
        launchServerAddress = favorite.address
        launchServerPort = favorite.port ?? ""
        linkMessage = "已设为启动服务器：\(favorite.addressText)"
    }

    func launchSelectedServerFavorite() async {
        guard selectedServerFavorite != nil else {
            linkMessage = "请先选择一个常用服务器"
            return
        }
        useSelectedServerFavoriteForLaunch()
        selectedPage = .launch
        await launchSelectedInstance()
    }

    func copySelectedServerFavoriteAddress() {
        guard let favorite = selectedServerFavorite else {
            linkMessage = "请先选择一个常用服务器"
            return
        }
        copyToPasteboard(favorite.addressText)
        linkMessage = "已复制服务器地址：\(favorite.addressText)"
    }

    func removeSelectedServerFavorite() {
        guard let favorite = selectedServerFavorite else {
            linkMessage = "请先选择一个常用服务器"
            return
        }
        serverFavorites.removeAll { $0.id == favorite.id }
        selectedServerFavoriteID = serverFavorites.first?.id
        linkMessage = "已移除常用服务器：\(favorite.displayName)"
    }

    private func upsertServerFavorite(_ favorite: LauncherServerFavorite) {
        guard let normalized = favorite.normalized else {
            linkMessage = "请先填写服务器地址"
            return
        }
        serverFavorites.removeAll { $0.id == normalized.id }
        serverFavorites.insert(normalized, at: 0)
        if serverFavorites.count > 50 {
            serverFavorites.removeLast(serverFavorites.count - 50)
        }
        selectedServerFavoriteID = normalized.id
        serverFavoriteDraftName = ""
        serverFavoriteDraftAddress = ""
        serverFavoriteDraftPort = ""
        linkMessage = "已保存常用服务器：\(normalized.displayName)（\(normalized.addressText)）"
    }

    func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
            linkMessage = "已打开 macOS 网络设置"
        }
    }

    func openHelpDocument() {
        guard let url = helpDocumentURL() else {
            helpMessage = "没有找到 README.html，请重新构建应用或检查 PCLMac/README.html。"
            return
        }
        NSWorkspace.shared.open(url)
        helpMessage = "已打开帮助文档：\(url.lastPathComponent)"
    }

    func revealHelpDocumentInFinder() {
        guard let url = helpDocumentURL() else {
            helpMessage = "没有找到 README.html，请重新构建应用或检查 PCLMac/README.html。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        helpMessage = "已在 Finder 中显示帮助文档"
    }

    func refreshMinecraftLogs() async {
        if isLoadingMinecraftLogs { return }
        isLoadingMinecraftLogs = true
        minecraftLogMessage = "正在扫描日志和崩溃报告"
        let minecraftDirectory = self.minecraftDirectory
        let additionalDirectories = diagnosticLogDirectories()
        let entries = await Task.detached(priority: .utility) {
            MinecraftLogManager().scan(
                minecraftDirectory: minecraftDirectory,
                additionalDirectories: additionalDirectories
            )
        }.value
        minecraftLogEntries = entries
        if let selectedMinecraftLogID,
           entries.contains(where: { $0.id == selectedMinecraftLogID }) {
            updateSelectedMinecraftLogPreview()
        } else {
            selectedMinecraftLogID = entries.first?.id
        }
        minecraftLogMessage = entries.isEmpty ? "没有发现日志文件" : "已发现 \(entries.count) 个日志/崩溃报告"
        isLoadingMinecraftLogs = false
    }

    func revealSelectedMinecraftLogInFinder() {
        guard let entry = selectedMinecraftLogEntry else {
            minecraftLogMessage = "请先选择一个日志"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        minecraftLogMessage = "已在 Finder 中显示 \(entry.name)"
    }

    func copySelectedMinecraftLogSummary() {
        guard let entry = selectedMinecraftLogEntry else {
            minecraftLogMessage = "请先选择一个日志"
            return
        }
        var summaryLines = [
            entry.name,
            "类型：\(entry.kind.displayName)",
            "路径：\(entry.url.path)",
            "摘要：\(entry.summary)"
        ]
        if selectedMinecraftLogDiagnoses.isEmpty {
            summaryLines.append("诊断：未识别到明确崩溃特征")
        } else {
            summaryLines.append("诊断：")
            for diagnosis in selectedMinecraftLogDiagnoses {
                summaryLines.append("- \(diagnosis.title)：\(diagnosis.detail)")
                if !diagnosis.suggestions.isEmpty {
                    summaryLines.append("  建议：\(diagnosis.suggestions.joined(separator: "；"))")
                }
                if let matchedLine = diagnosis.matchedLine {
                    summaryLines.append("  命中：\(matchedLine)")
                }
            }
        }
        copyToPasteboard(summaryLines.joined(separator: "\n"))
        minecraftLogMessage = "已复制 \(entry.name) 的摘要"
    }

    private func updateSelectedMinecraftLogPreview() {
        guard let entry = selectedMinecraftLogEntry else {
            selectedMinecraftLogPreview = ""
            selectedMinecraftLogDiagnoses = []
            return
        }
        let manager = MinecraftLogManager()
        let preview = manager.preview(entry)
        let prefix = preview.isTruncated ? "仅显示最后 160 行，共 \(preview.lineCount) 行\n\n" : ""
        selectedMinecraftLogPreview = prefix + preview.text
        selectedMinecraftLogDiagnoses = manager.diagnose(entry)
    }

    private func diagnosticLogDirectories() -> [URL] {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return [
            currentDirectory,
            sourceDirectory,
            sourceDirectory.deletingLastPathComponent()
        ].uniquedByPath()
    }

    private func helpDocumentURL() -> URL? {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.url(forResource: "README", withExtension: "html"),
            currentDirectory.appendingPathComponent("PCLMac/README.html"),
            currentDirectory.appendingPathComponent("README.html"),
            sourceDirectory.appendingPathComponent("README.html")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

func discoverLocalIPv4Addresses() -> [String] {
    guard let output = runProcess("/sbin/ifconfig", arguments: []) else { return [] }
    return parseLocalIPv4Addresses(output)
}

func parseLocalIPv4Addresses(_ output: String) -> [String] {
    var addresses: [String] = []
    var seen: Set<String> = []

    for line in output.split(separator: "\n") {
        let parts = line
            .split(separator: " ")
            .map(String.init)
        guard parts.count >= 2, parts[0] == "inet" else { continue }
        let address = parts[1]
        guard !address.hasPrefix("127."),
              !address.hasPrefix("169.254."),
              address.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil,
              !seen.contains(address) else {
            continue
        }
        seen.insert(address)
        addresses.append(address)
    }

    return addresses
}

struct MacPlatformPaths: Sendable {
    let appSupportDirectory: URL
    let cacheDirectory: URL
    let minecraftDirectory: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        appSupportDirectory = support.appendingPathComponent("PCL", isDirectory: true)
        cacheDirectory = cache.appendingPathComponent("PCL", isDirectory: true)
        minecraftDirectory = support.appendingPathComponent("minecraft", isDirectory: true)
    }

    func prepare() {
        try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

struct JavaDiscoveryService: Sendable {
    func discover(appSupportDirectory: URL? = nil) async -> [JavaInstallation] {
        await Task.detached(priority: .utility) {
            var candidates = OrderedURLSet()

            if let javaHome = runProcess("/usr/libexec/java_home", arguments: [])?.trimmed,
               !javaHome.isEmpty {
                candidates.insert(URL(fileURLWithPath: javaHome).appendingPathComponent("bin/java"))
            }

            if let whichJava = runProcess("/usr/bin/which", arguments: ["java"])?.trimmed,
               !whichJava.isEmpty {
                candidates.insert(URL(fileURLWithPath: whichJava))
            }

            let home = FileManager.default.homeDirectoryForCurrentUser
            candidates.insert(home.appendingPathComponent(".sdkman/candidates/java/current/bin/java"))

            for root in [
                URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines", isDirectory: true),
                home.appendingPathComponent("Library/Java/JavaVirtualMachines", isDirectory: true)
            ] {
                let jdks = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                for jdk in jdks {
                    candidates.insert(jdk.appendingPathComponent("Contents/Home/bin/java"))
                }
            }

            if let appSupportDirectory {
                let runtimeRoot = appSupportDirectory.appendingPathComponent("JavaRuntimes", isDirectory: true)
                let enumerator = FileManager.default.enumerator(
                    at: runtimeRoot,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )
                while let url = enumerator?.nextObject() as? URL {
                    guard url.lastPathComponent == "java",
                          url.deletingLastPathComponent().lastPathComponent == "bin" else {
                        continue
                    }
                    candidates.insert(url)
                }
            }

            return candidates.urls.compactMap { executable in
                guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
                let output = runProcess(executable.path, arguments: ["-version"]) ?? ""
                let summary = parseJavaVersion(output)
                return JavaInstallation(executable: executable, versionSummary: summary, source: sourceName(for: executable))
            }
        }.value
    }
}

struct MinecraftInstanceScanner: Sendable {
    func scan(minecraftDirectory: URL) async -> [MinecraftInstance] {
        await Task.detached(priority: .utility) {
            let versionsDirectory = minecraftDirectory.appendingPathComponent("versions", isDirectory: true)
            guard let folders = try? FileManager.default.contentsOfDirectory(
                at: versionsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return folders.compactMap { folder -> MinecraftInstance? in
                let name = folder.lastPathComponent
                let jsonURL = folder.appendingPathComponent("\(name).json")
                guard let data = try? Data(contentsOf: jsonURL) else { return nil }
                let metadata = (try? JSONDecoder().decode(MinecraftVersionMetadata.self, from: data)) ?? MinecraftVersionMetadata(id: name, type: "unknown", releaseTime: "")
                return MinecraftInstance(
                    name: metadata.id.isEmpty ? name : metadata.id,
                    path: folder,
                    jsonURL: jsonURL,
                    type: metadata.type,
                    releaseTime: metadata.releaseTime
                )
            }
            .sorted { lhs, rhs in
                if lhs.releaseTime == rhs.releaseTime { return lhs.name > rhs.name }
                return lhs.releaseTime > rhs.releaseTime
            }
        }.value
    }
}

struct MinecraftVersionMetadata: Decodable, Sendable {
    let id: String
    let type: String
    let releaseTime: String
}

struct OrderedURLSet: Sendable {
    private(set) var urls: [URL] = []
    private var paths: Set<String> = []

    mutating func insert(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !paths.contains(path) else { return }
        paths.insert(path)
        urls.append(url.standardizedFileURL)
    }
}

func runProcess(_ executable: String, arguments: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

func parseJavaVersion(_ output: String) -> String {
    let lines = output
        .split(separator: "\n")
        .map { String($0).trimmed }
        .filter { !$0.isEmpty }

    if let standardLine = lines.first(where: { line in
        let lowercased = line.lowercased()
        return lowercased.hasPrefix("openjdk version") || lowercased.hasPrefix("java version")
    }) {
        return standardLine.replacingOccurrences(of: "\"", with: "")
    }

    if let vmLine = lines.first(where: { $0.lowercased().contains("java vm:") }) {
        let cleaned = vmLine
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "Java VM:", with: "")
            .trimmed
        if let version = versionInsideParentheses(in: cleaned) {
            return cleaned.lowercased().contains("openjdk") ? "OpenJDK \(version)" : "Java \(version)"
        }
        return cleaned
    }

    if let jreLine = lines.first(where: { $0.lowercased().contains("jre version:") }),
       let version = versionInsideParentheses(in: jreLine) {
        return "Java \(version)"
    }

    return lines.first?.replacingOccurrences(of: "\"", with: "") ?? "Java"
}

private func versionInsideParentheses(in value: String) -> String? {
    guard let open = value.firstIndex(of: "("),
          let close = value[open...].firstIndex(of: ")") else {
        return nil
    }
    let version = value[value.index(after: open)..<close]
        .split(separator: ",")
        .first
        .map(String.init)?
        .trimmed
    return version?.isEmpty == false ? version : nil
}

func sourceName(for executable: URL) -> String {
    let path = executable.path
    if path.contains("/Application Support/PCL/JavaRuntimes/") { return "PCL Runtime" }
    if path.contains(".sdkman") { return "SDKMAN" }
    if path.contains("/Library/Java/JavaVirtualMachines") { return "JavaVirtualMachines" }
    if path == "/usr/bin/java" { return "System shim" }
    return "Manual"
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

struct LauncherRootView: View {
    @EnvironmentObject private var model: LauncherModel
    @State private var activePage: LauncherPage = .launch
    @State private var renderedPage: LauncherPage = .launch
    @State private var transitionDirection: PageTransitionDirection = .forward

    var body: some View {
        ZStack {
            if model.useHighPerformanceMode {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            } else {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            }
            if !model.useHighPerformanceMode {
                LauncherBackgroundImageLayer(
                    imagePath: model.backgroundImagePath,
                    opacity: model.backgroundImageOpacity
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                TitleBar(
                    selectedPage: displayedPage,
                    onSelectPage: { selectPage($0, syncModel: true) },
                    onRefresh: { Task { await model.refreshEnvironment() } }
                )
                Divider().opacity(0.6)
                HStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        leftPanel
                            .frame(width: 304, alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .id(leftPanelIdentity)
                            .transition(pageTransition)
                    }
                    .frame(width: 304)
                    .background {
                        leftPanelBackground
                    }
                    .clipped()
                    Divider()
                    ZStack(alignment: .topLeading) {
                        rightPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .id(rightPanelIdentity)
                            .transition(pageTransition)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(model.backgroundImagePath == nil ? 1 : 0.90))
                    .clipped()
                }
            }
        }
        .environment(\.pclThemePalette, model.selectedThemePreset.palette)
        .environment(\.pclUsesHighPerformanceMode, model.useHighPerformanceMode)
        .preferredColorScheme(model.selectedAppearanceMode.colorScheme)
        .onAppear {
            activePage = model.selectedPage
            renderedPage = model.selectedPage
        }
        .onChange(of: model.selectedPage) { _, newPage in
            guard !model.useHighPerformanceMode else { return }
            guard newPage != activePage || newPage != renderedPage else { return }
            selectPage(newPage, syncModel: false)
        }
        .onChange(of: model.useHighPerformanceMode) { _, _ in
            activePage = model.selectedPage
            renderedPage = model.selectedPage
        }
        .onDisappear {
            model.flushPendingPreferences()
        }
    }

    private var displayedPage: LauncherPage {
        model.useHighPerformanceMode ? model.selectedPage : renderedPage
    }

    private var pageTransition: AnyTransition {
        guard !model.useHighPerformanceMode else { return .identity }
        return AnyTransition.asymmetric(
            insertion: .modifier(
                active: PCLSlideFadeModifier(opacity: 0, x: transitionDirection.insertionOffset, y: 3, scale: 0.992),
                identity: PCLSlideFadeModifier(opacity: 1, x: 0, scale: 1)
            ),
            removal: .modifier(
                active: PCLSlideFadeModifier(opacity: 0, x: transitionDirection.removalOffset, y: -1, scale: 0.998),
                identity: PCLSlideFadeModifier(opacity: 1, x: 0, scale: 1)
            )
        )
    }

    private var leftPanelIdentity: String {
        model.useHighPerformanceMode ? "left-panel" : "left-\(renderedPage.rawValue)"
    }

    private var rightPanelIdentity: String {
        model.useHighPerformanceMode ? "right-panel" : "right-\(renderedPage.rawValue)"
    }

    @ViewBuilder
    private var leftPanelBackground: some View {
        if model.useHighPerformanceMode {
            Color(nsColor: .controlBackgroundColor).opacity(0.96)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    private func selectPage(_ page: LauncherPage, syncModel: Bool) {
        if model.useHighPerformanceMode {
            syncSelectedPageIfNeeded(page, syncModel: syncModel)
            return
        }

        guard activePage != page || renderedPage != page else {
            syncSelectedPageIfNeeded(page, syncModel: syncModel)
            return
        }

        let previousRenderedPage = renderedPage
        let direction: PageTransitionDirection = page.sortIndex >= previousRenderedPage.sortIndex ? .forward : .backward

        withAnimation(PCLMotion.page) {
            transitionDirection = direction
            activePage = page
            renderedPage = page
        }

        syncSelectedPageIfNeeded(page, syncModel: syncModel)
    }

    private func syncSelectedPageIfNeeded(_ page: LauncherPage, syncModel: Bool) {
        guard syncModel, model.selectedPage != page else { return }
        model.selectedPage = page
    }

    @ViewBuilder
    private var leftPanel: some View {
        switch displayedPage {
        case .launch:
            LaunchLeftPanel()
        case .download:
            DownloadLeftPanel()
        case .link:
            LinkLeftPanel()
        case .settings:
            SettingsLeftPanel()
        case .more:
            MoreLeftPanel()
        }
    }

    @ViewBuilder
    private var rightPanel: some View {
        switch displayedPage {
        case .launch:
            LaunchDashboard()
        case .download:
            DownloadDashboard()
        case .link:
            LinkDashboard()
        case .settings:
            SettingsDashboard()
        case .more:
            MoreDashboard()
        }
    }
}

struct LauncherBackgroundImageLayer: View {
    let imagePath: String?
    let opacity: Double
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(opacity)
                    .overlay(Color.black.opacity(0.18 * opacity))
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(PCLMotion.section, value: imagePath)
        .animation(PCLMotion.fast, value: opacity)
        .task(id: imagePath) {
            image = Self.loadImage(at: imagePath)
        }
    }

    private static func loadImage(at path: String?) -> NSImage? {
        guard let path = path?.trimmed.nonEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }
}

struct TitleBar: View {
    let selectedPage: LauncherPage
    let onSelectPage: (LauncherPage) -> Void
    let onRefresh: () -> Void
    @Environment(\.pclThemePalette) private var palette
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode
    @Namespace private var pageSelectionNamespace

    var body: some View {
        HStack(spacing: 14) {
            LogoMark()
                .padding(.leading, 76)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                ForEach(LauncherPage.allCases) { page in
                    PageButton(
                        page: page,
                        selected: selectedPage == page,
                        namespace: pageSelectionNamespace
                    ) {
                        onSelectPage(page)
                    }
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background {
                if usesHighPerformanceMode {
                    Capsule().fill(Color.white.opacity(0.14))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }

            Spacer(minLength: 12)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
            .padding(.trailing, 18)
        }
        .frame(height: 50)
        .background(
            LinearGradient(colors: [palette.titleStart, palette.titleEnd], startPoint: .leading, endPoint: .trailing)
        )
        .foregroundStyle(.white)
    }
}

struct LogoMark: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 20, weight: .semibold))
            Text("PCL")
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .accessibilityLabel("Plain Craft Launcher (PCL) macOS")
    }
}

struct PageButton: View {
    let page: LauncherPage
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                if selected {
                    selectedBackground
                } else if isHovering {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                }
                Label(page.title, systemImage: page.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            .frame(width: 88, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(buttonScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(page.title)
        .animation(usesHighPerformanceMode ? PCLMotion.performanceSelection : PCLMotion.selection, value: selected)
        .animation(usesHighPerformanceMode ? PCLMotion.performanceSelection : PCLMotion.fast, value: isHovering)
        .onHover { isHovering = $0 }
        .help(page.title)
    }

    private var buttonScale: CGFloat {
        isHovering && !selected ? (usesHighPerformanceMode ? 1.006 : 1.018) : 1
    }

    @ViewBuilder
    private var selectedBackground: some View {
        if usesHighPerformanceMode {
            Capsule()
                .fill(Color.white.opacity(0.24))
        } else {
            Capsule()
                .fill(Color.white.opacity(0.24))
                .matchedGeometryEffect(id: "top-page-selection", in: namespace)
        }
    }
}

enum PCLTheme {
    static let blue = Color(red: 0.08, green: 0.42, blue: 0.84)
    static let blueLight = Color(red: 0.26, green: 0.62, blue: 0.96)
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor).opacity(0.82)
}

struct PCLThemePalette {
    let accent: Color
    let accentLight: Color
    let accentSoft: Color
    let titleStart: Color
    let titleEnd: Color

    static let fallback = LauncherThemePreset.pclBlue.palette
}

private struct PCLThemePaletteKey: EnvironmentKey {
    static let defaultValue = PCLThemePalette.fallback
}

private struct PCLUsesHighPerformanceModeKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var pclThemePalette: PCLThemePalette {
        get { self[PCLThemePaletteKey.self] }
        set { self[PCLThemePaletteKey.self] = newValue }
    }

    var pclUsesHighPerformanceMode: Bool {
        get { self[PCLUsesHighPerformanceModeKey.self] }
        set { self[PCLUsesHighPerformanceModeKey.self] = newValue }
    }
}

extension LauncherThemePreset {
    var palette: PCLThemePalette {
        switch self {
        case .pclBlue:
            PCLThemePalette(
                accent: Color(red: 0.07, green: 0.36, blue: 0.80),
                accentLight: Color(red: 0.28, green: 0.57, blue: 0.96),
                accentSoft: Color(red: 0.83, green: 0.90, blue: 0.99),
                titleStart: Color(red: 0.29, green: 0.56, blue: 0.96),
                titleEnd: Color(red: 0.05, green: 0.37, blue: 0.80)
            )
        case .grass:
            PCLThemePalette(
                accent: Color(red: 0.13, green: 0.49, blue: 0.24),
                accentLight: Color(red: 0.29, green: 0.67, blue: 0.33),
                accentSoft: Color(red: 0.83, green: 0.93, blue: 0.83),
                titleStart: Color(red: 0.30, green: 0.66, blue: 0.36),
                titleEnd: Color(red: 0.10, green: 0.43, blue: 0.23)
            )
        case .amethyst:
            PCLThemePalette(
                accent: Color(red: 0.48, green: 0.28, blue: 0.75),
                accentLight: Color(red: 0.68, green: 0.48, blue: 0.90),
                accentSoft: Color(red: 0.91, green: 0.85, blue: 0.97),
                titleStart: Color(red: 0.63, green: 0.42, blue: 0.88),
                titleEnd: Color(red: 0.38, green: 0.24, blue: 0.67)
            )
        case .redstone:
            PCLThemePalette(
                accent: Color(red: 0.72, green: 0.12, blue: 0.10),
                accentLight: Color(red: 0.91, green: 0.25, blue: 0.20),
                accentSoft: Color(red: 0.98, green: 0.84, blue: 0.82),
                titleStart: Color(red: 0.88, green: 0.24, blue: 0.19),
                titleEnd: Color(red: 0.60, green: 0.09, blue: 0.08)
            )
        case .copper:
            PCLThemePalette(
                accent: Color(red: 0.73, green: 0.34, blue: 0.14),
                accentLight: Color(red: 0.93, green: 0.55, blue: 0.27),
                accentSoft: Color(red: 0.98, green: 0.88, blue: 0.78),
                titleStart: Color(red: 0.90, green: 0.52, blue: 0.24),
                titleEnd: Color(red: 0.62, green: 0.28, blue: 0.12)
            )
        }
    }
}

extension LauncherAppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

extension LauncherHomeCard {
    var title: String {
        switch self {
        case .status: "状态"
        case .java: "Java"
        case .launchConfig: "启动配置"
        case .dependency: "依赖补全"
        case .command: "启动命令"
        case .launchLog: "启动日志"
        case .versions: "版本列表"
        }
    }

    var systemImage: String {
        switch self {
        case .status: "play.circle.fill"
        case .java: "cup.and.saucer.fill"
        case .launchConfig: "slider.horizontal.3"
        case .dependency: "arrow.down.doc.fill"
        case .command: "terminal.fill"
        case .launchLog: "doc.text.magnifyingglass"
        case .versions: "square.stack.3d.up.fill"
        }
    }
}

struct PCLSlideFadeModifier: ViewModifier {
    let opacity: Double
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat

    init(opacity: Double, x: CGFloat, y: CGFloat = 0, scale: CGFloat) {
        self.opacity = opacity
        self.x = x
        self.y = y
        self.scale = scale
    }

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: x, y: y)
            .scaleEffect(scale, anchor: .top)
    }
}

enum PCLMotion {
    static let deferredWorkDelayNanoseconds: UInt64 = 220_000_000
    static let preferenceSaveDelayNanoseconds: UInt64 = 180_000_000
    static let fast = Animation.easeOut(duration: 0.08)
    static let press = Animation.interactiveSpring(response: 0.06, dampingFraction: 0.86, blendDuration: 0.003)
    static let selection = Animation.spring(response: 0.13, dampingFraction: 0.90, blendDuration: 0.004)
    static let page = Animation.spring(response: 0.18, dampingFraction: 0.94, blendDuration: 0.006)
    static let section = Animation.spring(response: 0.15, dampingFraction: 0.94, blendDuration: 0.006)
    static let performancePage = Animation.easeOut(duration: 0.11)
    static let performanceSection = Animation.easeOut(duration: 0.09)
    static let performanceSelection = Animation.easeOut(duration: 0.07)

    @MainActor static var sectionTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PCLSlideFadeModifier(opacity: 0, x: 12, y: 2, scale: 0.994),
                identity: PCLSlideFadeModifier(opacity: 1, x: 0, scale: 1)
            ),
            removal: .modifier(
                active: PCLSlideFadeModifier(opacity: 0, x: -6, y: -1, scale: 0.998),
                identity: PCLSlideFadeModifier(opacity: 1, x: 0, scale: 1)
            )
        )
    }

    @MainActor static var performanceSectionTransition: AnyTransition {
        .identity
    }
}

struct PCLPressableButtonStyle: ButtonStyle {
    let pressedScale: CGFloat
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(usesHighPerformanceMode ? 1 : (configuration.isPressed ? pressedScale : 1))
            .animation(usesHighPerformanceMode ? nil : PCLMotion.press, value: configuration.isPressed)
    }
}

struct PCLSidebarNavigation<Item: Hashable & Identifiable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    let itemTitle: (Item) -> String
    let itemSystemImage: (Item) -> String
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode
    @Namespace private var selectionNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                ForEach(items) { item in
                    PCLSidebarRow(
                        title: itemTitle(item),
                        systemImage: itemSystemImage(item),
                        selected: selection == item,
                        namespace: selectionNamespace
                    ) {
                        select(item)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
        }
        .background(PCLTheme.sidebarBackground)
        .animation(usesHighPerformanceMode ? nil : PCLMotion.selection, value: selection)
    }

    private func select(_ item: Item) {
        guard selection != item else { return }
        if usesHighPerformanceMode {
            selection = item
        } else {
            withAnimation(PCLMotion.section) {
                selection = item
            }
        }
    }
}

struct PCLSidebarRow: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @Environment(\.pclThemePalette) private var palette
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? palette.accent : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background {
                rowBackground
            }
            .overlay(alignment: .leading) {
                if selected {
                    selectionIndicator
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(rowScale, anchor: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
        .animation(usesHighPerformanceMode ? PCLMotion.performanceSelection : PCLMotion.selection, value: selected)
        .animation(usesHighPerformanceMode ? PCLMotion.performanceSelection : PCLMotion.fast, value: isHovering)
        .help(title)
    }

    private var rowScale: CGFloat {
        isHovering && !selected ? (usesHighPerformanceMode ? 1.004 : 1.01) : 1
    }

    @ViewBuilder
    private var rowBackground: some View {
        if selected {
            if usesHighPerformanceMode {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.accent.opacity(0.13))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.accent.opacity(0.14))
                    .matchedGeometryEffect(id: "sidebar-selection-background", in: namespace)
            }
        } else if isHovering {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if usesHighPerformanceMode {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.accent)
                .frame(width: 3)
                .padding(.vertical, 8)
        } else {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.accent)
                .frame(width: 3)
                .padding(.vertical, 8)
                .matchedGeometryEffect(id: "sidebar-selection-indicator", in: namespace)
        }
    }
}

struct PCLContentCard<Content: View>: View {
    private let title: String?
    private let systemImage: String?
    private let content: Content
    @Environment(\.pclThemePalette) private var palette
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(palette.accent)
                    }
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 8)
                }
            }

            content
        }
        .padding(16)
        .background {
            cardBackground
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(usesHighPerformanceMode ? 0.34 : 0.45), lineWidth: 1)
        )
        .shadow(color: usesHighPerformanceMode ? .clear : .black.opacity(0.06), radius: usesHighPerformanceMode ? 0 : 12, x: 0, y: usesHighPerformanceMode ? 0 : 5)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if usesHighPerformanceMode {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

struct PCLCapsuleBadge: View {
    let title: String
    let systemImage: String
    var tint: Color?
    @Environment(\.pclThemePalette) private var palette

    var body: some View {
        let resolvedTint = tint ?? palette.accent
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(resolvedTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(resolvedTint.opacity(0.12), in: Capsule())
    }
}

struct PCLInfoRow: View {
    let title: String
    let value: String
    let systemImage: String
    var valueLineLimit: Int? = 1
    @Environment(\.pclThemePalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(valueLineLimit)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }
}

struct MinecraftDiagnosisPanel: View {
    let diagnoses: [MinecraftLogDiagnosis]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("诊断建议", systemImage: "stethoscope")
                .font(.system(size: 13, weight: .semibold))

            if diagnoses.isEmpty {
                Text("未识别到明确崩溃特征，可以查看尾部日志或复制摘要继续排查。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(diagnoses) { diagnosis in
                    MinecraftDiagnosisRow(diagnosis: diagnosis)
                }
            }
        }
    }
}

struct MinecraftDiagnosisRow: View {
    let diagnosis: MinecraftLogDiagnosis

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: diagnosis.severity.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(diagnosis.severity.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(diagnosis.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(diagnosis.severity.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(diagnosis.severity.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(diagnosis.severity.tint.opacity(0.12), in: Capsule())
                }

                Text(diagnosis.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(diagnosis.suggestions, id: \.self) { suggestion in
                    Text("- \(suggestion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let matchedLine = diagnosis.matchedLine {
                    Text(matchedLine)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(diagnosis.severity.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(diagnosis.severity.tint.opacity(0.15), lineWidth: 1)
        )
    }
}

struct PCLHintBanner: View {
    let title: String
    let message: String
    var systemImage = "info.circle.fill"
    @Environment(\.pclThemePalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.accent.opacity(0.18), lineWidth: 1)
        )
    }
}

struct PCLSearchField: View {
    let prompt: String
    @Binding var text: String
    @Environment(\.pclThemePalette) private var palette

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(text.isEmpty ? Color(nsColor: .separatorColor).opacity(0.65) : palette.accent.opacity(0.45), lineWidth: 1)
        )
    }
}

struct LaunchLeftPanel: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.pclThemePalette) private var palette
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    loginModeSelector
                    accountCard
                    versionCard
                    serverCard
                    if model.isScanning || model.isPreparingLaunch || model.isLaunching {
                        launchProgressCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 18)
            }

            Divider()

            launchFooter
                .padding(18)
                .background {
                    if usesHighPerformanceMode {
                        Color(nsColor: .controlBackgroundColor).opacity(0.98)
                    } else {
                        Rectangle().fill(.regularMaterial)
                    }
                }
        }
        .background(PCLTheme.sidebarBackground)
    }

    private var loginModeSelector: some View {
        Picker("", selection: $model.loginMode) {
            Text("正版").tag("正版")
            Text("离线").tag("离线")
            Text("统一").tag("统一通行证")
            Text("Authlib").tag("Authlib")
        }
        .pickerStyle(.segmented)
        .help("选择登录方式")
    }

    private var accountCard: some View {
        PCLContentCard("登录", systemImage: loginIcon) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    PCLCapsuleBadge(title: model.loginMode, systemImage: loginIcon)
                    Spacer()
                    if let account = model.selectedLaunchModeAccount {
                        Text(account.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                accountEditor

                if !model.launchModeAccounts.isEmpty {
                    Picker("当前启动账户", selection: Binding(
                        get: { model.selectedLaunchModeAccountID },
                        set: { model.selectedLaunchModeAccountID = $0 }
                    )) {
                        ForEach(model.launchModeAccounts) { account in
                            Text("\(account.displayName) · \(account.kind.displayName)")
                                .tag(Optional(account.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text(model.accountVaultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var accountEditor: some View {
        switch model.loginMode {
        case "正版":
            if let account = model.selectedLaunchAccount, account.kind == .microsoft {
                PCLInfoRow(title: "Microsoft 账户", value: account.displayName, systemImage: "checkmark.shield.fill")
            } else {
                Text(model.microsoftClientIDResolution.isConfigured ? "点击登录后会打开 Microsoft 设备码授权。" : "当前应用未配置 Microsoft 授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await model.startMicrosoftLogin() }
            } label: {
                Label(model.isMicrosoftLoginInProgress ? "等待授权" : "登录 Microsoft", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.borderless)
            .disabled(model.isMicrosoftLoginInProgress)

            if let code = model.microsoftDeviceCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设备验证码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(code.userCode)
                        .font(.system(.headline, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

        case "统一通行证":
            TextField("服务器 ID", text: $model.nideServerID)
                .textFieldStyle(.roundedBorder)
            TextField("统一通行证账号", text: $model.nideUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("统一通行证密码", text: $model.nidePassword)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await model.startNideLogin() }
            } label: {
                Label(model.isNideLoginInProgress ? "正在登录" : "登录统一通行证", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.borderless)
            .disabled(model.isNideLoginInProgress)

        case "Authlib":
            TextField("Authlib 服务器", text: $model.authlibServerURL)
                .textFieldStyle(.roundedBorder)
            TextField("Authlib 账号", text: $model.authlibUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("Authlib 密码", text: $model.authlibPassword)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await model.startAuthlibLogin() }
            } label: {
                Label(model.isAuthlibLoginInProgress ? "正在登录" : "登录 Authlib", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.borderless)
            .disabled(model.isAuthlibLoginInProgress)

        default:
            TextField("玩家名", text: $model.offlineUsername)
                .textFieldStyle(.roundedBorder)
            Button {
                model.saveCurrentOfflineAccount()
            } label: {
                Label("保存离线账户", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private var versionCard: some View {
        let visibleInstances = model.visibleMinecraftInstances
        let hiddenCount = model.hiddenMinecraftInstanceCount
        let favoriteCount = model.favoriteMinecraftInstanceCount
        let query = model.localVersionQuery.trimmed
        return PCLContentCard("版本", systemImage: "cube.box.fill") {
            VStack(alignment: .leading, spacing: 12) {
                PCLSearchField(prompt: "搜索本地版本", text: $model.localVersionQuery)

                Picker("快速筛选", selection: $model.localVersionFilter) {
                    ForEach(LocalVersionFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("版本选择", selection: Binding(
                    get: { model.selectedInstanceID },
                    set: { model.selectedInstanceID = $0 }
                )) {
                    if visibleInstances.isEmpty {
                        Text(model.minecraftInstances.isEmpty ? "未发现版本" : (query.isEmpty ? "无可见版本" : "无匹配版本"))
                            .tag(Optional<MinecraftInstance.ID>.none)
                    } else {
                        ForEach(visibleInstances) { instance in
                            Label(instance.name, systemImage: model.isFavoriteInstance(instance) ? "star.fill" : (model.isHiddenInstance(instance) ? "eye.slash" : "cube.box"))
                                .tag(Optional(instance.id))
                        }
                    }
                }
                .pickerStyle(.menu)

                if hiddenCount > 0 || favoriteCount > 0 || !query.isEmpty || model.selectedLocalVersionFilter != .all {
                    HStack(spacing: 8) {
                        if favoriteCount > 0 {
                            PCLCapsuleBadge(title: "\(favoriteCount) 个收藏", systemImage: "star.fill")
                        }
                        if hiddenCount > 0 {
                            PCLCapsuleBadge(title: model.showsHiddenInstances ? "显示隐藏" : "\(hiddenCount) 个隐藏", systemImage: model.showsHiddenInstances ? "eye" : "eye.slash")
                        }
                        if !query.isEmpty {
                            PCLCapsuleBadge(title: "搜索 \(query)", systemImage: "magnifyingglass")
                        }
                        if let filterTitle = model.localVersionFilterBadgeTitle {
                            PCLCapsuleBadge(title: filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }

                Picker("Java", selection: Binding(
                    get: { model.selectedJavaID },
                    set: { model.selectedJavaID = $0 }
                )) {
                    if model.javaInstallations.isEmpty {
                        Text("未发现 Java").tag(Optional<JavaInstallation.ID>.none)
                    } else {
                        ForEach(model.javaInstallations) { java in
                            Text(java.versionSummary).tag(Optional(java.id))
                        }
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        PCLInfoRow(title: "版本要求", value: model.selectedInstanceJavaRequirementText, systemImage: "cup.and.saucer")
                        PCLInfoRow(title: "实际使用", value: model.effectiveJavaSummary, systemImage: "checkmark.circle")
                    }
                    Text(model.effectiveJavaDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Button {
                        model.openMinecraftFolder()
                    } label: {
                        Image(systemName: "folder")
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("打开 Minecraft 根目录")

                    Button {
                        model.openSelectedInstanceFolder()
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("打开当前实例目录")
                    .disabled(model.selectedInstance == nil)

                    Button {
                        model.chooseAndImportLocalInstanceArchive()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("导入实例备份")
                    .disabled(model.isManagingInstance)

                    Button {
                        model.toggleFavoriteSelectedInstance()
                    } label: {
                        Image(systemName: model.selectedInstanceIsFavorite ? "star.fill" : "star")
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(model.selectedInstanceIsFavorite ? "取消收藏当前实例" : "收藏当前实例")
                    .disabled(model.selectedInstance == nil)

                    Button {
                        model.toggleHiddenSelectedInstance()
                    } label: {
                        Image(systemName: model.selectedInstanceIsHidden ? "eye" : "eye.slash")
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(model.selectedInstanceIsHidden ? "取消隐藏当前实例" : "隐藏当前实例")
                    .disabled(model.selectedInstance == nil)

                    Button {
                        model.openSelectedVersionSettings()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("版本设置")

                    Menu {
                        Button {
                            model.toggleFavoriteSelectedInstance()
                        } label: {
                            Label(model.selectedInstanceIsFavorite ? "取消收藏当前实例" : "收藏当前实例", systemImage: model.selectedInstanceIsFavorite ? "star.slash" : "star")
                        }
                        .disabled(model.selectedInstance == nil)

                        Button {
                            model.toggleHiddenSelectedInstance()
                        } label: {
                            Label(model.selectedInstanceIsHidden ? "取消隐藏当前实例" : "隐藏当前实例", systemImage: model.selectedInstanceIsHidden ? "eye" : "eye.slash")
                        }
                        .disabled(model.selectedInstance == nil)

                        Divider()

                        Button {
                            Task { await model.duplicateSelectedInstance() }
                        } label: {
                            Label("复制当前实例", systemImage: "doc.on.doc")
                        }
                        .disabled(model.selectedInstance == nil || model.isManagingInstance)

                        Button {
                            model.chooseAndExportSelectedInstance()
                        } label: {
                            Label("导出当前实例", systemImage: "square.and.arrow.up")
                        }
                        .disabled(model.selectedInstance == nil || model.isManagingInstance)

                        Button(role: .destructive) {
                            model.confirmRemoveSelectedInstance()
                        } label: {
                            Label("删除当前实例", systemImage: "trash")
                        }
                        .disabled(model.selectedInstance == nil || model.isManagingInstance || model.isLaunching || model.isPreparingLaunch)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .help("实例操作")

                    Spacer()
                }
            }
        }
    }

    private var serverCard: some View {
        PCLContentCard("服务器", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 10) {
                PCLInfoRow(title: "启动目标", value: model.launchServerTargetText, systemImage: "link")
                Text(model.launchServerTargetScopeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if model.serverFavorites.isEmpty {
                    Text("可在「联机」页保存常用服务器")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("常用服务器", selection: Binding(
                        get: { model.selectedServerFavoriteID },
                        set: { model.selectedServerFavoriteID = $0 }
                    )) {
                        ForEach(model.serverFavorites) { favorite in
                            Text(favorite.displayName)
                                .tag(Optional(favorite.id))
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Button {
                            model.useSelectedServerFavoriteForLaunch()
                        } label: {
                            Label("设为启动", systemImage: "play.rectangle.on.rectangle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.selectedServerFavorite == nil)

                        Button {
                            Task { await model.launchSelectedServerFavorite() }
                        } label: {
                            Label("启动并进服", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.selectedServerFavorite == nil || !model.canLaunchSelectedInstance)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var launchProgressCard: some View {
        PCLContentCard("启动状态", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.launchStatus.title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if model.isScanning || model.isPreparingLaunch {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                ProgressView(value: model.launchStatus.progress)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                    GridRow {
                        Text("当前步骤").foregroundStyle(.secondary)
                        Text(model.launchStatus.detail).lineLimit(1)
                    }
                    GridRow {
                        Text("登录方式").foregroundStyle(.secondary)
                        Text(model.loginMode)
                    }
                    GridRow {
                        Text("启动进度").foregroundStyle(.secondary)
                        Text("\(Int(model.launchStatus.progress * 100)) %")
                    }
                }
                .font(.caption)
            }
        }
    }

    private var launchFooter: some View {
        let readiness = model.launchReadiness
        return VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button {
                    Task { await model.launchSelectedInstance() }
                } label: {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [palette.accentLight, palette.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        VStack(spacing: 3) {
                            Text(model.isScanning || model.isPreparingLaunch ? "正在准备" : (readiness.isReady ? "启动游戏" : "无法启动"))
                                .font(.system(size: 17, weight: .bold))
                            Text(readiness.isReady ? (model.selectedInstance?.name ?? model.launchStatus.detail) : readiness.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .opacity(0.86)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 56)
                    .opacity(readiness.isReady ? 1 : 0.58)
                }
                .buttonStyle(.plain)
                .disabled(!model.canLaunchSelectedInstance)

                if model.isLaunching {
                    Button {
                        model.stopGame()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("关闭 Minecraft")
                }
            }

            Label(readiness.isReady ? model.lastEvent : readiness.detail, systemImage: readiness.systemImage)
                .font(.caption)
                .foregroundStyle(readiness.isReady ? Color.secondary : Color.orange)
                .lineLimit(2)
        }
    }

    private var loginIcon: String {
        switch model.loginMode {
        case "正版": "checkmark.shield.fill"
        case "统一通行证": "network"
        case "Authlib": "key.fill"
        default: "person.fill"
        }
    }
}

struct LaunchDashboard: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.showsHomeHint {
                    PCLHintBanner(
                        title: "Plain Craft Launcher (PCL) macOS",
                        message: "当前首屏按 PCL 的启动页结构重做：左侧负责登录、版本和启动，右侧保留启动日志、环境状态与版本列表。"
                    )
                    .transition(usesHighPerformanceMode ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                summaryPanels

                if model.isHomeCardVisible(.dependency), model.selectedInstance != nil || model.isPreparingLaunch || !model.dependencyProgressEntries.isEmpty {
                    DependencyProgressPanel()
                        .transition(usesHighPerformanceMode ? PCLMotion.performanceSectionTransition : PCLMotion.sectionTransition)
                }

                if model.isHomeCardVisible(.launchConfig), model.selectedInstance != nil {
                    launchConfigurationCard
                        .transition(usesHighPerformanceMode ? PCLMotion.performanceSectionTransition : PCLMotion.sectionTransition)
                }

                if model.isHomeCardVisible(.command), !model.launchCommandPreview.isEmpty {
                    PCLContentCard("启动命令", systemImage: "terminal.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if model.isLaunchCommandPreviewTruncated {
                                    PCLCapsuleBadge(title: "已折叠长命令", systemImage: "text.alignleft")
                                }
                                Spacer()
                                Button {
                                    model.copyLaunchCommandPreview()
                                } label: {
                                    Label("复制完整命令", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }

                            Text(model.launchCommandPreviewDisplay)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if model.isHomeCardVisible(.launchLog) {
                    PCLContentCard("启动日志", systemImage: "doc.text.magnifyingglass") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.lastEvent)
                                .font(.system(size: 13, weight: .medium))
                            Text(model.launchStatus.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if model.isHomeCardVisible(.versions) {
                    versionListCard
                }

                if !hasVisibleHomeContent {
                    ContentUnavailableView("首页卡片已隐藏", systemImage: "rectangle.3.group", description: Text("到「设置 → 界面 → 主页卡片」重新打开需要的卡片"))
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(22)
        }
        .animation(usesHighPerformanceMode ? nil : PCLMotion.section, value: model.showsHomeHint)
        .animation(usesHighPerformanceMode ? nil : PCLMotion.section, value: model.hiddenHomeCardIDs)
    }

    @ViewBuilder
    private var summaryPanels: some View {
        let showStatus = model.isHomeCardVisible(.status)
        let showJava = model.isHomeCardVisible(.java)
        if showStatus || showJava {
            HStack(alignment: .top, spacing: 14) {
                if showStatus {
                    StatusPanel()
                }
                if showJava {
                    JavaPanel()
                }
            }
        }
    }

    private var hasVisibleHomeContent: Bool {
        model.isHomeCardVisible(.status)
            || model.isHomeCardVisible(.java)
            || (model.isHomeCardVisible(.dependency) && (model.selectedInstance != nil || model.isPreparingLaunch || !model.dependencyProgressEntries.isEmpty))
            || (model.isHomeCardVisible(.launchConfig) && model.selectedInstance != nil)
            || (model.isHomeCardVisible(.command) && !model.launchCommandPreview.isEmpty)
            || model.isHomeCardVisible(.launchLog)
            || model.isHomeCardVisible(.versions)
    }

    private var launchConfigurationCard: some View {
        let readiness = model.launchReadiness
        return PCLContentCard("启动配置", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PCLCapsuleBadge(
                        title: readiness.title,
                        systemImage: readiness.systemImage,
                        tint: readiness.isReady ? .green : .orange
                    )
                    PCLCapsuleBadge(title: model.selectedInstance?.name ?? "未选择版本", systemImage: "cube.box.fill")
                    PCLCapsuleBadge(title: model.loginMode, systemImage: "person.crop.circle")
                    if launchExtraArgumentsText != "无" {
                        PCLCapsuleBadge(title: launchExtraArgumentsText, systemImage: "terminal")
                    }
                    Spacer()
                    Button {
                        model.copySelectedLaunchConfigurationSummary()
                    } label: {
                        Label("复制摘要", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        Task { await model.prepareSelectedInstanceDependencies() }
                    } label: {
                        Label("预补全", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canPrepareSelectedInstanceDependencies)

                    Button {
                        model.openSelectedVersionSettings()
                    } label: {
                        Label("版本设置", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        PCLInfoRow(title: "就绪检查", value: readiness.detail, systemImage: readiness.systemImage)
                        PCLInfoRow(title: "版本", value: model.selectedInstance?.name ?? "未选择", systemImage: "cube.box")
                        PCLInfoRow(title: "登录", value: model.launchAccountSummaryText, systemImage: "person.fill")
                        PCLInfoRow(title: "Java", value: model.effectiveJavaSummary, systemImage: "cup.and.saucer")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 10) {
                        PCLInfoRow(title: "内存", value: "\(Int(model.effectiveVersionMemory)) MB", systemImage: "memorychip")
                        PCLInfoRow(title: "窗口", value: model.selectedInstanceWindowText, systemImage: model.effectiveVersionFullscreen ? "arrow.up.left.and.arrow.down.right" : "macwindow")
                        PCLInfoRow(title: "游戏目录", value: model.effectiveVersionIsolation ? "版本目录" : "Minecraft 根目录", systemImage: "folder")
                        PCLInfoRow(title: "自动进服", value: model.launchServerTargetText, systemImage: "link")
                        PCLInfoRow(title: "额外参数", value: launchExtraArgumentsText, systemImage: "terminal")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Text(model.selectedInstanceGameDirectoryText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }

    private var launchExtraArgumentsText: String {
        model.selectedEffectiveExtraArgumentsSummaryText
    }

    private var versionListCard: some View {
        let visibleInstances = model.visibleMinecraftInstances
        let hiddenCount = model.hiddenMinecraftInstanceCount
        let favoriteCount = model.favoriteMinecraftInstanceCount
        let query = model.localVersionQuery.trimmed
        return PCLContentCard("版本列表", systemImage: "square.stack.3d.up.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PCLCapsuleBadge(title: "\(visibleInstances.count)/\(model.minecraftInstances.count) 个版本", systemImage: "cube.box.fill")
                    if favoriteCount > 0 {
                        PCLCapsuleBadge(title: "\(favoriteCount) 个收藏", systemImage: "star.fill")
                    }
                    if hiddenCount > 0 {
                        PCLCapsuleBadge(title: "\(hiddenCount) 个隐藏", systemImage: "eye.slash")
                    }
                    if !query.isEmpty {
                        PCLCapsuleBadge(title: "搜索 \(query)", systemImage: "magnifyingglass")
                    }
                    if let filterTitle = model.localVersionFilterBadgeTitle {
                        PCLCapsuleBadge(title: filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Spacer()
                    PCLSearchField(prompt: "搜索版本/路径", text: $model.localVersionQuery)
                        .frame(width: 220)
                    Picker("快速筛选", selection: $model.localVersionFilter) {
                        ForEach(LocalVersionFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 116)
                    Toggle("显示隐藏", isOn: $model.showsHiddenInstances)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(hiddenCount == 0)
                }

                HStack(spacing: 10) {
                    Button {
                        model.toggleFavoriteSelectedInstance()
                    } label: {
                        Label(model.selectedInstanceIsFavorite ? "取消收藏" : "收藏", systemImage: model.selectedInstanceIsFavorite ? "star.slash" : "star")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil)

                    Button {
                        model.toggleHiddenSelectedInstance()
                    } label: {
                        Label(model.selectedInstanceIsHidden ? "取消隐藏" : "隐藏", systemImage: model.selectedInstanceIsHidden ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil)

                    Button {
                        model.chooseAndImportLocalInstanceArchive()
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isManagingInstance)

                    Button {
                        model.openSelectedInstanceFolder()
                    } label: {
                        Label("打开", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil)

                    Button {
                        Task { await model.duplicateSelectedInstance() }
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil || model.isManagingInstance)

                    Button {
                        model.chooseAndExportSelectedInstance()
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil || model.isManagingInstance)

                    Button(role: .destructive) {
                        model.confirmRemoveSelectedInstance()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil || model.isManagingInstance || model.isLaunching || model.isPreparingLaunch)

                    Button {
                        Task { await model.refreshEnvironment() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }

                if model.minecraftInstances.isEmpty {
                    ContentUnavailableView("未发现 Minecraft 版本", systemImage: "cube.transparent", description: Text(model.minecraftDirectory.path))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if visibleInstances.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty && model.selectedLocalVersionFilter == .all ? "没有可见版本" : "没有匹配版本",
                        systemImage: query.isEmpty && model.selectedLocalVersionFilter == .all ? "eye.slash" : "magnifyingglass",
                        description: Text(emptyVersionListDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    Table(visibleInstances, selection: $model.selectedInstanceID) {
                        TableColumn("名称") { instance in
                            HStack(spacing: 7) {
                                Image(systemName: model.isFavoriteInstance(instance) ? "star.fill" : (model.isHiddenInstance(instance) ? "eye.slash" : "cube.box"))
                                    .foregroundStyle(model.isFavoriteInstance(instance) ? .yellow : .secondary)
                                    .frame(width: 16)
                                Text(instance.name)
                                    .lineLimit(1)
                            }
                            .contextMenu {
                                versionContextMenu(for: instance)
                            }
                        }
                        TableColumn("类型") { instance in
                            Label(model.localVersionKindDisplay(for: instance), systemImage: model.localVersionLoaderSystemImage(for: instance))
                                .foregroundStyle(.secondary)
                                .contextMenu {
                                    versionContextMenu(for: instance)
                                }
                        }
                        TableColumn("路径") { instance in
                            Text(instance.path.path)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .contextMenu {
                                    versionContextMenu(for: instance)
                                }
                        }
                    }
                    .frame(minHeight: 260)

                    if let instance = model.selectedInstance {
                        selectedVersionDetails(instance)
                    }
                }
            }
        }
    }

    private func selectedVersionDetails(_ instance: MinecraftInstance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack {
                Label("选中版本详情", systemImage: "info.circle")
                    .font(.headline)
                Spacer()
                Button {
                    model.copySelectedInstanceSummary()
                } label: {
                    Label("复制详情", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)

                Button {
                    model.openSelectedVersionSettings()
                } label: {
                    Label("版本设置", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)

                Button {
                    model.openSelectedInstanceFolder()
                } label: {
                    Label("打开目录", systemImage: "folder")
                }
                .buttonStyle(.borderless)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    PCLInfoRow(title: "加载器", value: model.localVersionLoaderDisplay(for: instance), systemImage: model.localVersionLoaderSystemImage(for: instance))
                    PCLInfoRow(title: "版本类型", value: model.localVersionMetadataTypeDisplay(for: instance), systemImage: "tag")
                    PCLInfoRow(title: "Java 要求", value: model.selectedInstanceJavaRequirementText, systemImage: "cup.and.saucer")
                    PCLInfoRow(title: "启动 Java", value: model.effectiveJavaSummary, systemImage: "checkmark.circle")
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 10) {
                    PCLInfoRow(title: "游戏目录", value: model.effectiveVersionIsolation ? "版本目录" : "Minecraft 根目录", systemImage: "folder")
                    PCLInfoRow(title: "内存", value: "\(Int(model.effectiveVersionMemory)) MB", systemImage: "memorychip")
                    PCLInfoRow(title: "窗口", value: model.selectedInstanceWindowText, systemImage: model.effectiveVersionFullscreen ? "arrow.up.left.and.arrow.down.right" : "macwindow")
                    PCLInfoRow(title: "自动进服", value: model.launchServerTargetText, systemImage: "link")
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("版本目录", systemImage: "folder.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(instance.path.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 2)
    }

    private var emptyVersionListDescription: String {
        if !model.localVersionQuery.trimmed.isEmpty {
            return "清空搜索、切回“全部”，或打开“显示隐藏”扩大匹配范围"
        }
        if model.selectedLocalVersionFilter != .all {
            return "切回“全部”，或打开“显示隐藏”扩大匹配范围"
        }
        return "隐藏版本已被过滤，打开“显示隐藏”即可恢复列表"
    }

    @ViewBuilder
    private func versionContextMenu(for instance: MinecraftInstance) -> some View {
        Button {
            model.selectInstance(instance)
            Task { await model.launchSelectedInstance() }
        } label: {
            Label("启动此版本", systemImage: "play.fill")
        }
        .disabled(model.selectedJava == nil || model.isPreparingLaunch || model.isLaunching)

        Button {
            model.selectInstance(instance)
            model.openSelectedVersionSettings()
        } label: {
            Label("版本设置", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button {
            model.selectInstance(instance)
            model.toggleFavoriteSelectedInstance()
        } label: {
            Label(model.isFavoriteInstance(instance) ? "取消收藏" : "收藏版本", systemImage: model.isFavoriteInstance(instance) ? "star.slash" : "star")
        }

        Button {
            model.selectInstance(instance)
            model.toggleHiddenSelectedInstance()
        } label: {
            Label(model.isHiddenInstance(instance) ? "取消隐藏" : "隐藏版本", systemImage: model.isHiddenInstance(instance) ? "eye" : "eye.slash")
        }

        Divider()

        Button {
            model.selectInstance(instance)
            model.openSelectedInstanceFolder()
        } label: {
            Label("打开版本文件夹", systemImage: "folder")
        }

        Button {
            model.selectInstance(instance)
            Task { await model.duplicateSelectedInstance() }
        } label: {
            Label("复制版本", systemImage: "doc.on.doc")
        }
        .disabled(model.isManagingInstance)

        Button {
            model.selectInstance(instance)
            model.chooseAndExportSelectedInstance()
        } label: {
            Label("导出版本", systemImage: "square.and.arrow.up")
        }
        .disabled(model.isManagingInstance)

        Divider()

        Button(role: .destructive) {
            model.selectInstance(instance)
            model.confirmRemoveSelectedInstance()
        } label: {
            Label("删除版本", systemImage: "trash")
        }
        .disabled(model.isManagingInstance || model.isLaunching || model.isPreparingLaunch)
    }
}

struct StatusPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        let status = model.currentLaunchReadinessStatus
        PCLContentCard("状态", systemImage: model.isScanning || model.isPreparingLaunch ? "magnifyingglass" : statusIcon(for: status)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(status.title)
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    if model.isScanning || model.isPreparingLaunch {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                ProgressView(value: status.progress)
                Text(status.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(model.lastEvent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func statusIcon(for status: LaunchStatus) -> String {
        status.progress > 0 ? "play.circle.fill" : "exclamationmark.triangle.fill"
    }
}

struct DependencyProgressPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        PCLContentCard("依赖补全", systemImage: "arrow.down.doc.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PCLCapsuleBadge(title: model.dependencyProgressSummary, systemImage: "list.bullet.rectangle")
                    Spacer(minLength: 8)
                    if model.isPreparingLaunch {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        Task { await model.prepareSelectedInstanceDependencies() }
                    } label: {
                        Label("预补全", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canPrepareSelectedInstanceDependencies)
                }

                ProgressView(value: model.latestDependencyProgress?.finishedValue ?? model.launchStatus.progress)

                if model.dependencyProgressEntries.isEmpty {
                    ContentUnavailableView(
                        dependencyPlaceholderTitle,
                        systemImage: dependencyPlaceholderSystemImage,
                        description: Text(dependencyPlaceholderDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 96)
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.dependencyProgressEntries.prefix(8)) { entry in
                            DependencyProgressRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private var dependencyPlaceholderTitle: String {
        if model.isPreparingLaunch {
            return "正在准备依赖检查"
        }
        if model.launchStatus.title == "依赖已就绪" {
            return "依赖已就绪"
        }
        return "尚未补全依赖"
    }

    private var dependencyPlaceholderSystemImage: String {
        if model.isPreparingLaunch {
            return "arrow.clockwise"
        }
        if model.launchStatus.title == "依赖已就绪" {
            return "checkmark.circle"
        }
        return "tray.and.arrow.down"
    }

    private var dependencyPlaceholderDescription: String {
        if model.launchStatus.title == "依赖已就绪" {
            return model.launchStatus.detail
        }
        return "可先下载 client、libraries、natives 和 assets，之后启动会更快"
    }
}

private struct DependencyProgressRow: View {
    let entry: DependencyProgressEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.state == .downloaded ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(entry.state == .downloaded ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            Text(entry.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(entry.state.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(entry.finished)/\(entry.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private extension DependencyProgressEntry {
    var finishedValue: Double {
        guard total > 0 else { return 1 }
        return Double(finished) / Double(total)
    }
}

struct JavaPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        PCLContentCard("Java", systemImage: "cup.and.saucer.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    PCLCapsuleBadge(title: "\(model.javaInstallations.count) 个 Java", systemImage: "terminal.fill")
                    if model.effectiveJavaCompatibilityMessage != nil {
                        PCLCapsuleBadge(title: "版本过低", systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 5) {
                    PCLInfoRow(title: "当前版本要求", value: model.selectedInstanceJavaRequirementText, systemImage: "cube.box")
                    PCLInfoRow(title: "启动将使用", value: model.effectiveJavaSummary, systemImage: "checkmark.circle")
                    Text(model.effectiveJavaDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 2)

                if let javaIssue = model.effectiveJavaCompatibilityMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(javaIssue)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if model.recommendedCompatibleJava != nil {
                                Button {
                                    model.useRecommendedCompatibleJavaForSelectedVersion()
                                } label: {
                                    Label("使用兼容 Java", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else if model.canInstallRecommendedJavaRuntime || model.isInstallingJavaRuntime {
                                Button {
                                    model.installRecommendedJavaRuntime()
                                } label: {
                                    Label(
                                        model.isInstallingJavaRuntime ? "正在安装 Java" : model.recommendedJavaRuntimeInstallButtonTitle,
                                        systemImage: model.isInstallingJavaRuntime ? "arrow.down.circle" : "arrow.down.circle.fill"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!model.canInstallRecommendedJavaRuntime)
                            }

                            Button {
                                model.openSelectedVersionJavaSettings()
                            } label: {
                                Label("版本 Java 设置", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                model.copySelectedJavaDiagnostics()
                            } label: {
                                Label("复制诊断", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                        if model.isInstallingJavaRuntime {
                            ProgressView(value: model.launchStatus.progress)
                                .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                ForEach(model.javaInstallations.prefix(3)) { java in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(java.versionSummary)
                            .lineLimit(1)
                        Text(java.executable.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Divider()
                }
                if model.javaInstallations.isEmpty {
                    Text("未发现 Java")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 74)
                }
            }
        }
    }
}

struct DownloadLeftPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        PCLSidebarNavigation(
            title: "下载",
            items: DownloadSection.allCases,
            selection: $model.selectedDownloadSection,
            itemTitle: { section in
                if section == .tasks, model.activeDownloadTaskCount > 0 {
                    return "任务 (\(model.activeDownloadTaskCount))"
                }
                return section.rawValue
            },
            itemSystemImage: { $0.systemImage }
        )
    }
}

struct DownloadDashboard: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        Group {
            switch model.selectedDownloadSection {
            case .tasks:
                DownloadTasksDashboard()
            case .vanilla:
                VanillaDownloadDashboard()
            case .mods:
                ResourceDownloadDashboard(projectType: .mod, section: .mods)
            case .modpacks:
                ResourceDownloadDashboard(projectType: .modpack, section: .modpacks)
            case .datapacks:
                ResourceDownloadDashboard(projectType: .datapack, section: .datapacks)
            case .resourcepacks:
                ResourceDownloadDashboard(projectType: .resourcepack, section: .resourcepacks)
            case .shaders:
                ResourceDownloadDashboard(projectType: .shader, section: .shaders)
            }
        }
        .id(usesHighPerformanceMode ? "download-dashboard" : model.selectedDownloadSection.id)
        .transition(usesHighPerformanceMode ? PCLMotion.performanceSectionTransition : PCLMotion.sectionTransition)
        .animation(usesHighPerformanceMode ? nil : PCLMotion.section, value: model.selectedDownloadSection)
    }
}

struct VanillaDownloadDashboard: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("搜索版本", text: $model.remoteVersionQuery)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $model.remoteVersionFilter) {
                    Text("正式版").tag("release")
                    Text("快照版").tag("snapshot")
                    Text("全部").tag("all")
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Button {
                    Task { await model.loadRemoteVersions() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingRemoteVersions)
            }

            HStack(alignment: .top, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("原版游戏", systemImage: "cube.box.fill")
                                .font(.headline)
                            Spacer()
                            if model.isLoadingRemoteVersions {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if model.remoteVersions.isEmpty {
                            ContentUnavailableView("尚未加载版本列表", systemImage: "arrow.down.circle", description: Text("点击刷新获取 Mojang 版本清单"))
                                .frame(minHeight: 260)
                        } else {
                            Table(model.filteredRemoteVersions, selection: $model.selectedRemoteVersionID) {
                                TableColumn("版本") { version in
                                    Text(version.id)
                                }
                                TableColumn("类型") { version in
                                    Text(version.displayType)
                                        .foregroundStyle(.secondary)
                                }
                                TableColumn("发布时间") { version in
                                    Text(version.releaseTime)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(minHeight: 300)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("安装", systemImage: "tray.and.arrow.down.fill")
                            .font(.headline)

                        if let version = model.selectedRemoteVersion {
                            LabeledContent("版本") {
                                Text(version.id)
                            }
                            LabeledContent("类型") {
                                Text(version.displayType)
                            }
                        } else {
                            Text("未选择版本")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Picker("下载源", selection: $model.downloadSource) {
                            ForEach(MinecraftDownloadSource.allCases) { source in
                                Text(source.rawValue).tag(source.rawValue)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("加载器", selection: $model.selectedInstallLoader) {
                            Text("原版").tag("原版")
                            Text("Forge").tag("Forge")
                            Text("Fabric").tag("Fabric")
                            Text("Quilt").tag("Quilt")
                            Text("NeoForge").tag("NeoForge")
                        }

                        Slider(value: $model.maxDownloadThreads, in: 1...64, step: 1) {
                            Text("线程")
                        } minimumValueLabel: {
                            Text("1")
                        } maximumValueLabel: {
                            Text("64")
                        }
                        Text("线程：\(Int(model.maxDownloadThreads))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            model.startSelectedRemoteVersionInstall()
                        } label: {
                            Text(model.isInstallingVersion ? "正在安装" : "安装版本")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isInstallingVersion || model.selectedRemoteVersion == nil)

                        Button {
                            model.showDownloadTasks()
                        } label: {
                            Label("查看任务", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Text(model.installMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(4)
                    .frame(width: 260)
                }
            }

            Spacer()
        }
        .padding(22)
        .task {
            if model.remoteVersions.isEmpty {
                await model.loadRemoteVersions()
            }
        }
    }
}

struct DownloadTasksDashboard: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下载任务")
                        .font(.system(size: 20, weight: .semibold))
                    Text(model.activeDownloadTaskCount == 0 ? "最近安装和导入记录" : "\(model.activeDownloadTaskCount) 个任务正在进行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.pauseSelectedDownloadTask()
                } label: {
                    Label("暂停", systemImage: "pause.circle")
                }
                .disabled(!model.canPauseSelectedDownloadTask)

                Button {
                    Task { await model.retrySelectedDownloadTask() }
                } label: {
                    Label(model.selectedDownloadTaskResumeButtonTitle, systemImage: model.selectedDownloadTaskResumeButtonSystemImage)
                }
                .disabled(!model.canRetrySelectedDownloadTask)

                Button {
                    model.copySelectedDownloadTaskSummary()
                } label: {
                    Label("复制摘要", systemImage: "doc.on.doc")
                }
                .disabled(model.selectedDownloadTask == nil)

                Button {
                    model.revealSelectedDownloadTaskInFinder()
                } label: {
                    Label("打开位置", systemImage: "folder")
                }
                .disabled(model.selectedDownloadTask?.destinationPath == nil)

                Menu {
                    Button {
                        model.clearFinishedDownloadTasks()
                    } label: {
                        Label("清理已完成", systemImage: "checkmark.circle")
                    }
                    .disabled(!model.downloadTaskRecords.contains { $0.status == .succeeded })

                    Button {
                        model.clearFailedDownloadTasks()
                    } label: {
                        Label("清理失败/暂停", systemImage: "xmark.circle")
                    }
                    .disabled(model.failedDownloadTaskCount == 0)

                    Divider()

                    Button(role: .destructive) {
                        model.clearDownloadTaskHistory()
                    } label: {
                        Label("清空历史", systemImage: "trash")
                    }
                    .disabled(!model.downloadTaskRecords.contains { $0.status != .running })
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }

            HStack(alignment: .top, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("任务列表", systemImage: "list.bullet.rectangle")
                                .font(.headline)
                            Spacer()
                            if model.activeDownloadTaskCount > 0 {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if model.downloadTaskRecords.isEmpty {
                            ContentUnavailableView(
                                "暂无任务",
                                systemImage: "tray",
                                description: Text("安装版本、下载 Mod 或导入整合包后会显示在这里")
                            )
                            .frame(minHeight: 340)
                        } else {
                            Table(model.downloadTaskRecords, selection: $model.selectedDownloadTaskID) {
                                TableColumn("名称") { task in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .font(.body.weight(.semibold))
                                            .lineLimit(1)
                                        Text(task.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                TableColumn("类型") { task in
                                    Text(task.category)
                                        .foregroundStyle(.secondary)
                                }
                                .width(110)
                                TableColumn("状态") { task in
                                    HStack(spacing: 5) {
                                        Image(systemName: task.status.systemImage)
                                            .foregroundStyle(task.status.tint)
                                        Text(task.status.rawValue)
                                            .foregroundStyle(task.status.tint)
                                    }
                                }
                                .width(92)
                                TableColumn("进度") { task in
                                    if task.status == .running {
                                        ProgressView(value: task.progress)
                                            .frame(width: 86)
                                    } else {
                                        Text(task.updatedAt.formatted(date: .omitted, time: .shortened))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .width(110)
                            }
                            .frame(minHeight: 360)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("详情", systemImage: "info.circle")
                            .font(.headline)

                        if let task = model.selectedDownloadTask {
                            PCLInfoRow(title: "名称", value: task.title, systemImage: "doc")
                            PCLInfoRow(title: "类型", value: task.category, systemImage: "tag")
                            PCLInfoRow(title: "状态", value: task.status.rawValue, systemImage: task.status.systemImage)
                            PCLInfoRow(title: "更新时间", value: task.updatedAt.formatted(date: .numeric, time: .shortened), systemImage: "clock")

                            if let progress = task.progress {
                                ProgressView(value: progress)
                                Text("\(Int(progress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            Text(task.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if task.status == .running && model.canPauseSelectedDownloadTask {
                                Button {
                                    model.pauseSelectedDownloadTask()
                                } label: {
                                    Label("暂停任务", systemImage: "pause.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            if task.status.isRecoverable && task.isRetryable {
                                Button {
                                    Task { await model.retrySelectedDownloadTask() }
                                } label: {
                                    Label(task.status == .paused ? "继续任务" : "重试任务", systemImage: task.status == .paused ? "play.circle" : "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isInstallingVersion)
                            }

                            Button {
                                model.copySelectedDownloadTaskSummary()
                            } label: {
                                Label("复制任务摘要", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            if let destinationPath = task.destinationPath {
                                Text(destinationPath)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)

                                Button {
                                    model.revealSelectedDownloadTaskInFinder()
                                } label: {
                                    Label("在 Finder 中显示", systemImage: "magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            ContentUnavailableView("未选择任务", systemImage: "info.circle", description: Text("从左侧表格选择一条任务"))
                                .frame(minHeight: 260)
                        }
                    }
                    .padding(4)
                    .frame(width: 280)
                }
            }
            Spacer()
        }
        .padding(22)
    }
}

private extension DownloadTaskStatus {
    var isRecoverable: Bool {
        switch self {
        case .failed, .paused, .cancelled:
            return true
        case .running, .succeeded:
            return false
        }
    }

    var systemImage: String {
        switch self {
        case .running: "arrow.down.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .running: Color.accentColor
        case .succeeded: .green
        case .failed: .red
        case .paused, .cancelled: .orange
        }
    }
}

struct ResourceDownloadDashboard: View {
    let projectType: ModrinthProjectType
    let section: DownloadSection
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        Group {
            if model.resourceProvider == "CurseForge",
               let curseForgeResourceType = section.curseForgeResourceType {
                CurseForgeResourceDashboard(resourceType: curseForgeResourceType, section: section)
            } else {
                ModrinthResourceDashboard(projectType: projectType, section: section)
            }
        }
        .onAppear {
            model.scheduleDownloadResourcePreparation()
        }
    }
}

struct ResourceProviderControl: View {
    let section: DownloadSection
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        if section.curseForgeResourceType != nil {
            Picker("来源", selection: $model.resourceProvider) {
                Text("Modrinth").tag("Modrinth")
                Text("CurseForge").tag("CurseForge")
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
    }
}

struct ResourceMetricGrid: View {
    let rows: [(String, String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                PCLInfoRow(title: row.0, value: row.1, systemImage: row.2)
            }
        }
    }
}

struct ResourceVersionFilePanel: View {
    let files: [ResourceVersionFilePreview]
    let message: String
    let isLoading: Bool
    @Binding var selectedFileID: ResourceVersionFilePreview.ID?
    let onRefresh: () -> Void
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("版本文件", systemImage: "doc.badge.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("刷新版本文件")
            }

            if files.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(files) { file in
                            Button {
                                select(file)
                            } label: {
                                ResourceVersionFileRow(
                                    file: file,
                                    selected: selectedFileID == file.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 178)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func select(_ file: ResourceVersionFilePreview) {
        if usesHighPerformanceMode {
            selectedFileID = file.id
        } else {
            withAnimation(PCLMotion.fast) {
                selectedFileID = file.id
            }
        }
    }
}

private struct ResourceVersionFileRow: View {
    let file: ResourceVersionFilePreview
    let selected: Bool
    @Environment(\.pclThemePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent)
                }
                Text(file.versionName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(file.releaseType)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(file.releaseTypeTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(file.releaseTypeTint.opacity(0.12), in: Capsule())
                if file.isPrimary {
                    Text("主文件")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
            }

            Text(file.fileName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(file.versionSummary, systemImage: "cube.box")
                Label(file.loaderSummary, systemImage: "puzzlepiece.extension")
                Spacer(minLength: 0)
                if let size = file.size {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.accent.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? palette.accent.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }
}

struct ProjectCategoryChips: View {
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items.prefix(8), id: \.self) { item in
                        Text(item)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
            }
        }
    }
}

struct ModrinthResourceDashboard: View {
    let projectType: ModrinthProjectType
    let section: DownloadSection
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ResourceProviderControl(section: section)

                TextField("搜索 Modrinth \(projectType.displayName)", text: $model.modrinthQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await model.searchModrinthResources(projectType) }
                    }

                Button {
                    Task { await model.searchModrinthResources(projectType) }
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .disabled(model.isSearchingModrinth)
            }

            HStack(alignment: .top, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Modrinth \(projectType.displayName)", systemImage: section.systemImage)
                                .font(.headline)
                            Spacer()
                            if model.isSearchingModrinth {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if model.modrinthResults.isEmpty {
                            ContentUnavailableView("尚未搜索\(projectType.displayName)", systemImage: "magnifyingglass", description: Text("输入关键词并点击搜索"))
                                .frame(minHeight: 300)
                        } else {
                            Table(model.modrinthResults, selection: $model.selectedModrinthProjectID) {
                                TableColumn("名称") { project in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.title)
                                            .font(.body.weight(.semibold))
                                            .lineLimit(1)
                                        Text(project.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                TableColumn("下载") { project in
                                    Text(project.downloads.formatted())
                                        .foregroundStyle(.secondary)
                                }
                                .width(90)
                            }
                            .frame(minHeight: 330)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(projectType.installActionTitle, systemImage: "square.and.arrow.down.fill")
                            .font(.headline)

                        if let project = model.selectedModrinthProject {
                            LabeledContent("项目") {
                                Text(project.title)
                                    .lineLimit(1)
                            }
                            Text(project.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .textSelection(.enabled)

                            ResourceMetricGrid(rows: [
                                ("作者", project.author ?? "-", "person"),
                                ("下载", project.downloads.formatted(), "arrow.down.circle"),
                                ("关注", project.follows.formatted(), "star"),
                                ("版本", project.versionSummary, "number")
                            ])

                            ProjectCategoryChips(items: project.categories)

                            HStack {
                                Button {
                                    model.openSelectedModrinthProjectPage(projectType)
                                } label: {
                                    Label("网页", systemImage: "safari")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    model.copySelectedModrinthProjectSummary(projectType)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            ResourceVersionFilePanel(
                                files: model.modrinthVersionFilePreviews,
                                message: model.modrinthVersionFilesMessage,
                                isLoading: model.isLoadingModrinthVersionFiles,
                                selectedFileID: $model.selectedModrinthVersionFileID
                            ) {
                                Task { await model.loadSelectedModrinthVersionFiles(projectType, force: true) }
                            }
                        } else {
                            Text("未选择\(projectType.displayName)")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        LabeledContent("目标实例") {
                            Text(targetInstanceText)
                                .lineLimit(1)
                        }
                        LabeledContent("保存位置") {
                            Text(projectType.destinationDescription)
                                .lineLimit(1)
                        }
                        LabeledContent("版本") {
                            Text(model.selectedInstance?.name ?? model.selectedRemoteVersion?.id ?? "自动")
                                .lineLimit(1)
                        }

                        Button {
                            model.openModrinthDestinationFolder(projectType)
                        } label: {
                            Label("打开保存目录", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(projectType == .mod && model.selectedInstance == nil)

                        Button {
                            Task { await model.installSelectedModrinthResource(projectType) }
                        } label: {
                            Text(model.isInstallingModrinthMod ? "正在处理" : model.modrinthInstallButtonTitle(projectType))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(installButtonDisabled)

                        Button {
                            model.showDownloadTasks()
                        } label: {
                            Label("查看任务", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if projectType == .modpack {
                            Button {
                                model.chooseAndImportLocalModrinthPack()
                            } label: {
                                Label("导入本地 .mrpack", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isInstallingModrinthMod)
                        }

                        if let lastFile = model.lastModrinthFileURL {
                            Divider()
                            LabeledContent("最近保存") {
                                Text(lastFile.lastPathComponent)
                                    .lineLimit(1)
                            }
                            Text(lastFile.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Button {
                                model.revealLastModrinthFileInFinder()
                            } label: {
                                Label("在 Finder 中显示", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        if projectType == .modpack, let plan = model.lastModrinthPackPlan {
                            Divider()
                            Label("整合包预检", systemImage: "checkmark.shield")
                                .font(.subheadline.weight(.semibold))
                            LabeledContent("名称") {
                                Text(plan.name)
                                    .lineLimit(1)
                            }
                            LabeledContent("Minecraft") {
                                Text(plan.minecraftVersion)
                            }
                            LabeledContent("加载器") {
                                Text(plan.loaderSummary)
                                    .lineLimit(1)
                            }
                            LabeledContent("文件") {
                                Text("\(plan.fileCount) 个远程文件 / \(plan.overrideEntryCount) 个覆盖文件")
                                    .lineLimit(1)
                            }

                            if let importResult = model.lastModrinthPackImportResult {
                                Divider()
                                Label("已导入实例", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                                LabeledContent("实例") {
                                    Text(importResult.instanceName)
                                        .lineLimit(1)
                                }
                                LabeledContent("写入") {
                                    Text("下载 \(importResult.downloadedFiles) / 跳过 \(importResult.skippedFiles) / 覆盖 \(importResult.copiedOverrides)")
                                        .lineLimit(1)
                                }
                                Button {
                                    model.showImportedModrinthPackInstance()
                                } label: {
                                    Label("进入启动页", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        Text(model.modrinthMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    .padding(4)
                    .frame(width: 280)
                }
            }

            if projectType == .mod {
                LocalModManagementPanel()
            }

            Spacer()
        }
        .padding(22)
        .onAppear {
            model.scheduleDownloadResourcePreparation()
        }
        .task(id: model.modrinthVersionFilesRequestKey(projectType)) {
            await model.loadSelectedModrinthVersionFiles(projectType)
        }
    }

    private var installButtonDisabled: Bool {
        if model.isInstallingModrinthMod || model.selectedModrinthProject == nil {
            return true
        }
        return projectType == .mod && model.selectedInstance == nil
    }

    private var targetInstanceText: String {
        switch projectType {
        case .mod:
            return model.selectedInstance?.name ?? "未选择"
        case .modpack:
            return "导入为独立实例"
        case .datapack:
            return "下载后选择存档导入"
        case .resourcepack, .shader:
            return model.selectedInstance?.name ?? "全局目录"
        }
    }
}

struct LocalModManagementPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Label("本地 Mod 管理", systemImage: "puzzlepiece.extension.fill")
                        .font(.headline)
                    if let instance = model.selectedInstance {
                        Text(instance.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if model.isLoadingLocalMods {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        Task { await model.refreshLocalMods() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil || model.isLoadingLocalMods)

                    Button {
                        model.chooseAndImportLocalMods()
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil || model.isLoadingLocalMods)

                    Button {
                        model.openLocalModsFolder()
                    } label: {
                        Label("打开文件夹", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedInstance == nil)

                    Button {
                        model.revealSelectedLocalModInFinder()
                    } label: {
                        Label("显示", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedLocalModFile == nil)

                    Button {
                        Task { await model.toggleSelectedLocalMod() }
                    } label: {
                        Label(toggleButtonTitle, systemImage: toggleButtonImage)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.selectedLocalModFile == nil || model.isLoadingLocalMods)
                }

                if model.localModFiles.isEmpty {
                    ContentUnavailableView(
                        model.selectedInstance == nil ? "未选择实例" : "没有本地 Mod",
                        systemImage: "puzzlepiece.extension",
                        description: Text(model.selectedInstance == nil ? "先在启动页选择 Minecraft 实例" : "点击添加，或把 .jar/.zip/.litemod 放入 mods 文件夹后刷新")
                    )
                    .frame(minHeight: 160)
                } else {
                    Table(model.localModFiles, selection: $model.selectedLocalModFileID) {
                        TableColumn("名称") { file in
                            HStack(spacing: 8) {
                                Image(systemName: file.status == .enabled ? "checkmark.circle.fill" : "pause.circle")
                                    .foregroundStyle(file.status == .enabled ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.displayName)
                                        .lineLimit(1)
                                    if file.metadata?.description != nil || file.displayName != file.url.deletingPathExtension().lastPathComponent {
                                        Text(file.url.lastPathComponent)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        TableColumn("加载器") { file in
                            Text(file.metadata?.loader ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        .width(72)
                        TableColumn("版本") { file in
                            Text(file.metadata?.version ?? "-")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .width(90)
                        TableColumn("状态") { file in
                            Text(file.status.rawValue)
                                .foregroundStyle(file.status == .enabled ? .green : .secondary)
                        }
                        .width(78)
                        TableColumn("大小") { file in
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                        .width(90)
                        TableColumn("更新时间") { file in
                            Text(file.modifiedAt?.formatted(date: .numeric, time: .shortened) ?? "-")
                                .foregroundStyle(.secondary)
                        }
                        .width(150)
                    }
                    .frame(minHeight: 190)
                }

                Text(model.localModMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(4)
        }
        .onAppear {
            Task { await model.refreshLocalMods() }
        }
    }

    private var toggleButtonTitle: String {
        guard let file = model.selectedLocalModFile else { return "切换" }
        return file.status == .enabled ? "禁用" : "启用"
    }

    private var toggleButtonImage: String {
        guard let file = model.selectedLocalModFile else { return "power" }
        return file.status == .enabled ? "pause.circle" : "play.circle"
    }
}

struct CurseForgeResourceDashboard: View {
    let resourceType: CurseForgeResourceType
    let section: DownloadSection
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ResourceProviderControl(section: section)

                TextField("搜索 CurseForge \(resourceType.displayName)", text: $model.curseForgeQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await model.searchCurseForgeResources(resourceType) }
                    }
                    .disabled(!model.hasCurseForgeAPIKey)

                Button {
                    Task { await model.searchCurseForgeResources(resourceType) }
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .disabled(!model.hasCurseForgeAPIKey || model.isSearchingCurseForge)
            }

            HStack(alignment: .top, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("CurseForge \(resourceType.displayName)", systemImage: section.systemImage)
                                .font(.headline)
                            Spacer()
                            if model.isSearchingCurseForge {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if !model.hasCurseForgeAPIKey {
                            ContentUnavailableView(
                                "需要 CurseForge API Key",
                                systemImage: "key.fill",
                                description: Text("在下载设置中填写，或通过环境变量 PCL_CURSEFORGE_API_KEY 提供")
                            )
                            .frame(minHeight: 300)
                        } else if model.curseForgeResults.isEmpty {
                            ContentUnavailableView("尚未搜索\(resourceType.displayName)", systemImage: "magnifyingglass", description: Text("输入关键词并点击搜索"))
                                .frame(minHeight: 300)
                        } else {
                            Table(model.curseForgeResults, selection: $model.selectedCurseForgeProjectID) {
                                TableColumn("名称") { project in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .font(.body.weight(.semibold))
                                            .lineLimit(1)
                                        Text(project.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                TableColumn("下载") { project in
                                    Text(project.downloadCount.formatted())
                                        .foregroundStyle(.secondary)
                                }
                                .width(90)
                            }
                            .frame(minHeight: 330)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(resourceType.installActionTitle, systemImage: "square.and.arrow.down.fill")
                            .font(.headline)

                        if let project = model.selectedCurseForgeProject {
                            LabeledContent("项目") {
                                Text(project.name)
                                    .lineLimit(1)
                            }
                            Text(project.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .textSelection(.enabled)

                            ResourceMetricGrid(rows: [
                                ("作者", project.authorSummary, "person"),
                                ("下载", project.downloadCount.formatted(), "arrow.down.circle"),
                                ("项目 ID", "\(project.id)", "number"),
                                ("Slug", project.slug ?? "-", "link")
                            ])

                            HStack {
                                Button {
                                    model.openSelectedCurseForgeProjectPage(resourceType)
                                } label: {
                                    Label("网页", systemImage: "safari")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(project.websiteURL(resourceType: resourceType) == nil)

                                Button {
                                    model.copySelectedCurseForgeProjectSummary(resourceType)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            ResourceVersionFilePanel(
                                files: model.curseForgeFilePreviews,
                                message: model.curseForgeFilesMessage,
                                isLoading: model.isLoadingCurseForgeFiles,
                                selectedFileID: $model.selectedCurseForgeFileID
                            ) {
                                Task { await model.loadSelectedCurseForgeFiles(resourceType, force: true) }
                            }
                        } else {
                            Text("未选择\(resourceType.displayName)")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        LabeledContent("目标实例") {
                            Text(targetInstanceText)
                                .lineLimit(1)
                        }
                        LabeledContent("保存位置") {
                            Text(resourceType.destinationDescription)
                                .lineLimit(1)
                        }
                        LabeledContent("版本") {
                            Text(model.selectedInstance?.name ?? model.selectedRemoteVersion?.id ?? "自动")
                                .lineLimit(1)
                        }

                        if !model.hasCurseForgeAPIKey {
                            Button {
                                model.selectedSettingsSection = .download
                                model.selectedPage = .settings
                            } label: {
                                Label("打开下载设置", systemImage: "key.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            model.openCurseForgeDestinationFolder(resourceType)
                        } label: {
                            Label("打开保存目录", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(resourceType == .mod && model.selectedInstance == nil)

                        Button {
                            Task { await model.installSelectedCurseForgeResource(resourceType) }
                        } label: {
                            Text(model.isInstallingCurseForgeResource ? "正在处理" : model.curseForgeInstallButtonTitle(resourceType))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(installButtonDisabled)

                        Button {
                            model.showDownloadTasks()
                        } label: {
                            Label("查看任务", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if resourceType == .modpack {
                            Button {
                                model.chooseAndImportLocalCurseForgePack()
                            } label: {
                                Label("导入本地 .zip", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!model.hasCurseForgeAPIKey || model.isInstallingCurseForgeResource)
                        }

                        if let lastFile = model.lastCurseForgeFileURL {
                            Divider()
                            LabeledContent("最近保存") {
                                Text(lastFile.lastPathComponent)
                                    .lineLimit(1)
                            }
                            Text(lastFile.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Button {
                                model.revealLastCurseForgeFileInFinder()
                            } label: {
                                Label("在 Finder 中显示", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        if resourceType == .modpack, let plan = model.lastCurseForgePackPlan {
                            Divider()
                            Label("整合包预检", systemImage: "checkmark.shield")
                                .font(.subheadline.weight(.semibold))
                            LabeledContent("名称") {
                                Text(plan.name)
                                    .lineLimit(1)
                            }
                            LabeledContent("Minecraft") {
                                Text(plan.minecraftVersion)
                            }
                            LabeledContent("加载器") {
                                Text(plan.loaderSummary)
                                    .lineLimit(1)
                            }
                            LabeledContent("文件") {
                                Text("\(plan.requiredFileCount)/\(plan.fileCount) 个必需文件 / \(plan.overrideEntryCount) 个覆盖文件")
                                    .lineLimit(1)
                            }

                            if let importResult = model.lastCurseForgePackImportResult {
                                Divider()
                                Label("已导入实例", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                                LabeledContent("实例") {
                                    Text(importResult.instanceName)
                                        .lineLimit(1)
                                }
                                LabeledContent("写入") {
                                    Text("下载 \(importResult.downloadedFiles) / 跳过 \(importResult.skippedFiles) / 覆盖 \(importResult.copiedOverrides)")
                                        .lineLimit(1)
                                }
                                Button {
                                    model.showImportedCurseForgePackInstance()
                                } label: {
                                    Label("进入启动页", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        Text(model.curseForgeMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    .padding(4)
                    .frame(width: 280)
                }
            }

            if resourceType == .mod {
                LocalModManagementPanel()
            }

            Spacer()
        }
        .padding(22)
        .onAppear {
            model.scheduleDownloadResourcePreparation()
        }
        .task(id: model.curseForgeFilesRequestKey(resourceType)) {
            await model.loadSelectedCurseForgeFiles(resourceType)
        }
    }

    private var installButtonDisabled: Bool {
        if !model.hasCurseForgeAPIKey || model.isInstallingCurseForgeResource || model.selectedCurseForgeProject == nil {
            return true
        }
        return resourceType == .mod && model.selectedInstance == nil
    }

    private var targetInstanceText: String {
        switch resourceType {
        case .mod:
            return model.selectedInstance?.name ?? "未选择"
        case .modpack:
            return "下载为 CurseForge ZIP"
        case .resourcePack:
            return model.selectedInstance?.name ?? "全局目录"
        }
    }
}

struct LinkLeftPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        PCLSidebarNavigation(
            title: "联机",
            items: LinkSection.allCases,
            selection: $model.selectedLinkSection,
            itemTitle: { $0.rawValue },
            itemSystemImage: { $0.systemImage }
        )
    }
}

struct LinkDashboard: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        Group {
            switch model.selectedLinkSection {
            case .rooms:
                LANRoomsDashboard()
            case .connection:
                LinkNetworkDashboard(
                    title: "连接信息",
                    systemImage: "link",
                    message: "复制本机地址后，可配合 Minecraft 的局域网世界入口使用。"
                )
            case .settings:
                LinkNetworkDashboard(
                    title: "网络设置",
                    systemImage: "slider.horizontal.3",
                    message: "这里保留可执行的 macOS 网络入口，避免出现无动作的联机配置按钮。"
                )
            }
        }
        .id(usesHighPerformanceMode ? "link-dashboard" : model.selectedLinkSection.id)
        .transition(usesHighPerformanceMode ? PCLMotion.performanceSectionTransition : PCLMotion.sectionTransition)
        .animation(usesHighPerformanceMode ? nil : PCLMotion.section, value: model.selectedLinkSection)
    }
}

struct LANRoomsDashboard: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PCLHintBanner(
                    title: "局域网房间",
                    message: "扫描同一网络内 Minecraft 对局域网开放的世界，发现后可复制地址，或直接写入启动参数用于自动进服。",
                    systemImage: "person.2.fill"
                )

                HStack(alignment: .top, spacing: 14) {
                    PCLContentCard("发现的房间", systemImage: "dot.radiowaves.left.and.right") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                PCLCapsuleBadge(title: "\(model.lanWorlds.count) 个房间", systemImage: "network")
                                Spacer()
                                if model.isScanningLANWorlds {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Button {
                                    Task { await model.scanLANWorlds() }
                                } label: {
                                    Label(model.isScanningLANWorlds ? "扫描中" : "扫描", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.isScanningLANWorlds)
                            }

                            if model.lanWorlds.isEmpty {
                                ContentUnavailableView(
                                    model.isScanningLANWorlds ? "正在监听广播" : "未发现房间",
                                    systemImage: "antenna.radiowaves.left.and.right",
                                    description: Text(model.isScanningLANWorlds ? "Minecraft LAN 广播通常需要几秒钟出现" : "让同一网络内的玩家在游戏内选择“对局域网开放”，然后点击扫描")
                                )
                                .frame(maxWidth: .infinity, minHeight: 240)
                            } else {
                                Table(model.lanWorlds, selection: $model.selectedLANWorldID) {
                                    TableColumn("世界") { world in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(world.motd)
                                                .font(.body.weight(.semibold))
                                                .lineLimit(1)
                                            Text(world.address)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    TableColumn("主机") { world in
                                        Text(world.host)
                                            .foregroundStyle(.secondary)
                                    }
                                    .width(130)
                                    TableColumn("端口") { world in
                                        Text("\(world.port)")
                                            .foregroundStyle(.secondary)
                                    }
                                    .width(72)
                                }
                                .frame(minHeight: 280)
                            }
                        }
                    }

                    PCLContentCard("房间操作", systemImage: "link.badge.plus") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let world = model.selectedLANWorld {
                                PCLInfoRow(title: "世界", value: world.motd, systemImage: "globe.asia.australia")
                                PCLInfoRow(title: "地址", value: world.address, systemImage: "link")
                            } else {
                                ContentUnavailableView("未选择房间", systemImage: "cursorarrow.click", description: Text("从左侧列表选择一个局域网房间"))
                                    .frame(minHeight: 130)
                            }

                            Button {
                                model.copySelectedLANWorldAddress()
                            } label: {
                                Label("复制房间地址", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.selectedLANWorld == nil)

                            Button {
                                model.useSelectedLANWorldForLaunch()
                            } label: {
                                Label("设为启动服务器", systemImage: "play.rectangle.on.rectangle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.selectedLANWorld == nil)

                            Button {
                                model.saveSelectedLANWorldAsFavorite()
                            } label: {
                                Label("收藏到常用服务器", systemImage: "star")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.selectedLANWorld == nil)

                            Text(model.linkMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .frame(width: 300)
                }

                PCLContentCard("常用服务器", systemImage: "star.fill") {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                PCLCapsuleBadge(title: "\(model.serverFavorites.count) 个服务器", systemImage: "server.rack")
                                Spacer()
                            }

                            if model.serverFavorites.isEmpty {
                                ContentUnavailableView(
                                    "暂无常用服务器",
                                    systemImage: "star",
                                    description: Text("保存服务器后，可一键复制、设为启动目标或直接启动当前实例")
                                )
                                .frame(maxWidth: .infinity, minHeight: 180)
                            } else {
                                Table(model.serverFavorites, selection: $model.selectedServerFavoriteID) {
                                    TableColumn("名称") { favorite in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(favorite.displayName)
                                                .font(.body.weight(.semibold))
                                                .lineLimit(1)
                                            Text(favorite.addressText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    TableColumn("地址") { favorite in
                                        Text(favorite.address)
                                            .foregroundStyle(.secondary)
                                    }
                                    TableColumn("端口") { favorite in
                                        Text(favorite.port ?? "-")
                                            .foregroundStyle(.secondary)
                                    }
                                    .width(72)
                                }
                                .frame(minHeight: 220)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label("保存服务器", systemImage: "plus.circle")
                                .font(.headline)

                            TextField("名称", text: $model.serverFavoriteDraftName)
                                .textFieldStyle(.roundedBorder)
                            TextField("服务器地址", text: $model.serverFavoriteDraftAddress)
                                .textFieldStyle(.roundedBorder)
                            TextField("端口（可选）", text: $model.serverFavoriteDraftPort)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                model.saveServerFavoriteDraft()
                            } label: {
                                Label("保存到常用", systemImage: "star")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                model.saveCurrentLaunchServerAsFavorite()
                            } label: {
                                Label("保存当前启动服务器", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.launchServerAddress.trimmed.isEmpty)

                            Divider()

                            if let favorite = model.selectedServerFavorite {
                                PCLInfoRow(title: "选中", value: favorite.displayName, systemImage: "server.rack")
                                PCLInfoRow(title: "地址", value: favorite.addressText, systemImage: "link")
                            } else {
                                Text("未选择常用服务器")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Button {
                                    model.copySelectedServerFavoriteAddress()
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.selectedServerFavorite == nil)

                                Button {
                                    model.useSelectedServerFavoriteForLaunch()
                                } label: {
                                    Label("设为启动", systemImage: "play.rectangle.on.rectangle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.selectedServerFavorite == nil)
                            }

                            Button {
                                Task { await model.launchSelectedServerFavorite() }
                            } label: {
                                Label("启动并进服", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.selectedServerFavorite == nil || !model.canLaunchSelectedInstance)

                            Button(role: .destructive) {
                                model.removeSelectedServerFavorite()
                            } label: {
                                Label("移除服务器", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.selectedServerFavorite == nil)
                        }
                        .frame(width: 280)
                    }
                }
            }
            .padding(22)
        }
    }
}

struct LinkNetworkDashboard: View {
    let title: String
    let systemImage: String
    let message: String
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PCLHintBanner(title: title, message: message, systemImage: systemImage)

                HStack(alignment: .top, spacing: 14) {
                    PCLContentCard("本机地址", systemImage: "network") {
                        VStack(alignment: .leading, spacing: 10) {
                            if model.localNetworkAddresses.isEmpty {
                                ContentUnavailableView("未发现局域网地址", systemImage: "wifi.exclamationmark", description: Text("检查网络后点击刷新"))
                                    .frame(maxWidth: .infinity, minHeight: 130)
                            } else {
                                ForEach(model.localNetworkAddresses, id: \.self) { address in
                                    PCLInfoRow(title: "IPv4", value: address, systemImage: "display")
                                }
                            }

                            HStack {
                                Button {
                                    model.refreshLocalNetworkInfo()
                                } label: {
                                    Label("刷新", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    model.copyPrimaryLocalAddress()
                                } label: {
                                    Label("复制地址", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.localNetworkAddresses.isEmpty)
                            }
                        }
                    }

                    PCLContentCard("连接", systemImage: "link") {
                        VStack(alignment: .leading, spacing: 10) {
                            PCLInfoRow(title: "当前实例", value: model.selectedInstance?.name ?? "未选择", systemImage: "cube.box")
                            PCLInfoRow(title: "网络状态", value: model.linkMessage, systemImage: "waveform.path.ecg")

                            Button {
                                model.openNetworkSettings()
                            } label: {
                                Label("打开网络设置", systemImage: "gearshape")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                model.openMinecraftFolder()
                            } label: {
                                Label("打开 Minecraft 文件夹", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await model.launchSelectedInstance() }
                            } label: {
                                Label("启动当前实例", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canLaunchSelectedInstance)
                        }
                    }
                    .frame(width: 300)
                }
            }
            .padding(22)
        }
        .onAppear {
            model.refreshLocalNetworkInfo()
        }
    }
}

struct SettingsLeftPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        PCLSidebarNavigation(
            title: "设置",
            items: SettingsSection.allCases,
            selection: $model.selectedSettingsSection,
            itemTitle: { $0.rawValue },
            itemSystemImage: { $0.systemImage }
        )
    }
}

struct SettingsDashboard: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        Form {
            switch model.selectedSettingsSection {
            case .launch:
                accountSettings
                launchSettings
            case .version:
                versionSettings
            case .system:
                systemSettings
            case .appearance:
                appearanceSettings
            case .download:
                downloadSettings
            }
        }
        .id(usesHighPerformanceMode ? "settings-dashboard" : model.selectedSettingsSection.id)
        .transition(usesHighPerformanceMode ? PCLMotion.performanceSectionTransition : PCLMotion.sectionTransition)
        .animation(usesHighPerformanceMode ? nil : PCLMotion.section, value: model.selectedSettingsSection)
        .formStyle(.grouped)
        .padding(22)
    }

    private var accountSettings: some View {
        Section("账户") {
            LabeledContent("正版授权") {
                Label(model.microsoftClientIDStatusText, systemImage: model.microsoftClientIDResolution.isConfigured ? "checkmark.shield" : "exclamationmark.triangle")
            }
            Text(model.microsoftClientIDDetailText)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Microsoft Client ID（高级覆盖）", text: $model.microsoftClientID)
                .textFieldStyle(.roundedBorder)
            TextField("统一通行证服务器 ID", text: $model.nideServerID)
                .textFieldStyle(.roundedBorder)
            TextField("统一通行证账号", text: $model.nideUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("统一通行证密码", text: $model.nidePassword)
                .textFieldStyle(.roundedBorder)
            TextField("Authlib 服务器", text: $model.authlibServerURL)
                .textFieldStyle(.roundedBorder)
            TextField("Authlib 账号", text: $model.authlibUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("Authlib 密码", text: $model.authlibPassword)
                .textFieldStyle(.roundedBorder)

            Picker("当前账户", selection: $model.selectedAccountID) {
                if model.accounts.isEmpty {
                    Text("未保存账户").tag(Optional<LauncherAccountProfile.ID>.none)
                } else {
                    ForEach(model.accounts) { account in
                        Text("\(account.displayName) · \(account.kind.displayName)")
                            .tag(Optional(account.id))
                    }
                }
            }

            HStack {
                Button {
                    Task { await model.startMicrosoftLogin() }
                } label: {
                    Label("登录 Microsoft", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(model.isMicrosoftLoginInProgress)

                Button {
                    Task { await model.startAuthlibLogin() }
                } label: {
                    Label("登录 Authlib", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(model.isAuthlibLoginInProgress)

                Button {
                    Task { await model.startNideLogin() }
                } label: {
                    Label("登录统一通行证", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(model.isNideLoginInProgress)

                Button {
                    model.saveCurrentOfflineAccount()
                } label: {
                    Label("保存离线账户", systemImage: "person.badge.plus")
                }

                Button(role: .destructive) {
                    model.removeSelectedAccount()
                } label: {
                    Label("移除账户", systemImage: "trash")
                }
                .disabled(model.selectedAccount == nil)
            }

            LabeledContent("安全存储") {
                Text("Keychain")
                    .foregroundStyle(.secondary)
            }

            Text(model.accountVaultMessage)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var launchSettings: some View {
        Section("启动") {
            Toggle("自动选择 Java", isOn: $model.autoSelectJava)
            Toggle("高性能模式", isOn: $model.useHighPerformanceMode)
            Text(model.useHighPerformanceMode ? "已关闭重型转场、毛玻璃、阴影、背景图、模糊和复杂页面动画，并合并设置保存，优先保证点击反馈、切页与滚动响应。" : "保留完整毛玻璃、阴影、背景图和弹性过渡效果。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("全屏启动", isOn: $model.launchFullscreen)
            Toggle("版本隔离", isOn: $model.useVersionIsolation)
            Toggle("启动后隐藏启动器", isOn: $model.hideLauncherOnGameStart)
            Toggle("游戏退出后显示启动器", isOn: $model.showLauncherOnGameExit)
                .disabled(!model.hideLauncherOnGameStart)
            Toggle("原生通知", isOn: $model.showNativeNotifications)
            Text(model.showNativeNotifications ? "安装、导入、下载任务和游戏退出结果会通过 macOS 通知中心提示。" : "结果提示只显示在启动器内。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Dock 角标", isOn: $model.showDockBadge)
            Text(model.showDockBadge ? "下载、安装任务进行中会在 Dock 显示数量；游戏运行时显示 MC。" : "Dock 图标不显示任务或游戏运行状态。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $model.memoryLimit, in: 1024...16384, step: 512) {
                Text("内存")
            }
            Text("\(Int(model.memoryLimit)) MB")
                .foregroundStyle(.secondary)
            LabeledContent("内存预设") {
                Menu {
                    ForEach(GameMemoryPreset.allCases) { preset in
                        Button {
                            model.applyGlobalMemoryPreset(preset)
                        } label: {
                            Text(preset.displayName)
                        }
                    }
                } label: {
                    Label("应用预设", systemImage: "memorychip")
                }
            }

            LabeledContent("游戏窗口") {
                Text("\(Int(model.gameWindowWidth)) × \(Int(model.gameWindowHeight))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LabeledContent("窗口预设") {
                Menu {
                    ForEach(GameWindowSizePreset.allCases) { preset in
                        Button {
                            model.applyGlobalGameWindowPreset(preset)
                        } label: {
                            Text(preset.displayName)
                        }
                    }
                } label: {
                    Label("应用预设", systemImage: "rectangle.resize")
                }
            }
            Stepper("宽度", value: $model.gameWindowWidth, in: 320...7680, step: 16)
            Stepper("高度", value: $model.gameWindowHeight, in: 240...4320, step: 16)

            TextField("服务器地址", text: $model.launchServerAddress)
            TextField("服务器端口（可选）", text: $model.launchServerPort)
        }

        Section("全局高级参数") {
            VStack(alignment: .leading, spacing: 8) {
                Text("额外 JVM 参数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.extraJvmArguments)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 64)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("额外游戏参数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.extraGameArguments)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 64)
            }

            Text("全局参数会应用到所有版本；「设置 → 版本 → 高级参数」中的参数会追加在全局参数之后。支持引号包裹空格。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var versionSettings: some View {
        Section("当前版本") {
            if let instance = model.selectedInstance {
                LabeledContent("名称") {
                    Text(instance.name)
                        .textSelection(.enabled)
                }
                LabeledContent("类型") {
                    Text(instance.type)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("目录") {
                    Text(instance.path.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                HStack {
                    Button {
                        model.openSelectedInstanceFolder()
                    } label: {
                        Label("打开版本目录", systemImage: "folder")
                    }

                    Button {
                        model.resetSelectedVersionSettings()
                    } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                    }
                }

                Text(model.versionSettingsMessage)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("未选择版本", systemImage: "cube.transparent", description: Text("回到启动页或版本列表选择一个 Minecraft 实例"))
            }
        }

        Section("启动覆盖") {
            Toggle("使用全局 Java", isOn: Binding(
                get: { model.versionSettings.usesGlobalJava },
                set: { useGlobal in
                    model.versionSettings.usesGlobalJava = useGlobal
                    if !useGlobal, model.versionSettings.javaExecutablePath == nil {
                        model.versionSettings.javaExecutablePath = model.selectedJava?.executable.path
                    }
                }
            ))

            Picker("Java", selection: Binding<String?>(
                get: { model.versionSettingsJavaPath },
                set: { model.versionSettings.javaExecutablePath = $0 }
            )) {
                if model.javaInstallations.isEmpty {
                    Text("未发现 Java").tag(Optional<String>.none)
                } else {
                    ForEach(model.javaInstallations) { java in
                        Text("\(java.versionSummary) · \(java.source)")
                            .tag(Optional(java.executable.path))
                    }
                }
            }
            .disabled(model.versionSettings.usesGlobalJava || model.selectedInstance == nil)

            Toggle("使用全局内存", isOn: Binding(
                get: { model.versionSettings.usesGlobalMemory },
                set: { useGlobal in
                    model.versionSettings.usesGlobalMemory = useGlobal
                    if !useGlobal, model.versionSettings.memoryMegabytes == nil {
                        model.versionSettings.memoryMegabytes = model.memoryLimit
                    }
                }
            ))

            Slider(value: Binding(
                get: { model.effectiveVersionMemory },
                set: { model.versionSettings.memoryMegabytes = $0 }
            ), in: 1024...32768, step: 512) {
                Text("内存")
            }
            .disabled(model.versionSettings.usesGlobalMemory || model.selectedInstance == nil)

            Text(model.versionSettings.usesGlobalMemory ? "使用全局内存：\(Int(model.memoryLimit)) MB" : "当前版本内存：\(Int(model.effectiveVersionMemory)) MB")
                .foregroundStyle(.secondary)

            LabeledContent("内存预设") {
                Menu {
                    ForEach(GameMemoryPreset.allCases) { preset in
                        Button {
                            model.applyVersionMemoryPreset(preset)
                        } label: {
                            Text(preset.displayName)
                        }
                    }
                } label: {
                    Label("应用预设", systemImage: "memorychip")
                }
            }
            .disabled(model.versionSettings.usesGlobalMemory || model.selectedInstance == nil)

            Toggle("使用全局窗口", isOn: Binding(
                get: { model.versionSettings.usesGlobalWindow },
                set: { useGlobal in
                    model.versionSettings.usesGlobalWindow = useGlobal
                    if !useGlobal {
                        if model.versionSettings.windowWidth == nil {
                            model.versionSettings.windowWidth = model.gameWindowWidth
                        }
                        if model.versionSettings.windowHeight == nil {
                            model.versionSettings.windowHeight = model.gameWindowHeight
                        }
                        if model.versionSettings.fullscreen == nil {
                            model.versionSettings.fullscreen = model.launchFullscreen
                        }
                    }
                }
            ))

            LabeledContent("游戏窗口") {
                Text("\(Int(model.effectiveVersionWindowWidth)) × \(Int(model.effectiveVersionWindowHeight))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            LabeledContent("窗口预设") {
                Menu {
                    ForEach(GameWindowSizePreset.allCases) { preset in
                        Button {
                            model.applyVersionGameWindowPreset(preset)
                        } label: {
                            Text(preset.displayName)
                        }
                    }
                } label: {
                    Label("应用预设", systemImage: "rectangle.resize")
                }
            }
            .disabled(model.versionSettings.usesGlobalWindow || model.selectedInstance == nil)

            Stepper("宽度", value: Binding(
                get: { model.effectiveVersionWindowWidth },
                set: { model.versionSettings.windowWidth = $0 }
            ), in: 320...7680, step: 16)
            .disabled(model.versionSettings.usesGlobalWindow || model.selectedInstance == nil)

            Stepper("高度", value: Binding(
                get: { model.effectiveVersionWindowHeight },
                set: { model.versionSettings.windowHeight = $0 }
            ), in: 240...4320, step: 16)
            .disabled(model.versionSettings.usesGlobalWindow || model.selectedInstance == nil)

            Toggle("版本全屏启动", isOn: Binding(
                get: { model.effectiveVersionFullscreen },
                set: { model.versionSettings.fullscreen = $0 }
            ))
            .disabled(model.versionSettings.usesGlobalWindow || model.selectedInstance == nil)

            Text(model.versionSettings.usesGlobalWindow ? "使用全局窗口：\(Int(model.gameWindowWidth)) × \(Int(model.gameWindowHeight))" : "当前版本窗口：\(Int(model.effectiveVersionWindowWidth)) × \(Int(model.effectiveVersionWindowHeight))")
                .foregroundStyle(.secondary)

            Toggle("使用全局游戏目录设置", isOn: Binding(
                get: { model.versionSettings.usesGlobalGameDirectory },
                set: { useGlobal in
                    model.versionSettings.usesGlobalGameDirectory = useGlobal
                    if !useGlobal, model.versionSettings.usesIsolatedGameDirectory == nil {
                        model.versionSettings.usesIsolatedGameDirectory = model.useVersionIsolation
                    }
                }
            ))

            Toggle("当前版本使用独立目录", isOn: Binding(
                get: { model.effectiveVersionIsolation },
                set: { model.versionSettings.usesIsolatedGameDirectory = $0 }
            ))
            .disabled(model.versionSettings.usesGlobalGameDirectory || model.selectedInstance == nil)

            Text(model.versionSettings.usesGlobalGameDirectory ? (model.useVersionIsolation ? "使用全局版本隔离：版本目录" : "使用全局版本隔离：Minecraft 根目录") : (model.effectiveVersionIsolation ? "当前版本目录：独立 saves / mods / config" : "当前版本目录：共用 Minecraft 根目录"))
                .foregroundStyle(.secondary)

            Toggle("使用全局服务器设置", isOn: Binding(
                get: { model.versionSettings.usesGlobalServer },
                set: { useGlobal in
                    model.versionSettings.usesGlobalServer = useGlobal
                    if !useGlobal {
                        if model.versionSettings.serverAddress == nil {
                            model.versionSettings.serverAddress = model.launchServerAddress
                        }
                        if model.versionSettings.serverPort == nil {
                            model.versionSettings.serverPort = model.launchServerPort
                        }
                    }
                }
            ))

            TextField("服务器地址", text: Binding(
                get: { model.effectiveVersionServerAddress },
                set: { model.versionSettings.serverAddress = $0 }
            ))
            .disabled(model.versionSettings.usesGlobalServer || model.selectedInstance == nil)

            TextField("服务器端口（可选）", text: Binding(
                get: { model.effectiveVersionServerPort },
                set: { model.versionSettings.serverPort = $0 }
            ))
            .disabled(model.versionSettings.usesGlobalServer || model.selectedInstance == nil)
        }

        Section("高级参数") {
            VStack(alignment: .leading, spacing: 8) {
                Text("额外 JVM 参数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { model.versionSettings.extraJvmArguments },
                    set: { model.versionSettings.extraJvmArguments = $0 }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 64)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("额外游戏参数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { model.versionSettings.extraGameArguments },
                    set: { model.versionSettings.extraGameArguments = $0 }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 64)
            }

            Text("参数按命令行规则解析，支持引号包裹空格。会保存在当前版本目录的 pclmac-version-settings.json，并追加在全局高级参数之后。")
                .foregroundStyle(.secondary)
        }
    }

    private var systemSettings: some View {
        Section("路径") {
            LabeledContent("Minecraft") {
                VStack(alignment: .trailing, spacing: 4) {
                    PCLCapsuleBadge(
                        title: model.isUsingCustomMinecraftDirectory ? "自定义" : "默认",
                        systemImage: model.isUsingCustomMinecraftDirectory ? "folder.badge.gearshape" : "folder"
                    )
                    Text(model.minecraftDirectory.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            LabeledContent("PCL") {
                Text(model.paths.appSupportDirectory.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Button {
                    model.openMinecraftFolder()
                } label: {
                    Label("打开 Minecraft 文件夹", systemImage: "folder")
                }

                Button {
                    model.chooseMinecraftDirectory()
                } label: {
                    Label("选择文件夹", systemImage: "folder.badge.gearshape")
                }

                Button {
                    model.resetMinecraftDirectory()
                } label: {
                    Label("恢复默认", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.isUsingCustomMinecraftDirectory)
            }
        }
    }

    @ViewBuilder
    private var appearanceSettings: some View {
        Section("主题") {
            LabeledContent("主题色") {
                ThemePresetSwatches(selection: $model.themePreset)
            }

            Picker("窗口外观", selection: $model.appearanceMode) {
                ForEach(LauncherAppearanceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle("显示启动页提示", isOn: $model.showsHomeHint)
        }

        Section("主页卡片") {
            ForEach(LauncherHomeCard.allCases) { card in
                Toggle(isOn: Binding(
                    get: { model.isHomeCardVisible(card) },
                    set: { model.setHomeCard(card, visible: $0) }
                )) {
                    Label(card.title, systemImage: card.systemImage)
                }
            }

            Button {
                model.resetHomeCards()
            } label: {
                Label("恢复默认卡片", systemImage: "arrow.counterclockwise")
            }
            .disabled(model.hiddenHomeCardIDs.isEmpty)
        }

        Section("背景") {
            LabeledContent("背景图") {
                Text(model.backgroundImagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未设置")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Button {
                    model.chooseBackgroundImage()
                } label: {
                    Label("选择图片", systemImage: "photo")
                }

                Button(role: .destructive) {
                    model.clearBackgroundImage()
                } label: {
                    Label("清除", systemImage: "xmark.circle")
                }
                .disabled(model.backgroundImagePath == nil)
            }

            Slider(value: $model.backgroundImageOpacity, in: 0.08...0.65, step: 0.01) {
                Text("背景强度")
            }
            .disabled(model.backgroundImagePath == nil)

            Text("\(Int(model.backgroundImageOpacity * 100))%")
                .foregroundStyle(.secondary)
        }

        Section("预览") {
            PCLThemePreview(
                preset: model.selectedThemePreset,
                showsHomeHint: model.showsHomeHint
            )
        }
    }

    private var downloadSettings: some View {
        Section("下载") {
            Picker("下载源", selection: $model.downloadSource) {
                ForEach(MinecraftDownloadSource.allCases) { source in
                    Text(source.rawValue).tag(source.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Picker("资源平台", selection: $model.resourceProvider) {
                Text("Modrinth").tag("Modrinth")
                Text("CurseForge").tag("CurseForge")
            }
            .pickerStyle(.segmented)

            SecureField("CurseForge API Key", text: $model.curseForgeAPIKey)
                .textFieldStyle(.roundedBorder)
            Text(model.hasCurseForgeAPIKey ? "CurseForge 已可用于 Mod、整合包和资源包搜索下载。" : "也可以通过环境变量 PCL_CURSEFORGE_API_KEY 提供。")
                .foregroundStyle(.secondary)

            Picker("默认加载器", selection: $model.selectedInstallLoader) {
                Text("原版").tag("原版")
                Text("Forge").tag("Forge")
                Text("Fabric").tag("Fabric")
                Text("Quilt").tag("Quilt")
                Text("NeoForge").tag("NeoForge")
            }
            Slider(value: $model.maxDownloadThreads, in: 1...64, step: 1) {
                Text("线程")
            }
            Text("线程：\(Int(model.maxDownloadThreads))")
                .foregroundStyle(.secondary)
        }
    }
}

struct ThemePresetSwatches: View {
    @Binding var selection: String
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LauncherThemePreset.allCases) { preset in
                ThemePresetSwatch(
                    preset: preset,
                    selected: selection == preset.rawValue
                ) {
                    select(preset)
                }
            }
        }
    }

    private func select(_ preset: LauncherThemePreset) {
        if usesHighPerformanceMode {
            selection = preset.rawValue
        } else {
            withAnimation(PCLMotion.fast) {
                selection = preset.rawValue
            }
        }
    }
}

struct ThemePresetSwatch: View {
    let preset: LauncherThemePreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [preset.palette.accentLight, preset.palette.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(3)
            .overlay(
                Circle()
                    .stroke(selected ? preset.palette.accent : Color(nsColor: .separatorColor).opacity(0.7), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(preset.rawValue)
        .accessibilityLabel(preset.rawValue)
    }
}

struct PCLThemePreview: View {
    let preset: LauncherThemePreset
    let showsHomeHint: Bool

    private var palette: PCLThemePalette {
        preset.palette
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("PCL")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text("启动")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.22), in: Capsule())
                Text("下载")
                    .font(.caption.weight(.semibold))
                    .opacity(0.88)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(
                LinearGradient(colors: [palette.titleStart, palette.titleEnd], startPoint: .leading, endPoint: .trailing)
            )

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    previewRow("登录", systemImage: "person.fill", selected: true)
                    previewRow("版本", systemImage: "cube.box.fill", selected: false)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [palette.accentLight, palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 26)
                }
                .padding(10)
                .frame(width: 124, height: 122)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.76))

                VStack(alignment: .leading, spacing: 8) {
                    if showsHomeHint {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.accent.opacity(0.10))
                            .frame(height: 26)
                    }
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(height: 48)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(height: 48)
                    }
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(height: 30)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private func previewRow(_ title: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
                .font(.caption.weight(selected ? .semibold : .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? palette.accent : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? palette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct MoreLeftPanel: View {
    @EnvironmentObject private var model: LauncherModel

    var body: some View {
        PCLSidebarNavigation(
            title: "更多",
            items: MoreSection.allCases,
            selection: $model.selectedMoreSection,
            itemTitle: { $0.rawValue },
            itemSystemImage: { $0.systemImage }
        )
    }
}

struct MoreDashboard: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.pclUsesHighPerformanceMode) private var usesHighPerformanceMode

    var body: some View {
        Group {
            switch model.selectedMoreSection {
        case .help:
            VStack(alignment: .leading, spacing: 16) {
                PCLHintBanner(
                    title: "帮助文档",
                    message: "README.html 已按分区、交互和一键复制参数整理，可从这里直接打开。若应用已打包，会优先打开包内文档。",
                    systemImage: "questionmark.circle"
                )

                PCLContentCard("文档", systemImage: "doc.richtext") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            PCLInfoRow(title: "格式", value: "README.html", systemImage: "safari")
                            Spacer(minLength: 0)
                        }

                        HStack {
                            Button {
                                model.openHelpDocument()
                            } label: {
                                Label("打开帮助文档", systemImage: "safari")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                model.revealHelpDocumentInFinder()
                            } label: {
                                Label("在 Finder 中显示", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(model.helpMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(22)
        case .about:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PCLContentCard("原作与授权", systemImage: "heart.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            PCLInfoRow(title: "原作作者", value: "龙腾猫跃", systemImage: "person.crop.circle")
                            Text("本项目是第三方基于 PCL 独立进行二次创作的 macOS 原生重构，不是官方 PCL。源码仓库会保留原项目 LICENCE 指南和署名说明。")
                                .foregroundStyle(.secondary)
                            HStack {
                                Button {
                                    model.openOriginalPCLSponsorPage()
                                } label: {
                                    Label("赞助原作者", systemImage: "heart")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    model.openOriginalPCLRepository()
                                } label: {
                                    Label("原项目仓库", systemImage: "safari")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    PCLHintBanner(
                        title: "关于 Plain Craft Launcher (PCL) macOS",
                        message: "这里显示当前正在运行的 .app 身份、版本和路径，方便区分 dist 构建、Applications 安装包和调试运行。",
                        systemImage: "shippingbox.fill"
                    )

                    HStack(alignment: .top, spacing: 14) {
                        PCLContentCard {
                            HStack(spacing: 16) {
                                Image(nsImage: NSApp.applicationIconImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.appNameText)
                                        .font(.system(size: 24, weight: .bold))
                                    Text("macOS 原生重构预览")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    PCLCapsuleBadge(title: model.appInstallLocationText, systemImage: "location.fill")
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        PCLContentCard("应用身份", systemImage: "app.badge") {
                            VStack(alignment: .leading, spacing: 12) {
                                PCLInfoRow(title: "版本", value: model.appVersionSummaryText, systemImage: "number")
                                PCLInfoRow(title: "Bundle ID", value: model.appBundleIdentifierText, systemImage: "tag")
                                PCLInfoRow(title: "运行位置", value: model.appInstallLocationText, systemImage: "location")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    PCLContentCard("运行路径", systemImage: "folder.badge.gearshape") {
                        VStack(alignment: .leading, spacing: 12) {
                            PCLInfoRow(title: "当前应用", value: model.appBundlePathText, systemImage: "app", valueLineLimit: 3)

                            HStack {
                                Button {
                                    model.copyAppBundlePath()
                                } label: {
                                    Label("复制路径", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    model.copyAppBundleSummary()
                                } label: {
                                    Label("复制摘要", systemImage: "list.clipboard")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    model.revealAppBundleInFinder()
                                } label: {
                                    Label("在 Finder 中显示", systemImage: "magnifyingglass")
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(model.aboutMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(22)
            }
        case .logs:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PCLContentCard("运行日志", systemImage: "doc.text") {
                        VStack(alignment: .leading, spacing: 8) {
                            PCLInfoRow(title: "最近事件", value: model.lastEvent, systemImage: "clock")
                            PCLInfoRow(title: "当前状态", value: model.launchStatus.title, systemImage: "waveform.path.ecg")
                            Text(model.launchStatus.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("日志与崩溃报告", systemImage: "doc.text.magnifyingglass")
                                        .font(.headline)
                                    Spacer()
                                    if model.isLoadingMinecraftLogs {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Button {
                                        Task { await model.refreshMinecraftLogs() }
                                    } label: {
                                        Label("刷新", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                }

                                if model.minecraftLogEntries.isEmpty {
                                    ContentUnavailableView(
                                        "没有发现日志",
                                        systemImage: "doc.text",
                                        description: Text("会扫描 Minecraft logs、crash-reports 和当前目录的 hs_err_pid 日志")
                                    )
                                    .frame(minHeight: 300)
                                } else {
                                    Table(model.minecraftLogEntries, selection: $model.selectedMinecraftLogID) {
                                        TableColumn("名称") { entry in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.name)
                                                    .font(.body.weight(.semibold))
                                                    .lineLimit(1)
                                                Text(entry.summary)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        TableColumn("类型") { entry in
                                            Label(entry.kind.displayName, systemImage: entry.kind.systemImage)
                                                .foregroundStyle(.secondary)
                                        }
                                        .width(112)
                                        TableColumn("大小") { entry in
                                            Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                                .foregroundStyle(.secondary)
                                        }
                                        .width(86)
                                        TableColumn("时间") { entry in
                                            Text(entry.modifiedAt?.formatted(date: .numeric, time: .shortened) ?? "-")
                                                .foregroundStyle(.secondary)
                                        }
                                        .width(145)
                                    }
                                    .frame(minHeight: 320)
                                }

                                Text(model.minecraftLogMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(4)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("预览", systemImage: "text.page")
                                    .font(.headline)

                                if let entry = model.selectedMinecraftLogEntry {
                                    PCLInfoRow(title: "文件", value: entry.name, systemImage: entry.kind.systemImage)
                                    PCLInfoRow(title: "摘要", value: entry.summary, systemImage: "lightbulb")

                                    HStack {
                                        Button {
                                            model.revealSelectedMinecraftLogInFinder()
                                        } label: {
                                            Label("显示", systemImage: "magnifyingglass")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)

                                        Button {
                                            model.copySelectedMinecraftLogSummary()
                                        } label: {
                                            Label("复制", systemImage: "doc.on.doc")
                                                .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                    MinecraftDiagnosisPanel(diagnoses: model.selectedMinecraftLogDiagnoses)

                                    ScrollView {
                                        Text(model.selectedMinecraftLogPreview.isEmpty ? "无法预览该日志" : model.selectedMinecraftLogPreview)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                    }
                                    .frame(minHeight: 260)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                } else {
                                    ContentUnavailableView("未选择日志", systemImage: "doc.text", description: Text("从左侧选择一个日志或崩溃报告"))
                                        .frame(minHeight: 300)
                                }
                            }
                            .padding(4)
                            .frame(width: 360)
                        }
                    }
                }
                .padding(22)
            }
            .task {
                if model.minecraftLogEntries.isEmpty {
                    await model.refreshMinecraftLogs()
                }
            }
            }
        }
        .id(usesHighPerformanceMode ? "more-dashboard" : model.selectedMoreSection.id)
        .transition(usesHighPerformanceMode ? PCLMotion.performanceSectionTransition : PCLMotion.sectionTransition)
        .animation(usesHighPerformanceMode ? nil : PCLMotion.section, value: model.selectedMoreSection)
    }
}

private extension MinecraftLogKind {
    var systemImage: String {
        switch self {
        case .latest: "doc.text"
        case .crashReport: "exclamationmark.triangle"
        case .jvmCrash: "xmark.octagon"
        case .installer: "shippingbox"
        }
    }
}

private extension MinecraftLogDiagnosisSeverity {
    var systemImage: String {
        switch self {
        case .critical: "exclamationmark.triangle.fill"
        case .warning: "wrench.and.screwdriver.fill"
        case .info: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}

private extension ResourceVersionFilePreview {
    var releaseTypeTint: Color {
        switch releaseType.lowercased() {
        case "release": .green
        case "beta": .orange
        case "alpha": .red
        default: .secondary
        }
    }
}

private extension Array where Element == URL {
    func uniquedByPath() -> [URL] {
        var seen = Set<String>()
        return filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 900, height: 560)
            window.toolbarStyle = .unifiedCompact
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}
