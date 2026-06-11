import Foundation

enum LaunchBuildError: LocalizedError, Sendable {
    case missingVersionJson(URL)
    case invalidVersionJson(URL)
    case missingMainClass(String)
    case missingJava(URL)
    case noRunnableCommand

    var errorDescription: String? {
        switch self {
        case .missingVersionJson(let url):
            "未找到版本 JSON：\(url.path)"
        case .invalidVersionJson(let url):
            "无法读取版本 JSON：\(url.path)"
        case .missingMainClass(let version):
            "版本 \(version) 缺少 mainClass"
        case .missingJava(let url):
            "Java 不可执行：\(url.path)"
        case .noRunnableCommand:
            "未能生成可执行启动命令"
        }
    }
}

struct AuthlibInjectorConfiguration: Sendable {
    let jarURL: URL
    let serverURL: URL
    let prefetchedMetadata: String

    var prefetchedBase64: String {
        Data(prefetchedMetadata.utf8).base64EncodedString()
    }
}

struct NideInjectorConfiguration: Sendable {
    let jarURL: URL
    let serverID: String
}

struct MinecraftLaunchRequest: Sendable {
    struct Identity: Sendable {
        let username: String
        let uuid: String
        let accessToken: String
        let userType: String
        let clientToken: String?

        init(
            username: String,
            uuid: String,
            accessToken: String,
            userType: String,
            clientToken: String? = nil
        ) {
            self.username = username
            self.uuid = uuid
            self.accessToken = accessToken
            self.userType = userType
            self.clientToken = clientToken
        }

        static func offline(username: String) -> Identity {
            Identity(
                username: sanitizeUsername(username),
                uuid: offlineUUID(for: username),
                accessToken: "0",
                userType: "legacy",
                clientToken: nil
            )
        }
    }

    let instance: MinecraftInstance
    let minecraftDirectory: URL
    let javaExecutable: URL
    let identity: Identity
    let memoryMegabytes: Int
    let windowWidth: Int
    let windowHeight: Int
    let fullscreen: Bool
    let gameDirectory: URL?
    let serverAddress: String?
    let serverPort: Int?
    let authlibInjector: AuthlibInjectorConfiguration?
    let nideInjector: NideInjectorConfiguration?
    let extraJvmArguments: [String]
    let extraGameArguments: [String]

    init(
        instance: MinecraftInstance,
        minecraftDirectory: URL,
        javaExecutable: URL,
        username: String,
        memoryMegabytes: Int,
        windowWidth: Int,
        windowHeight: Int,
        fullscreen: Bool = false,
        gameDirectory: URL? = nil,
        serverAddress: String? = nil,
        serverPort: Int? = nil,
        extraJvmArguments: [String] = [],
        extraGameArguments: [String] = []
    ) {
        self.init(
            instance: instance,
            minecraftDirectory: minecraftDirectory,
            javaExecutable: javaExecutable,
            identity: .offline(username: username),
            memoryMegabytes: memoryMegabytes,
            windowWidth: windowWidth,
            windowHeight: windowHeight,
            fullscreen: fullscreen,
            gameDirectory: gameDirectory,
            serverAddress: serverAddress,
            serverPort: serverPort,
            authlibInjector: nil,
            nideInjector: nil,
            extraJvmArguments: extraJvmArguments,
            extraGameArguments: extraGameArguments
        )
    }

    init(
        instance: MinecraftInstance,
        minecraftDirectory: URL,
        javaExecutable: URL,
        identity: Identity,
        memoryMegabytes: Int,
        windowWidth: Int,
        windowHeight: Int,
        fullscreen: Bool = false,
        gameDirectory: URL? = nil,
        serverAddress: String? = nil,
        serverPort: Int? = nil,
        authlibInjector: AuthlibInjectorConfiguration? = nil,
        nideInjector: NideInjectorConfiguration? = nil,
        extraJvmArguments: [String] = [],
        extraGameArguments: [String] = []
    ) {
        self.instance = instance
        self.minecraftDirectory = minecraftDirectory
        self.javaExecutable = javaExecutable
        self.identity = identity
        self.memoryMegabytes = memoryMegabytes
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.fullscreen = fullscreen
        self.gameDirectory = gameDirectory
        let target = Self.normalizedServerTarget(address: serverAddress, port: serverPort)
        self.serverAddress = target.address
        self.serverPort = target.port
        self.authlibInjector = authlibInjector
        self.nideInjector = nideInjector
        self.extraJvmArguments = extraJvmArguments
        self.extraGameArguments = extraGameArguments
    }

