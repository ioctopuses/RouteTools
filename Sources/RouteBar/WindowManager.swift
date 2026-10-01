import AppKit
import SwiftUI

/// 统一管理 RouteBar 的窗口（主窗口 / 设置 / 添加·编辑路由）。
///
/// **为什么用 AppKit 管窗口，而不是 SwiftUI 的 `Window` Scene**：
/// 快速启动页由 `AppDelegate` 用 `NSHostingController` 桥接进 `NSPopover`，
/// 那个视图**不在任何 Scene 里**，拿不到 SwiftUI 注入的 `openWindow`
/// 环境值 —— 在它里面调 `openWindow(id:)` 会静默失效（点了没反应）。
/// 改为 AppKit 统一创建/前置窗口后，菜单栏、应用菜单、主窗口三个入口
/// 走的是同一条确定路径，不再依赖环境值是否存在。
///
/// **激活策略**（决定「有没有 Dock 图标、顶部菜单栏显不显示」）：
///   - 只要有窗口可见 → `.regular`：有 Dock 图标，顶部出现 RouteBar 应用菜单
///   - 窗口全关且菜单栏快速启动图标开着 → `.accessory`：完全收回菜单栏，不占 Dock
///   - 窗口全关但**菜单栏图标关着** → 保持 `.regular`：Dock 图标成为唯一入口，
///     否则用户会陷入「图标关了、窗口关了、没地方点」的死路
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {

    static let shared = WindowManager()

    private var store: RouteStore?

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var editWindow: NSWindow?

    private override init() { super.init() }

    /// 由 AppDelegate 在启动时注入
    func configure(store: RouteStore) {
        self.store = store
    }

    // MARK: - 对外入口

    /// 打开（或前置）主窗口「路由管理」
    func showMainWindow() {
        guard let store else { return }
        if mainWindow == nil {
            let root = RouteListView().environmentObject(store)
            mainWindow = makeWindow(title: "路由管理",
                                    size: NSSize(width: 620, height: 460),
                                    minSize: NSSize(width: 520, height: 320),
                                    root: root)
        }
        present(mainWindow)
    }

    /// 打开（或前置）设置窗口
    func showSettings() {
        guard let store else { return }
        if settingsWindow == nil {
            let root = SettingsView().environmentObject(store)
            settingsWindow = makeWindow(title: "设置",
                                        size: NSSize(width: 580, height: 660),
                                        minSize: NSSize(width: 520, height: 540),
                                        root: root)
        }
        present(settingsWindow)
    }

    /// 打开添加（`route == nil`）或编辑路由窗口
    func showEditor(route: Route?) {
        guard let store else { return }
        editWindow?.close()   // 同一时刻只留一个编辑窗口

        let root = RouteEditView(route: route) { [weak self] in
            self?.editWindow?.close()
        }
        .environmentObject(store)

        let window = makeWindow(title: route == nil ? "添加路由" : "编辑路由",
                                size: NSSize(width: 440, height: 300),
                                minSize: NSSize(width: 420, height: 280),
                                root: root)
        editWindow = window
        present(window)
    }

    /// 「关于 RouteBar」（走系统标准面板）
    func showAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// 当前是否有任何窗口可见
    var hasVisibleWindow: Bool {
        [mainWindow, settingsWindow, editWindow].contains { $0?.isVisible == true }
    }

    /// 重新计算激活策略。窗口开合、以及「菜单栏快速启动图标」开关变化时都要调。
    func refreshActivationPolicy() {
        if hasVisibleWindow {
            NSApp.setActivationPolicy(.regular)
            return
        }
        // 没有窗口：菜单栏图标还在 → 收回 Dock 图标；图标关着 → 保留 Dock 图标当入口
        let menuBarIconOn = store?.showInMenuBar ?? true
        NSApp.setActivationPolicy(menuBarIconOn ? .accessory : .regular)
    }

    // MARK: - 内部

    private func makeWindow<Content: View>(title: String,
                                           size: NSSize,
                                           minSize: NSSize,
                                           root: Content) -> NSWindow {
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.contentMinSize = minSize
        // 关掉窗口不释放对象 —— 下次 showMainWindow()/showSettings() 直接复用
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 关闭瞬间 isVisible 还没翻转，等下一轮再算
        DispatchQueue.main.async { [weak self] in
            self?.refreshActivationPolicy()
        }
    }
}
