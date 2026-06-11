import Foundation

enum MinecraftLogKind: String, CaseIterable, Sendable {
    case latest = "Latest Log"
    case crashReport = "Crash Report"
    case jvmCrash = "JVM Crash"
    case installer = "Installer Log"

    var displayName: String {
        switch self {
        case .latest: "最新日志"
        case .crashReport: "崩溃报告"
        case .jvmCrash: "JVM 崩溃"
        case .installer: "安装器日志"
        }
    }
}

struct MinecraftLogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let kind: MinecraftLogKind
    let name: String
    let modifiedAt: Date?
    let size: Int64
    let summary: String
}

struct MinecraftLogPreview: Sendable {
    let text: String
    let lineCount: Int
    let isTruncated: Bool
}

enum MinecraftLogDiagnosisSeverity: String, Sendable {
    case critical
    case warning
    case info

    var displayName: String {
        switch self {
        case .critical: "需要处理"
        case .warning: "建议检查"
        case .info: "参考信息"
        }
    }
}

struct MinecraftLogDiagnosis: Identifiable, Hashable, Sendable {
    let id: String
    let severity: MinecraftLogDiagnosisSeverity
    let title: String
    let detail: String
    let suggestions: [String]
    let matchedLine: String?

    init(
        id: String,
        severity: MinecraftLogDiagnosisSeverity,
        title: String,
        detail: String,
        suggestions: [String],
        matchedLine: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestions = suggestions
        self.matchedLine = matchedLine
    }
}

struct MinecraftLogManager: @unchecked Sendable {
    var fileManager: FileManager = .default

