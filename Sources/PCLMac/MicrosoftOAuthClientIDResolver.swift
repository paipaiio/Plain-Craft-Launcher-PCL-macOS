import Foundation

enum MicrosoftOAuthClientIDSource: String, Sendable {
    case settings
    case environment
    case bundle

    var displayName: String {
        switch self {
        case .settings:
            "高级覆盖"
        case .environment:
            "PCL_MS_CLIENT_ID"
        case .bundle:
            "应用内置"
        }
    }
}

struct MicrosoftOAuthClientIDResolution: Equatable, Sendable {
    let clientID: String
    let source: MicrosoftOAuthClientIDSource?

    var isConfigured: Bool {
        !clientID.isEmpty
    }
}

struct MicrosoftOAuthClientIDResolver: Sendable {
    static let environmentKey = "PCL_MS_CLIENT_ID"
    static let bundleInfoKey = "PCLMicrosoftClientID"

    let settingsClientID: String?
    let environmentClientID: String?
    let bundleClientID: String?

    init(
        settingsClientID: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) {
        self.init(
            settingsClientID: settingsClientID,
            environmentClientID: environment[Self.environmentKey],
            bundleClientID: bundle.object(forInfoDictionaryKey: Self.bundleInfoKey) as? String
        )
    }

    init(settingsClientID: String?, environmentClientID: String?, bundleClientID: String?) {
        self.settingsClientID = settingsClientID
        self.environmentClientID = environmentClientID
        self.bundleClientID = bundleClientID
    }

    func resolve() -> MicrosoftOAuthClientIDResolution {
        for candidate in [
            (settingsClientID, MicrosoftOAuthClientIDSource.settings),
            (environmentClientID, MicrosoftOAuthClientIDSource.environment),
            (bundleClientID, MicrosoftOAuthClientIDSource.bundle)
        ] {
            if let clientID = candidate.0?.trimmed, !clientID.isEmpty {
                return MicrosoftOAuthClientIDResolution(clientID: clientID, source: candidate.1)
            }
        }

        return MicrosoftOAuthClientIDResolution(clientID: "", source: nil)
    }
}
