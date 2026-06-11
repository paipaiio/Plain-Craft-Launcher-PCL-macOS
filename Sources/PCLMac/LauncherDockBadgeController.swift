import Foundation
@preconcurrency import AppKit

struct LauncherDockBadgeController: Sendable {
    static let disabled = LauncherDockBadgeController(setBadge: { _ in })

    static let live = LauncherDockBadgeController { badge in
        NSApp.dockTile.badgeLabel = badge
    }

    let setBadge: @MainActor @Sendable (String?) -> Void

    init(setBadge: @escaping @MainActor @Sendable (String?) -> Void) {
        self.setBadge = setBadge
    }
}
