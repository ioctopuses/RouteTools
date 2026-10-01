import Foundation

/// 应用级常量。
enum AppConfig {

    /// RouteBar 自身的 Bundle Identifier。
    ///
    /// 必须与 `Info.plist` 的 `CFBundleIdentifier` 一致 —— 自动更新会用它
    /// 校验下载下来的新包「是不是本应用」，对不上就拒绝安装。
    static let bundleID = "com.example.routebar"

    /// 更新源仓库（`owner/repo`）。
    ///
    /// RouteTools 仓库本身是**公开**的，客户端可以直接读它的 Release，
    /// 因此不像 ApexBar 那样需要另建一个 releases-only 仓库。
    static let updateFeedRepo = "ioctopuses/RouteTools"

    /// 启动后自动检查更新的延迟（秒）。
    ///
    /// 放到启动若干秒之后：让菜单栏图标、路由同步先就位，避免更新检查
    /// 与首帧渲染抢主线程。失败静默，只有真的发现新版本才打扰用户。
    static let updateCheckLaunchDelay: TimeInterval = 8.0
}

/// 读取应用版本号（`CFBundleShortVersionString`）。
///
/// 放在这里而不是 `RouteBarApp.swift`：视图文件（主窗口 / 设置页 / 快速启动）
/// 都要读版本号，而离屏渲染这些视图时**不需要**也不应该带上 `@main` 入口。
extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