    func scan(minecraftDirectory: URL, additionalDirectories: [URL] = []) -> [MinecraftLogEntry] {
        var urls: [(URL, MinecraftLogKind)] = []
        let latestLog = minecraftDirectory.appendingPathComponent("logs/latest.log")
        if fileManager.fileExists(atPath: latestLog.path) {
            urls.append((latestLog, .latest))
        }

        let logsDirectory = minecraftDirectory.appendingPathComponent("logs", isDirectory: true)
        urls.append(contentsOf: files(in: logsDirectory, matching: { name in
            name.hasSuffix(".log") && name != "latest.log"
        }).map { ($0, installerKind(for: $0)) })

        let crashDirectory = minecraftDirectory.appendingPathComponent("crash-reports", isDirectory: true)
        urls.append(contentsOf: files(in: crashDirectory, matching: { name in
            name.hasPrefix("crash-") && name.hasSuffix(".txt")
        }).map { ($0, MinecraftLogKind.crashReport) })

        for directory in additionalDirectories {
            urls.append(contentsOf: files(in: directory, matching: { name in
                name.hasPrefix("hs_err_pid") && name.hasSuffix(".log")
            }).map { ($0, MinecraftLogKind.jvmCrash) })
        }

        return urls
            .map { entry(url: $0.0, kind: $0.1) }
            .sorted { lhs, rhs in
                (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
    }

    func preview(_ entry: MinecraftLogEntry, maxLines: Int = 160) -> MinecraftLogPreview {
        guard let content = try? String(contentsOf: entry.url, encoding: .utf8) else {
            return MinecraftLogPreview(text: "无法读取日志文件：\(entry.url.path)", lineCount: 0, isTruncated: false)
        }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count <= maxLines {
            return MinecraftLogPreview(text: content, lineCount: lines.count, isTruncated: false)
        }
        let tail = lines.suffix(maxLines).joined(separator: "\n")
        return MinecraftLogPreview(text: tail, lineCount: lines.count, isTruncated: true)
    }

    func diagnose(_ entry: MinecraftLogEntry) -> [MinecraftLogDiagnosis] {
        guard let content = try? String(contentsOf: entry.url, encoding: .utf8) else {
            return [
                MinecraftLogDiagnosis(
                    id: "unreadable",
                    severity: .warning,
                    title: "无法读取日志",
                    detail: "启动器没有读到这个日志文件的文本内容。",
                    suggestions: ["在 Finder 中检查文件权限", "确认日志文件没有被其他应用占用"]
                )
            ]
        }
        return diagnose(content: content, kind: entry.kind)
    }

    func diagnose(content: String, kind: MinecraftLogKind) -> [MinecraftLogDiagnosis] {
        let lowercased = content.lowercased()
        var diagnoses: [MinecraftLogDiagnosis] = []

        if lowercased.contains("unsupportedclassversionerror")
            || lowercased.contains("has been compiled by a more recent version of the java runtime")
            || lowercased.contains("class file version") {
            let requiredJava = requiredJavaVersion(in: content)
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "java-version",
                    severity: .critical,
                    title: "Java 版本不匹配",
                    detail: requiredJava.map { "日志显示游戏或 Mod 需要 Java \($0) 或更高版本。" } ?? "日志显示当前 Java 版本无法加载某些 class 文件。",
                    suggestions: [
                        "在启动页或 设置 > 版本 中切换到更高版本 Java",
                        "Minecraft 1.20.5 及以上通常建议 Java 21",
                        "切换 Java 后重新启动一次游戏"
                    ],
                    matchedLine: firstLineContaining(in: content, markers: ["UnsupportedClassVersionError", "class file version"])
                )
            )
        }

        if lowercased.contains("outofmemoryerror")
            || lowercased.contains("java heap space")
            || lowercased.contains("gc overhead limit exceeded") {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "out-of-memory",
                    severity: .critical,
                    title: "内存不足",
                    detail: "游戏进程用尽了分配的堆内存，常见于整合包、高清材质或大量 Mod。",
                    suggestions: [
                        "在 设置 > 启动 或 设置 > 版本 中提高内存",
                        "关闭不必要的资源包或降低视距",
                        "如果已经分配很大内存，检查是否有异常 Mod 占用"
                    ],
                    matchedLine: firstLineContaining(in: content, markers: ["OutOfMemoryError", "Java heap space", "GC overhead"])
                )
            )
        }

        if lowercased.contains("modresolutionexception")
            || lowercased.contains("unmet dependency")
            || lowercased.contains("missing required")
            || lowercased.contains("requires any version")
            || lowercased.contains("requires version")
            || lowercased.contains("depends on") {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "mod-dependency",
                    severity: .critical,
                    title: "Mod 缺少依赖或版本不兼容",
                    detail: "日志里出现依赖解析失败，通常是前置 Mod 未安装、加载器不对，或 Mod 版本和 Minecraft 版本不匹配。",
                    suggestions: [
                        "在下载页搜索并安装缺少的前置 Mod",
                        "确认 Fabric、Forge、Quilt 或 NeoForge 与实例一致",
                        "把最近新增的 Mod 暂时禁用后再试"
                    ],
                    matchedLine: firstLineContaining(in: content, markers: ["ModResolutionException", "Unmet dependency", "Missing required", "requires any version", "requires version", "depends on"])
                )
            )
        }

        if lowercased.contains("mixin apply failed")
            || lowercased.contains("mixintransformererror")
            || lowercased.contains("injectionerror")
            || lowercased.contains("critical injection failure") {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "mixin-conflict",
                    severity: .critical,
                    title: "Mixin 注入冲突",
                    detail: "某个 Mod 在修改游戏代码时失败，常见于 Mod 互相冲突或版本不匹配。",
                    suggestions: [
                        "优先检查最近更新或新增的 Mod",
                        "把相关 Mod 更新到同一 Minecraft 版本对应的构建",
                        "必要时二分禁用 mods 文件夹里的 Mod"
                    ],
                    matchedLine: firstLineContaining(in: content, markers: ["Mixin apply failed", "MixinTransformerError", "InjectionError", "Critical injection failure"])
                )
            )
        }

        if lowercased.contains("noclassdeffounderror")
            || lowercased.contains("classnotfoundexception")
            || lowercased.contains("nosuchmethoderror")
            || lowercased.contains("nosuchfielderror") {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "missing-class",
                    severity: .warning,
                    title: "缺少类或 API 不兼容",
                    detail: "运行时找不到某个 class、方法或字段，通常来自缺少前置库、Mod 版本不匹配，或加载器版本过旧。",
                    suggestions: [
                        "检查日志匹配行里的包名或 Mod 名",
                        "更新相关前置库和加载器",
                        "确认 Mod 下载的是当前实例对应的 Minecraft 版本"
                    ],
                    matchedLine: firstLineContaining(in: content, markers: ["NoClassDefFoundError", "ClassNotFoundException", "NoSuchMethodError", "NoSuchFieldError"])
                )
            )
        }

        let graphicsMatchedLine = firstLineContaining(
            in: content,
            markers: [
                "GLFW error",
                "Failed to create window",
                "LWJGLException",
                "Could not create GL",
                "OpenGL error",
                "OpenGL context",
                "No OpenGL context",
                "Failed to initialize OpenGL"
            ]
        )
        if let graphicsMatchedLine {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "graphics-native",
                    severity: .warning,
                    title: "图形或原生库问题",
                    detail: "日志包含 GLFW、LWJGL 或 OpenGL 相关错误，可能与 macOS 原生库、显卡能力或 Java 架构有关。",
                    suggestions: [
                        "确认使用 arm64 Java，避免混用 x86_64 Java",
                        "尝试切换 Java 版本后重新启动",
                        "如果使用光影或渲染类 Mod，先临时禁用"
                    ],
                    matchedLine: graphicsMatchedLine
                )
            )
        }

        if lowercased.contains("invalid session")
            || lowercased.contains("access token")
            || lowercased.contains("authentication servers")
            || lowercased.contains("401 unauthorized")
            || lowercased.contains("forbidden operation") {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "auth-session",
                    severity: .warning,
                    title: "登录会话或认证失败",
                    detail: "日志显示账号会话、access token 或认证服务器访问异常。",
                    suggestions: [
                        "重新登录当前账户",
                        "如果是第三方认证，检查 Authlib 或统一通行证服务器地址",
                        "确认网络可以访问认证服务器"
                    ],
                    matchedLine: firstLineContaining(in: content, markers: ["Invalid session", "access token", "authentication servers", "401 Unauthorized", "Forbidden operation"])
                )
            )
        }

        if lowercased.contains("zipexception")
            || lowercased.contains("invalid loc header")
            || lowercased.contains("checksum")
            || lowercased.contains("sha-1")
            || lowercased.contains("corrupt") {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "corrupt-file",
                    severity: .warning,
                    title: "文件可能损坏",
                    detail: "日志里出现压缩包、校验或损坏文件相关错误。",
                    suggestions: [
                        "删除对应 library、Mod 或资源包后重新下载",
                        "在下载页查看任务是否有失败记录",
                        "如果是整合包，重新导入一次"
                    ],
                    matchedLine: firstLineContaining(in: content, markers: ["ZipException", "invalid LOC header", "checksum", "SHA-1", "corrupt"])
                )
            )
        }

        if kind == .jvmCrash {
            diagnoses.append(
                MinecraftLogDiagnosis(
                    id: "jvm-crash",
                    severity: diagnoses.isEmpty ? .critical : .warning,
                    title: "JVM 原生崩溃",
                    detail: "这是 Java 虚拟机级别的崩溃，不只是 Minecraft 普通异常。macOS 上常见诱因包括原生库、图形栈、Java 架构或 JNI Mod。",
                    suggestions: [
                        "优先切换到另一套 Java 运行时",
                        "检查是否有渲染、输入法、语音或 JNI 类 Mod",
                        "把 Problematic frame 发给 Mod 作者或保留用于排查"
                    ],
                    matchedLine: firstMatchingLine(in: content, prefixes: ["# Problematic frame:"]) ?? firstLineContaining(in: content, markers: ["Problematic frame"])
                )
            )
        }

        return Array(diagnoses.prefix(4))
    }

    private func files(in directory: URL, matching predicate: (String) -> Bool) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { url in
            guard predicate(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                return false
            }
            return true
        }
    }

    private func installerKind(for url: URL) -> MinecraftLogKind {
        let name = url.lastPathComponent.lowercased()
        return name.contains("installer") ? .installer : .latest
    }

    private func entry(url: URL, kind: MinecraftLogKind) -> MinecraftLogEntry {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        let summary = summarize(url: url, kind: kind)
        return MinecraftLogEntry(
            id: url.path,
            url: url,
            kind: kind,
            name: url.lastPathComponent,
            modifiedAt: values?.contentModificationDate,
            size: size,
            summary: summary
        )
    }

    private func summarize(url: URL, kind: MinecraftLogKind) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "无法读取"
        }
        switch kind {
        case .jvmCrash:
            return summarizeJVMCrash(content)
        case .crashReport:
            return firstMatchingLine(in: content, prefixes: ["Description:"])
                ?? firstMatchingLine(in: content, prefixes: ["Time:"])
                ?? "Minecraft 崩溃报告"
        case .installer:
            return firstInterestingLine(in: content) ?? "加载器安装日志"
        case .latest:
            return firstInterestingLine(in: content) ?? "Minecraft 运行日志"
        }
    }

    private func summarizeJVMCrash(_ content: String) -> String {
        let java = parseJavaVersion(content)
        if let problematicFrame = firstMatchingLine(in: content, prefixes: ["# Problematic frame:"]) {
            return "\(java) · \(problematicFrame.replacingOccurrences(of: "#", with: "").trimmed)"
        }
        return java
    }

    private func firstInterestingLine(in content: String) -> String? {
        let markers = ["error", "exception", "failed", "warn", "crash"]
        return content
            .split(separator: "\n")
            .map { String($0).trimmed }
            .last { line in
                let lowercased = line.lowercased()
                return markers.contains { lowercased.contains($0) }
            }
    }

    private func firstMatchingLine(in content: String, prefixes: [String]) -> String? {
        content
            .split(separator: "\n")
            .map { String($0).trimmed }
            .first { line in
                prefixes.contains { line.hasPrefix($0) }
            }
    }

    private func firstLineContaining(in content: String, markers: [String]) -> String? {
        let markerSet = markers.map { $0.lowercased() }
        return content
            .split(separator: "\n")
            .map { String($0).trimmed }
            .first { line in
                let lowercased = line.lowercased()
                return markerSet.contains { lowercased.contains($0) }
            }
            .map(clippedDiagnosticLine)
    }

    private func requiredJavaVersion(in content: String) -> Int? {
        let pattern = #"class file version(?:\s+is)?\s+([0-9]+)(?:\.0)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges > 1,
              let majorRange = Range(match.range(at: 1), in: content),
              let major = Int(content[majorRange]),
              major >= 49 else {
            return nil
        }
        return major - 44
    }

    private func clippedDiagnosticLine(_ line: String) -> String {
        guard line.count > 220 else { return line }
        let cutoff = line.index(line.startIndex, offsetBy: 220)
        return "\(line[..<cutoff])..."
    }
}
