import CryptoKit
import Foundation
import Testing
@testable import PCLMac

private final class NotificationSink: @unchecked Sendable {
    var notifications: [LauncherNotification] = []
}

private final class DockBadgeSink: @unchecked Sendable {
    var badges: [String?] = []
}

struct MinecraftLaunchCoreTests {
    @Test func persistsLauncherPreferencesInUserDefaults() throws {
        let suiteName = "PCLMacPreferencesTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences")
        let preferences = LauncherPreferences(
            loginMode: "正版",
            offlineUsername: "Steve",
            selectedAccountID: "microsoft:steve",
            microsoftClientID: "client-id",
            nideServerID: "server-id",
            nideUsername: "nide@example.com",
            authlibServerURL: "https://skin.example.com/authserver",
            authlibUsername: "steve@example.com",
            selectedInstanceName: "1.20.1",
            selectedJavaPath: "/Library/Java/JavaVirtualMachines/jdk/Contents/Home/bin/java",
            customMinecraftDirectoryPath: "/Users/steve/Games/Minecraft",
            localVersionQuery: "fabric",
            localVersionFilter: LocalVersionFilter.fabric.rawValue,
            favoriteInstanceNames: ["1.20.1", "Fabric 1.20.1"],
            hiddenInstanceNames: ["Old 1.12.2"],
            showsHiddenInstances: true,
            downloadSource: "官方 + BMCLAPI",
            resourceProvider: "CurseForge",
            curseForgeAPIKey: "curse-key",
            selectedInstallLoader: "Fabric",
            maxDownloadThreads: 16,
            memoryLimit: 8192,
            gameWindowWidth: 1280,
            gameWindowHeight: 720,
            launchFullscreen: true,
            useVersionIsolation: false,
            launchServerAddress: "play.example.com",
            launchServerPort: "25566",
            serverFavorites: [
                LauncherServerFavorite(name: "Hypixel", address: "mc.hypixel.net", port: nil),
                LauncherServerFavorite(name: "Local", address: "192.168.1.20", port: "25565")
            ],
            extraJvmArguments: #"-Dglobal="hello world""#,
            extraGameArguments: #"--demo "global mode""#,
            hideLauncherOnGameStart: true,
            showLauncherOnGameExit: false,
            showNativeNotifications: false,
            showDockBadge: false,
            useHighPerformanceMode: false,
            autoSelectJava: false,
            remoteVersionFilter: "snapshot",
            themePreset: LauncherThemePreset.grass.rawValue,
            appearanceMode: LauncherAppearanceMode.dark.rawValue,
            showsHomeHint: false,
            hiddenHomeCardIDs: [LauncherHomeCard.java.rawValue, LauncherHomeCard.versions.rawValue],
            backgroundImagePath: "/tmp/pcl-background.png",
            backgroundImageOpacity: 0.44
        )

        store.save(preferences)