    private static func normalizedServerTarget(address: String?, port: Int?) -> (address: String?, port: Int?) {
        guard let trimmedAddress = address?.trimmed.nonEmpty else {
            return (nil, nil)
        }
        let explicitPort = port.flatMap { (1...65535).contains($0) ? $0 : nil }
        let parsed = splitAddressAndPort(trimmedAddress)
        return (
            address: parsed.address.nonEmpty,
            port: explicitPort ?? parsed.port
        )
    }

    private static func splitAddressAndPort(_ address: String) -> (address: String, port: Int?) {
        if address.hasPrefix("["),
           let close = address.firstIndex(of: "]") {
            let host = String(address[address.index(after: address.startIndex)..<close])
            let suffixStart = address.index(after: close)
            if suffixStart < address.endIndex,
               address[suffixStart] == ":" {
                let portText = String(address[address.index(after: suffixStart)...])
                if let port = Int(portText), (1...65535).contains(port) {
                    return (host, port)
                }
            }
            return (address, nil)
        }

        let colonCount = address.reduce(0) { $1 == ":" ? $0 + 1 : $0 }
        guard colonCount == 1,
              let colon = address.lastIndex(of: ":") else {
            return (address, nil)
        }
        let host = String(address[..<colon])
        let portText = String(address[address.index(after: colon)...])
        guard !host.isEmpty,
              let port = Int(portText),
              (1...65535).contains(port) else {
            return (address, nil)
        }
        return (host, port)
    }
}

struct MinecraftLaunchCommand: Sendable {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]
    let nativesDirectory: URL
    let commandLinePreview: String
}

struct MinecraftLaunchBuilder: Sendable {
    func build(request: MinecraftLaunchRequest) throws -> MinecraftLaunchCommand {
        guard FileManager.default.isExecutableFile(atPath: request.javaExecutable.path) else {
            throw LaunchBuildError.missingJava(request.javaExecutable)
        }

        let chain = try MinecraftVersionRepository().loadVersionChain(instance: request.instance, minecraftDirectory: request.minecraftDirectory)
        guard let effectiveVersion = chain.last else {
            throw LaunchBuildError.invalidVersionJson(request.instance.jsonURL)
        }
        let mainClass = chain.reversed().compactMap(\.mainClass).first
        guard let mainClass, !mainClass.isEmpty else {
            throw LaunchBuildError.missingMainClass(effectiveVersion.id)
        }

        let libraries = MinecraftLibraryResolver().collectLibraries(from: chain, minecraftDirectory: request.minecraftDirectory)
        let classpath = buildClasspath(libraries: libraries, chain: chain, request: request)
        let nativesDirectory = request.instance.path.appendingPathComponent("\(request.instance.name)-natives", isDirectory: true)
        try prepareNatives(libraries: libraries, nativesDirectory: nativesDirectory)

        let replacements = replacementMap(
            request: request,
            mainClass: mainClass,
            classpath: classpath,
            nativesDirectory: nativesDirectory,
            version: effectiveVersion,
            chain: chain
        )

        let jvmArgs = buildJvmArguments(from: chain, replacements: replacements, memoryMegabytes: request.memoryMegabytes)
            + authlibInjectorArguments(request.authlibInjector)
            + nideInjectorArguments(request.nideInjector)
            + request.extraJvmArguments
        var gameArgs = buildGameArguments(from: chain, replacements: replacements, version: effectiveVersion)
        if request.fullscreen,
           !gameArgs.contains("--fullscreen"),
           !request.extraGameArguments.contains("--fullscreen") {
            gameArgs.append("--fullscreen")
        }
        gameArgs = appendServerArguments(gameArgs, request: request)
        gameArgs += request.extraGameArguments
        let allArguments = jvmArgs + [mainClass] + gameArgs
        guard !allArguments.isEmpty else { throw LaunchBuildError.noRunnableCommand }

        let environment = buildEnvironment(javaExecutable: request.javaExecutable, minecraftDirectory: request.minecraftDirectory)
        let preview = ([request.javaExecutable.path] + allArguments).map(shellQuote).joined(separator: " ")
        return MinecraftLaunchCommand(
            executable: request.javaExecutable,
            arguments: allArguments,
            workingDirectory: gameDirectory(for: request),
            environment: environment,
            nativesDirectory: nativesDirectory,
            commandLinePreview: preview
        )
    }

