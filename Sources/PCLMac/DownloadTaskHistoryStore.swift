import Foundation

struct DownloadTaskHistoryStore: @unchecked Sendable {
    static let live = DownloadTaskHistoryStore()

    private let userDefaults: UserDefaults
    private let key: String
    private let limit: Int

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "PCLMac.DownloadTaskHistory",
        limit: Int = 80
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.limit = limit
    }

    func load() -> [DownloadTaskRecord] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DownloadTaskRecord].self, from: data) else {
            return []
        }
        return trimmed(decoded)
    }

    func save(_ records: [DownloadTaskRecord]) {
        guard let data = try? JSONEncoder().encode(trimmed(records)) else { return }
        userDefaults.set(data, forKey: key)
    }

    private func trimmed(_ records: [DownloadTaskRecord]) -> [DownloadTaskRecord] {
        Array(records.prefix(max(1, limit)))
    }
}
