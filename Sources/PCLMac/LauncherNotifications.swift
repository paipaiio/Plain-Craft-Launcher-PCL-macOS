import Foundation
@preconcurrency import UserNotifications

struct LauncherNotification: Equatable, Sendable {
    var title: String
    var body: String
}

struct LauncherNotificationCenter: Sendable {
    static let disabled = LauncherNotificationCenter(
        requestAuthorization: { false },
        deliver: { _ in }
    )

    static let live = LauncherNotificationCenter(
        requestAuthorization: {
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        },
        deliver: { notification in
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "pclmac.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    )

    let requestAuthorization: @Sendable () async -> Bool
    let deliver: @Sendable (LauncherNotification) -> Void

    init(
        requestAuthorization: @escaping @Sendable () async -> Bool,
        deliver: @escaping @Sendable (LauncherNotification) -> Void
    ) {
        self.requestAuthorization = requestAuthorization
        self.deliver = deliver
    }
}