    private func buildClasspath(libraries: [ResolvedLibrary], chain: [MinecraftVersionFile], request: MinecraftLaunchRequest) -> String {
        var entries = libraries.filter { !$0.isNative }.map(\.localPath.path)
        for jarOwner in minecraftClientJarOwners(from: chain, fallback: request.instance.name) {
            let jarURL = request.minecraftDirectory
                .appendingPathComponent("versions", isDirectory: true)
                .appendingPathComponent(jarOwner, isDirectory: true)
                .appendingPathComponent("\(jarOwner).jar")
            entries.append(jarURL.path)
        }
        return entries.uniqued().joined(separator: ":")
    }

    private func prepareNatives(libraries: [ResolvedLibrary], nativesDirectory: URL) throws {
        try FileManager.default.createDirectory(at: nativesDirectory, withIntermediateDirectories: true)
        for library in libraries where library.isNative && FileManager.default.fileExists(atPath: library.localPath.path) {
            try extractNativeJar(library.localPath, to: nativesDirectory)
        }
    }

    private func extractNativeJar(_ jarURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", jarURL.path, destination.path]
        try process.run()
        process.waitUntilExit()
    }

    private func replacementMap(
        request: MinecraftLaunchRequest,
        mainClass: String,
        classpath: String,
        nativesDirectory: URL,
        version: MinecraftVersionFile,
        chain: [MinecraftVersionFile]
    ) -> [String: String] {
        let assetOwner = chain.reversed().first { item in
            item.assetIndex?.id?.isEmpty == false || item.assets?.isEmpty == false
        } ?? version
        let assetsIndex = assetOwner.assetIndex?.id ?? assetOwner.assets ?? version.id
        let gameDirectory = gameDirectory(for: request)
        return [
            "${natives_directory}": nativesDirectory.path,
            "${launcher_name}": "PCL",
            "${launcher_version}": "MacPreview",
            "${classpath}": classpath,
            "${classpath_separator}": ":",
            "${library_directory}": request.minecraftDirectory.appendingPathComponent("libraries").path,
            "${libraries_directory}": request.minecraftDirectory.appendingPathComponent("libraries").path,
            "${version_name}": version.id,
            "${game_directory}": gameDirectory.path,
            "${assets_root}": request.minecraftDirectory.appendingPathComponent("assets").path,
            "${assets_index_name}": assetsIndex,
            "${auth_player_name}": request.identity.username,
            "${auth_uuid}": request.identity.uuid,
            "${auth_access_token}": request.identity.accessToken,
            "${access_token}": request.identity.accessToken,
            "${clientid}": request.identity.clientToken ?? "",
            "${auth_xuid}": "",
            "${user_type}": request.identity.userType,
            "${version_type}": version.type ?? "PCL",
            "${resolution_width}": "\(request.windowWidth)",
            "${resolution_height}": "\(request.windowHeight)",
            "${user_properties}": "{}",
            "${game_assets}": request.minecraftDirectory.appendingPathComponent("assets/virtual/legacy").path,
            "${primary_jar}": request.instance.path.appendingPathComponent("\(request.instance.name).jar").path,
            "${main_class}": mainClass
        ]
    }

    private func buildJvmArguments(from chain: [MinecraftVersionFile], replacements: [String: String], memoryMegabytes: Int) -> [String] {
        var args = ["-Xmx\(max(memoryMegabytes, 1024))M", "-Djava.library.path=${natives_directory}"]
        for version in chain {
            if let jvmArguments = version.arguments?.jvm {
                args.append(contentsOf: jvmArguments.flatMap { argumentValues($0) })
            }
        }
        if !args.contains("-cp") && !args.contains("-classpath") {
            args.append(contentsOf: ["-cp", "${classpath}"])
        }
        return replaceTokens(in: args.uniqued(), replacements: replacements)
    }

