# Plain Craft Launcher (PCL) macOS

这是第三方基于 Plain Craft Launcher 独立进行二次创作的 macOS 原生重构工程，不是官方 PCL。当前目标是用 SwiftUI/AppKit 提供接近 PCL 的启动、下载、联机、设置和更多页体验，并尽量使用 Apple 原生组件。

交互式文档请看 [README.html](README.html)，其中包含分区展示和一键复制按钮。本文件用于 GitHub README 与普通 Markdown 阅读场景。

## 授权与署名

本项目属于原 `LICENCE` 中的重度使用：它重新实现了 PCL 的 Minecraft 启动、下载和 Mod 管理等实质功能。因此仓库、应用关于页和文档均明确标注第三方二创身份，并保留原作者署名。

| 项目 | 内容 |
| --- | --- |
| 原作作者 | 龙腾猫跃 |
| 原项目 | <https://github.com/Meloong-Git/PCL> |
| 赞助链接 | <https://meloong.com/afd/a/LTCat> |
| 授权文件 | [LICENCE](LICENCE) |

## 环境要求

- macOS 14 或更新版本
- Xcode Command Line Tools
- Swift Package Manager
- Minecraft Java 版本地目录，默认使用 `~/Library/Application Support/minecraft`

## 运行

```bash
cd PCLMac
swift run PCLMac
```

如果你是在独立仓库根目录运行：

```bash
swift run PCLMac
```

## 构建 `.app`

```bash
cd PCLMac
chmod +x Scripts/build-macos-app.sh
Scripts/build-macos-app.sh
open "dist/Plain Craft Launcher (PCL) macOS.app"
```

如果你是在独立仓库根目录运行：

```bash
chmod +x Scripts/build-macos-app.sh
Scripts/build-macos-app.sh
open "dist/Plain Craft Launcher (PCL) macOS.app"
```

打包脚本默认输出到 `dist`，Bundle ID 默认为 `com.paipaiio.pcl`。如果需要安装到 Applications：

```bash
Scripts/build-macos-app.sh --install
open "/Applications/Plain Craft Launcher (PCL) macOS.app"
```

## 当前已接入

- SwiftUI/AppKit 原生 macOS 窗口、菜单栏和快捷键。
- 接近 PCL 的顶部导航、左右分栏和启动页布局。
- Minecraft 文件夹扫描，可在设置页切换自定义 Minecraft 根目录。
- Java 探测与自动选择，支持 `/usr/libexec/java_home`、`which java`、SDKMAN、`/Library/Java/JavaVirtualMachines`，以及 PCL 自带 Mojang Java Runtime 目录。
- 离线启动链：解析版本 JSON、继承链、library、macOS natives、classpath，并执行 Java 进程。
- 依赖补全：下载 client jar、libraries、native jars、asset index、asset objects，并做 SHA-1 校验。
- 版本列表管理：搜索、收藏、隐藏、显示隐藏版本、快速筛选和右键菜单。
- 版本下载：支持官方、BMCLAPI、官方 + BMCLAPI 下载源。
- Fabric、Quilt、Forge、NeoForge 安装链。
- Microsoft 正版登录链：Device Code、OAuth refresh、Xbox Live、XSTS、Minecraft Services、正版资格校验和 Profile 获取。
- 统一通行证 Nide 登录链，按 PCL 原版添加 `nide8auth.jar` JVM agent。
- Authlib-Injector 登录链，支持服务器地址、认证、刷新、多角色选择和 JVM agent 参数。
- Keychain 凭据保存，Microsoft、Nide、Authlib 的敏感凭据不写入普通偏好设置。
- Modrinth 与 CurseForge 的 Mod、整合包、资源包搜索与安装。
- 本地 `.mrpack` / CurseForge `.zip` 整合包导入为独立实例。
- 本地 Mod 管理：扫描、识别、启用/禁用、Finder 显示和添加本地 Mod 文件。
- 联机页：扫描 Minecraft 局域网广播、复制房间地址、写入启动后自动进服设置、保存常用服务器。
- 日志与崩溃报告：扫描 `latest.log`、`crash-reports`、`hs_err_pid*.log`，提供摘要、预览、复制和本地诊断。
- 启动退出监控：记录 PID、退出码和运行时长，异常退出自动切到日志诊断。
- 启动配置摘要、启动前就绪检查、启动命令预览与停止按钮。
- Mojang Java Runtime 安装，安装到 `~/Library/Application Support/PCL/JavaRuntimes`。
- macOS 原生通知，默认关闭，可在设置页开启。
- Dock 角标，默认开启，用于显示任务数量或游戏运行状态。
- 高性能模式，降低毛玻璃、阴影、背景图、模糊和复杂动画成本。

## 偏好设置

启动器使用 macOS 原生 `UserDefaults` 保存轻量设置。Keychain 只用于保存敏感登录凭据。

| 分类 | 内容 |
| --- | --- |
| 账户 | 登录模式、离线玩家名、统一通行证服务器 ID、Authlib 服务器、上次选择账户 |
| 启动 | 内存、窗口尺寸、全屏、版本隔离、自动进服、全局 JVM 参数、全局游戏参数 |
| 系统 | 自定义 Minecraft 文件夹、自动选择 Java |
| 下载 | 下载源、下载线程、默认加载器、CurseForge API Key |
| 界面 | 高性能模式、主题色、窗口外观、首页卡片、背景图 |
| 任务 | 下载任务历史、暂停/继续/重试状态 |

## Microsoft Client ID

`client_id` 是 Microsoft 应用注册的公开应用编号，用来告诉 Microsoft 正在请求授权的是哪个启动器应用。它不是用户密码，也不是 client secret。

macOS 版会按下面顺序读取：

1. 设置页填写的高级覆盖值。
2. 运行环境变量 `PCL_MS_CLIENT_ID`。
3. app 包内置的 `PCLMicrosoftClientID`。

正式分发包应在打包时内置它，普通用户不需要自己填写：

```bash
PCL_MS_CLIENT_ID="你的 Microsoft 应用 Client ID" Scripts/build-macos-app.sh
plutil -p "dist/Plain Craft Launcher (PCL) macOS.app/Contents/Info.plist" | grep PCLMicrosoftClientID
```

## CurseForge API Key

CurseForge 搜索下载需要 API Key。可以在设置页填写，也可以通过环境变量提供：

```bash
export PCL_CURSEFORGE_API_KEY="你的 CurseForge API Key"
swift run PCLMac
```

## 测试

```bash
swift test
```

当前测试覆盖启动参数生成、依赖下载计划、登录链、整合包导入、Mod 管理、任务中心、Java Runtime 安装、通知、Dock 角标和崩溃诊断等核心路径。

## 重要说明

- 本项目不是 Mojang、Microsoft 或 PCL 官方产品。
- 本项目不会在仓库中提交 Microsoft Client ID、CurseForge API Key 或任何用户凭据。
- `README.html` 是交互式技术文档版本；`README.md` 是 GitHub/Markdown 阅读版本，两者会并行保留。
