import Foundation
import Security

enum LauncherAccountKind: String, Codable, Sendable {
    case offline
    case microsoft
    case nide
    case authlib

    var displayName: String {
        switch self {
        case .offline: "离线"
        case .microsoft: "Microsoft"
        case .nide: "统一通行证"
        case .authlib: "Authlib"
        }
    }
}

struct LauncherAccountProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: LauncherAccountKind
    var displayName: String
    var playerUUID: String?
    var serverURL: URL?
    var createdAt: Date
    var lastUsedAt: Date

    static func offline(username: String, date: Date = Date()) -> LauncherAccountProfile {
        LauncherAccountProfile(
            id: "offline:\(username.trimmed.lowercased())",
            kind: .offline,
            displayName: username.trimmed.isEmpty ? "Player" : username.trimmed,
            playerUUID: nil,
            serverURL: nil,
            createdAt: date,
            lastUsedAt: date
        )
    }
}

struct LauncherAccountSecret: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String? = nil
    var clientToken: String? = nil
    var username: String? = nil
    var password: String? = nil
    var expiresAt: Date? = nil
}

enum LauncherAccountStoreError: LocalizedError, Sendable {
    case keychain(OSStatus)
    case invalidSecretData

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Keychain 操作失败：\(status)"
        case .invalidSecretData:
            "Keychain 中的账户凭据无法读取"
        }
    }
}

protocol AccountSecretStore: Sendable {
    func save(_ secret: LauncherAccountSecret, for accountID: String) throws
    func load(for accountID: String) throws -> LauncherAccountSecret?
    func delete(for accountID: String) throws
}

struct KeychainAccountSecretStore: AccountSecretStore {
    static let live = KeychainAccountSecretStore()

    private let service: String

    init(service: String = "com.paipaiio.pcl.account") {
        self.service = service
    }

    func save(_ secret: LauncherAccountSecret, for accountID: String) throws {
        let data = try JSONEncoder().encode(secret)
        try delete(for: accountID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LauncherAccountStoreError.keychain(status)
        }
    }

    func load(for accountID: String) throws -> LauncherAccountSecret? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw LauncherAccountStoreError.keychain(status)
        }
        guard let data = item as? Data,
              let secret = try? JSONDecoder().decode(LauncherAccountSecret.self, from: data) else {
            throw LauncherAccountStoreError.invalidSecretData
        }
        return secret
    }

    func delete(for accountID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LauncherAccountStoreError.keychain(status)
        }
    }
}

struct LauncherAccountStore: @unchecked Sendable {
    static let live = LauncherAccountStore()

    private let userDefaults: UserDefaults
    private let profilesKey: String
    private let secretStore: any AccountSecretStore

    init(
        userDefaults: UserDefaults = .standard,
        profilesKey: String = "pcl.mac.launcher.accounts",
        secretStore: any AccountSecretStore = KeychainAccountSecretStore.live
    ) {
        self.userDefaults = userDefaults
        self.profilesKey = profilesKey
        self.secretStore = secretStore
    }

    func loadProfiles() -> [LauncherAccountProfile] {
        guard let data = userDefaults.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([LauncherAccountProfile].self, from: data) else {
            return []
        }
        return profiles.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    func upsert(_ profile: LauncherAccountProfile, secret: LauncherAccountSecret? = nil) throws {
        var profiles = loadProfiles().filter { $0.id != profile.id }
        profiles.append(profile)
        try saveProfiles(profiles)
        if let secret {
            try secretStore.save(secret, for: profile.id)
        }
    }

    func loadSecret(for accountID: String) throws -> LauncherAccountSecret? {
        try secretStore.load(for: accountID)
    }

    func delete(accountID: String) throws {
        let profiles = loadProfiles().filter { $0.id != accountID }
        try saveProfiles(profiles)
        try secretStore.delete(for: accountID)
    }

    private func saveProfiles(_ profiles: [LauncherAccountProfile]) throws {
        let data = try JSONEncoder().encode(profiles.sorted { $0.lastUsedAt > $1.lastUsedAt })
        userDefaults.set(data, forKey: profilesKey)
    }
}

final class InMemoryAccountSecretStore: AccountSecretStore, @unchecked Sendable {
    private var values: [String: LauncherAccountSecret] = [:]

    func save(_ secret: LauncherAccountSecret, for accountID: String) {
        values[accountID] = secret
    }

    func load(for accountID: String) -> LauncherAccountSecret? {
        values[accountID]
    }

    func delete(for accountID: String) {
        values.removeValue(forKey: accountID)
    }
}