    private func authlibInjectorArguments(_ configuration: AuthlibInjectorConfiguration?) -> [String] {
        guard let configuration else { return [] }
        return [
            "-javaagent:\(configuration.jarURL.path)=\(configuration.serverURL.absoluteString)",
            "-Dauthlibinjector.side=client",
            "-Dauthlibinjector.yggdrasil.prefetched=\(configuration.prefetchedBase64)"
        ]
    }

    private func nideInjectorArguments(_ configuration: NideInjectorConfiguration?) -> [String] {
        guard let configuration else { return [] }
        return ["-javaagent:\(configuration.jarURL.path)=\(configuration.serverID)"]
    }

    private func buildGameArguments(from chain: [MinecraftVersionFile], replacements: [String: String], version: MinecraftVersionFile) -> [String] {
        var args: [String] = []
        for item in chain.compactMap(\.arguments?.game).flatMap({ $0 }) {
            args.append(contentsOf: argumentValues(item))
        }
        if args.isEmpty, let legacy = chain.reversed().compactMap(\.minecraftArguments).first {
            args = splitLegacyArguments(legacy)
        }
        return replaceTokens(in: args, replacements: replacements)
    }

    private func appendServerArguments(_ gameArgs: [String], request: MinecraftLaunchRequest) -> [String] {
        guard let serverAddress = request.serverAddress else { return gameArgs }
        let existingArgs = gameArgs + request.extraGameArguments
        guard !existingArgs.contains("--server") else { return gameArgs }
        var args = gameArgs + ["--server", serverAddress]
        if let serverPort = request.serverPort,
           !existingArgs.contains("--port") {
            args += ["--port", "\(serverPort)"]
        }
        return args
    }

    private func argumentValues(_ item: MinecraftArgument) -> [String] {
        switch item {
        case .string(let value):
            [value]
        case .ruled(let ruled):
            MinecraftRuleEvaluator.shouldInclude(rules: ruled.rules) ? ruled.value.values : []
        }
    }

    private func replaceTokens(in args: [String], replacements: [String: String]) -> [String] {
        args.map { arg in
            replacements.reduce(arg) { current, pair in
                current.replacingOccurrences(of: pair.key, with: pair.value)
            }
        }
        .filter { !$0.isEmpty }
    }

    private func buildEnvironment(javaExecutable: URL, minecraftDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let javaBin = javaExecutable.deletingLastPathComponent().path
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(javaBin):\(existingPath)"
        environment["APPDATA"] = minecraftDirectory.path
        return environment
    }

    private func gameDirectory(for request: MinecraftLaunchRequest) -> URL {
        request.gameDirectory ?? request.instance.path
    }

