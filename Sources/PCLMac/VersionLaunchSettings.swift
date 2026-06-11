import Foundation

struct VersionLaunchSettings: Codable, Equatable, Sendable {
    var usesGlobalJava: Bool
    var javaExecutablePath: String?
    var usesGlobalMemory: Bool
    var memoryMegabytes: Double?
    var usesGlobalWindow: Bool
    var windowWidth: Double?
    var windowHeight: Double?
    var fullscreen: Bool?
    var usesGlobalGameDirectory: Bool
    var usesIsolatedGameDirectory: Bool?
    var usesGlobalServer: Bool
    var serverAddress: String?
    var serverPort: String?
    var extraJvmArguments: String
    var extraGameArguments: String

    init(
        usesGlobalJava: Bool,
        javaExecutablePath: String?,
        usesGlobalMemory: Bool,
        memoryMegabytes: Double?,
        usesGlobalWindow: Bool = true,
        windowWidth: Double? = nil,
        windowHeight: Double? = nil,
        fullscreen: Bool? = nil,
        usesGlobalGameDirectory: Bool = true,
        usesIsolatedGameDirectory: Bool? = nil,
        usesGlobalServer: Bool = true,
        serverAddress: String? = nil,
        serverPort: String? = nil,
        extraJvmArguments: String,
        extraGameArguments: String
    ) {
        self.usesGlobalJava = usesGlobalJava
        self.javaExecutablePath = javaExecutablePath
        self.usesGlobalMemory = usesGlobalMemory
        self.memoryMegabytes = memoryMegabytes
        self.usesGlobalWindow = usesGlobalWindow
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.fullscreen = fullscreen
        self.usesGlobalGameDirectory = usesGlobalGameDirectory
        self.usesIsolatedGameDirectory = usesIsolatedGameDirectory
        self.usesGlobalServer = usesGlobalServer
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.extraJvmArguments = extraJvmArguments
        self.extraGameArguments = extraGameArguments
    }

    static let defaults = VersionLaunchSettings(
        usesGlobalJava: true,
        javaExecutablePath: nil,
        usesGlobalMemory: true,
        memoryMegabytes: nil,
        usesGlobalWindow: true,
        windowWidth: nil,
        windowHeight: nil,
        fullscreen: nil,
        usesGlobalGameDirectory: true,
        usesIsolatedGameDirectory: nil,
        usesGlobalServer: true,
        serverAddress: nil,
        serverPort: nil,
        extraJvmArguments: "",
        extraGameArguments: ""
    )

    var normalized: VersionLaunchSettings {
        var value = self
        value.javaExecutablePath = value.javaExecutablePath?.trimmed
        if value.javaExecutablePath?.isEmpty == true {
            value.javaExecutablePath = nil
        }
        if let memory = value.memoryMegabytes {
            value.memoryMegabytes = min(max(memory, 1024), 32768)
        }
        if let width = value.windowWidth {
            value.windowWidth = min(max(width, 320), 7680)
        }
        if let height = value.windowHeight {
            value.windowHeight = min(max(height, 240), 4320)
        }
        value.serverAddress = value.serverAddress?.trimmed
        if value.serverAddress?.isEmpty == true {
            value.serverAddress = nil
        }
        value.serverPort = Self.normalizedServerPort(value.serverPort)
        value.extraJvmArguments = value.extraJvmArguments.trimmed
        value.extraGameArguments = value.extraGameArguments.trimmed
        return value
    }

    var extraJvmArgumentList: [String] {
        Self.splitArguments(extraJvmArguments)
    }

    var extraGameArgumentList: [String] {
        Self.splitArguments(extraGameArguments)
    }

    static func splitArguments(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        func flush() {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }

        for character in value {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }
            if character == "\\" {
                isEscaping = true
                continue
            }
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                } else {
                    current.append(character)
                }
                continue
            }
            if character.isWhitespace, quote == nil {
                flush()
            } else {
                current.append(character)
            }
        }
        if isEscaping {
            current.append("\\")
        }
        flush()
        return result
    }

    enum CodingKeys: String, CodingKey {
        case usesGlobalJava
        case javaExecutablePath
        case usesGlobalMemory
        case memoryMegabytes
        case usesGlobalWindow
        case windowWidth
        case windowHeight
        case fullscreen
        case usesGlobalGameDirectory
        case usesIsolatedGameDirectory
        case usesGlobalServer
        case serverAddress
        case serverPort
        case extraJvmArguments
        case extraGameArguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            usesGlobalJava: try container.decodeIfPresent(Bool.self, forKey: .usesGlobalJava) ?? Self.defaults.usesGlobalJava,
            javaExecutablePath: try container.decodeIfPresent(String.self, forKey: .javaExecutablePath),
            usesGlobalMemory: try container.decodeIfPresent(Bool.self, forKey: .usesGlobalMemory) ?? Self.defaults.usesGlobalMemory,
            memoryMegabytes: try container.decodeIfPresent(Double.self, forKey: .memoryMegabytes),
            usesGlobalWindow: try container.decodeIfPresent(Bool.self, forKey: .usesGlobalWindow) ?? Self.defaults.usesGlobalWindow,
            windowWidth: try container.decodeIfPresent(Double.self, forKey: .windowWidth),
            windowHeight: try container.decodeIfPresent(Double.self, forKey: .windowHeight),
            fullscreen: try container.decodeIfPresent(Bool.self, forKey: .fullscreen),
            usesGlobalGameDirectory: try container.decodeIfPresent(Bool.self, forKey: .usesGlobalGameDirectory) ?? Self.defaults.usesGlobalGameDirectory,
            usesIsolatedGameDirectory: try container.decodeIfPresent(Bool.self, forKey: .usesIsolatedGameDirectory),
            usesGlobalServer: try container.decodeIfPresent(Bool.self, forKey: .usesGlobalServer) ?? Self.defaults.usesGlobalServer,
            serverAddress: try container.decodeIfPresent(String.self, forKey: .serverAddress),
            serverPort: try container.decodeIfPresent(String.self, forKey: .serverPort),
            extraJvmArguments: try container.decodeIfPresent(String.self, forKey: .extraJvmArguments) ?? Self.defaults.extraJvmArguments,
            extraGameArguments: try container.decodeIfPresent(String.self, forKey: .extraGameArguments) ?? Self.defaults.extraGameArguments
        )
    }

    private static func normalizedServerPort(_ port: String?) -> String? {
        guard let text = port?.trimmed, !text.isEmpty, let value = Int(text), (1...65535).contains(value) else {
            return nil
        }
        return "\(value)"
    }
}

struct VersionLaunchSettingsStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let fileName: String

    init(fileManager: FileManager = .default, fileName: String = "pclmac-version-settings.json") {
        self.fileManager = fileManager
        self.fileName = fileName
    }

    func settingsURL(for instance: MinecraftInstance) -> URL {
        instance.path.appendingPathComponent(fileName)
    }

    func load(for instance: MinecraftInstance) -> VersionLaunchSettings {
        let url = settingsURL(for: instance)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VersionLaunchSettings.self, from: data) else {
            return .defaults
        }
        return decoded.normalized
    }

    func save(_ settings: VersionLaunchSettings, for instance: MinecraftInstance) throws {
        try fileManager.createDirectory(at: instance.path, withIntermediateDirectories: true)
        let data = try JSONEncoder.pclPretty.encode(settings.normalized)
        try data.write(to: settingsURL(for: instance), options: [.atomic])
    }

    func reset(for instance: MinecraftInstance) throws {
        let url = settingsURL(for: instance)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

private extension JSONEncoder {
    static var pclPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
