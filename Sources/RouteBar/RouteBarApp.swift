import SwiftUI
import AppKit

/// 应用入口。
///
/// **窗口不由 SwiftUI 的 `Window` Scene 管理**，而是统一交给 `WindowManager`
/// （AppKit）。原因见 `WindowManager` 的注释：快速启动页是从 `AppDelegate`
/// 桥接进 `NSPopover` 的，不在任何 Scene 里，拿不到 `openWindow` 环境值。
///
/// 这里只保留一个 `Settings` 场景作为 **Scene 锚点** —— SwiftUI 的 `App`
/// 必须提供至少一个 Scene，且应用菜单（`.commands`）需要挂在它上面。
/// 真正打开窗口时一律走 `WindowManager`。
///
/// 界面本体在 `MainWindow.swift`（主窗口 / 路由行 / 添加编辑表单）、
/// `QuickLaunchView.swift`、`SettingsView.swift`，与入口分开以便单独复用。
@main
struct RouteBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // 真正的设置窗口由 WindowManager 创建，这里只是占位
            EmptyView()
        }
        .commands {
            // ── 关于 RouteBar ──────────────────────────────────────
            CommandGroup(replacing: .appInfo) {
                Button("关于 RouteBar") { WindowManager.shared.showAbout() }
            }

            // ── 偏好设置… ⌘, ───────────────────────────────────────
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置…") { WindowManager.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }

            // ── 窗口与维护 ────────────────────────────────────────
            // 注意：这里**只放窗口/维护入口**，「在菜单栏显示快速启动图标」
            // 与「启动时自动应用已启用路由」两个开关按设计已移到设置页，
            // 不再出现在应用菜单里。
            CommandGroup(after: .appSettings) {
                Button("打开主窗口") { WindowManager.shared.showMainWindow() }
                    .keyboardShortcut("o", modifiers: .command)

                Button("打开快速启动") {
                    NotificationCenter.default.post(name: .rbToggleQuickLaunch, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                Button("清除授权缓存") { PrivilegedRunner.resetAuthorization() }
            }

            // ── 退出 ──────────────────────────────────────────────
            CommandGroup(replacing: .appTermination) {
                Button("退出 RouteBar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
