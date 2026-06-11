import Foundation

struct GameLaunchExitSummary: Equatable, Sendable {
    let instanceName: String
    let processIdentifier: Int32
    let exitCode: Int32
    let startedAt: Date
    let endedAt: Date
    let wasUserRequestedStop: Bool

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    var title: String {
        if wasUserRequestedStop {
            return "游戏已关闭"
        }
        return exitCode == 0 ? "游戏正常退出" : "游戏异常退出"
    }

    var detail: String {
        let seconds = Int(duration.rounded())
        if wasUserRequestedStop {
            return "已按你的操作关闭 \(instanceName)，运行 \(seconds) 秒"
        }
        if exitCode == 0 {
            return "\(instanceName) 正常结束，运行 \(seconds) 秒"
        }
        return "\(instanceName) 返回码 \(exitCode)，已准备查看崩溃日志"
    }

    var lastEvent: String {
        if wasUserRequestedStop {
            return "游戏进程已手动关闭"
        }
        if exitCode == 0 {
            return "游戏进程正常结束"
        }
        return "游戏异常退出，已打开日志诊断"
    }

    var shouldOpenLogDiagnostics: Bool {
        !wasUserRequestedStop && exitCode != 0
    }
}