        #expect(store.load() == preferences)
    }

    @Test func normalizesInvalidLauncherPreferences() throws {
        let suiteName = "PCLMacPreferenceNormalizeTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences")
        store.save(
            LauncherPreferences(
                loginMode: "broken",
                offlineUsername: "   ",
                selectedAccountID: nil,
                microsoftClientID: "",
                nideServerID: "",
                nideUsername: "",
                authlibServerURL: "",
                authlibUsername: "",
                selectedInstanceName: nil,
                selectedJavaPath: nil,
                customMinecraftDirectoryPath: "  ~/Games/Minecraft  ",
                localVersionQuery: "  old  ",
                localVersionFilter: "broken",
                favoriteInstanceNames: ["  1.20.1  ", "", "1.20.1", "Fabric"],
                hiddenInstanceNames: ["1.20.1", "  Old  ", "", "Old"],
                showsHiddenInstances: true,
                downloadSource: "broken",
                resourceProvider: "broken",
                curseForgeAPIKey: "",
                selectedInstallLoader: "broken",
                maxDownloadThreads: 999,
                memoryLimit: 128,
                gameWindowWidth: 100,
                gameWindowHeight: 99999,
                launchFullscreen: true,
                useVersionIsolation: false,
                launchServerAddress: "   ",
                launchServerPort: "99999",
                serverFavorites: [
                    LauncherServerFavorite(name: "  Hypixel  ", address: " mc.hypixel.net ", port: " 25565 "),
                    LauncherServerFavorite(name: "Duplicate", address: "mc.hypixel.net", port: "25565"),
                    LauncherServerFavorite(name: "Bad", address: " ", port: "25565"),
                    LauncherServerFavorite(name: "No Port", address: "play.example.com", port: "99999")
                ],
                extraJvmArguments: "  -Dglobal=true  ",
                extraGameArguments: #" --demo "global mode" "#,
                hideLauncherOnGameStart: true,
                showLauncherOnGameExit: false,
                showNativeNotifications: false,
                showDockBadge: false,
                useHighPerformanceMode: true,
                autoSelectJava: true,
                remoteVersionFilter: "ancient",
                themePreset: "broken",
                appearanceMode: "broken",
                showsHomeHint: true,
                hiddenHomeCardIDs: ["java", "broken", "java", "versions"],
                backgroundImagePath: "   ",
                backgroundImageOpacity: 9
            )
        )

        let loaded = store.load()
        #expect(loaded.loginMode == "离线")
        #expect(loaded.offlineUsername == "Player")
        #expect(loaded.downloadSource == "官方 + BMCLAPI")
        #expect(loaded.maxDownloadThreads == 64)
        #expect(loaded.memoryLimit == 1024)
        #expect(loaded.gameWindowWidth == 320)
        #expect(loaded.gameWindowHeight == 4320)
        #expect(loaded.useVersionIsolation == false)
        #expect(loaded.launchServerAddress == nil)
        #expect(loaded.launchServerPort == nil)
        #expect(loaded.serverFavorites == [
            LauncherServerFavorite(name: "Hypixel", address: "mc.hypixel.net", port: "25565"),
            LauncherServerFavorite(name: "No Port", address: "play.example.com", port: nil)
        ])
        #expect(loaded.hideLauncherOnGameStart)
        #expect(loaded.showLauncherOnGameExit == false)
        #expect(loaded.showNativeNotifications == false)
        #expect(loaded.showDockBadge == false)
        #expect(loaded.remoteVersionFilter == "release")
        #expect(loaded.resourceProvider == "Modrinth")
        #expect(loaded.themePreset == LauncherThemePreset.pclBlue.rawValue)
        #expect(loaded.appearanceMode == LauncherAppearanceMode.system.rawValue)
        #expect(loaded.hiddenHomeCardIDs == [LauncherHomeCard.java.rawValue, LauncherHomeCard.versions.rawValue])
        #expect(loaded.backgroundImagePath == nil)
        #expect(loaded.backgroundImageOpacity == 0.65)
        #expect(loaded.microsoftClientID == nil)
        #expect(loaded.nideServerID == nil)
        #expect(loaded.nideUsername == nil)
        #expect(loaded.selectedInstallLoader == "原版")
        #expect(loaded.extraJvmArguments == "-Dglobal=true")
        #expect(loaded.extraGameArguments == #"--demo "global mode""#)
        #expect(loaded.customMinecraftDirectoryPath == NSString(string: "~/Games/Minecraft").expandingTildeInPath)
        #expect(loaded.localVersionQuery == "old")
        #expect(loaded.localVersionFilter == LocalVersionFilter.all.rawValue)
        #expect(loaded.favoriteInstanceNames == ["1.20.1", "Fabric"])
        #expect(loaded.hiddenInstanceNames == ["Old"])
        #expect(loaded.showsHiddenInstances)
    }

    @MainActor
    @Test func appliesGameMemoryAndWindowPresetsGloballyAndPerVersion() throws {
        let suiteName = "PCLMacWindowPresetTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacWindowPresetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let instanceDirectory = root.appendingPathComponent("versions/1.20.1", isDirectory: true)
        let instance = MinecraftInstance(
            name: "1.20.1",
            path: instanceDirectory,
            jsonURL: instanceDirectory.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2024-01-01T00:00:00+00:00"
        )
        let preferencesStore = LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences")
        let model = LauncherModel(
            preferencesStore: preferencesStore,
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            )
        )

        model.minecraftInstances = [instance]
        model.selectedInstanceID = instance.id
        model.launchFullscreen = true

        model.applyGlobalMemoryPreset(.eightGB)
        model.applyGlobalGameWindowPreset(.fullHD)

        #expect(model.memoryLimit == 8192)
        #expect(model.gameWindowWidth == 1920)
        #expect(model.gameWindowHeight == 1080)
        #expect(preferencesStore.load().memoryLimit == 8192)
        #expect(preferencesStore.load().gameWindowWidth == 1920)
        #expect(preferencesStore.load().gameWindowHeight == 1080)

        model.applyVersionMemoryPreset(.sixGB)
        model.applyVersionGameWindowPreset(.hd)

        #expect(model.versionSettings.usesGlobalMemory == false)
        #expect(model.versionSettings.memoryMegabytes == 6144)
        #expect(model.versionSettings.usesGlobalWindow == false)
        #expect(model.versionSettings.windowWidth == 1280)
        #expect(model.versionSettings.windowHeight == 720)
        #expect(model.versionSettings.fullscreen == true)
        #expect(model.effectiveVersionMemory == 6144)
        #expect(model.effectiveVersionWindowWidth == 1280)
        #expect(model.effectiveVersionWindowHeight == 720)
        #expect(model.selectedLaunchConfigurationSummaryText.contains("内存：6144 MB"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("窗口：1280 × 720"))

        model.extraJvmArguments = #" -Dglobal="hello world" "#
        model.extraGameArguments = #" --demo "global mode" "#
        model.versionSettings.extraJvmArguments = "-Dversion=true"
        model.versionSettings.extraGameArguments = #"--server "local host""#

        #expect(model.globalExtraJvmArgumentList == ["-Dglobal=hello world"])
        #expect(model.globalExtraGameArgumentList == ["--demo", "global mode"])
        #expect(model.selectedEffectiveExtraJvmArgumentList == ["-Dglobal=hello world", "-Dversion=true"])
        #expect(model.selectedEffectiveExtraGameArgumentList == ["--demo", "global mode", "--server", "local host"])
        #expect(model.selectedEffectiveExtraArgumentsSummaryText == "JVM 2 项，游戏 4 项")
        #expect(model.selectedLaunchConfigurationSummaryText.contains("额外 JVM 参数：-Dglobal=hello world -Dversion=true"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("额外游戏参数：--demo global mode --server local host"))

        let saved = VersionLaunchSettingsStore().load(for: instance)
        #expect(saved.usesGlobalMemory == false)
        #expect(saved.memoryMegabytes == 6144)
        #expect(saved.usesGlobalWindow == false)
        #expect(saved.windowWidth == 1280)
        #expect(saved.windowHeight == 720)
        #expect(saved.fullscreen == true)
        #expect(saved.extraJvmArgumentList == ["-Dversion=true"])
        #expect(saved.extraGameArgumentList == ["--server", "local host"])
    }

    @MainActor
    @Test func managesServerFavoritesAndAppliesLaunchTarget() async throws {
        let suiteName = "PCLMacServerFavoritesTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences")
        let model = LauncherModel(
            preferencesStore: store,
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            ),
            downloadTaskHistoryStore: DownloadTaskHistoryStore(userDefaults: userDefaults, key: "download-tasks", limit: 50)
        )

        model.serverFavoriteDraftName = "  Home Server  "
        model.serverFavoriteDraftAddress = "  play.home.test  "
        model.serverFavoriteDraftPort = " 25566 "
        model.saveServerFavoriteDraft()

        #expect(model.serverFavorites == [
            LauncherServerFavorite(name: "Home Server", address: "play.home.test", port: "25566")
        ])
        #expect(model.selectedServerFavorite?.addressText == "play.home.test:25566")
        #expect(model.serverFavoriteDraftAddress.isEmpty)

        model.useSelectedServerFavoriteForLaunch()

        #expect(model.launchServerAddress == "play.home.test")
        #expect(model.launchServerPort == "25566")
        #expect(model.launchServerTargetText == "play.home.test:25566")

        model.launchServerAddress = ""
        model.launchServerPort = ""
        await model.launchSelectedServerFavorite()

        #expect(model.launchServerAddress == "play.home.test")
        #expect(model.launchServerPort == "25566")
        #expect(model.selectedPage == .launch)
        #expect(model.launchStatus.title == "无法启动")

        let reloadedModel = LauncherModel(
            preferencesStore: store,
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            ),
            downloadTaskHistoryStore: DownloadTaskHistoryStore(userDefaults: userDefaults, key: "download-tasks", limit: 50)
        )

        #expect(reloadedModel.serverFavorites == model.serverFavorites)
        #expect(reloadedModel.launchServerAddress == "play.home.test")
        #expect(reloadedModel.launchServerPort == "25566")

        reloadedModel.removeSelectedServerFavorite()

        #expect(reloadedModel.serverFavorites.isEmpty)
        #expect(store.load().serverFavorites.isEmpty)
    }

    @MainActor
    @Test func togglesHomeCardsAndPersistsPreferences() throws {
        let suiteName = "PCLMacHomeCardTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let preferencesStore = LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences")
        let model = LauncherModel(
            preferencesStore: preferencesStore,
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            )
        )

        #expect(model.isHomeCardVisible(.java))
        #expect(model.isHomeCardVisible(.launchConfig))
        model.setHomeCard(.java, visible: false)
        model.setHomeCard(.versions, visible: false)
        model.setHomeCard(.java, visible: false)

        #expect(model.hiddenHomeCardIDs == [LauncherHomeCard.java.rawValue, LauncherHomeCard.versions.rawValue])
        #expect(model.isHomeCardVisible(.java) == false)
        #expect(preferencesStore.load().hiddenHomeCardIDs == [LauncherHomeCard.java.rawValue, LauncherHomeCard.versions.rawValue])

        let reloadedModel = LauncherModel(
            preferencesStore: preferencesStore,
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            )
        )
        #expect(reloadedModel.isHomeCardVisible(.java) == false)
        #expect(reloadedModel.isHomeCardVisible(.versions) == false)

        reloadedModel.resetHomeCards()
        #expect(reloadedModel.hiddenHomeCardIDs.isEmpty)
        #expect(preferencesStore.load().hiddenHomeCardIDs.isEmpty)
    }

    @MainActor
    @Test func exposesCurrentAppIdentityForAboutPage() throws {
        let suiteName = "PCLMacAboutTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let model = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            )
        )

        #expect(model.appNameText.isEmpty == false)
        #expect(model.appVersionSummaryText.isEmpty == false)
        #expect(model.appBundleIdentifierText.isEmpty == false)
        #expect(model.appBundlePathText.isEmpty == false)
        #expect(model.appInstallLocationText.isEmpty == false)
        #expect(model.appBundleSummaryText.contains("Bundle ID：\(model.appBundleIdentifierText)"))
        #expect(model.appBundleSummaryText.contains("路径：\(model.appBundlePathText)"))
    }

    @Test func resolvesMicrosoftClientIDFromOverrideEnvironmentOrBundle() {
        let bundled = MicrosoftOAuthClientIDResolver(
            settingsClientID: nil,
            environmentClientID: nil,
            bundleClientID: "bundle-client"
        ).resolve()
        #expect(bundled.clientID == "bundle-client")
        #expect(bundled.source == .bundle)

        let environment = MicrosoftOAuthClientIDResolver(
            settingsClientID: "  ",
            environmentClientID: "env-client",
            bundleClientID: "bundle-client"
        ).resolve()
        #expect(environment.clientID == "env-client")
        #expect(environment.source == .environment)

        let settings = MicrosoftOAuthClientIDResolver(
            settingsClientID: "settings-client",
            environmentClientID: "env-client",
            bundleClientID: "bundle-client"
        ).resolve()
        #expect(settings.clientID == "settings-client")
        #expect(settings.source == .settings)

        let missing = MicrosoftOAuthClientIDResolver(
            settingsClientID: "",
            environmentClientID: nil,
            bundleClientID: nil
        ).resolve()
        #expect(!missing.isConfigured)
        #expect(missing.source == nil)
    }

    @Test func storesAccountProfilesAndSecretsSeparately() throws {
        let suiteName = "PCLMacAccountTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let secretStore = InMemoryAccountSecretStore()
        let store = LauncherAccountStore(
            userDefaults: userDefaults,
            profilesKey: "accounts",
            secretStore: secretStore
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = LauncherAccountProfile(
            id: "microsoft:alex",
            kind: .microsoft,
            displayName: "Alex",
            playerUUID: "00000000-0000-0000-0000-000000000000",
            serverURL: nil,
            createdAt: date,
            lastUsedAt: date
        )
        let secret = LauncherAccountSecret(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: date.addingTimeInterval(3600)
        )

        try store.upsert(profile, secret: secret)

        #expect(store.loadProfiles() == [profile])
        #expect(try store.loadSecret(for: profile.id) == secret)

        try store.delete(accountID: profile.id)

        #expect(store.loadProfiles().isEmpty)
        #expect(try store.loadSecret(for: profile.id) == nil)
    }

    @MainActor
    @Test func recordsAndClearsDownloadTasks() throws {
        let suiteName = "PCLMacDownloadTaskTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let taskStore = DownloadTaskHistoryStore(userDefaults: userDefaults, key: "download-tasks", limit: 50)
        let model = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            ),
            downloadTaskHistoryStore: taskStore
        )

        let runningID = model.beginDownloadTask(
            title: "Fabric 1.20.1",
            category: "版本安装",
            detail: "正在安装",
            progress: 0.2
        )
        let finishedID = model.beginDownloadTask(
            title: "Sodium",
            category: "Modrinth Mod",
            detail: "正在下载",
            progress: 0.1
        )
        model.updateDownloadTask(
            finishedID,
            status: .succeeded,
            detail: "已保存 Sodium",
            progress: 1,
            destinationPath: "/tmp/sodium.jar"
        )
        let failedID = model.beginDownloadTask(
            title: "Forge 1.20.1",
            category: "版本安装",
            detail: "正在下载 installer",
            progress: 0.3,
            retryAction: .installVersion(
                versionID: "1.20.1",
                loader: "Forge",
                downloadSource: "官方 + BMCLAPI"
            )
        )
        model.updateDownloadTask(
            failedID,
            status: .failed,
            detail: "安装失败：网络中断",
            progress: 1
        )

        #expect(model.downloadTaskRecords.count == 3)
        #expect(model.selectedDownloadTaskID == failedID)
        #expect(model.activeDownloadTaskCount == 1)
        #expect(model.failedDownloadTaskCount == 1)
        #expect(model.downloadTaskRecords.first?.summaryText.contains("安装失败：网络中断") == true)
        #expect(model.downloadTaskRecords.first?.summaryText.contains("重试：安装 Forge 1.20.1") == true)
        #expect(model.canRetrySelectedDownloadTask)

        let reloadedModel = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            ),
            downloadTaskHistoryStore: taskStore
        )
        #expect(reloadedModel.downloadTaskRecords.map(\.id) == [failedID, finishedID, runningID])
        #expect(reloadedModel.selectedDownloadTaskID == failedID)
        #expect(reloadedModel.selectedDownloadTask?.retryAction == .installVersion(
            versionID: "1.20.1",
            loader: "Forge",
            downloadSource: "官方 + BMCLAPI"
        ))
        #expect(reloadedModel.canRetrySelectedDownloadTask)

        model.clearFinishedDownloadTasks()

        #expect(model.downloadTaskRecords.map(\.id) == [failedID, runningID])
        #expect(model.selectedDownloadTaskID == failedID)
        #expect(model.activeDownloadTaskCount == 1)
        #expect(model.failedDownloadTaskCount == 1)

        model.clearFailedDownloadTasks()

        #expect(model.downloadTaskRecords.map(\.id) == [runningID])
        #expect(model.selectedDownloadTaskID == runningID)
        #expect(!model.canRetrySelectedDownloadTask)
        #expect(taskStore.load().map(\.id) == [runningID])
    }

    @MainActor
    @Test func sendsNativeNotificationsForDownloadTaskResultsWhenEnabled() throws {
        let suiteName = "PCLMacNotificationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let sink = NotificationSink()
        let model = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            ),
            notificationCenter: LauncherNotificationCenter(
                requestAuthorization: { true },
                deliver: { notification in
                    sink.notifications.append(notification)
                }
            )
        )

        model.showNativeNotifications = true
        let taskID = model.beginDownloadTask(
            title: "Sodium",
            category: "Modrinth Mod",
            detail: "正在下载",
            progress: 0.2
        )
        model.updateDownloadTask(taskID, status: .succeeded, detail: "已保存 Sodium", progress: 1)
        model.updateDownloadTask(taskID, status: .succeeded, detail: "重复保存", progress: 1)

        #expect(sink.notifications == [
            LauncherNotification(title: "任务已完成", body: "Sodium：已保存 Sodium")
        ])

        model.showNativeNotifications = false
        let failedID = model.beginDownloadTask(
            title: "Forge 1.20.1",
            category: "版本安装",
            detail: "正在安装",
            progress: 0.2
        )
        model.updateDownloadTask(failedID, status: .failed, detail: "安装失败：网络中断", progress: 1)

        #expect(sink.notifications.count == 1)
    }

    @MainActor
    @Test func updatesDockBadgeForActiveTasksAndRunningGame() throws {
        let suiteName = "PCLMacDockBadgeTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let sink = DockBadgeSink()
        let model = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            ),
            dockBadgeController: LauncherDockBadgeController { badge in
                sink.badges.append(badge)
            }
        )

        model.showDockBadge = true
        let firstID = model.beginDownloadTask(
            title: "Fabric 1.20.1",
            category: "版本安装",
            detail: "正在安装",
            progress: 0.2
        )
        #expect(sink.badges.last == "1")

        let secondID = model.beginDownloadTask(
            title: "Sodium",
            category: "Modrinth Mod",
            detail: "正在下载",
            progress: 0.1
        )
        #expect(sink.badges.last == "2")

        model.updateDownloadTask(secondID, status: .succeeded, detail: "已保存 Sodium", progress: 1)
        #expect(sink.badges.last == "1")

        model.isLaunching = true
        #expect(sink.badges.last == "1+")

        model.updateDownloadTask(firstID, status: .succeeded, detail: "已安装 Fabric", progress: 1)
        #expect(sink.badges.last == "MC")

        model.showDockBadge = false
        #expect(sink.badges.last! == nil)

        model.isLaunching = false
        #expect(sink.badges.last! == nil)
    }

    @MainActor
    @Test func pausesCancellableDownloadTaskAndKeepsContinueAvailable() throws {
        let suiteName = "PCLMacDownloadTaskCancellationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let model = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            ),
            downloadTaskHistoryStore: DownloadTaskHistoryStore(userDefaults: userDefaults, key: "download-tasks", limit: 50)
        )
        let taskID = model.beginDownloadTask(
            title: "Fabric 1.20.1",
            category: "版本安装",
            detail: "正在安装",
            progress: 0.2,
            retryAction: .installVersion(
                versionID: "1.20.1",
                loader: "Fabric",
                downloadSource: "官方 + BMCLAPI"
            )
        )
        let operation = Task {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
        }
        defer { operation.cancel() }

        model.registerDownloadTaskOperation(taskID, operation: operation)

        #expect(model.canPauseSelectedDownloadTask)

        model.pauseSelectedDownloadTask()

        #expect(operation.isCancelled)
        #expect(model.selectedDownloadTask?.status == .paused)
        #expect(model.selectedDownloadTask?.detail.contains("正在暂停") == true)

        model.updateDownloadTask(taskID, status: .paused, detail: "已暂停；点击继续会跳过已完成部分")
        model.finishDownloadTaskOperation(taskID)

        #expect(!model.canPauseSelectedDownloadTask)
        #expect(model.canRetrySelectedDownloadTask)
        #expect(model.selectedDownloadTaskResumeButtonTitle == "继续")
        #expect(model.selectedDownloadTask?.summaryText.contains("继续：安装 Fabric 1.20.1") == true)

        model.clearFailedDownloadTasks()

        #expect(model.downloadTaskRecords.isEmpty)
    }

    @MainActor
    @Test func filtersSortsAndTogglesFavoriteHiddenMinecraftInstances() async throws {
        let suiteName = "PCLMacInstanceVisibilityTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacInstanceVisibilityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func makeInstance(_ name: String) throws -> MinecraftInstance {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let jsonURL = directory.appendingPathComponent("\(name).json")
            try Data("""
            {
              "id": "\(name)",
              "type": "release",
              "mainClass": "net.minecraft.client.main.Main",
              "libraries": []
            }
            """.utf8).write(to: jsonURL)
            return MinecraftInstance(
                name: name,
                path: directory,
                jsonURL: jsonURL,
                type: "release",
                releaseTime: "2024-01-01T00:00:00+00:00"
            )
        }

        let normal = try makeInstance("1.20.1")
        let hidden = try makeInstance("1.12.2")
        let favorite = try makeInstance("Fabric 1.20.1")
        let forge = try makeInstance("Forge 1.20.1")
        let model = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            )
        )
        model.minecraftInstances = [hidden, normal, favorite, forge]
        model.favoriteInstanceNames = [favorite.name]
        model.hiddenInstanceNames = [hidden.name]

        #expect(model.visibleMinecraftInstances.map(\.name) == [favorite.name, normal.name, forge.name])
        #expect(model.localVersionKindDisplay(for: normal) == "原版 · 正式版")
        #expect(model.localVersionKindDisplay(for: favorite) == "Fabric · 正式版")
        #expect(model.localVersionKindDisplay(for: forge) == "Forge · 正式版")

        model.localVersionFilter = LocalVersionFilter.favorites.rawValue
        #expect(model.visibleMinecraftInstances.map(\.name) == [favorite.name])

        model.localVersionFilter = LocalVersionFilter.vanilla.rawValue
        #expect(model.visibleMinecraftInstances.map(\.name) == [normal.name])

        model.localVersionFilter = LocalVersionFilter.fabric.rawValue
        #expect(model.visibleMinecraftInstances.map(\.name) == [favorite.name])

        model.localVersionFilter = LocalVersionFilter.forge.rawValue
        #expect(model.visibleMinecraftInstances.map(\.name) == [forge.name])

        model.localVersionFilter = LocalVersionFilter.all.rawValue
        model.localVersionQuery = "fabric"
        #expect(model.visibleMinecraftInstances.map(\.name) == [favorite.name])

        model.localVersionQuery = "原版"
        #expect(model.visibleMinecraftInstances.map(\.name) == [normal.name])

        model.localVersionQuery = "1.12"
        #expect(model.visibleMinecraftInstances.isEmpty)

        model.showsHiddenInstances = true
        #expect(model.visibleMinecraftInstances.map(\.name) == [hidden.name])
        model.selectInstance(hidden)
        #expect(model.selectedInstance?.name == hidden.name)
        #expect(!model.launchReadiness.isReady)
        #expect(model.launchReadiness.title == "缺少 Java")
        await model.prepareSelectedInstanceDependencies()
        #expect(model.launchStatus.title == "无法预补全")
        #expect(model.launchStatus.detail.contains("Java"))
        model.javaInstallations = [
            JavaInstallation(
                executable: URL(fileURLWithPath: "/bin/sh"),
                versionSummary: "Test Java 21",
                source: "Test"
            )
        ]
        #expect(model.launchReadiness.isReady)
        #expect(model.canLaunchSelectedInstance)
        model.loginMode = "Authlib"
        #expect(!model.launchReadiness.isReady)
        #expect(model.launchReadiness.detail.contains("Authlib"))
        #expect(model.canPrepareSelectedInstanceDependencies)
        await model.prepareSelectedInstanceDependencies()
        #expect(model.launchStatus.title == "依赖已就绪")
        let accountDate = Date()
        let microsoftAccount = LauncherAccountProfile(
            id: "microsoft:test",
            kind: .microsoft,
            displayName: "MS User",
            playerUUID: "ms-user",
            serverURL: nil,
            createdAt: accountDate,
            lastUsedAt: accountDate
        )
        let authlibAccount = LauncherAccountProfile(
            id: "authlib:test",
            kind: .authlib,
            displayName: "Skin User",
            playerUUID: "skin-user",
            serverURL: URL(string: "https://skin.example.com/authserver"),
            createdAt: accountDate,
            lastUsedAt: accountDate
        )
        let offlineAccount = LauncherAccountProfile.offline(username: "Alex", date: accountDate)
        model.accounts = [microsoftAccount, authlibAccount, offlineAccount]
        model.selectedAccountID = microsoftAccount.id
        #expect(model.launchModeAccounts.map(\.id) == [authlibAccount.id])
        #expect(model.selectedLaunchModeAccountID == authlibAccount.id)
        #expect(model.selectedLaunchAccount?.id == authlibAccount.id)
        #expect(model.launchReadiness.isReady)
        model.selectedLaunchModeAccountID = authlibAccount.id
        #expect(model.selectedAccountID == authlibAccount.id)
        model.loginMode = "正版"
        #expect(model.launchModeAccounts.map(\.id) == [microsoftAccount.id])
        #expect(model.selectedLaunchAccount?.id == microsoftAccount.id)
        model.loginMode = "离线"
        #expect(model.launchModeAccounts.map(\.id) == [offlineAccount.id])
        #expect(model.selectedInstanceSummaryText.contains("名称：\(hidden.name)"))
        #expect(model.selectedInstanceSummaryText.contains("类型：原版 · 正式版"))
        #expect(model.selectedInstanceSummaryText.contains("版本目录：\(hidden.path.path)"))
        #expect(model.selectedInstanceSummaryText.contains("Java 要求：未声明"))
        #expect(model.selectedInstanceSummaryText.contains("内存：4096 MB"))
        #expect(model.selectedInstanceSummaryText.contains("窗口：854 × 480"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("版本：\(hidden.name)"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("登录：离线：Player"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("游戏目录：\(hidden.path.path)"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("自动进服：未设置"))

        model.versionSettings = VersionLaunchSettings(
            usesGlobalJava: true,
            javaExecutablePath: nil,
            usesGlobalMemory: true,
            memoryMegabytes: 8192,
            extraJvmArguments: "-Dfoo=bar",
            extraGameArguments: "--demo"
        )
        #expect(model.effectiveVersionMemory == 4096)
        #expect(model.selectedLaunchConfigurationSummaryText.contains("内存：4096 MB"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("额外 JVM 参数：-Dfoo=bar"))
        #expect(model.selectedLaunchConfigurationSummaryText.contains("额外游戏参数：--demo"))

        model.localVersionQuery = ""
        #expect(model.visibleMinecraftInstances.map(\.name) == [favorite.name, normal.name, forge.name, hidden.name])

        model.showsHiddenInstances = false
        model.selectedInstanceID = favorite.id
        model.toggleHiddenSelectedInstance()

        #expect(!model.favoriteInstanceNames.contains(favorite.name))
        #expect(model.hiddenInstanceNames.contains(favorite.name))
        #expect(model.visibleMinecraftInstances.map(\.name) == [normal.name, forge.name])
        #expect(model.selectedInstanceID == normal.id)
    }

    @MainActor
    @Test func switchesCustomMinecraftDirectoryAndPersistsIt() async throws {
        let suiteName = "PCLMacCustomMinecraftDirectoryTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacCustomMinecraftDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let customMinecraft = root.appendingPathComponent("Custom Minecraft", isDirectory: true)
        let store = LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences")
        let model = LauncherModel(
            preferencesStore: store,
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            )
        )

        await model.setMinecraftDirectory(customMinecraft)

        #expect(model.minecraftDirectory == customMinecraft.standardizedFileURL)
        #expect(store.load().customMinecraftDirectoryPath == customMinecraft.standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: customMinecraft.appendingPathComponent("versions", isDirectory: true).path))
        #expect(FileManager.default.fileExists(atPath: customMinecraft.appendingPathComponent("assets", isDirectory: true).path))

        await model.setMinecraftDirectory(nil)

        #expect(!model.isUsingCustomMinecraftDirectory)
        #expect(store.load().customMinecraftDirectoryPath == nil)
    }

    @Test func buildsTrimmedOfflineAccountProfile() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = LauncherAccountProfile.offline(username: "  Steve  ", date: date)
        #expect(profile.id == "offline:steve")
        #expect(profile.displayName == "Steve")
        #expect(profile.kind == .offline)
        #expect(profile.createdAt == date)
        #expect(profile.lastUsedAt == date)
    }

    @Test func parsesJavaVersionFromCrashReportFallback() {
        let output = """
        #
        # A fatal error has been detected by the Java Runtime Environment:
        #
        # JRE version:  (21.0.11) (build )
        # Java VM: OpenJDK 64-Bit Server VM (21.0.11, mixed mode, sharing, tiered, compressed oops, compressed class ptrs, g1 gc, bsd-aarch64)
        # Problematic frame:
        """

        #expect(parseJavaVersion(output) == "OpenJDK 21.0.11")
    }

    @Test func decodesRequiredJavaVersionFromMinecraftVersionChain() throws {
        let parent = try JSONDecoder().decode(MinecraftVersionFile.self, from: Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "javaVersion": {
            "component": "java-runtime-gamma",
            "majorVersion": 17
          },
          "libraries": []
        }
        """.utf8))
        let child = try JSONDecoder().decode(MinecraftVersionFile.self, from: Data("""
        {
          "id": "fabric-loader-0.16.14-1.20.1",
          "type": "release",
          "inheritsFrom": "1.20.1",
          "libraries": []
        }
        """.utf8))
        let override = try JSONDecoder().decode(MinecraftVersionFile.self, from: Data("""
        {
          "id": "custom-runtime",
          "type": "release",
          "javaVersion": {
            "component": "java-runtime-delta",
            "majorVersion": 21
          },
          "libraries": []
        }
        """.utf8))

        #expect(requiredMinecraftJavaMajorVersion(from: [parent, child]) == 17)
        #expect(requiredMinecraftJavaMajorVersion(from: [parent, child, override]) == 21)
    }

    @Test func selectsClosestCompatibleJavaRuntime() {
        let java8 = JavaInstallation(
            executable: URL(fileURLWithPath: "/jdk8/bin/java"),
            versionSummary: "java version 1.8.0_402",
            source: "Test"
        )
        let java17 = JavaInstallation(
            executable: URL(fileURLWithPath: "/jdk17/bin/java"),
            versionSummary: "OpenJDK 17.0.11",
            source: "Test"
        )
        let java21 = JavaInstallation(
            executable: URL(fileURLWithPath: "/jdk21/bin/java"),
            versionSummary: "OpenJDK 21.0.2",
            source: "Test"
        )
        let selector = JavaVersionSelector()

        #expect(JavaVersionSelector.majorVersion(from: java8.versionSummary) == 8)
        #expect(selector.select(from: [java21, java8, java17], requiredMajorVersion: 17, fallback: java21)?.executable == java17.executable)
        #expect(selector.select(from: [java21, java8, java17], requiredMajorVersion: 8, fallback: java21)?.executable == java8.executable)
        #expect(selector.select(from: [java8, java17], requiredMajorVersion: 21, fallback: java8)?.executable == java17.executable)
        #expect(selector.select(from: [java8, java17], requiredMajorVersion: nil, fallback: java17)?.executable == java17.executable)
    }

    @MainActor
    @Test func blocksLaunchWhenSelectedJavaIsBelowMinecraftRequirement() async throws {
        let suiteName = "PCLMacJavaCompatibilityTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacJavaCompatibilityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let versionDirectory = minecraft.appendingPathComponent("versions/26.1.2", isDirectory: true)
        try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        let jsonURL = versionDirectory.appendingPathComponent("26.1.2.json")
        try Data("""
        {
          "id": "26.1.2",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "javaVersion": {
            "component": "java-runtime-delta",
            "majorVersion": 25
          },
          "libraries": []
        }
        """.utf8).write(to: jsonURL)

        let instance = MinecraftInstance(
            name: "26.1.2",
            path: versionDirectory,
            jsonURL: jsonURL,
            type: "release",
            releaseTime: "2026-04-09T10:12:23+00:00"
        )
        let model = LauncherModel(
            preferencesStore: LauncherPreferencesStore(userDefaults: userDefaults, key: "preferences"),
            accountStore: LauncherAccountStore(
                userDefaults: userDefaults,
                profilesKey: "accounts",
                secretStore: InMemoryAccountSecretStore()
            )
        )
        model.customMinecraftDirectoryPath = minecraft.path
        model.minecraftInstances = [instance]
        model.selectedInstanceID = instance.id
        let java21 = JavaInstallation(
            executable: URL(fileURLWithPath: "/bin/sh"),
            versionSummary: "OpenJDK 21.0.11",
            source: "Test"
        )
        let java25 = JavaInstallation(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            versionSummary: "OpenJDK 25.0.1",
            source: "Test"
        )
        model.javaInstallations = [java21]

        #expect(!model.launchReadiness.isReady)
        #expect(model.launchReadiness.title == "Java 版本过低")
        #expect(model.launchReadiness.detail.contains("Java 25+"))
        #expect(model.launchReadiness.detail.contains("OpenJDK 21.0.11"))
        #expect(!model.canLaunchSelectedInstance)
        #expect(model.currentLaunchReadinessStatus.title == "Java 版本过低")
        #expect(model.currentLaunchReadinessStatus.progress == 0)
        #expect(model.effectiveJavaCompatibilityMessage?.contains("Java 25+") == true)
        #expect(model.recommendedCompatibleJava == nil)
        #expect(model.recommendedJavaRuntimeComponent == "java-runtime-epsilon")
        #expect(model.canInstallRecommendedJavaRuntime)
        #expect(model.canPrepareSelectedInstanceDependencies)

        model.copySelectedJavaDiagnostics()
        #expect(model.lastEvent == "已复制 Java 诊断")

        model.openSelectedVersionJavaSettings()
        #expect(model.selectedPage == .settings)
        #expect(model.selectedSettingsSection == .version)
        #expect(model.versionSettings.usesGlobalJava)
        #expect(model.versionSettings.javaExecutablePath == nil)

        await model.prepareSelectedInstanceDependencies()
        #expect(model.launchStatus.title == "依赖已就绪")

        await model.launchSelectedInstance()
        #expect(model.launchStatus.title == "无法启动")
        #expect(model.launchStatus.detail.contains("Java 25+"))

        model.autoSelectJava = false
        model.selectedJavaID = java21.id
        model.javaInstallations.append(java25)
        #expect(model.recommendedCompatibleJava?.executable == java25.executable)
        #expect(!model.launchReadiness.isReady)

        model.useRecommendedCompatibleJavaForSelectedVersion()

        #expect(model.launchReadiness.isReady)
        #expect(model.currentLaunchReadinessStatus.title == "可以启动")
        #expect(model.effectiveJavaSummary.contains("OpenJDK 25.0.1"))
        #expect(model.versionSettings.javaExecutablePath == java25.executable.path)
    }

    @Test func installsMojangJavaRuntimeFromManifest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacMojangJavaRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestURL = URL(string: "https://example.com/runtime-manifest.json")!
        let javaURL = URL(string: "https://example.com/java")!
        let readmeURL = URL(string: "https://example.com/release")!
        let javaData = Data("#!/bin/sh\nexit 0\n".utf8)
        let readmeData = Data("runtime".utf8)
        let indexData = Data("""
        {
          "mac-os-arm64": {
            "java-runtime-epsilon": [
              {
                "manifest": { "url": "\(manifestURL.absoluteString)" },
                "version": { "name": "25.0.1", "released": "2026-01-01T00:00:00+00:00" }
              }
            ]
          }
        }
        """.utf8)
        let manifestData = Data("""
        {
          "files": {
            "jre.bundle": { "type": "directory" },
            "jre.bundle/Contents": { "type": "directory" },
            "jre.bundle/Contents/Home": { "type": "directory" },
            "jre.bundle/Contents/Home/bin": { "type": "directory" },
            "jre.bundle/Contents/Home/legal/java.base": { "type": "directory" },
            "jre.bundle/Contents/Home/bin/java": {
              "type": "file",
              "executable": true,
              "downloads": {
                "raw": {
                  "sha1": "\(MojangJavaRuntimeInstaller.sha1Hex(javaData))",
                  "size": \(javaData.count),
                  "url": "\(javaURL.absoluteString)"
                }
              }
            },
            "jre.bundle/Contents/Home/legal/java.base/LICENSE": {
              "type": "file",
              "downloads": {
                "raw": {
                  "sha1": "\(MojangJavaRuntimeInstaller.sha1Hex(readmeData))",
                  "size": \(readmeData.count),
                  "url": "\(readmeURL.absoluteString)"
                }
              }
            },
            "jre.bundle/Contents/Home/legal/java.compiler/LICENSE": {
              "type": "link",
              "target": "../java.base/LICENSE"
            }
          }
        }
        """.utf8)
        let payloads: [URL: Data] = [
            MojangJavaRuntimeInstaller.runtimeIndexURL: indexData,
            manifestURL: manifestData,
            javaURL: javaData,
            readmeURL: readmeData
        ]
        let installer = MojangJavaRuntimeInstaller(
            downloadSource: .official,
            platformID: "mac-os-arm64"
        ) { url in
            guard let data = payloads[url] else { throw URLError(.badURL) }
            return data
        }

        let progressRecorder = JavaRuntimeProgressRecorder()
        let result = try await installer.install(
            component: "java-runtime-epsilon",
            appSupportDirectory: root
        ) { progress in
            await progressRecorder.append(progress)
        }
        let progressEvents = await progressRecorder.values

        #expect(result.component == "java-runtime-epsilon")
        #expect(result.versionName == "25.0.1")
        #expect(result.installedFiles == 2)
        #expect(result.skippedFiles == 0)
        #expect(FileManager.default.isExecutableFile(atPath: result.javaExecutable.path))
        #expect(progressEvents.last?.finished == 2)
        #expect(progressEvents.last?.downloaded == 2)

        let link = result.runtimeDirectory
            .appendingPathComponent("jre.bundle/Contents/Home/legal/java.compiler/LICENSE")
        let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(linkTarget == "../java.base/LICENSE")

        let skippedResult = try await installer.install(
            component: "java-runtime-epsilon",
            appSupportDirectory: root
        )
        #expect(skippedResult.installedFiles == 0)
        #expect(skippedResult.skippedFiles == 2)
        #expect(MojangJavaRuntimeInstaller.component(forMajorVersion: 25) == "java-runtime-epsilon")
        #expect(MojangJavaRuntimeInstaller.component(forMajorVersion: 21) == "java-runtime-delta")
    }

    @Test func scansMinecraftLogsAndCrashReports() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacLogScanTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let logs = minecraft.appendingPathComponent("logs", isDirectory: true)
        let crashes = minecraft.appendingPathComponent("crash-reports", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: crashes, withIntermediateDirectories: true)

        try """
        [Render thread/INFO]: Starting Minecraft
        [Render thread/ERROR]: Failed to load test resource
        """.write(to: logs.appendingPathComponent("latest.log"), atomically: true, encoding: .utf8)
        try """
        ---- Minecraft Crash Report ----
        Time: 2026-06-11
        Description: Unexpected test crash
        """.write(to: crashes.appendingPathComponent("crash-2026-06-11_01.00.00-client.txt"), atomically: true, encoding: .utf8)
        try """
        #
        # JRE version:  (21.0.11) (build )
        # Java VM: OpenJDK 64-Bit Server VM (21.0.11, mixed mode)
        # Problematic frame:
        # C  [libobjc.A.dylib+0x1234]
        """.write(to: root.appendingPathComponent("hs_err_pid123.log"), atomically: true, encoding: .utf8)

        let manager = MinecraftLogManager()
        let entries = manager.scan(minecraftDirectory: minecraft, additionalDirectories: [root])
        let kinds = Set(entries.map(\.kind))

        #expect(kinds.contains(.latest))
        #expect(kinds.contains(.crashReport))
        #expect(kinds.contains(.jvmCrash))
        #expect(entries.first(where: { $0.kind == .latest })?.summary.contains("Failed to load") == true)
        #expect(entries.first(where: { $0.kind == .crashReport })?.summary == "Description: Unexpected test crash")
        #expect(entries.first(where: { $0.kind == .jvmCrash })?.summary.contains("OpenJDK 21.0.11") == true)
    }

    @Test func truncatesMinecraftLogPreviewToTail() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacLogPreviewTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let logURL = root.appendingPathComponent("latest.log")
        let content = (1...12).map { "line-\($0)" }.joined(separator: "\n")
        try content.write(to: logURL, atomically: true, encoding: .utf8)

        let entry = MinecraftLogEntry(
            id: logURL.path,
            url: logURL,
            kind: .latest,
            name: "latest.log",
            modifiedAt: nil,
            size: 0,
            summary: "test"
        )
        let preview = MinecraftLogManager().preview(entry, maxLines: 5)

        #expect(preview.isTruncated)
        #expect(preview.lineCount == 12)
        #expect(preview.text.hasPrefix("line-8"))
        #expect(preview.text.contains("line-12"))
    }

    @Test func diagnosesJavaVersionMismatchFromCrashLog() {
        let content = """
        java.lang.UnsupportedClassVersionError: net/example/TestMod has been compiled by a more recent version of the Java Runtime
        The class file version is 65.0, this version of the Java Runtime only recognizes class file versions up to 61.0
        """

        let diagnoses = MinecraftLogManager().diagnose(content: content, kind: .latest)

        #expect(diagnoses.first?.id == "java-version")
        #expect(diagnoses.first?.detail.contains("Java 21") == true)
        #expect(diagnoses.first?.matchedLine?.contains("UnsupportedClassVersionError") == true)
    }

    @Test func diagnosesModDependencyAndMixinFailures() {
        let content = """
        net.fabricmc.loader.impl.FormattedException: net.fabricmc.loader.impl.discovery.ModResolutionException: Unmet dependency listing:
        Mod fabric-api depends on minecraft requires version >=1.21
        org.spongepowered.asm.mixin.transformer.throwables.MixinTransformerError: Mixin apply failed sodium.mixins.json
        """

        let diagnoses = MinecraftLogManager().diagnose(content: content, kind: .crashReport)
        let ids = diagnoses.map(\.id)

        #expect(ids.contains("mod-dependency"))
        #expect(ids.contains("mixin-conflict"))
    }

    @Test func diagnosesJvmCrashReports() {
        let content = """
        #
        # A fatal error has been detected by the Java Runtime Environment:
        # JRE version:  (21.0.11) (build )
        # Problematic frame:
        # C  [liblwjgl.dylib+0x1234]
        0x000000022a806000  /System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libCoreFSCache.dylib
        """

        let diagnoses = MinecraftLogManager().diagnose(content: content, kind: .jvmCrash)

        #expect(diagnoses.contains(where: { $0.id == "jvm-crash" }))
        #expect(!diagnoses.contains(where: { $0.id == "graphics-native" }))
        #expect(diagnoses.first(where: { $0.id == "jvm-crash" })?.matchedLine?.contains("Problematic frame") == true)
    }

    @Test func summarizesGameLaunchExitStates() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let endedAt = Date(timeIntervalSince1970: 145)

        let normal = GameLaunchExitSummary(
            instanceName: "1.21.1",
            processIdentifier: 1001,
            exitCode: 0,
            startedAt: startedAt,
            endedAt: endedAt,
            wasUserRequestedStop: false
        )
        #expect(normal.title == "游戏正常退出")
        #expect(normal.detail.contains("运行 45 秒"))
        #expect(!normal.shouldOpenLogDiagnostics)

        let crashed = GameLaunchExitSummary(
            instanceName: "1.21.1",
            processIdentifier: 1002,
            exitCode: 255,
            startedAt: startedAt,
            endedAt: endedAt,
            wasUserRequestedStop: false
        )
        #expect(crashed.title == "游戏异常退出")
        #expect(crashed.detail.contains("返回码 255"))
        #expect(crashed.shouldOpenLogDiagnostics)

        let stopped = GameLaunchExitSummary(
            instanceName: "1.21.1",
            processIdentifier: 1003,
            exitCode: 143,
            startedAt: startedAt,
            endedAt: endedAt,
            wasUserRequestedStop: true
        )
        #expect(stopped.title == "游戏已关闭")
        #expect(!stopped.shouldOpenLogDiagnostics)
    }

    @Test func parsesLocalIPv4AddressesFromIfconfig() {
        let output = """
        lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
            inet 127.0.0.1 netmask 0xff000000
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 192.168.31.8 netmask 0xffffff00 broadcast 192.168.31.255
        en1: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
            inet 169.254.10.1 netmask 0xffff0000 broadcast 169.254.255.255
            inet 10.0.0.12 netmask 0xffffff00 broadcast 10.0.0.255
        """

        #expect(parseLocalIPv4Addresses(output) == ["192.168.31.8", "10.0.0.12"])
    }

    @Test func parsesMinecraftLANAnnouncements() throws {
        let world = try #require(MinecraftLANDiscoveryService.parseAnnouncement(
            "[MOTD]Steve 的世界[/MOTD][AD]51234[/AD]",
            host: "192.168.31.23",
            discoveredAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        #expect(world.motd == "Steve 的世界")
        #expect(world.host == "192.168.31.23")
        #expect(world.port == 51234)
        #expect(world.address == "192.168.31.23:51234")
        #expect(MinecraftLANDiscoveryService.parseAnnouncement("[MOTD]Bad[/MOTD][AD]99999[/AD]", host: "192.168.31.23") == nil)
        #expect(MinecraftLANDiscoveryService.parseAnnouncement("[MOTD]Missing Port[/MOTD]", host: "192.168.31.23") == nil)
    }

    @Test func duplicatesMinecraftInstanceSafely() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacInstanceDuplicateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let instanceDirectory = minecraft.appendingPathComponent("versions/1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": []
        }
        """.utf8).write(to: instanceDirectory.appendingPathComponent("1.20.1.json"))
        try Data("jar".utf8).write(to: instanceDirectory.appendingPathComponent("1.20.1.jar"))

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: instanceDirectory,
            jsonURL: instanceDirectory.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let result = try MinecraftInstanceManager().duplicate(instance, minecraftDirectory: minecraft)

        #expect(result.name == "1.20.1-副本")
        #expect(FileManager.default.fileExists(atPath: result.directory.path))
        #expect(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("1.20.1-副本.jar").path))
        #expect(!FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("1.20.1.jar").path))

        let profile = try JSONSerialization.jsonObject(with: Data(contentsOf: result.jsonURL)) as? [String: Any]
        #expect(profile?["id"] as? String == "1.20.1-副本")

        let instances = await MinecraftInstanceScanner().scan(minecraftDirectory: minecraft)
        #expect(instances.contains { $0.name == "1.20.1-副本" })
    }

    @Test func exportsMinecraftInstanceArchive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacInstanceExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let instanceDirectory = minecraft.appendingPathComponent("versions/1.20.1", isDirectory: true)
        let modsDirectory = instanceDirectory.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": []
        }
        """.utf8).write(to: instanceDirectory.appendingPathComponent("1.20.1.json"))
        try Data("jar".utf8).write(to: instanceDirectory.appendingPathComponent("1.20.1.jar"))
        try Data("mod".utf8).write(to: modsDirectory.appendingPathComponent("fabric-api.jar"))

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: instanceDirectory,
            jsonURL: instanceDirectory.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let archiveURL = root.appendingPathComponent("exports/1.20.1.zip")
        let result = try MinecraftInstanceManager().exportArchive(instance, minecraftDirectory: minecraft, destination: archiveURL)

        #expect(result.name == "1.20.1")
        #expect(result.archiveURL == archiveURL)
        #expect(result.byteCount > 0)
        #expect(FileManager.default.fileExists(atPath: archiveURL.path))

        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try extractZipArchive(archiveURL, to: extracted)
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("1.20.1/1.20.1.json").path))
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("1.20.1/1.20.1.jar").path))
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("1.20.1/mods/fabric-api.jar").path))

        do {
            _ = try MinecraftInstanceManager().exportArchive(
                instance,
                minecraftDirectory: minecraft,
                destination: instanceDirectory.appendingPathComponent("backup.zip")
            )
            Issue.record("Expected unsafe export destination rejection")
        } catch let error as MinecraftInstanceManagerError {
            guard case .unsafeExportDestination = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func importsMinecraftInstanceArchiveWithUniqueName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacInstanceImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let instanceDirectory = minecraft.appendingPathComponent("versions/1.20.1", isDirectory: true)
        let modsDirectory = instanceDirectory.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": []
        }
        """.utf8).write(to: instanceDirectory.appendingPathComponent("1.20.1.json"))
        try Data("jar".utf8).write(to: instanceDirectory.appendingPathComponent("1.20.1.jar"))
        try Data("mod".utf8).write(to: modsDirectory.appendingPathComponent("fabric-api.jar"))

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: instanceDirectory,
            jsonURL: instanceDirectory.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let archiveURL = root.appendingPathComponent("exports/1.20.1.zip")
        _ = try MinecraftInstanceManager().exportArchive(instance, minecraftDirectory: minecraft, destination: archiveURL)

        let result = try MinecraftInstanceManager().importArchive(archiveURL, minecraftDirectory: minecraft)

        #expect(result.originalName == "1.20.1")
        #expect(result.name == "1.20.1-2")
        #expect(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("1.20.1-2.json").path))
        #expect(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("1.20.1-2.jar").path))
        #expect(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("mods/fabric-api.jar").path))

        let profile = try JSONSerialization.jsonObject(with: Data(contentsOf: result.jsonURL)) as? [String: Any]
        #expect(profile?["id"] as? String == "1.20.1-2")
    }

    @Test func rejectsUnsafeMinecraftInstanceArchivePaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacUnsafeInstanceImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let archiveURL = root.appendingPathComponent("unsafe.zip")
        try makeZipArchiveWithUnsafeParentEntry(to: archiveURL)

        do {
            _ = try MinecraftInstanceManager().importArchive(
                archiveURL,
                minecraftDirectory: root.appendingPathComponent("minecraft", isDirectory: true)
            )
            Issue.record("Expected unsafe import path rejection")
        } catch let error as MinecraftInstanceManagerError {
            guard case .unsafeImportPath(let path) = error, path == "../evil.txt" else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func rejectsUnsafeMinecraftInstanceManagementPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacUnsafeInstanceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let jsonURL = outside.appendingPathComponent("outside.json")
        try Data(#"{"id":"outside","libraries":[]}"#.utf8).write(to: jsonURL)

        let instance = MinecraftInstance(
            name: "outside",
            path: outside,
            jsonURL: jsonURL,
            type: "release",
            releaseTime: "2026-06-10T00:00:00+00:00"
        )

        do {
            _ = try MinecraftInstanceManager().duplicate(instance, minecraftDirectory: minecraft)
            Issue.record("Expected unsafe instance path rejection")
        } catch let error as MinecraftInstanceManagerError {
            guard case .unsafeInstancePath = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func scansAndTogglesLocalModFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacLocalModTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let instance = root.appendingPathComponent("versions/1.20.1", isDirectory: true)
        let mods = instance.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        try Data("enabled".utf8).write(to: mods.appendingPathComponent("fabric-api.jar"))
        try Data("disabled".utf8).write(to: mods.appendingPathComponent("sodium.jar.disabled"))
        try Data("ignored".utf8).write(to: mods.appendingPathComponent("readme.txt"))

        let manager = LocalModManager()
        let scanned = try manager.scan(instanceDirectory: instance)

        #expect(scanned.map(\.displayName) == ["fabric-api", "sodium"])
        #expect(scanned.map(\.status) == [.enabled, .disabled])

        let fabric = try #require(scanned.first { $0.displayName == "fabric-api" })
        let disabled = try manager.toggle(fabric)

        #expect(disabled.url.lastPathComponent == "fabric-api.jar.disabled")
        #expect(disabled.status == .disabled)
        #expect(!FileManager.default.fileExists(atPath: mods.appendingPathComponent("fabric-api.jar").path))

        let enabled = try manager.toggle(disabled)

        #expect(enabled.url.lastPathComponent == "fabric-api.jar")
        #expect(enabled.status == .enabled)
        #expect(FileManager.default.fileExists(atPath: mods.appendingPathComponent("fabric-api.jar").path))
    }

    @Test func importsLocalModFilesIntoInstanceModsFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacLocalModImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let instance = root.appendingPathComponent("versions/1.20.1", isDirectory: true)
        let importSource = root.appendingPathComponent("import-source", isDirectory: true)
        try FileManager.default.createDirectory(at: importSource, withIntermediateDirectories: true)
        let firstSource = importSource.appendingPathComponent("fabric-api.jar")
        let secondSource = importSource.appendingPathComponent("mini-map.litemod")
        try Data("fabric".utf8).write(to: firstSource)
        try Data("map".utf8).write(to: secondSource)

        let manager = LocalModManager()
        let imported = try manager.importFiles([firstSource, secondSource], instanceDirectory: instance)
        let mods = instance.appendingPathComponent("mods", isDirectory: true)

        #expect(imported.map(\.url.lastPathComponent).sorted() == ["fabric-api.jar", "mini-map.litemod"])
        #expect(try Data(contentsOf: mods.appendingPathComponent("fabric-api.jar")) == Data("fabric".utf8))
        #expect(try Data(contentsOf: mods.appendingPathComponent("mini-map.litemod")) == Data("map".utf8))

        do {
            _ = try manager.importFiles([firstSource], instanceDirectory: instance)
            Issue.record("Expected duplicate local mod rejection")
        } catch let error as LocalModManagerError {
            guard case .targetAlreadyExists(let name) = error, name == "fabric-api.jar" else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func readsLocalModMetadataFromJarFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacLocalModMetadataTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let instance = root.appendingPathComponent("versions/1.20.1", isDirectory: true)
        let mods = instance.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)

        let fabricSource = root.appendingPathComponent("fabric-source", isDirectory: true)
        try FileManager.default.createDirectory(at: fabricSource, withIntermediateDirectories: true)
        try Data("""
        {
          "schemaVersion": 1,
          "id": "fabric-api",
          "name": "Fabric API",
          "version": "0.100.0",
          "description": "Hooks and interoperability layers"
        }
        """.utf8).write(to: fabricSource.appendingPathComponent("fabric.mod.json"))
        try makeZipArchive(from: fabricSource, to: mods.appendingPathComponent("fabric-api.jar"))

        let forgeSource = root.appendingPathComponent("forge-source", isDirectory: true)
        let forgeMeta = forgeSource.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: forgeMeta, withIntermediateDirectories: true)
        try Data("""
        modLoader="javafml"
        loaderVersion="[47,)"
        [[mods]]
        modId="jei"
        version="15.3.0"
        displayName="Just Enough Items"
        description="Recipe and item lookup"
        """.utf8).write(to: forgeMeta.appendingPathComponent("mods.toml"))
        try makeZipArchive(from: forgeSource, to: mods.appendingPathComponent("jei.jar.disabled"))

        let scanned = try LocalModManager().scan(instanceDirectory: instance)

        let fabric = try #require(scanned.first { $0.url.lastPathComponent == "fabric-api.jar" })
        #expect(fabric.displayName == "Fabric API")
        #expect(fabric.metadata?.version == "0.100.0")
        #expect(fabric.metadata?.loader == "Fabric")
        #expect(fabric.metadata?.description == "Hooks and interoperability layers")

        let forge = try #require(scanned.first { $0.url.lastPathComponent == "jei.jar.disabled" })
        #expect(forge.displayName == "Just Enough Items")
        #expect(forge.metadata?.version == "15.3.0")
        #expect(forge.metadata?.loader == "Forge")
        #expect(forge.status == .disabled)
    }

    @Test func requestsMicrosoftDeviceCodeWithPCLScope() async throws {
        final class Capture: @unchecked Sendable {
            var body = ""
        }
        let capture = Capture()
        let service = MicrosoftMinecraftLoginService(clientID: "client-id") { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")
            #expect(request.httpMethod == "POST")
            capture.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (
                Data(#"{"user_code":"ABCD-EFGH","device_code":"device","verification_uri":"https://microsoft.com/devicelogin","expires_in":900,"interval":5}"#.utf8),
                response
            )
        }

        let code = try await service.requestDeviceCode()

        #expect(capture.body.contains("client_id=client-id"))
        #expect(capture.body.contains("scope=XboxLive.signin%20offline_access"))
        #expect(capture.body.contains("tenant=/consumers"))
        #expect(code.userCode == "ABCD-EFGH")
    }

    @Test func completesMicrosoftRefreshLoginThroughMinecraftServices() async throws {
        final class MockHTTP: @unchecked Sendable {
            var calls: [(url: String, method: String, body: String, authorization: String?)] = []

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                calls.append((
                    url: url.absoluteString,
                    method: request.httpMethod ?? "GET",
                    body: body,
                    authorization: request.value(forHTTPHeaderField: "Authorization")
                ))

                let payload: String
                switch url.absoluteString {
                case "https://login.live.com/oauth20_token.srf":
                    #expect(body.contains("client_id=client-id"))
                    #expect(body.contains("refresh_token=refresh-one"))
                    payload = #"{"access_token":"oauth-access","refresh_token":"refresh-two","expires_in":3600}"#
                case "https://user.auth.xboxlive.com/user/authenticate":
                    #expect(body.contains(#""RpsTicket":"d=oauth-access""#))
                    payload = #"{"Token":"xbl-token"}"#
                case "https://xsts.auth.xboxlive.com/xsts/authorize":
                    #expect(body.contains(#""RelyingParty":"rp:\/\/api.minecraftservices.com\/""#))
                    payload = #"{"Token":"xsts-token","DisplayClaims":{"xui":[{"uhs":"uhs-token"}]}}"#
                case "https://api.minecraftservices.com/authentication/login_with_xbox":
                    #expect(body.contains("XBL3.0 x=uhs-token;xsts-token"))
                    payload = #"{"access_token":"minecraft-access","expires_in":7200}"#
                case "https://api.minecraftservices.com/entitlements/mcstore":
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer minecraft-access")
                    payload = #"{"items":[{"name":"game_minecraft"}]}"#
                case "https://api.minecraftservices.com/minecraft/profile":
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer minecraft-access")
                    payload = #"{"id":"00000000000000000000000000000000","name":"Alex","skins":[]}"#
                default:
                    Issue.record("Unexpected URL: \(url.absoluteString)")
                    payload = #"{}"#
                }

                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (Data(payload.utf8), response)
            }
        }

        let http = MockHTTP()
        let service = MicrosoftMinecraftLoginService(clientID: "client-id") { request in
            try http.respond(to: request)
        }

        let result = try await service.loginWithRefreshToken("refresh-one")

        #expect(http.calls.map(\.url) == [
            "https://login.live.com/oauth20_token.srf",
            "https://user.auth.xboxlive.com/user/authenticate",
            "https://xsts.auth.xboxlive.com/xsts/authorize",
            "https://api.minecraftservices.com/authentication/login_with_xbox",
            "https://api.minecraftservices.com/entitlements/mcstore",
            "https://api.minecraftservices.com/minecraft/profile"
        ])
        #expect(result.profile.id == "microsoft:00000000000000000000000000000000")
        #expect(result.profile.displayName == "Alex")
        #expect(result.profile.playerUUID == "00000000000000000000000000000000")
        #expect(result.secret.accessToken == "minecraft-access")
        #expect(result.secret.refreshToken == "refresh-two")
        #expect(result.minecraftProfileJSON.contains(#""skins":[]"#))
    }

    @Test func authenticatesAuthlibAndRefreshesSelectedProfile() async throws {
        final class MockHTTP: @unchecked Sendable {
            var calls: [(url: String, body: String)] = []

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                calls.append((url.absoluteString, body))
                let payload: String
                switch url.absoluteString {
                case "https://skin.example.com/authserver/authenticate":
                    #expect(body.contains(#""username":"user@example.com""#))
                    #expect(body.contains(#""password":"password""#))
                    payload = """
                    {
                      "accessToken": "access-one",
                      "clientToken": "client-one",
                      "availableProfiles": [
                        {"id":"profile-a","name":"Alex"},
                        {"id":"profile-b","name":"Steve"}
                      ]
                    }
                    """
                case "https://skin.example.com/authserver/refresh":
                    #expect(body.contains(#""id":"profile-b""#))
                    payload = """
                    {
                      "accessToken": "access-two",
                      "clientToken": "client-two",
                      "selectedProfile": {"id":"profile-b","name":"Steve"},
                      "availableProfiles": [
                        {"id":"profile-b","name":"Steve"}
                      ]
                    }
                    """
                default:
                    Issue.record("Unexpected Authlib URL: \(url.absoluteString)")
                    payload = "{}"
                }
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (Data(payload.utf8), response)
            }
        }

        let http = MockHTTP()
        let service = AuthlibLoginService { request in
            try http.respond(to: request)
        }

        let result = try await service.login(
            AuthlibLoginRequest(
                serverURL: URL(string: "https://skin.example.com/authserver")!,
                username: "user@example.com",
                password: "password",
                preferredProfileID: "profile-b"
            )
        )

        #expect(http.calls.map(\.url) == [
            "https://skin.example.com/authserver/authenticate",
            "https://skin.example.com/authserver/refresh"
        ])
        #expect(result.profile.kind == .authlib)
        #expect(result.profile.displayName == "Steve")
        #expect(result.profile.playerUUID == "profile-b")
        #expect(result.profile.serverURL?.absoluteString == "https://skin.example.com/authserver")
        #expect(result.secret.accessToken == "access-two")
        #expect(result.secret.clientToken == "client-two")
        #expect(result.secret.password == "password")
    }

    @Test func authenticatesNideWithDedicatedAccountKind() async throws {
        final class MockHTTP: @unchecked Sendable {
            var calls: [(url: String, body: String)] = []

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                calls.append((url.absoluteString, body))
                #expect(url.absoluteString == "https://auth.mc-user.com:233/server-id/authserver/authenticate")
                #expect(body.contains(#""username":"nide@example.com""#))
                #expect(body.contains(#""password":"password""#))
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (
                    Data(#"{"accessToken":"access","clientToken":"client","selectedProfile":{"id":"profile-id","name":"Alex"},"availableProfiles":[{"id":"profile-id","name":"Alex"}]}"#.utf8),
                    response
                )
            }
        }

        let http = MockHTTP()
        let service = AuthlibLoginService { request in
            try http.respond(to: request)
        }

        let result = try await service.login(
            AuthlibLoginRequest(
                serverURL: URL(string: "https://auth.mc-user.com:233/server-id/authserver")!,
                username: "nide@example.com",
                password: "password",
                accountKind: .nide
            )
        )

        #expect(http.calls.count == 1)
        #expect(result.profile.id == "nide:https://auth.mc-user.com:233/server-id/authserver:profile-id")
        #expect(result.profile.kind == .nide)
        #expect(result.profile.displayName == "Alex")
        #expect(result.profile.serverURL?.absoluteString == "https://auth.mc-user.com:233/server-id/authserver")
        #expect(result.secret.accessToken == "access")
        #expect(result.secret.clientToken == "client")
        #expect(result.secret.username == "nide@example.com")
        #expect(result.secret.password == "password")
    }

    @Test func preparesAuthlibInjectorJarAndPrefetchMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacAuthlibInjectorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jarData = Data("jar-bytes".utf8)
        let digest = SHA256.hash(data: jarData).map { String(format: "%02x", $0) }.joined()
        final class MockLoader: @unchecked Sendable {
            let jarData: Data
            let digest: String
            var urls: [String] = []

            init(jarData: Data, digest: String) {
                self.jarData = jarData
                self.digest = digest
            }

            func load(_ url: URL) throws -> Data {
                urls.append(url.absoluteString)
                switch url.absoluteString {
                case "https://authlib-injector.yushi.moe/artifact/latest.json":
                    return Data(#"{"download_url":"https://download.example.com/authlib-injector.jar","checksums":{"sha256":"\#(digest)"}}"#.utf8)
                case "https://download.example.com/authlib-injector.jar":
                    return jarData
                case "https://skin.example.com":
                    return Data(#"{"meta":{"serverName":"Skin Server"}}"#.utf8)
                default:
                    Issue.record("Unexpected URL: \(url.absoluteString)")
                    return Data()
                }
            }
        }
        let loader = MockLoader(jarData: jarData, digest: digest)
        let manager = AuthlibInjectorManager { url in
            try loader.load(url)
        }

        let configuration = try await manager.prepare(
            authserverURL: URL(string: "https://skin.example.com/authserver")!,
            appSupportDirectory: root
        )

        #expect(loader.urls == [
            "https://authlib-injector.yushi.moe/artifact/latest.json",
            "https://download.example.com/authlib-injector.jar",
            "https://skin.example.com"
        ])
        #expect(FileManager.default.fileExists(atPath: configuration.jarURL.path))
        #expect(configuration.serverURL.absoluteString == "https://skin.example.com")
        #expect(configuration.prefetchedMetadata.contains("Skin Server"))
    }

    @Test func preparesNideInjectorJarFromPCLServerMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacNideInjectorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jarData = Data("nide-jar-bytes".utf8)
        let digest = Insecure.SHA1.hash(data: jarData).map { String(format: "%02x", $0) }.joined()
        final class MockLoader: @unchecked Sendable {
            let jarData: Data
            let digest: String
            var urls: [String] = []

            init(jarData: Data, digest: String) {
                self.jarData = jarData
                self.digest = digest
            }

            func load(_ url: URL) throws -> Data {
                urls.append(url.absoluteString)
                switch url.absoluteString {
                case "https://auth.mc-user.com:233/server-id":
                    return Data(#"{"jarHash":"\#(digest)"}"#.utf8)
                case "https://login.mc-user.com:233/index/jar":
                    return jarData
                default:
                    Issue.record("Unexpected Nide URL: \(url.absoluteString)")
                    return Data()
                }
            }
        }
        let loader = MockLoader(jarData: jarData, digest: digest)
        let manager = NideInjectorManager { url in
            try loader.load(url)
        }

        let configuration = try await manager.prepare(
            serverID: "/server-id/",
            appSupportDirectory: root
        )

        #expect(loader.urls == [
            "https://auth.mc-user.com:233/server-id",
            "https://login.mc-user.com:233/index/jar"
        ])
        #expect(configuration.serverID == "server-id")
        #expect(configuration.jarURL.path.hasSuffix("/tools/nide8auth.jar"))
        #expect(FileManager.default.fileExists(atPath: configuration.jarURL.path))
        #expect(manager.serverID(from: try manager.authserverURL(serverID: "server-id")) == "server-id")
    }

    @Test func fetchesRemoteVersionManifestWithInjectedLoader() async throws {
        let manifestURL = URL(string: "https://example.invalid/manifest.json")!
        let manifest = """
        {
          "latest": {
            "release": "1.20.1",
            "snapshot": "23w01a"
          },
          "versions": [
            {
              "id": "1.20.1",
              "type": "release",
              "url": "https://example.invalid/versions/1.20.1.json",
              "time": "2023-06-12T00:00:00+00:00",
              "releaseTime": "2023-06-12T00:00:00+00:00"
            }
          ]
        }
        """

        let installer = MinecraftVersionInstaller(manifestURL: manifestURL) { url in
            #expect(url == manifestURL)
            return Data(manifest.utf8)
        }

        let decoded = try await installer.fetchManifest()
        #expect(decoded.latest.release == "1.20.1")
        #expect(decoded.latest.snapshot == "23w01a")
        #expect(decoded.versions.first?.displayType == "正式版")
        #expect(decoded.versions.first?.url.absoluteString == "https://example.invalid/versions/1.20.1.json")
    }

    @Test func routesMinecraftDownloadsThroughConfiguredSource() async throws {
        let hybrid = MinecraftDownloadSource(preference: "官方 + BMCLAPI")
        let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
        let libraryURL = URL(string: "https://libraries.minecraft.net/com/mojang/brigadier/1.0.18/brigadier-1.0.18.jar")!
        let forgeURL = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml")!
        let assetURL = URL(string: "https://resources.download.minecraft.net/b6/b62ca8ec10d07e6bf5ac8dae0c8c1d2e6a1e3356")!
        let clientURL = URL(string: "https://piston-data.mojang.com/v1/objects/4e618f09a0c649dde3fdf829df443ce0b8831e65/client.jar")!

        #expect(hybrid.versionManifestURL.absoluteString == "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json")
        #expect(hybrid.candidates(for: manifestURL).map(\.absoluteString) == [
            "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json",
            "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
        ])
        #expect(hybrid.candidates(for: libraryURL).map(\.absoluteString) == [
            "https://bmclapi2.bangbang93.com/maven/com/mojang/brigadier/1.0.18/brigadier-1.0.18.jar",
            "https://libraries.minecraft.net/com/mojang/brigadier/1.0.18/brigadier-1.0.18.jar"
        ])
        #expect(hybrid.candidates(for: forgeURL).first?.absoluteString == "https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/maven-metadata.xml")
        #expect(hybrid.candidates(for: assetURL).first?.absoluteString == "https://bmclapi2.bangbang93.com/assets/b6/b62ca8ec10d07e6bf5ac8dae0c8c1d2e6a1e3356")
        #expect(hybrid.candidates(for: clientURL).first?.absoluteString == "https://bmclapi2.bangbang93.com/v1/objects/4e618f09a0c649dde3fdf829df443ce0b8831e65/client.jar")
        #expect(MinecraftDownloadSource(preference: "官方").candidates(for: libraryURL) == [libraryURL])

        final class AttemptRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var urls: [String] = []

            func load(_ url: URL) throws -> Data {
                try lock.withLock {
                    urls.append(url.absoluteString)
                    if urls.count == 1 {
                        throw URLError(.badServerResponse)
                    }
                    return Data("ok".utf8)
                }
            }
        }

        let recorder = AttemptRecorder()
        let data = try await hybrid.loadData(from: libraryURL) { url in
            try recorder.load(url)
        }
        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect(recorder.urls == [
            "https://bmclapi2.bangbang93.com/maven/com/mojang/brigadier/1.0.18/brigadier-1.0.18.jar",
            "https://libraries.minecraft.net/com/mojang/brigadier/1.0.18/brigadier-1.0.18.jar"
        ])
    }

    @Test func installsRemoteVersionJsonIntoMinecraftVersionsDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacVersionInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let versionURL = URL(string: "https://example.invalid/versions/1.20.1.json")!
        let version = MinecraftRemoteVersion(
            id: "1.20.1",
            type: "release",
            url: versionURL,
            time: "2023-06-12T00:00:00+00:00",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let versionJSON = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": []
        }
        """

        let installer = MinecraftVersionInstaller { url in
            #expect(url == versionURL)
            return Data(versionJSON.utf8)
        }

        let result = try await installer.install(version, minecraftDirectory: minecraft)
        #expect(result.jsonURL.path.hasSuffix("/minecraft/versions/1.20.1/1.20.1.json"))
        #expect(FileManager.default.fileExists(atPath: result.jsonURL.path))

        let installed = try JSONDecoder().decode(MinecraftVersionFile.self, from: Data(contentsOf: result.jsonURL))
        #expect(installed.id == "1.20.1")
        #expect(installed.mainClass == "net.minecraft.client.main.Main")
    }

    @Test func installsFabricProfileAndPlansMavenDependencies() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacFabricInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let versionURL = URL(string: "https://example.invalid/versions/1.20.1.json")!
        let version = MinecraftRemoteVersion(
            id: "1.20.1",
            type: "release",
            url: versionURL,
            time: "2023-06-12T00:00:00+00:00",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let vanillaJSON = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "downloads": {
            "client": {
              "url": "https://example.invalid/client.jar",
              "sha1": "client-sha1",
              "size": 123
            }
          },
          "libraries": []
        }
        """
        let fabricProfile = """
        {
          "id": "fabric-loader-0.19.3-1.20.1",
          "inheritsFrom": "1.20.1",
          "type": "release",
          "mainClass": "net.fabricmc.loader.impl.launch.knot.KnotClient",
          "arguments": {
            "jvm": ["-DFabricMcEmu= net.minecraft.client.main.Main "],
            "game": []
          },
          "libraries": [
            {
              "name": "net.fabricmc:fabric-loader:0.19.3",
              "url": "https://maven.fabricmc.net/",
              "sha1": "fabric-sha1",
              "size": 456
            }
          ]
        }
        """
        final class MockLoader: @unchecked Sendable {
            var urls: [String] = []
            let versionURL: String
            let vanillaJSON: String
            let fabricProfile: String

            init(versionURL: URL, vanillaJSON: String, fabricProfile: String) {
                self.versionURL = versionURL.absoluteString
                self.vanillaJSON = vanillaJSON
                self.fabricProfile = fabricProfile
            }

            func load(_ url: URL) -> Data {
                urls.append(url.absoluteString)
                switch url.absoluteString {
                case versionURL:
                    return Data(vanillaJSON.utf8)
                case "https://meta.fabricmc.net/v2/versions/loader/1.20.1":
                    return Data(#"[{"loader":{"version":"0.19.2","stable":false}},{"loader":{"version":"0.19.3","stable":true}}]"#.utf8)
                case "https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.19.3/profile/json":
                    return Data(fabricProfile.utf8)
                default:
                    Issue.record("Unexpected Fabric URL: \(url.absoluteString)")
                    return Data()
                }
            }
        }
        let loader = MockLoader(versionURL: versionURL, vanillaJSON: vanillaJSON, fabricProfile: fabricProfile)
        let installer = FabricVersionInstaller { url in
            loader.load(url)
        }

        let result = try await installer.install(version, minecraftDirectory: minecraft)

        #expect(loader.urls == [
            "https://example.invalid/versions/1.20.1.json",
            "https://meta.fabricmc.net/v2/versions/loader/1.20.1",
            "https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.19.3/profile/json"
        ])
        #expect(result.profileID == "fabric-loader-0.19.3-1.20.1")
        #expect(result.loaderVersion == "0.19.3")
        #expect(FileManager.default.fileExists(atPath: minecraft.appendingPathComponent("versions/1.20.1/1.20.1.json").path))
        #expect(FileManager.default.fileExists(atPath: result.jsonURL.path))

        let instance = MinecraftInstance(
            name: result.profileID,
            path: result.jsonURL.deletingLastPathComponent(),
            jsonURL: result.jsonURL,
            type: "release",
            releaseTime: "2026-06-10T00:00:00+00:00"
        )
        let request = MinecraftLaunchRequest(
            instance: instance,
            minecraftDirectory: minecraft,
            javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
            username: "Tester",
            memoryMegabytes: 2048,
            windowWidth: 854,
            windowHeight: 480
        )

        let chain = try MinecraftVersionRepository().loadVersionChain(instance: instance, minecraftDirectory: minecraft)
        let dependencies = try MinecraftDependencyDownloader().dependencyItems(from: chain, request: request)
        #expect(dependencies.contains {
            $0.name == "net.fabricmc:fabric-loader:0.19.3" &&
            $0.url.absoluteString == "https://maven.fabricmc.net/net/fabricmc/fabric-loader/0.19.3/fabric-loader-0.19.3.jar"
        })
        #expect(dependencies.contains { $0.name == "1.20.1.jar" })

        let command = try MinecraftLaunchBuilder().build(request: request)
        #expect(command.arguments.contains("net.fabricmc.loader.impl.launch.knot.KnotClient"))
        #expect(command.commandLinePreview.contains("/versions/1.20.1/1.20.1.jar"))
    }

    @Test func installsFabricProfileWithRequestedLoaderVersion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacFabricRequestedLoaderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let versionURL = URL(string: "https://example.invalid/versions/1.20.1.json")!
        let version = MinecraftRemoteVersion(
            id: "1.20.1",
            type: "release",
            url: versionURL,
            time: "2023-06-12T00:00:00+00:00",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        final class MockLoader: @unchecked Sendable {
            var urls: [String] = []
            let versionURL: String

            init(versionURL: URL) {
                self.versionURL = versionURL.absoluteString
            }

            func load(_ url: URL) -> Data {
                urls.append(url.absoluteString)
                switch url.absoluteString {
                case versionURL:
                    return Data(#"{"id":"1.20.1","type":"release","libraries":[]}"#.utf8)
                case "https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.15.11/profile/json":
                    return Data("""
                    {
                      "id": "fabric-loader-0.15.11-1.20.1",
                      "inheritsFrom": "1.20.1",
                      "type": "release",
                      "mainClass": "net.fabricmc.loader.impl.launch.knot.KnotClient",
                      "libraries": []
                    }
                    """.utf8)
                default:
                    Issue.record("Unexpected Fabric URL: \(url.absoluteString)")
                    return Data()
                }
            }
        }

        let loader = MockLoader(versionURL: versionURL)
        let result = try await FabricVersionInstaller { url in
            loader.load(url)
        }.install(version, loaderVersion: "0.15.11", minecraftDirectory: minecraft)

        #expect(loader.urls == [
            "https://example.invalid/versions/1.20.1.json",
            "https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.15.11/profile/json"
        ])
        #expect(result.loaderVersion == "0.15.11")
        #expect(result.profileID == "fabric-loader-0.15.11-1.20.1")
    }

    @Test func installsQuiltProfileAndPrefersStableLoader() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacQuiltInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let versionURL = URL(string: "https://example.invalid/versions/1.20.1.json")!
        let version = MinecraftRemoteVersion(
            id: "1.20.1",
            type: "release",
            url: versionURL,
            time: "2023-06-12T00:00:00+00:00",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let vanillaJSON = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "downloads": {
            "client": {
              "url": "https://example.invalid/client.jar",
              "sha1": "client-sha1",
              "size": 123
            }
          },
          "libraries": []
        }
        """
        let quiltProfile = """
        {
          "id": "quilt-loader-0.27.0-1.20.1",
          "inheritsFrom": "1.20.1",
          "type": "release",
          "mainClass": "org.quiltmc.loader.impl.launch.knot.KnotClient",
          "arguments": {
            "game": []
          },
          "libraries": [
            {
              "name": "org.quiltmc:quilt-loader:0.27.0",
              "url": "https://maven.quiltmc.org/repository/release/"
            }
          ]
        }
        """
        final class MockLoader: @unchecked Sendable {
            var urls: [String] = []
            let versionURL: String
            let vanillaJSON: String
            let quiltProfile: String

            init(versionURL: URL, vanillaJSON: String, quiltProfile: String) {
                self.versionURL = versionURL.absoluteString
                self.vanillaJSON = vanillaJSON
                self.quiltProfile = quiltProfile
            }

            func load(_ url: URL) -> Data {
                urls.append(url.absoluteString)
                switch url.absoluteString {
                case versionURL:
                    return Data(vanillaJSON.utf8)
                case "https://meta.quiltmc.org/v3/versions/loader/1.20.1":
                    return Data(#"[{"loader":{"version":"0.29.2-beta.5"}},{"loader":{"version":"0.27.0"}},{"loader":{"version":"0.20.0-beta.9"}}]"#.utf8)
                case "https://meta.quiltmc.org/v3/versions/loader/1.20.1/0.27.0/profile/json":
                    return Data(quiltProfile.utf8)
                default:
                    Issue.record("Unexpected Quilt URL: \(url.absoluteString)")
                    return Data()
                }
            }
        }
        let loader = MockLoader(versionURL: versionURL, vanillaJSON: vanillaJSON, quiltProfile: quiltProfile)
        let installer = QuiltVersionInstaller { url in
            loader.load(url)
        }

        let result = try await installer.install(version, minecraftDirectory: minecraft)

        #expect(loader.urls == [
            "https://example.invalid/versions/1.20.1.json",
            "https://meta.quiltmc.org/v3/versions/loader/1.20.1",
            "https://meta.quiltmc.org/v3/versions/loader/1.20.1/0.27.0/profile/json"
        ])
        #expect(result.profileID == "quilt-loader-0.27.0-1.20.1")
        #expect(result.loaderVersion == "0.27.0")
        #expect(FileManager.default.fileExists(atPath: result.jsonURL.path))

        let instance = MinecraftInstance(
            name: result.profileID,
            path: result.jsonURL.deletingLastPathComponent(),
            jsonURL: result.jsonURL,
            type: "release",
            releaseTime: "2026-06-10T00:00:00+00:00"
        )
        let request = MinecraftLaunchRequest(
            instance: instance,
            minecraftDirectory: minecraft,
            javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
            username: "Tester",
            memoryMegabytes: 2048,
            windowWidth: 854,
            windowHeight: 480
        )

        let chain = try MinecraftVersionRepository().loadVersionChain(instance: instance, minecraftDirectory: minecraft)
        let dependencies = try MinecraftDependencyDownloader().dependencyItems(from: chain, request: request)
        #expect(dependencies.contains {
            $0.name == "org.quiltmc:quilt-loader:0.27.0" &&
            $0.url.absoluteString == "https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-loader/0.27.0/quilt-loader-0.27.0.jar"
        })
        #expect(dependencies.contains { $0.name == "1.20.1.jar" })

        let command = try MinecraftLaunchBuilder().build(request: request)
        #expect(command.arguments.contains("org.quiltmc.loader.impl.launch.knot.KnotClient"))
        #expect(command.commandLinePreview.contains("/versions/1.20.1/1.20.1.jar"))
    }

    @Test func installsForgeViaMavenInstallerJar() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacForgeInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        let versionURL = URL(string: "https://example.invalid/versions/1.20.1.json")!
        let version = MinecraftRemoteVersion(
            id: "1.20.1",
            type: "release",
            url: versionURL,
            time: "2023-06-12T00:00:00+00:00",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let vanillaJSON = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": []
        }
        """
        let metadata = """
        <metadata>
          <versioning>
            <versions>
              <version>1.20.1-47.4.18</version>
              <version>1.20.1-47.4.20</version>
              <version>1.19.4-45.2.0</version>
            </versions>
          </versioning>
        </metadata>
        """
        final class MockForge: @unchecked Sendable {
            var urls: [String] = []
            var runRequests: [ForgeLikeInstallerRunRequest] = []
            let versionURL: String
            let vanillaJSON: String
            let metadata: String
            let minecraft: URL

            init(versionURL: URL, vanillaJSON: String, metadata: String, minecraft: URL) {
                self.versionURL = versionURL.absoluteString
                self.vanillaJSON = vanillaJSON
                self.metadata = metadata
                self.minecraft = minecraft
            }

            func load(_ url: URL) -> Data {
                urls.append(url.absoluteString)
                switch url.absoluteString {
                case versionURL:
                    return Data(vanillaJSON.utf8)
                case "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml":
                    return Data(metadata.utf8)
                case "https://maven.minecraftforge.net/net/minecraftforge/forge/1.20.1-47.4.20/forge-1.20.1-47.4.20-installer.jar":
                    return Data("forge-installer".utf8)
                default:
                    Issue.record("Unexpected Forge URL: \(url.absoluteString)")
                    return Data()
                }
            }

            func run(_ request: ForgeLikeInstallerRunRequest) throws -> ForgeLikeInstallerRunResult {
                runRequests.append(request)
                let profileID = "1.20.1-forge-47.4.20"
                let profileDirectory = minecraft.appendingPathComponent("versions/\(profileID)", isDirectory: true)
                try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
                try """
                {
                  "id": "\(profileID)",
                  "inheritsFrom": "1.20.1",
                  "mainClass": "net.minecraftforge.bootstrap.BootstrapLauncher",
                  "libraries": [
                    {"name":"net.minecraftforge:forge:1.20.1-47.4.20"}
                  ]
                }
                """.write(to: profileDirectory.appendingPathComponent("\(profileID).json"), atomically: true, encoding: .utf8)
                let logURL = minecraft.appendingPathComponent("logs/forge-installer.log")
                try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: logURL)
                return ForgeLikeInstallerRunResult(terminationStatus: 0, logURL: logURL)
            }
        }
        let mock = MockForge(versionURL: versionURL, vanillaJSON: vanillaJSON, metadata: metadata, minecraft: minecraft)
        let installer = ForgeLikeVersionInstaller(
            provider: .forge,
            dataLoader: { url in mock.load(url) },
            processRunner: { request in try mock.run(request) }
        )

        let result = try await installer.install(
            version,
            minecraftDirectory: minecraft,
            javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
            appSupportDirectory: appSupport
        )

        #expect(mock.urls == [
            "https://example.invalid/versions/1.20.1.json",
            "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml",
            "https://maven.minecraftforge.net/net/minecraftforge/forge/1.20.1-47.4.20/forge-1.20.1-47.4.20-installer.jar"
        ])
        #expect(mock.runRequests.count == 1)
        #expect(mock.runRequests[0].arguments == ["--installClient"])
        #expect(mock.runRequests[0].javaExecutable.path == "/usr/bin/java")
        #expect(result.profileID == "1.20.1-forge-47.4.20")
        #expect(result.loaderVersion == "1.20.1-47.4.20")
        #expect(result.displayLoaderVersion == "47.4.20")
        #expect(FileManager.default.fileExists(atPath: result.installerJarURL.path))
    }

    @Test func installsNeoForgeViaMavenInstallerJar() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacNeoForgeInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let appSupport = root.appendingPathComponent("support", isDirectory: true)
        let versionURL = URL(string: "https://example.invalid/versions/1.20.2.json")!
        let version = MinecraftRemoteVersion(
            id: "1.20.2",
            type: "release",
            url: versionURL,
            time: "2023-09-21T00:00:00+00:00",
            releaseTime: "2023-09-21T00:00:00+00:00"
        )
        let vanillaJSON = """
        {
          "id": "1.20.2",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": []
        }
        """
        let metadata = """
        <metadata>
          <versioning>
            <versions>
              <version>20.2.93</version>
              <version>20.2.94-beta</version>
              <version>20.1.10</version>
            </versions>
          </versioning>
        </metadata>
        """
        final class MockNeoForge: @unchecked Sendable {
            var urls: [String] = []
            var runRequests: [ForgeLikeInstallerRunRequest] = []
            let versionURL: String
            let vanillaJSON: String
            let metadata: String
            let minecraft: URL

            init(versionURL: URL, vanillaJSON: String, metadata: String, minecraft: URL) {
                self.versionURL = versionURL.absoluteString
                self.vanillaJSON = vanillaJSON
                self.metadata = metadata
                self.minecraft = minecraft
            }

            func load(_ url: URL) -> Data {
                urls.append(url.absoluteString)
                switch url.absoluteString {
                case versionURL:
                    return Data(vanillaJSON.utf8)
                case "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml":
                    return Data(metadata.utf8)
                case "https://maven.neoforged.net/releases/net/neoforged/neoforge/20.2.93/neoforge-20.2.93-installer.jar":
                    return Data("neoforge-installer".utf8)
                default:
                    Issue.record("Unexpected NeoForge URL: \(url.absoluteString)")
                    return Data()
                }
            }

            func run(_ request: ForgeLikeInstallerRunRequest) throws -> ForgeLikeInstallerRunResult {
                runRequests.append(request)
                let profileID = "neoforge-20.2.93"
                let profileDirectory = minecraft.appendingPathComponent("versions/\(profileID)", isDirectory: true)
                try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
                try """
                {
                  "id": "\(profileID)",
                  "inheritsFrom": "1.20.2",
                  "mainClass": "cpw.mods.bootstraplauncher.BootstrapLauncher",
                  "arguments": {"game": ["--fml.neoForgeVersion", "20.2.93"]},
                  "libraries": [
                    {"name":"net.neoforged:neoforge:20.2.93"}
                  ]
                }
                """.write(to: profileDirectory.appendingPathComponent("\(profileID).json"), atomically: true, encoding: .utf8)
                let logURL = minecraft.appendingPathComponent("logs/neoforge-installer.log")
                try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: logURL)
                return ForgeLikeInstallerRunResult(terminationStatus: 0, logURL: logURL)
            }
        }
        let mock = MockNeoForge(versionURL: versionURL, vanillaJSON: vanillaJSON, metadata: metadata, minecraft: minecraft)
        let installer = ForgeLikeVersionInstaller(
            provider: .neoForge,
            dataLoader: { url in mock.load(url) },
            processRunner: { request in try mock.run(request) }
        )

        let result = try await installer.install(
            version,
            minecraftDirectory: minecraft,
            javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
            appSupportDirectory: appSupport
        )

        #expect(mock.urls == [
            "https://example.invalid/versions/1.20.2.json",
            "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml",
            "https://maven.neoforged.net/releases/net/neoforged/neoforge/20.2.93/neoforge-20.2.93-installer.jar"
        ])
        #expect(mock.runRequests.count == 1)
        #expect(mock.runRequests[0].arguments == ["--install-client"])
        #expect(result.profileID == "neoforge-20.2.93")
        #expect(result.loaderVersion == "20.2.93")
        #expect(result.displayLoaderVersion == "20.2.93")
        #expect(FileManager.default.fileExists(atPath: result.installerJarURL.path))
    }

    @Test func buildsMacOfflineLaunchCommandFromVersionJson() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)

        let json = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "assets": "5",
          "arguments": {
            "jvm": [
              {"rules":[{"action":"allow","os":{"name":"osx"}}],"value":["-XstartOnFirstThread"]},
              "-Djava.library.path=${natives_directory}",
              "-cp",
              "${classpath}"
            ],
            "game": [
              "--username", "${auth_player_name}",
              "--version", "${version_name}",
              "--gameDir", "${game_directory}",
              "--assetsDir", "${assets_root}",
              "--assetIndex", "${assets_index_name}",
              "--uuid", "${auth_uuid}",
              "--accessToken", "${auth_access_token}",
              "--userType", "${user_type}"
            ]
          },
          "libraries": [
            {
              "name": "com.example:example-lib:1.0",
              "downloads": {
                "artifact": {
                  "path": "com/example/example-lib/1.0/example-lib-1.0.jar"
                }
              }
            },
            {
              "name": "org.lwjgl:lwjgl:3.3.1",
              "natives": {"osx": "natives-macos"},
              "downloads": {
                "classifiers": {
                  "natives-macos": {
                    "path": "org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1-natives-macos.jar"
                  }
                }
              }
            }
          ]
        }
        """
        try json.write(to: version.appendingPathComponent("1.20.1.json"), atomically: true, encoding: .utf8)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: version.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                username: "Tester",
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480
            )
        )

        #expect(command.arguments.contains("net.minecraft.client.main.Main"))
        #expect(command.arguments.contains("Tester"))
        #expect(command.arguments.contains("-XstartOnFirstThread"))
        #expect(command.arguments.contains { $0.contains("1.20.1-natives") })
        #expect(command.commandLinePreview.contains(":"))
        #expect(command.commandLinePreview.contains("--assetIndex 5"))
        #expect(command.workingDirectory == version)
        let defaultGameDirIndex = try #require(command.arguments.firstIndex(of: "--gameDir"))
        #expect(command.arguments[defaultGameDirIndex + 1] == version.path)
    }

    @Test func launchCommandCanUseSharedMinecraftGameDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacSharedGameDirTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "arguments": {
            "game": ["--gameDir", "${game_directory}", "--username", "${auth_player_name}"]
          },
          "libraries": []
        }
        """.utf8).write(to: version.appendingPathComponent("1.20.1.json"))

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: version.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )

        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                username: "Tester",
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480,
                gameDirectory: minecraft
            )
        )

        let gameDirIndex = try #require(command.arguments.firstIndex(of: "--gameDir"))
        #expect(command.arguments[gameDirIndex + 1] == minecraft.path)
        #expect(command.workingDirectory == minecraft)
    }

    @Test func launchCommandAppendsServerAddressWhenConfigured() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacServerLaunchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "arguments": {
            "game": ["--username", "${auth_player_name}"]
          },
          "libraries": []
        }
        """.utf8).write(to: version.appendingPathComponent("1.20.1.json"))

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: version.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )

        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                username: "Tester",
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480,
                serverAddress: " play.example.com ",
                serverPort: 25566
            )
        )

        let mainIndex = try #require(command.arguments.firstIndex(of: "net.minecraft.client.main.Main"))
        let serverIndex = try #require(command.arguments.firstIndex(of: "--server"))
        let portIndex = try #require(command.arguments.firstIndex(of: "--port"))
        #expect(serverIndex > mainIndex)
        #expect(command.arguments[serverIndex + 1] == "play.example.com")
        #expect(command.arguments[portIndex + 1] == "25566")
    }

    @Test func launchCommandParsesServerAddressWithPort() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacServerAddressPortTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "arguments": {
            "game": ["--username", "${auth_player_name}"]
          },
          "libraries": []
        }
        """.utf8).write(to: version.appendingPathComponent("1.20.1.json"))

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: version.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )

        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                username: "Tester",
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480,
                serverAddress: "play.example.com:25567"
            )
        )

        let serverIndex = try #require(command.arguments.firstIndex(of: "--server"))
        let portIndex = try #require(command.arguments.firstIndex(of: "--port"))
        #expect(command.arguments[serverIndex + 1] == "play.example.com")
        #expect(command.arguments[portIndex + 1] == "25567")
    }

    @Test func inheritedProfileUsesParentAssetIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacInheritedAssetsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let versions = minecraft.appendingPathComponent("versions", isDirectory: true)
        let parent = versions.appendingPathComponent("1.20.1", isDirectory: true)
        let child = versions.appendingPathComponent("Adventure-Pack-1.0.0", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "assets": "5",
          "arguments": {
            "jvm": ["-cp", "${classpath}"],
            "game": ["--assetIndex", "${assets_index_name}"]
          },
          "libraries": []
        }
        """.utf8).write(to: parent.appendingPathComponent("1.20.1.json"))
        try Data("""
        {
          "id": "Adventure-Pack-1.0.0",
          "type": "release",
          "inheritsFrom": "1.20.1",
          "libraries": []
        }
        """.utf8).write(to: child.appendingPathComponent("Adventure-Pack-1.0.0.json"))

        let instance = MinecraftInstance(
            name: "Adventure-Pack-1.0.0",
            path: child,
            jsonURL: child.appendingPathComponent("Adventure-Pack-1.0.0.json"),
            type: "release",
            releaseTime: "2026-06-10T00:00:00+00:00"
        )
        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                username: "Tester",
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480
            )
        )

        #expect(command.commandLinePreview.contains("--assetIndex 5"))
        #expect(!command.commandLinePreview.contains("--assetIndex Adventure-Pack-1.0.0"))
    }

    @Test func buildsMicrosoftLaunchCommandWithAccountIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacMicrosoftLaunchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "arguments": {
            "game": [
              "--username", "${auth_player_name}",
              "--uuid", "${auth_uuid}",
              "--accessToken", "${auth_access_token}",
              "--userType", "${user_type}"
            ]
          },
          "libraries": []
        }
        """.write(to: version.appendingPathComponent("1.20.1.json"), atomically: true, encoding: .utf8)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: version.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                identity: .init(
                    username: "Alex",
                    uuid: "00000000000000000000000000000000",
                    accessToken: "minecraft-access",
                    userType: "msa"
                ),
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480
            )
        )

        #expect(command.arguments.contains("Alex"))
        #expect(command.arguments.contains("00000000000000000000000000000000"))
        #expect(command.arguments.contains("minecraft-access"))
        #expect(command.arguments.contains("msa"))
    }

    @Test func buildsAuthlibLaunchCommandWithInjectorArguments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacAuthlibLaunchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "arguments": {
            "jvm": ["-cp", "${classpath}"],
            "game": [
              "--username", "${auth_player_name}",
              "--uuid", "${auth_uuid}",
              "--accessToken", "${auth_access_token}",
              "--userType", "${user_type}"
            ]
          },
          "libraries": []
        }
        """.write(to: version.appendingPathComponent("1.20.1.json"), atomically: true, encoding: .utf8)
        let jarURL = root.appendingPathComponent("tools/authlib-injector.jar")
        try FileManager.default.createDirectory(at: jarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: jarURL)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: version.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                identity: .init(
                    username: "Steve",
                    uuid: "profile-b",
                    accessToken: "authlib-access",
                    userType: "msa",
                    clientToken: "authlib-client"
                ),
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480,
                authlibInjector: AuthlibInjectorConfiguration(
                    jarURL: jarURL,
                    serverURL: URL(string: "https://skin.example.com")!,
                    prefetchedMetadata: #"{"meta":{"serverName":"Skin Server"}}"#
                )
            )
        )

        #expect(command.arguments.contains("-javaagent:\(jarURL.path)=https://skin.example.com"))
        #expect(command.arguments.contains("-Dauthlibinjector.side=client"))
        #expect(command.arguments.contains { $0.hasPrefix("-Dauthlibinjector.yggdrasil.prefetched=") })
        #expect(command.arguments.contains("authlib-access"))
        #expect(command.arguments.contains("msa"))
    }

    @Test func buildsNideLaunchCommandWithInjectorArgument() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacNideLaunchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "arguments": {
            "jvm": ["-cp", "${classpath}"],
            "game": [
              "--username", "${auth_player_name}",
              "--uuid", "${auth_uuid}",
              "--accessToken", "${auth_access_token}",
              "--userType", "${user_type}"
            ]
          },
          "libraries": []
        }
        """.write(to: version.appendingPathComponent("1.20.1.json"), atomically: true, encoding: .utf8)
        let jarURL = root.appendingPathComponent("tools/nide8auth.jar")
        try FileManager.default.createDirectory(at: jarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: jarURL)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: version.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                identity: .init(
                    username: "Alex",
                    uuid: "profile-id",
                    accessToken: "nide-access",
                    userType: "msa",
                    clientToken: "nide-client"
                ),
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480,
                nideInjector: NideInjectorConfiguration(
                    jarURL: jarURL,
                    serverID: "server-id"
                )
            )
        )

        #expect(command.arguments.contains("-javaagent:\(jarURL.path)=server-id"))
        #expect(command.arguments.contains("nide-access"))
        #expect(command.arguments.contains("msa"))
    }

    @Test func buildsDependencyDownloadPlanForClientLibrariesAndAssets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacDependencyTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)

        let json = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "assetIndex": {
            "id": "5",
            "url": "https://example.invalid/indexes/5.json",
            "sha1": "abc",
            "size": 100
          },
          "downloads": {
            "client": {
              "url": "https://example.invalid/client.jar",
              "sha1": "def",
              "size": 200
            }
          },
          "libraries": [
            {
              "name": "com.example:example-lib:1.0",
              "downloads": {
                "artifact": {
                  "path": "com/example/example-lib/1.0/example-lib-1.0.jar",
                  "url": "https://example.invalid/example-lib-1.0.jar",
                  "sha1": "111",
                  "size": 300
                }
              }
            },
            {
              "name": "org.lwjgl:lwjgl:3.3.1",
              "natives": {"osx": "natives-macos"},
              "downloads": {
                "classifiers": {
                  "natives-macos": {
                    "path": "org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1-natives-macos.jar",
                    "url": "https://example.invalid/lwjgl-3.3.1-natives-macos.jar",
                    "sha1": "222",
                    "size": 400
                  }
                }
              }
            }
          ]
        }
        """
        let jsonURL = version.appendingPathComponent("1.20.1.json")
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)
        let indexURL = minecraft
            .appendingPathComponent("assets/indexes", isDirectory: true)
            .appendingPathComponent("5.json")
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "objects": {
            "minecraft/sounds/random/test.ogg": {
              "hash": "1234567890abcdef1234567890abcdef12345678",
              "size": 12
            }
          }
        }
        """.write(to: indexURL, atomically: true, encoding: .utf8)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: jsonURL,
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let request = MinecraftLaunchRequest(
            instance: instance,
            minecraftDirectory: minecraft,
            javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
            username: "Tester",
            memoryMegabytes: 2048,
            windowWidth: 854,
            windowHeight: 480
        )

        let downloader = MinecraftDependencyDownloader()
        let dependencies = try downloader.dependencyItems(from: try MinecraftVersionRepository().loadVersionChain(instance: instance, minecraftDirectory: minecraft), request: request)
        let dependencyNames = Set(dependencies.map(\.name))
        #expect(dependencyNames.contains("1.20.1.jar"))
        #expect(dependencyNames.contains("com.example:example-lib:1.0"))
        #expect(dependencyNames.contains("org.lwjgl:lwjgl:3.3.1"))
        #expect(dependencyNames.contains("assets-index-5"))

        let assets = try downloader.assetItems(from: try MinecraftVersionRepository().loadVersionChain(instance: instance, minecraftDirectory: minecraft), request: request)
        #expect(assets.count == 1)
        #expect(assets[0].url.absoluteString == "https://resources.download.minecraft.net/12/1234567890abcdef1234567890abcdef12345678")
        #expect(assets[0].destination.path.hasSuffix("/assets/objects/12/1234567890abcdef1234567890abcdef12345678"))

        let mirroredDownloader = MinecraftDependencyDownloader(downloadSource: .officialAndBMCLAPI)
        let mirroredAssets = try mirroredDownloader.assetItems(from: try MinecraftVersionRepository().loadVersionChain(instance: instance, minecraftDirectory: minecraft), request: request)
        #expect(mirroredAssets[0].url.absoluteString == "https://bmclapi2.bangbang93.com/assets/12/1234567890abcdef1234567890abcdef12345678")
        #expect(mirroredAssets[0].fallbackURLs.map(\.absoluteString) == [
            "https://resources.download.minecraft.net/12/1234567890abcdef1234567890abcdef12345678"
        ])
    }

    @Test func dependencyDownloaderUsesFastExistingFileCheckByDefault() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacDependencyFastPathTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = root.appendingPathComponent("libraries/example.jar")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("already here".utf8).write(to: destination)

        let item = MinecraftDownloadItem(
            id: "example",
            name: "example.jar",
            url: URL(string: "https://example.invalid/example.jar")!,
            fallbackURLs: [],
            destination: destination,
            sha1: "0000000000000000000000000000000000000000",
            size: 12
        )

        let fastDownloader = MinecraftDependencyDownloader(validateExistingFileHashes: false)
        #expect(try await fastDownloader.isSatisfied(item))

        let strictDownloader = MinecraftDependencyDownloader(validateExistingFileHashes: true)
        #expect(try await strictDownloader.isSatisfied(item) == false)

        let wrongSizeItem = MinecraftDownloadItem(
            id: "example-wrong-size",
            name: "example.jar",
            url: item.url,
            fallbackURLs: [],
            destination: destination,
            sha1: item.sha1,
            size: 13
        )
        #expect(try await fastDownloader.isSatisfied(wrongSizeItem) == false)
    }

    @Test func dependencyDownloaderReportsDownloadedAndSkippedProgress() async throws {
        final class ProgressSink: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var updates: [MinecraftDownloadProgress] = []

            func append(_ progress: MinecraftDownloadProgress) {
                lock.withLock {
                    updates.append(progress)
                }
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacDependencyProgressTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)

        let existingLibrary = minecraft
            .appendingPathComponent("libraries", isDirectory: true)
            .appendingPathComponent("com/example/example-lib/1.0/example-lib-1.0.jar")
        try FileManager.default.createDirectory(at: existingLibrary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("library".utf8).write(to: existingLibrary)

        let clientData = Data("client".utf8)
        let clientSHA1 = Insecure.SHA1.hash(data: clientData).map { String(format: "%02x", $0) }.joined()
        let json = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "downloads": {
            "client": {
              "url": "https://example.invalid/client.jar",
              "sha1": "\(clientSHA1)",
              "size": \(clientData.count)
            }
          },
          "libraries": [
            {
              "name": "com.example:example-lib:1.0",
              "downloads": {
                "artifact": {
                  "path": "com/example/example-lib/1.0/example-lib-1.0.jar",
                  "url": "https://example.invalid/example-lib-1.0.jar",
                  "sha1": "",
                  "size": 7
                }
              }
            }
          ]
        }
        """
        let jsonURL = version.appendingPathComponent("1.20.1.json")
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: jsonURL,
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let request = MinecraftLaunchRequest(
            instance: instance,
            minecraftDirectory: minecraft,
            javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
            username: "Tester",
            memoryMegabytes: 2048,
            windowWidth: 854,
            windowHeight: 480
        )

        let sink = ProgressSink()
        let downloader = MinecraftDependencyDownloader(
            maximumConcurrentDownloads: 1,
            itemDownloader: { item, _ in
                try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try clientData.write(to: item.destination)
            }
        )
        let summary = try await downloader.prepareDependencies(request: request) { progress in
            sink.append(progress)
        }

        #expect(summary.downloaded == 1)
        #expect(summary.skipped == 1)
        #expect(summary.total == 2)
        #expect(sink.updates.count == 2)
        #expect(sink.updates[0].action == .skipped)
        #expect(sink.updates[0].skipped == 1)
        #expect(sink.updates[1].action == .downloaded)
        #expect(sink.updates[1].downloaded == 1)
        #expect(sink.updates[1].finished == 2)
        #expect(sink.updates[1].fraction == 1)
    }

    @Test func dependencyDownloaderSkipsExistingFilesWithConcurrentChecks() async throws {
        final class ProgressSink: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var updates: [MinecraftDownloadProgress] = []

            func append(_ progress: MinecraftDownloadProgress) {
                lock.withLock {
                    updates.append(progress)
                }
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacDependencyConcurrentSkipTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let version = minecraft
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)

        let libraries = [
            ("com.example:alpha:1.0", "com/example/alpha/1.0/alpha-1.0.jar", "alpha"),
            ("com.example:beta:1.0", "com/example/beta/1.0/beta-1.0.jar", "beta"),
            ("com.example:gamma:1.0", "com/example/gamma/1.0/gamma-1.0.jar", "gamma")
        ]
        for (_, path, contents) in libraries {
            let destination = minecraft.appendingPathComponent("libraries", isDirectory: true).appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: destination)
        }

        let libraryJSON = libraries.map { name, path, contents in
            """
                {
                  "name": "\(name)",
                  "downloads": {
                    "artifact": {
                      "path": "\(path)",
                      "url": "https://example.invalid/\(path)",
                      "sha1": "",
                      "size": \(Data(contents.utf8).count)
                    }
                  }
                }
            """
        }.joined(separator: ",")
        let json = """
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "net.minecraft.client.main.Main",
          "libraries": [
        \(libraryJSON)
          ]
        }
        """
        let jsonURL = version.appendingPathComponent("1.20.1.json")
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: version,
            jsonURL: jsonURL,
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let request = MinecraftLaunchRequest(
            instance: instance,
            minecraftDirectory: minecraft,
            javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
            username: "Tester",
            memoryMegabytes: 2048,
            windowWidth: 854,
            windowHeight: 480
        )

        let sink = ProgressSink()
        let downloader = MinecraftDependencyDownloader(
            maximumConcurrentDownloads: 3,
            itemDownloader: { item, _ in
                throw NSError(
                    domain: "PCLMacTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected download for \(item.name)"]
                )
            }
        )
        let summary = try await downloader.prepareDependencies(request: request) { progress in
            sink.append(progress)
        }

        #expect(summary.downloaded == 0)
        #expect(summary.skipped == 3)
        #expect(summary.total == 3)
        #expect(sink.updates.count == 3)
        #expect(Set(sink.updates.map(\.currentName)) == Set(libraries.map(\.0)))
        #expect(sink.updates.allSatisfy { $0.action == .skipped })
        #expect(sink.updates.map(\.finished).max() == 3)
    }

    @Test func dependencyProgressUpdateGateThrottlesSkippedFilesButKeepsImportantUpdates() async throws {
        let gate = DependencyProgressUpdateGate(minimumFinishedDelta: 4, minimumTimeInterval: 1)
        let start = Date(timeIntervalSince1970: 100)

        func progress(_ finished: Int, _ action: MinecraftDownloadProgress.Action = .skipped) -> MinecraftDownloadProgress {
            MinecraftDownloadProgress(
                finished: finished,
                total: 10,
                currentName: "asset-\(finished)",
                downloaded: action == .downloaded ? 1 : 0,
                skipped: action == .skipped ? finished : finished - 1,
                action: action
            )
        }

        #expect(await gate.shouldEmit(progress(1), now: start))
        #expect(await gate.shouldEmit(progress(2), now: start.addingTimeInterval(0.1)) == false)
        #expect(await gate.shouldEmit(progress(5), now: start.addingTimeInterval(0.2)))
        #expect(await gate.shouldEmit(progress(6), now: start.addingTimeInterval(0.3)) == false)
        #expect(await gate.shouldEmit(progress(7), now: start.addingTimeInterval(1.4)))
        #expect(await gate.shouldEmit(progress(8, .downloaded), now: start.addingTimeInterval(1.5)))
        #expect(await gate.shouldEmit(progress(10), now: start.addingTimeInterval(1.6)))
    }

    @Test func javaRuntimeProgressUpdateGateThrottlesFileUpdatesButKeepsCompletion() async throws {
        let gate = JavaRuntimeProgressUpdateGate(minimumFinishedDelta: 4, minimumTimeInterval: 1)
        let start = Date(timeIntervalSince1970: 100)

        func progress(_ finished: Int) -> MojangJavaRuntimeInstallProgress {
            MojangJavaRuntimeInstallProgress(
                finished: finished,
                total: 10,
                currentName: "runtime-file-\(finished)",
                downloaded: finished,
                skipped: 0
            )
        }

        #expect(await gate.shouldEmit(progress(1), now: start))
        #expect(await gate.shouldEmit(progress(2), now: start.addingTimeInterval(0.1)) == false)
        #expect(await gate.shouldEmit(progress(5), now: start.addingTimeInterval(0.2)))
        #expect(await gate.shouldEmit(progress(6), now: start.addingTimeInterval(0.3)) == false)
        #expect(await gate.shouldEmit(progress(7), now: start.addingTimeInterval(1.4)))
        #expect(await gate.shouldEmit(progress(10), now: start.addingTimeInterval(1.5)))
    }

    @Test func storesVersionLaunchSettingsBesideInstance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacVersionSettingsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let instanceDirectory = root.appendingPathComponent("versions/1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        let instance = MinecraftInstance(
            name: "1.20.1",
            path: instanceDirectory,
            jsonURL: instanceDirectory.appendingPathComponent("1.20.1.json"),
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let store = VersionLaunchSettingsStore(fileName: "settings.json")
        let settings = VersionLaunchSettings(
            usesGlobalJava: false,
            javaExecutablePath: " /Library/Java/Test/bin/java ",
            usesGlobalMemory: false,
            memoryMegabytes: 99999,
            usesGlobalWindow: false,
            windowWidth: 99999,
            windowHeight: 100,
            fullscreen: true,
            usesGlobalGameDirectory: false,
            usesIsolatedGameDirectory: false,
            usesGlobalServer: false,
            serverAddress: " play.example.com ",
            serverPort: "65536",
            extraJvmArguments: #" -Dfoo="bar baz" "#,
            extraGameArguments: #" --server "local host" "#
        )

        try store.save(settings, for: instance)
        let loaded = store.load(for: instance)

        #expect(loaded.usesGlobalJava == false)
        #expect(loaded.javaExecutablePath == "/Library/Java/Test/bin/java")
        #expect(loaded.memoryMegabytes == 32768)
        #expect(loaded.usesGlobalWindow == false)
        #expect(loaded.windowWidth == 7680)
        #expect(loaded.windowHeight == 240)
        #expect(loaded.fullscreen == true)
        #expect(loaded.usesGlobalGameDirectory == false)
        #expect(loaded.usesIsolatedGameDirectory == false)
        #expect(loaded.usesGlobalServer == false)
        #expect(loaded.serverAddress == "play.example.com")
        #expect(loaded.serverPort == nil)
        #expect(loaded.extraJvmArgumentList == ["-Dfoo=bar baz"])
        #expect(loaded.extraGameArgumentList == ["--server", "local host"])

        try store.reset(for: instance)
        #expect(store.load(for: instance) == .defaults)
    }

    @Test func launchBuilderAppliesVersionExtraArguments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacVersionArgumentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let instanceDirectory = minecraft.appendingPathComponent("versions/1.20.1", isDirectory: true)
        try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        let jsonURL = instanceDirectory.appendingPathComponent("1.20.1.json")
        try Data("""
        {
          "id": "1.20.1",
          "type": "release",
          "mainClass": "com.example.Main",
          "arguments": {
            "game": ["--username", "${auth_player_name}"]
          },
          "libraries": []
        }
        """.utf8).write(to: jsonURL)

        let instance = MinecraftInstance(
            name: "1.20.1",
            path: instanceDirectory,
            jsonURL: jsonURL,
            type: "release",
            releaseTime: "2023-06-12T00:00:00+00:00"
        )
        let command = try MinecraftLaunchBuilder().build(
            request: MinecraftLaunchRequest(
                instance: instance,
                minecraftDirectory: minecraft,
                javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
                username: "Tester",
                memoryMegabytes: 2048,
                windowWidth: 854,
                windowHeight: 480,
                fullscreen: true,
                extraJvmArguments: ["-Ddemo=hello world"],
                extraGameArguments: ["--server", "local host"]
            )
        )

        let mainIndex = try #require(command.arguments.firstIndex(of: "com.example.Main"))
        let jvmIndex = try #require(command.arguments.firstIndex(of: "-Ddemo=hello world"))
        let fullscreenIndex = try #require(command.arguments.firstIndex(of: "--fullscreen"))
        let gameIndex = try #require(command.arguments.firstIndex(of: "--server"))
        #expect(jvmIndex < mainIndex)
        #expect(fullscreenIndex > mainIndex)
        #expect(gameIndex > mainIndex)
        #expect(command.arguments.contains("local host"))
    }

    @Test func buildsModrinthSearchAndVersionURLsWithFacets() throws {
        let service = ModrinthResourceService(baseURL: URL(string: "https://api.modrinth.com/v2")!) { _ in
            Issue.record("HTTP should not be called")
            return (Data(), HTTPURLResponse())
        }

        let searchURL = try service.searchURL(
            ModrinthSearchRequest(
                query: "fabric api",
                minecraftVersion: "1.20.1",
                loader: "Fabric",
                limit: 120
            )
        )
        let searchComponents = try #require(URLComponents(url: searchURL, resolvingAgainstBaseURL: false))
        let searchItems = Dictionary(uniqueKeysWithValues: (searchComponents.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(searchURL.absoluteString.hasPrefix("https://api.modrinth.com/v2/search?"))
        #expect(searchItems["query"] == "fabric api")
        #expect(searchItems["index"] == "downloads")
        #expect(searchItems["limit"] == "100")
        #expect(searchItems["facets"]?.contains(#""project_type:mod""#) == true)
        #expect(searchItems["facets"]?.contains(#""versions:1.20.1""#) == true)
        #expect(searchItems["facets"]?.contains(#""categories:fabric""#) == true)

        let versionsURL = try service.versionsURL(projectID: "P7dR8mSH", minecraftVersion: "1.20.1", loader: "fabric")
        let versionComponents = try #require(URLComponents(url: versionsURL, resolvingAgainstBaseURL: false))
        let versionItems = Dictionary(uniqueKeysWithValues: (versionComponents.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(versionsURL.absoluteString.hasPrefix("https://api.modrinth.com/v2/project/P7dR8mSH/version?"))
        #expect(versionItems["game_versions"] == #"["1.20.1"]"#)
        #expect(versionItems["loaders"] == #"["fabric"]"#)
    }

    @Test func buildsModrinthProjectDetailsForDisplay() {
        let project = ModrinthProject(
            projectID: "P7dR8mSH",
            slug: "fabric-api",
            title: "Fabric API",
            description: "Core API module",
            projectType: "mod",
            downloads: 12_345_678,
            follows: 42_000,
            author: "modmuss50",
            iconURL: URL(string: "https://cdn.example/icon.png"),
            latestVersion: "1.0.0",
            versions: ["1.21.1", "1.21", "1.20.6", "1.20.5", "1.20.4", "1.20.3"],
            categories: ["fabric", "library", "utility", "api", "quilt", "client"]
        )

        #expect(project.websiteURL(projectType: .mod)?.absoluteString == "https://modrinth.com/mod/fabric-api")
        #expect(project.versionSummary == "1.21.1, 1.21, 1.20.6, 1.20.5, 1.20.4")
        #expect(project.categorySummary == "fabric, library, utility, api, quilt")
        let summary = project.detailSummary(projectType: .mod)
        #expect(summary.contains("来源：Modrinth Mod"))
        #expect(summary.contains("作者：modmuss50"))
        #expect(summary.contains("https://modrinth.com/mod/fabric-api"))
    }

    @Test func decodesModrinthProjectWithEmptyIconURL() throws {
        let response = try JSONDecoder().decode(ModrinthSearchResponse.self, from: Data("""
        {
          "hits": [
            {
              "project_id": "message-api",
              "slug": "message-api",
              "title": "Message API",
              "description": "A project with an empty icon URL",
              "project_type": "mod",
              "downloads": 1,
              "follows": 0,
              "author": "tester",
              "icon_url": "",
              "latest_version": null,
              "versions": ["1.20.1"],
              "categories": ["fabric"]
            }
          ],
          "total_hits": 1
        }
        """.utf8))

        #expect(response.hits.first?.iconURL == nil)
        #expect(response.hits.first?.title == "Message API")
    }

    @Test func buildsModrinthVersionFilePreview() throws {
        let versions = try JSONDecoder().decode([ModrinthVersion].self, from: Data("""
        [
          {
            "id": "version-1",
            "name": "Fabric API 1.0.0",
            "version_number": "1.0.0",
            "version_type": "beta",
            "game_versions": ["1.20.1", "1.20"],
            "loaders": ["fabric", "quilt"],
            "files": [
              {
                "hashes": {"sha1": "abc"},
                "url": "https://cdn.example/fabric-api-sources.jar",
                "filename": "fabric-api-sources.jar",
                "primary": false,
                "size": 12
              },
              {
                "hashes": {"sha1": "def"},
                "url": "https://cdn.example/fabric-api.jar",
                "filename": "fabric-api.jar",
                "primary": true,
                "size": 34
              }
            ]
          }
        ]
        """.utf8))

        let previews = ResourceVersionFilePreview.modrinth(versions: versions, projectType: .mod)

        #expect(previews.count == 2)
        #expect(previews.first?.fileName == "fabric-api.jar")
        #expect(previews.first?.releaseType == "Beta")
        #expect(previews.first?.versionSummary == "1.20.1, 1.20")
        #expect(previews.first?.loaderSummary == "fabric, quilt")
        #expect(previews.first?.isPrimary == true)
    }

    @Test func buildsModrinthResourcePackSearchWithoutLoaderFacet() throws {
        let service = ModrinthResourceService(baseURL: URL(string: "https://api.modrinth.com/v2")!) { _ in
            Issue.record("HTTP should not be called")
            return (Data(), HTTPURLResponse())
        }

        let searchURL = try service.searchURL(
            ModrinthSearchRequest(
                projectType: .resourcepack,
                query: "faithful",
                minecraftVersion: "1.21.5",
                loader: "fabric",
                limit: 20
            )
        )
        let searchComponents = try #require(URLComponents(url: searchURL, resolvingAgainstBaseURL: false))
        let searchItems = Dictionary(uniqueKeysWithValues: (searchComponents.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(searchItems["facets"]?.contains(#""project_type:resourcepack""#) == true)
        #expect(searchItems["facets"]?.contains(#""versions:1.21.5""#) == true)
        #expect(searchItems["facets"]?.contains("categories:fabric") == false)
    }

    @Test func buildsModrinthDatapackSearchWithoutLoaderFacet() throws {
        let service = ModrinthResourceService(baseURL: URL(string: "https://api.modrinth.com/v2")!) { _ in
            Issue.record("HTTP should not be called")
            return (Data(), HTTPURLResponse())
        }

        let searchURL = try service.searchURL(
            ModrinthSearchRequest(
                projectType: .datapack,
                query: "terralith",
                minecraftVersion: "1.21.5",
                loader: "fabric",
                limit: 20
            )
        )
        let searchComponents = try #require(URLComponents(url: searchURL, resolvingAgainstBaseURL: false))
        let searchItems = Dictionary(uniqueKeysWithValues: (searchComponents.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(searchItems["facets"]?.contains(#""project_type:datapack""#) == true)
        #expect(searchItems["facets"]?.contains(#""versions:1.21.5""#) == true)
        #expect(searchItems["facets"]?.contains("categories:fabric") == false)
    }

    @Test func buildsCurseForgeSearchURLsAndSendsAPIKeyHeader() async throws {
        final class MockHTTP: @unchecked Sendable {
            var requests: [URLRequest] = []

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                requests.append(request)
                let body = Data("""
                {
                  "data": [
                    {
                      "id": 238222,
                      "gameId": 432,
                      "name": "Just Enough Items",
                      "slug": "jei",
                      "summary": "Recipe viewer",
                      "downloadCount": 12345,
                      "classId": 6,
                      "authors": [{"id": 1, "name": "mezz", "url": "https://example.invalid/mezz"}],
                      "logo": null
                    }
                  ],
                  "pagination": {"index": 0, "pageSize": 30, "resultCount": 1, "totalCount": 1}
                }
                """.utf8)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (body, response)
            }
        }

        let mock = MockHTTP()
        let service = CurseForgeResourceService(baseURL: URL(string: "https://api.curseforge.com/v1")!) {
            try mock.respond(to: $0)
        }

        let response = try await service.searchResources(
            CurseForgeSearchRequest(
                apiKey: "secret-key",
                resourceType: .mod,
                query: "jei",
                minecraftVersion: "1.20.1",
                loader: "Fabric",
                pageSize: 99
            )
        )

        let request = try #require(mock.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(url.absoluteString.hasPrefix("https://api.curseforge.com/v1/mods/search?"))
        #expect(queryItems["gameId"] == "432")
        #expect(queryItems["classId"] == "6")
        #expect(queryItems["searchFilter"] == "jei")
        #expect(queryItems["gameVersion"] == "1.20.1")
        #expect(queryItems["modLoaderType"] == "4")
        #expect(queryItems["pageSize"] == "50")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret-key")
        #expect(response.data.first?.name == "Just Enough Items")

        let filesURL = service.filesURL(modID: 238222, minecraftVersion: "1.20.1", loader: "NeoForge", pageSize: 100)
        let fileComponents = try #require(URLComponents(url: filesURL, resolvingAgainstBaseURL: false))
        let fileItems = Dictionary(uniqueKeysWithValues: (fileComponents.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(filesURL.path == "/v1/mods/238222/files")
        #expect(fileItems["gameVersion"] == "1.20.1")
        #expect(fileItems["modLoaderType"] == "6")
        #expect(fileItems["pageSize"] == "50")
    }

    @Test func buildsCurseForgeProjectDetailsForDisplay() {
        let project = CurseForgeProject(
            id: 238222,
            gameID: 432,
            name: "Just Enough Items",
            slug: "jei",
            summary: "Recipe viewer",
            downloadCount: 98_765_432,
            classID: 6,
            authors: [
                CurseForgeAuthor(id: 1, name: "mezz", url: URL(string: "https://example.com/mezz")),
                CurseForgeAuthor(id: 2, name: "CFGrafanaStats", url: nil)
            ],
            logo: nil
        )

        #expect(project.websiteURL(resourceType: .mod)?.absoluteString == "https://www.curseforge.com/minecraft/mc-mods/jei")
        #expect(project.authorSummary == "mezz, CFGrafanaStats")
        let summary = project.detailSummary(resourceType: .mod)
        #expect(summary.contains("来源：CurseForge Mod"))
        #expect(summary.contains("下载：98,765,432"))
        #expect(summary.contains("https://www.curseforge.com/minecraft/mc-mods/jei"))
    }

    @Test func buildsCurseForgeFilePreview() throws {
        let files = try JSONDecoder().decode([CurseForgeFile].self, from: Data("""
        [
          {
            "id": 1,
            "modId": 238222,
            "displayName": "JEI 1.20.1",
            "fileName": "jei-1.20.1.jar",
            "fileLength": 12345,
            "downloadUrl": "https://cdn.example/jei.jar",
            "hashes": [],
            "gameVersions": ["1.20.1", "Fabric"],
            "releaseType": 1
          },
          {
            "id": 2,
            "modId": 238222,
            "displayName": "JEI docs",
            "fileName": "jei-docs.txt",
            "fileLength": 10,
            "downloadUrl": null,
            "hashes": [],
            "gameVersions": ["1.20.1"],
            "releaseType": 2
          }
        ]
        """.utf8))

        let previews = ResourceVersionFilePreview.curseForge(files: files, resourceType: .mod)

        #expect(previews.count == 1)
        #expect(previews.first?.fileName == "jei-1.20.1.jar")
        #expect(previews.first?.releaseType == "Release")
        #expect(previews.first?.versionSummary == "1.20.1, Fabric")
        #expect(previews.first?.loaderSummary == "Fabric")
    }

    @Test func installsLatestCurseForgeJarIntoInstanceModsFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacCurseForgeInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jarData = Data("curseforge-mod-jar".utf8)
        let sha1 = Insecure.SHA1.hash(data: jarData).map { String(format: "%02x", $0) }.joined()

        final class MockHTTP: @unchecked Sendable {
            let jarData: Data
            let sha1: String
            var requests: [URLRequest] = []

            init(jarData: Data, sha1: String) {
                self.jarData = jarData
                self.sha1 = sha1
            }

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                requests.append(request)
                let url = try #require(request.url)
                let body: Data
                if url.path == "/v1/mods/238222/files" {
                    body = Data("""
                    {
                      "data": [
                        {
                          "id": 67890,
                          "modId": 238222,
                          "displayName": "JEI 1.20.1",
                          "fileName": "jei-1.20.1.jar",
                          "fileLength": \(jarData.count),
                          "downloadUrl": "https://cdn.example.invalid/jei-1.20.1.jar",
                          "hashes": [{"value": "\(sha1)", "algo": 1}],
                          "gameVersions": ["1.20.1", "Fabric"],
                          "releaseType": 1
                        }
                      ],
                      "pagination": {"index": 0, "pageSize": 20, "resultCount": 1, "totalCount": 1}
                    }
                    """.utf8)
                } else if url.absoluteString == "https://cdn.example.invalid/jei-1.20.1.jar" {
                    body = jarData
                } else {
                    Issue.record("Unexpected URL: \\(url.absoluteString)")
                    body = Data()
                }
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (body, response)
            }
        }

        let mock = MockHTTP(jarData: jarData, sha1: sha1)
        let service = CurseForgeResourceService(baseURL: URL(string: "https://api.curseforge.com/v1")!) {
            try mock.respond(to: $0)
        }
        let project = CurseForgeProject(
            id: 238222,
            gameID: 432,
            name: "Just Enough Items",
            slug: "jei",
            summary: "Recipe viewer",
            downloadCount: 12345,
            classID: 6,
            authors: [CurseForgeAuthor(id: 1, name: "mezz", url: nil)],
            logo: nil
        )
        let destination = root.appendingPathComponent("mods", isDirectory: true)

        let result = try await service.installLatestResource(
            project: project,
            resourceType: .mod,
            apiKey: "secret-key",
            minecraftVersion: "1.20.1",
            loader: "fabric",
            destinationDirectory: destination
        )

        #expect(result.destination.lastPathComponent == "jei-1.20.1.jar")
        #expect(try Data(contentsOf: result.destination) == jarData)
        #expect(mock.requests.first?.value(forHTTPHeaderField: "x-api-key") == "secret-key")
        #expect(mock.requests.last?.value(forHTTPHeaderField: "x-api-key") == nil)
    }

    @Test func installsSelectedCurseForgeFileIntoDestinationFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacCurseForgeSelectedFileTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let selectedData = Data("selected-curseforge-jar".utf8)
        let sha1 = Insecure.SHA1.hash(data: selectedData).map { String(format: "%02x", $0) }.joined()
        final class MockHTTP: @unchecked Sendable {
            let data: Data
            var requestedURLs: [String] = []

            init(data: Data) {
                self.data = data
            }

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                requestedURLs.append(url.absoluteString)
                return (
                    data,
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        }

        let mock = MockHTTP(data: selectedData)
        let service = CurseForgeResourceService(baseURL: URL(string: "https://api.curseforge.com/v1")!) {
            try mock.respond(to: $0)
        }
        let project = CurseForgeProject(
            id: 238222,
            gameID: 432,
            name: "Just Enough Items",
            slug: "jei",
            summary: "Recipe viewer",
            downloadCount: 12345,
            classID: 6,
            authors: [],
            logo: nil
        )
        let file = CurseForgeFile(
            id: 2,
            modID: 238222,
            displayName: "JEI selected",
            fileName: "jei-selected.jar",
            fileLength: selectedData.count,
            downloadURLString: "https://cdn.example.invalid/jei-selected.jar",
            hashes: [CurseForgeFileHash(value: sha1, algo: 1)],
            gameVersions: ["1.20.1", "Fabric"],
            releaseType: 1,
            modules: nil
        )

        let result = try await service.installResourceFile(
            project: project,
            file: file,
            resourceType: .mod,
            apiKey: "secret-key",
            destinationDirectory: root.appendingPathComponent("mods", isDirectory: true)
        )

        #expect(mock.requestedURLs == ["https://cdn.example.invalid/jei-selected.jar"])
        #expect(result.destination.lastPathComponent == "jei-selected.jar")
        #expect(try Data(contentsOf: result.destination) == selectedData)
    }

    @Test func installsLatestModrinthJarIntoInstanceModsFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacModrinthInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let instance = root.appendingPathComponent("versions/fabric-loader-0.19.3-1.20.1", isDirectory: true)
        let jarData = Data("mod-jar".utf8)
        let sha1 = Insecure.SHA1.hash(data: jarData).map { String(format: "%02x", $0) }.joined()
        final class MockHTTP: @unchecked Sendable {
            let jarData: Data
            let sha1: String
            var calls: [(url: String, userAgent: String?)] = []

            init(jarData: Data, sha1: String) {
                self.jarData = jarData
                self.sha1 = sha1
            }

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                calls.append((url.absoluteString, request.value(forHTTPHeaderField: "User-Agent")))
                let body: Data
                switch url.absoluteString {
                case #"https://api.modrinth.com/v2/project/fabric-api/version?game_versions=%5B%221.20.1%22%5D&loaders=%5B%22fabric%22%5D"#:
                    body = Data("""
                    [
                      {
                        "id": "version-id",
                        "name": "Fabric API",
                        "version_number": "0.100.0+1.20.1",
                        "game_versions": ["1.20.1"],
                        "loaders": ["fabric"],
                        "files": [
                          {
                            "hashes": {"sha1": "\(sha1)"},
                            "url": "https://cdn.modrinth.com/data/fabric-api.jar",
                            "filename": "fabric-api.jar",
                            "primary": true,
                            "size": \(jarData.count)
                          }
                        ]
                      }
                    ]
                    """.utf8)
                case "https://cdn.modrinth.com/data/fabric-api.jar":
                    body = jarData
                default:
                    Issue.record("Unexpected Modrinth URL: \(url.absoluteString)")
                    body = Data()
                }
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (body, response)
            }
        }
        let http = MockHTTP(jarData: jarData, sha1: sha1)
        let service = ModrinthResourceService { request in
            try http.respond(to: request)
        }

        let result = try await service.installLatestMod(
            project: nil,
            projectID: "fabric-api",
            minecraftVersion: "1.20.1",
            loader: "fabric",
            instanceDirectory: instance
        )

        #expect(http.calls.map(\.url) == [
            #"https://api.modrinth.com/v2/project/fabric-api/version?game_versions=%5B%221.20.1%22%5D&loaders=%5B%22fabric%22%5D"#,
            "https://cdn.modrinth.com/data/fabric-api.jar"
        ])
        #expect(http.calls.allSatisfy { $0.userAgent?.hasPrefix("PCLMac/") == true })
        #expect(result.destination.path.hasSuffix("/versions/fabric-loader-0.19.3-1.20.1/mods/fabric-api.jar"))
        #expect(try Data(contentsOf: result.destination) == jarData)
    }

    @Test func installsSelectedModrinthFileIntoDestinationFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacModrinthSelectedFileTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let selectedData = Data("selected-modrinth-jar".utf8)
        let sha1 = Insecure.SHA1.hash(data: selectedData).map { String(format: "%02x", $0) }.joined()
        final class MockHTTP: @unchecked Sendable {
            let data: Data
            var requestedURLs: [String] = []

            init(data: Data) {
                self.data = data
            }

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                requestedURLs.append(url.absoluteString)
                return (
                    data,
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        }

        let mock = MockHTTP(data: selectedData)
        let service = ModrinthResourceService {
            try mock.respond(to: $0)
        }
        let version = ModrinthVersion(
            id: "version-id",
            name: "Fabric API",
            versionNumber: "0.100.0+1.20.1",
            versionType: "release",
            gameVersions: ["1.20.1"],
            loaders: ["fabric"],
            files: []
        )
        let file = ModrinthFile(
            hashes: ModrinthFileHashes(sha1: sha1),
            url: URL(string: "https://cdn.modrinth.com/data/fabric-api-selected.jar")!,
            filename: "fabric-api-selected.jar",
            primary: false,
            size: selectedData.count
        )

        let result = try await service.installResourceFile(
            project: nil,
            version: version,
            file: file,
            projectType: .mod,
            destinationDirectory: root.appendingPathComponent("mods", isDirectory: true)
        )

        #expect(mock.requestedURLs == ["https://cdn.modrinth.com/data/fabric-api-selected.jar"])
        #expect(result.destination.lastPathComponent == "fabric-api-selected.jar")
        #expect(try Data(contentsOf: result.destination) == selectedData)
    }

    @Test func installsModrinthResourcePackZipIntoDestinationFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacResourcePackInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let packData = Data("resource-pack".utf8)
        let sha1 = Insecure.SHA1.hash(data: packData).map { String(format: "%02x", $0) }.joined()
        final class MockHTTP: @unchecked Sendable {
            let packData: Data
            let sha1: String
            var calls: [String] = []

            init(packData: Data, sha1: String) {
                self.packData = packData
                self.sha1 = sha1
            }

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                calls.append(url.absoluteString)
                let body: Data
                switch url.absoluteString {
                case #"https://api.modrinth.com/v2/project/faithful/version?game_versions=%5B%221.21.5%22%5D"#:
                    body = Data("""
                    [
                      {
                        "id": "version-id",
                        "name": "Faithful",
                        "version_number": "1.0.0",
                        "game_versions": ["1.21.5"],
                        "loaders": ["minecraft"],
                        "files": [
                          {
                            "hashes": {"sha1": "\(sha1)"},
                            "url": "https://cdn.modrinth.com/data/faithful.zip",
                            "filename": "Faithful.zip",
                            "primary": true,
                            "size": \(packData.count)
                          }
                        ]
                      }
                    ]
                    """.utf8)
                case "https://cdn.modrinth.com/data/faithful.zip":
                    body = packData
                default:
                    Issue.record("Unexpected Modrinth URL: \(url.absoluteString)")
                    body = Data()
                }
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (body, response)
            }
        }
        let http = MockHTTP(packData: packData, sha1: sha1)
        let service = ModrinthResourceService { request in
            try http.respond(to: request)
        }

        let result = try await service.installLatestResource(
            project: nil,
            projectID: "faithful",
            projectType: .resourcepack,
            minecraftVersion: "1.21.5",
            loader: "fabric",
            destinationDirectory: root.appendingPathComponent("resourcepacks", isDirectory: true)
        )

        #expect(http.calls == [
            #"https://api.modrinth.com/v2/project/faithful/version?game_versions=%5B%221.21.5%22%5D"#,
            "https://cdn.modrinth.com/data/faithful.zip"
        ])
        #expect(result.destination.path.hasSuffix("/resourcepacks/Faithful.zip"))
        #expect(try Data(contentsOf: result.destination) == packData)
    }

    @Test func installsModrinthDatapackZipIntoDestinationFolder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacDatapackInstallTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let packData = Data("datapack".utf8)
        let sha1 = Insecure.SHA1.hash(data: packData).map { String(format: "%02x", $0) }.joined()
        final class MockHTTP: @unchecked Sendable {
            let packData: Data
            let sha1: String
            var calls: [String] = []

            init(packData: Data, sha1: String) {
                self.packData = packData
                self.sha1 = sha1
            }

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                calls.append(url.absoluteString)
                let body: Data
                switch url.absoluteString {
                case #"https://api.modrinth.com/v2/project/terralith/version?game_versions=%5B%221.21.5%22%5D"#:
                    body = Data("""
                    [
                      {
                        "id": "version-id",
                        "name": "Terralith",
                        "version_number": "1.0.0",
                        "game_versions": ["1.21.5"],
                        "loaders": ["datapack"],
                        "files": [
                          {
                            "hashes": {"sha1": "\(sha1)"},
                            "url": "https://cdn.modrinth.com/data/terralith.zip",
                            "filename": "Terralith.zip",
                            "primary": true,
                            "size": \(packData.count)
                          }
                        ]
                      }
                    ]
                    """.utf8)
                case "https://cdn.modrinth.com/data/terralith.zip":
                    body = packData
                default:
                    Issue.record("Unexpected Modrinth URL: \(url.absoluteString)")
                    body = Data()
                }
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (body, response)
            }
        }
        let http = MockHTTP(packData: packData, sha1: sha1)
        let service = ModrinthResourceService { request in
            try http.respond(to: request)
        }

        let result = try await service.installLatestResource(
            project: nil,
            projectID: "terralith",
            projectType: .datapack,
            minecraftVersion: "1.21.5",
            loader: "fabric",
            destinationDirectory: root.appendingPathComponent("datapacks", isDirectory: true)
        )

        #expect(http.calls == [
            #"https://api.modrinth.com/v2/project/terralith/version?game_versions=%5B%221.21.5%22%5D"#,
            "https://cdn.modrinth.com/data/terralith.zip"
        ])
        #expect(result.destination.path.hasSuffix("/datapacks/Terralith.zip"))
        #expect(try Data(contentsOf: result.destination) == packData)
    }

    @Test func inspectsValidModrinthPackManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacMrpackInspectTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("overrides", isDirectory: true), withIntermediateDirectories: true)
        try Data("fullscreen:false".utf8).write(to: source.appendingPathComponent("overrides/options.txt"))
        try Data("""
        {
          "formatVersion": 1,
          "game": "minecraft",
          "versionId": "1.0.0",
          "name": "Adventure Pack",
          "summary": "A test pack",
          "files": [
            {
              "path": "mods/example.jar",
              "hashes": {"sha1": "abc"},
              "downloads": ["https://cdn.example/mod.jar"],
              "fileSize": 3
            }
          ],
          "dependencies": {
            "minecraft": "1.20.1",
            "fabric-loader": "0.15.11"
          }
        }
        """.utf8).write(to: source.appendingPathComponent("modrinth.index.json"))

        let pack = root.appendingPathComponent("pack.mrpack")
        try makeZipArchive(from: source, to: pack)

        let plan = try ModrinthPackInspector().inspect(pack, importRoot: root.appendingPathComponent("import", isDirectory: true))
        #expect(plan.name == "Adventure Pack")
        #expect(plan.versionID == "1.0.0")
        #expect(plan.minecraftVersion == "1.20.1")
        #expect(plan.loaderSummary == "Fabric 0.15.11")
        #expect(plan.fileCount == 1)
        #expect(plan.overrideEntryCount == 1)
    }

    @Test func detectsModrinthPackFileExtensionCaseInsensitively() {
        #expect(isModrinthPackFileURL(URL(fileURLWithPath: "/tmp/Pack.mrpack")))
        #expect(isModrinthPackFileURL(URL(fileURLWithPath: "/tmp/Pack.MRPACK")))
        #expect(!isModrinthPackFileURL(URL(fileURLWithPath: "/tmp/Pack.zip")))
    }

    @Test func importsModrinthPackIntoIndependentInstance() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacMrpackImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("overrides/config", isDirectory: true), withIntermediateDirectories: true)
        try Data("configured=true".utf8).write(to: source.appendingPathComponent("overrides/config/example.toml"))

        let modData = Data("client-mod".utf8)
        let modSha1 = Insecure.SHA1.hash(data: modData).map { String(format: "%02x", $0) }.joined()
        try Data("""
        {
          "formatVersion": 1,
          "game": "minecraft",
          "versionId": "1.0.0",
          "name": "Adventure Pack",
          "files": [
            {
              "path": "mods/example.jar",
              "hashes": {"sha1": "\(modSha1)"},
              "downloads": ["https://cdn.example/mod.jar"],
              "fileSize": \(modData.count),
              "env": {"client": "required", "server": "required"}
            },
            {
              "path": "mods/server-only.jar",
              "hashes": {"sha1": "0000000000000000000000000000000000000000"},
              "downloads": ["https://cdn.example/server-only.jar"],
              "fileSize": 3,
              "env": {"client": "unsupported", "server": "required"}
            }
          ],
          "dependencies": {
            "minecraft": "1.20.1",
            "fabric-loader": "0.15.11"
          }
        }
        """.utf8).write(to: source.appendingPathComponent("modrinth.index.json"))

        let pack = root.appendingPathComponent("pack.mrpack")
        try makeZipArchive(from: source, to: pack)

        final class MockDataLoader: @unchecked Sendable {
            let modData: Data
            var urls: [String] = []

            init(modData: Data) {
                self.modData = modData
            }

            func load(_ url: URL) -> Data {
                urls.append(url.absoluteString)
                if url.absoluteString == "https://cdn.example/mod.jar" {
                    return modData
                }
                Issue.record("Unexpected pack file URL: \(url.absoluteString)")
                return Data()
            }
        }
        let loader = MockDataLoader(modData: modData)
        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let result = try await ModrinthPackImporter { url in
            loader.load(url)
        }.importPack(
            pack,
            minecraftDirectory: minecraft,
            inheritedProfileID: "fabric-loader-0.15.11-1.20.1"
        )

        #expect(loader.urls == ["https://cdn.example/mod.jar"])
        #expect(result.instanceName == "Adventure-Pack-1.0.0")
        #expect(result.downloadedFiles == 1)
        #expect(result.skippedFiles == 0)
        #expect(result.copiedOverrides == 1)

        let instanceDirectory = minecraft.appendingPathComponent("versions/Adventure-Pack-1.0.0", isDirectory: true)
        #expect(try Data(contentsOf: instanceDirectory.appendingPathComponent("mods/example.jar")) == modData)
        #expect(!FileManager.default.fileExists(atPath: instanceDirectory.appendingPathComponent("mods/server-only.jar").path))
        #expect(try String(contentsOf: instanceDirectory.appendingPathComponent("config/example.toml"), encoding: .utf8) == "configured=true")

        let profileData = try Data(contentsOf: instanceDirectory.appendingPathComponent("Adventure-Pack-1.0.0.json"))
        let profile = try JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        #expect(profile?["id"] as? String == "Adventure-Pack-1.0.0")
        #expect(profile?["inheritsFrom"] as? String == "fabric-loader-0.15.11-1.20.1")

        let instances = await MinecraftInstanceScanner().scan(minecraftDirectory: minecraft)
        #expect(instances.contains { $0.name == "Adventure-Pack-1.0.0" })
    }

    @Test func inspectsValidCurseForgePackManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacCurseForgePackInspectTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("overrides/config", isDirectory: true), withIntermediateDirectories: true)
        try Data("configured=true".utf8).write(to: source.appendingPathComponent("overrides/config/example.toml"))
        try Data("""
        {
          "minecraft": {
            "version": "1.20.1",
            "modLoaders": [
              {"id": "fabric-0.15.11", "primary": true}
            ]
          },
          "manifestType": "minecraftModpack",
          "manifestVersion": 1,
          "name": "Curse Adventure",
          "version": "2.0.0",
          "author": "Tester",
          "files": [
            {"projectID": 238222, "fileID": 67890, "required": true},
            {"projectID": 238223, "fileID": 67891, "required": false}
          ],
          "overrides": "overrides"
        }
        """.utf8).write(to: source.appendingPathComponent("manifest.json"))

        let pack = root.appendingPathComponent("curse.zip")
        try makeZipArchive(from: source, to: pack)

        let plan = try CurseForgePackInspector().inspect(pack, importRoot: root.appendingPathComponent("import", isDirectory: true))
        #expect(plan.name == "Curse Adventure")
        #expect(plan.versionID == "2.0.0")
        #expect(plan.minecraftVersion == "1.20.1")
        #expect(plan.loaderSummary == "Fabric 0.15.11")
        #expect(plan.fileCount == 2)
        #expect(plan.requiredFileCount == 1)
        #expect(plan.overrideEntryCount == 1)
    }

    @Test func detectsCurseForgePackFileExtensionCaseInsensitively() {
        #expect(isCurseForgePackFileURL(URL(fileURLWithPath: "/tmp/Pack.zip")))
        #expect(isCurseForgePackFileURL(URL(fileURLWithPath: "/tmp/Pack.ZIP")))
        #expect(!isCurseForgePackFileURL(URL(fileURLWithPath: "/tmp/Pack.mrpack")))
    }

    @Test func importsCurseForgePackIntoIndependentInstance() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacCurseForgePackImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("overrides/config", isDirectory: true), withIntermediateDirectories: true)
        try Data("configured=true".utf8).write(to: source.appendingPathComponent("overrides/config/example.toml"))
        try Data("""
        {
          "minecraft": {
            "version": "1.20.1",
            "modLoaders": [
              {"id": "fabric-0.15.11", "primary": true}
            ]
          },
          "manifestType": "minecraftModpack",
          "manifestVersion": 1,
          "name": "Curse Adventure",
          "version": "2.0.0",
          "author": "Tester",
          "files": [
            {"projectID": 238222, "fileID": 67890, "required": true},
            {"projectID": 238223, "fileID": 67891, "required": false}
          ],
          "overrides": "overrides"
        }
        """.utf8).write(to: source.appendingPathComponent("manifest.json"))

        let pack = root.appendingPathComponent("curse.zip")
        try makeZipArchive(from: source, to: pack)

        let modData = Data("curse-pack-mod".utf8)
        let modSha1 = Insecure.SHA1.hash(data: modData).map { String(format: "%02x", $0) }.joined()

        final class MockHTTP: @unchecked Sendable {
            let modData: Data
            let modSha1: String
            var urls: [String] = []
            var apiKeys: [String?] = []

            init(modData: Data, modSha1: String) {
                self.modData = modData
                self.modSha1 = modSha1
            }

            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                urls.append(url.absoluteString)
                apiKeys.append(request.value(forHTTPHeaderField: "x-api-key"))
                let body: Data
                switch url.path {
                case "/v1/mods/238222/files/67890":
                    body = Data("""
                    {
                      "data": {
                        "id": 67890,
                        "modId": 238222,
                        "displayName": "Required Mod",
                        "fileName": "required-mod.jar",
                        "fileLength": \(modData.count),
                        "downloadUrl": "https://cdn.example.invalid/required-mod.jar",
                        "hashes": [{"value": "\(modSha1)", "algo": 1}],
                        "gameVersions": ["1.20.1", "Fabric"],
                        "releaseType": 1,
                        "modules": [{"name": "META-INF", "fingerprint": 1}]
                      }
                    }
                    """.utf8)
                default:
                    Issue.record("Unexpected CurseForge metadata URL: \(url.absoluteString)")
                    body = Data()
                }
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (body, response)
            }
        }

        final class MockDataLoader: @unchecked Sendable {
            let modData: Data
            var urls: [String] = []

            init(modData: Data) {
                self.modData = modData
            }

            func load(_ url: URL) -> Data {
                urls.append(url.absoluteString)
                if url.absoluteString == "https://cdn.example.invalid/required-mod.jar" {
                    return modData
                }
                Issue.record("Unexpected CurseForge file URL: \(url.absoluteString)")
                return Data()
            }
        }

        let http = MockHTTP(modData: modData, modSha1: modSha1)
        let loader = MockDataLoader(modData: modData)
        let service = CurseForgeResourceService(baseURL: URL(string: "https://api.curseforge.com/v1")!) {
            try http.respond(to: $0)
        }
        let minecraft = root.appendingPathComponent("minecraft", isDirectory: true)
        let result = try await CurseForgePackImporter(
            resourceService: service,
            dataLoader: { loader.load($0) }
        ).importPack(
            pack,
            apiKey: "secret-key",
            minecraftDirectory: minecraft,
            inheritedProfileID: "fabric-loader-0.15.11-1.20.1"
        )

        #expect(http.urls == ["https://api.curseforge.com/v1/mods/238222/files/67890"])
        #expect(http.apiKeys == ["secret-key"])
        #expect(loader.urls == ["https://cdn.example.invalid/required-mod.jar"])
        #expect(result.instanceName == "Curse-Adventure-2.0.0")
        #expect(result.downloadedFiles == 1)
        #expect(result.skippedFiles == 0)
        #expect(result.copiedOverrides == 1)

        let instanceDirectory = minecraft.appendingPathComponent("versions/Curse-Adventure-2.0.0", isDirectory: true)
        #expect(try Data(contentsOf: instanceDirectory.appendingPathComponent("mods/required-mod.jar")) == modData)
        #expect(!FileManager.default.fileExists(atPath: instanceDirectory.appendingPathComponent("mods/optional.jar").path))
        #expect(try String(contentsOf: instanceDirectory.appendingPathComponent("config/example.toml"), encoding: .utf8) == "configured=true")

        let profileData = try Data(contentsOf: instanceDirectory.appendingPathComponent("Curse-Adventure-2.0.0.json"))
        let profile = try JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        #expect(profile?["id"] as? String == "Curse-Adventure-2.0.0")
        #expect(profile?["inheritsFrom"] as? String == "fabric-loader-0.15.11-1.20.1")

        let instances = await MinecraftInstanceScanner().scan(minecraftDirectory: minecraft)
        #expect(instances.contains { $0.name == "Curse-Adventure-2.0.0" })
    }

    @Test func rejectsUnsafeModrinthPackPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacMrpackUnsafeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("""
        {
          "formatVersion": 1,
          "game": "minecraft",
          "versionId": "1.0.0",
          "name": "Bad Pack",
          "files": [
            {
              "path": "../evil.jar",
              "hashes": {"sha1": "abc"},
              "downloads": ["https://cdn.example/evil.jar"],
              "fileSize": 3
            }
          ],
          "dependencies": {
            "minecraft": "1.20.1"
          }
        }
        """.utf8).write(to: source.appendingPathComponent("modrinth.index.json"))

        let pack = root.appendingPathComponent("bad.mrpack")
        try makeZipArchive(from: source, to: pack)

        do {
            _ = try ModrinthPackInspector().inspect(pack, importRoot: root.appendingPathComponent("import", isDirectory: true))
            Issue.record("Expected unsafe Modrinth pack path rejection")
        } catch let error as ModrinthPackInspectionError {
            guard case .unsafePath("../evil.jar") = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func rejectsUnsafeModrinthFileName() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacUnsafeModrinthTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ModrinthResourceService { request in
            let url = try #require(request.url)
            let payload = """
            [
              {
                "id": "version-id",
                "name": "Bad Mod",
                "version_number": "1.0.0",
                "game_versions": ["1.20.1"],
                "loaders": ["fabric"],
                "files": [
                  {
                    "hashes": {"sha1": "abc"},
                    "url": "https://cdn.modrinth.com/data/bad.jar",
                    "filename": "../bad.jar",
                    "primary": true,
                    "size": 3
                  }
                ]
              }
            ]
            """
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data(payload.utf8), response)
        }

        do {
            _ = try await service.installLatestMod(
                project: nil,
                projectID: "bad-mod",
                minecraftVersion: "1.20.1",
                loader: "fabric",
                instanceDirectory: root
            )
            Issue.record("Expected unsafe file name rejection")
        } catch let error as ModrinthResourceError {
            guard case .unsafeFileName("../bad.jar") = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func rejectsModrinthChecksumMismatch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PCLMacModrinthChecksumTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        final class MockHTTP: @unchecked Sendable {
            func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
                let url = try #require(request.url)
                let payload: Data
                if url.absoluteString.contains("/version?") {
                    payload = Data("""
                    [
                      {
                        "id": "version-id",
                        "name": "Mismatch Mod",
                        "version_number": "1.0.0",
                        "game_versions": ["1.20.1"],
                        "loaders": ["fabric"],
                        "files": [
                          {
                            "hashes": {"sha1": "0000000000000000000000000000000000000000"},
                            "url": "https://cdn.modrinth.com/data/mismatch.jar",
                            "filename": "mismatch.jar",
                            "primary": true,
                            "size": 8
                          }
                        ]
                      }
                    ]
                    """.utf8)
                } else {
                    payload = Data("real-jar".utf8)
                }
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (payload, response)
            }
        }
        let http = MockHTTP()
        let service = ModrinthResourceService { request in
            try http.respond(to: request)
        }

        do {
            _ = try await service.installLatestMod(
                project: nil,
                projectID: "mismatch-mod",
                minecraftVersion: "1.20.1",
                loader: "fabric",
                instanceDirectory: root
            )
            Issue.record("Expected checksum mismatch")
        } catch let error as ModrinthResourceError {
            guard case .checksumMismatch = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("mods/mismatch.jar").path))
    }

    private func makeZipArchive(from sourceDirectory: URL, to destination: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", destination.path, "."]
        process.currentDirectoryURL = sourceDirectory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "PCLMacTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func extractZipArchive(_ archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "PCLMacTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private func makeZipArchiveWithUnsafeParentEntry(to destination: URL) throws {
        let root = destination.deletingLastPathComponent()
            .appendingPathComponent("unsafe-source-\(UUID().uuidString)", isDirectory: true)
        let inner = root.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("evil".utf8).write(to: root.appendingPathComponent("evil.txt"))

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", destination.path, "../evil.txt"]
        process.currentDirectoryURL = inner
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "PCLMacTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

private actor JavaRuntimeProgressRecorder {
    private var snapshots: [MojangJavaRuntimeInstallProgress] = []

    func append(_ progress: MojangJavaRuntimeInstallProgress) {
        snapshots.append(progress)
    }

    var values: [MojangJavaRuntimeInstallProgress] {
        snapshots
    }
}