    private func splitLegacyArguments(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for character in value {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character == " ", !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

struct MinecraftLaunchRunner: Sendable {
    func run(command: MinecraftLaunchCommand) throws -> Process {
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = command.environment
        try process.run()
        return process
    }
}

struct MinecraftVersionRepository: Sendable {
    func loadVersionChain(instance: MinecraftInstance, minecraftDirectory: URL) throws -> [MinecraftVersionFile] {
        var result: [MinecraftVersionFile] = []
        var seen = Set<String>()

        func load(jsonURL: URL) throws {
            guard FileManager.default.fileExists(atPath: jsonURL.path) else {
                throw LaunchBuildError.missingVersionJson(jsonURL)
            }
            guard let data = try? Data(contentsOf: jsonURL),
                  let version = try? JSONDecoder().decode(MinecraftVersionFile.self, from: data) else {
                throw LaunchBuildError.invalidVersionJson(jsonURL)
            }
            guard !seen.contains(version.id) else { return }
            seen.insert(version.id)

            if let parent = version.inheritsFrom, !parent.isEmpty {
                let parentURL = minecraftDirectory
                    .appendingPathComponent("versions", isDirectory: true)
                    .appendingPathComponent(parent, isDirectory: true)
                    .appendingPathComponent("\(parent).json")
                try load(jsonURL: parentURL)
            }
            result.append(version)
        }

        try load(jsonURL: instance.jsonURL)
        return result
    }
}

struct MinecraftLibraryResolver: Sendable {
    func collectLibraries(from chain: [MinecraftVersionFile], minecraftDirectory: URL) -> [ResolvedLibrary] {
        var resolved: [String: ResolvedLibrary] = [:]
        for version in chain {
            for library in version.libraries where MinecraftRuleEvaluator.shouldInclude(rules: library.rules) {
                guard let artifact = selectArtifact(for: library, minecraftDirectory: minecraftDirectory) else { continue }
                resolved[library.name + (artifact.isNative ? "#native" : "#artifact")] = artifact
            }
        }
        return Array(resolved.values).sorted { $0.localPath.path < $1.localPath.path }
    }

    func selectArtifact(for library: MinecraftLibrary, minecraftDirectory: URL) -> ResolvedLibrary? {
        let librariesDirectory = minecraftDirectory.appendingPathComponent("libraries", isDirectory: true)
        if let nativeClassifierTemplate = library.natives?["osx"] {
            let nativeClassifier = expandNativeClassifier(nativeClassifierTemplate)
            if let classifier = library.downloads?.classifiers?[nativeClassifier] {
                return ResolvedLibrary(name: library.name, artifact: classifier, localPath: artifactPath(classifier, librariesDirectory: librariesDirectory), isNative: true)
            }
        }

        if let artifact = library.downloads?.artifact {
            return ResolvedLibrary(name: library.name, artifact: artifact, localPath: artifactPath(artifact, librariesDirectory: librariesDirectory), isNative: false)
        }

        if let artifact = mavenArtifact(for: library) {
            return ResolvedLibrary(name: library.name, artifact: artifact, localPath: artifactPath(artifact, librariesDirectory: librariesDirectory), isNative: false)
        }

        return ResolvedLibrary(name: library.name, artifact: nil, localPath: legacyLibraryPath(library.name, librariesDirectory: librariesDirectory), isNative: false)
    }

    func artifactPath(_ artifact: MinecraftDownloadArtifact, librariesDirectory: URL) -> URL {
        if let path = artifact.path, !path.isEmpty {
            return librariesDirectory.appendingPathComponent(path)
        }
        return librariesDirectory
    }

    func legacyLibraryPath(_ name: String, librariesDirectory: URL) -> URL {
        librariesDirectory.appendingPathComponent(legacyLibraryRelativePath(name))
    }

    func legacyLibraryRelativePath(_ name: String) -> String {
        let pieces = name.split(separator: ":").map(String.init)
        guard pieces.count >= 3 else { return name.replacingOccurrences(of: ":", with: "/") + ".jar" }
        let groupPath = pieces[0].replacingOccurrences(of: ".", with: "/")
        let artifact = pieces[1]
        let version = pieces[2]
        let classifier = pieces.count >= 4 ? "-\(pieces[3])" : ""
        return "\(groupPath)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).jar"
    }

    func mavenArtifact(for library: MinecraftLibrary) -> MinecraftDownloadArtifact? {
        guard let baseURL = library.url, !baseURL.isEmpty else { return nil }
        let path = legacyLibraryRelativePath(library.name)
        let separator = baseURL.hasSuffix("/") ? "" : "/"
        return MinecraftDownloadArtifact(
            path: path,
            url: "\(baseURL)\(separator)\(path)",
            sha1: library.sha1,
            size: library.size
        )
    }

    func expandNativeClassifier(_ template: String) -> String {
        let arch = ProcessInfo.processInfo.machineHardwareName.contains("arm64") ? "64" : "64"
        return template.replacingOccurrences(of: "${arch}", with: arch)
    }
}

struct MinecraftRuleEvaluator {
    static func shouldInclude(rules: [MinecraftRule]?) -> Bool {
        guard let rules, !rules.isEmpty else { return true }
        var allowed = false
        for rule in rules {
            let matches = rule.matchesMac
            switch rule.action {
            case "allow":
                if matches { allowed = true }
            case "disallow":
                if matches { allowed = false }
            default:
                break
            }
        }
        return allowed
    }
}

struct ResolvedLibrary: Sendable {
    let name: String
    let artifact: MinecraftDownloadArtifact?
    let localPath: URL
    let isNative: Bool
}

struct MinecraftVersionFile: Decodable, Sendable {
    let id: String
    let type: String?
    let mainClass: String?
    let assets: String?
    let assetIndex: MinecraftAssetIndex?
    let arguments: MinecraftArguments?
    let minecraftArguments: String?
    let libraries: [MinecraftLibrary]
    let inheritsFrom: String?
    let jar: String?
    let downloads: MinecraftVersionDownloads?
    let javaVersion: MinecraftJavaVersion?
}

struct MinecraftVersionDownloads: Decodable, Sendable {
    let client: MinecraftDownloadArtifact?
}

struct MinecraftJavaVersion: Decodable, Sendable {
    let component: String?
    let majorVersion: Int?
}

func requiredMinecraftJavaMajorVersion(from chain: [MinecraftVersionFile]) -> Int? {
    chain.reversed().compactMap(\.javaVersion?.majorVersion).first
}

struct MinecraftAssetIndex: Decodable, Sendable {
    let id: String?
    let url: String?
    let sha1: String?
    let size: Int?
}

struct MinecraftArguments: Decodable, Sendable {
    let game: [MinecraftArgument]?
    let jvm: [MinecraftArgument]?
}

enum MinecraftArgument: Decodable, Sendable {
    case string(String)
    case ruled(MinecraftRuledArgument)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        self = .ruled(try container.decode(MinecraftRuledArgument.self))
    }
}

struct MinecraftRuledArgument: Decodable, Sendable {
    let rules: [MinecraftRule]?
    let value: MinecraftArgumentValue
}

enum MinecraftArgumentValue: Decodable, Sendable {
    case string(String)
    case array([String])

    var values: [String] {
        switch self {
        case .string(let string): [string]
        case .array(let array): array
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        self = .array(try container.decode([String].self))
    }
}

struct MinecraftLibrary: Decodable, Sendable {
    let name: String
    let url: String?
    let sha1: String?
    let size: Int?
    let downloads: MinecraftLibraryDownloads?
    let natives: [String: String]?
    let rules: [MinecraftRule]?
}

struct MinecraftLibraryDownloads: Decodable, Sendable {
    let artifact: MinecraftDownloadArtifact?
    let classifiers: [String: MinecraftDownloadArtifact]?
}

struct MinecraftDownloadArtifact: Decodable, Sendable {
    let path: String?
    let url: String?
    let sha1: String?
    let size: Int?
}

struct MinecraftRule: Decodable, Sendable {
    let action: String
    let os: MinecraftRuleOS?
    let features: [String: Bool]?

    var matchesMac: Bool {
        var matches = true
        if let os {
            if let name = os.name {
                matches = matches && (name == "osx" || name == "unknown")
            }
            if let arch = os.arch {
                let machine = ProcessInfo.processInfo.machineHardwareName
                if arch == "x86" {
                    matches = matches && machine.contains("x86")
                } else if arch == "arm64" {
                    matches = matches && machine.contains("arm64")
                }
            }
        }
        if let features, features.keys.contains(where: { $0.contains("quick_play") }) {
            matches = false
        }
        return matches
    }
}

struct MinecraftRuleOS: Decodable, Sendable {
    let name: String?
    let arch: String?
    let version: String?
}

private func sanitizeUsername(_ username: String) -> String {
    let cleaned = username.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    if cleaned.isEmpty { return "Player" }
    return String(cleaned.prefix(16))
}

private func offlineUUID(for username: String) -> String {
    UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        .uuidString
        .replacingOccurrences(of: "-", with: "")
}

private func shellQuote(_ value: String) -> String {
    if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))) == nil {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func minecraftClientJarOwners(from chain: [MinecraftVersionFile], fallback: String) -> [String] {
    let owners = chain.compactMap { version -> String? in
        if let jar = version.jar, !jar.isEmpty {
            return jar
        }
        if version.inheritsFrom == nil || version.downloads?.client != nil {
            return version.id
        }
        return nil
    }
    return owners.isEmpty ? [fallback] : owners.uniqued()
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let bytes = machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
