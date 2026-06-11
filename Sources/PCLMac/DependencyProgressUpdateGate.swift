import Foundation

actor DependencyProgressUpdateGate {
    private let minimumFinishedDelta: Int
    private let minimumTimeInterval: TimeInterval
    private var lastEmittedFinished: Int?
    private var lastEmittedAt: Date?

    init(minimumFinishedDelta: Int = 64, minimumTimeInterval: TimeInterval = 0.08) {
        self.minimumFinishedDelta = max(1, minimumFinishedDelta)
        self.minimumTimeInterval = max(0, minimumTimeInterval)
    }

    func shouldEmit(_ progress: MinecraftDownloadProgress, now: Date = Date()) -> Bool {
        if lastEmittedFinished == nil {
            record(progress, now: now)
            return true
        }

        if progress.action == .downloaded || progress.finished >= progress.total {
            record(progress, now: now)
            return true
        }

        if let lastEmittedFinished,
           progress.finished - lastEmittedFinished >= minimumFinishedDelta {
            record(progress, now: now)
            return true
        }

        if let lastEmittedAt,
           now.timeIntervalSince(lastEmittedAt) >= minimumTimeInterval {
            record(progress, now: now)
            return true
        }

        return false
    }

    private func record(_ progress: MinecraftDownloadProgress, now: Date) {
        lastEmittedFinished = progress.finished
        lastEmittedAt = now
    }
}
