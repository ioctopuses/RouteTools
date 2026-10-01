import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

/// AppDelegate 接管菜单栏 UI 与窗口生命周期。
///
/// **菜单栏图标点开的是「快速启动页」，不是主窗口** —— 这是两个不同的界面：
///   · 菜单栏图标 / ⌥⌘R → 快速启动页（搜索 + 一键开关，轻量）
///   · 主窗口「路由管理」 / 应用菜单 → 完整管理 + 设置入口
///
/// **为什么不用 SwiftUI 的 `MenuBarExtra`**：
///   1. SwiftUI 没有公开「可见性」绑定 —— 无法表达"在菜单栏里完全隐藏"，
///      而 `NSStatusItem.isVisible` 直接支持（「在菜单栏显示快速启动图标」开关要用）；
///   2. `NSStatusItem` 切换可见性时无需重建视图。
///
/// **菜单栏图标隐藏时的兜底入口**：用 Carbon `RegisterEventHotKey` 注册
/// 全局快捷键 ⌥⌘R 唤起快速启动页。Carbon 热键**无需任何权限**
/// （与 `NSEvent.addGlobalMonitorForEvents` 需要辅助功能权限不同）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 由 AppDelegate 持有，SwiftUI 视图通过 `environmentObject` 注入。
    ///
    /// 注意：`@NSApplicationDelegateAdaptor` 在 `App.init()` 之前实例化
    /// 本类，因此 `store` 在此期间就完成初始化（包含 RouteStore 的 `init`
    /// —— 读 UserDefaults、syncSystemRoutes 等都按既有逻辑进行）。
    let store = RouteStore()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 窗口管理统一交给 WindowManager
        WindowManager.shared.configure(store: store)

        // ── 状态栏按钮 ────────────────────────────────────────────
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
        }

        // ── Popover（SwiftUI 内容桥接） ──────────────────────────
        popover.behavior = .transient  // 点击外部自动关闭
        let content = QuickLaunchView().environmentObject(store)
        popover.contentViewController = NSHostingController(rootView: content)

        // ── 同步 showInMenuBar → statusItem.isVisible ─────────────
        statusItem.isVisible = store.showInMenuBar
        store.$showInMenuBar
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                guard let self = self else { return }
                self.statusItem.isVisible = visible
                // 关掉图标时如果 popover 还开着，先关掉 —— 否则显示逻辑矛盾
                if !visible, self.popover.isShown {
                    self.popover.performClose(nil)
                }
                // 图标开关会改变「窗口全关时要不要留 Dock 图标」的判定
                WindowManager.shared.refreshActivationPolicy()
            }
            .store(in: &cancellables)

        // ── 全局快捷键 ⌥⌘R：唤起快速启动页 ────────────────────────
        registerGlobalHotKey()

        NotificationCenter.default.publisher(for: .rbToggleQuickLaunch)
            .sink { [weak self] _ in
                self?.togglePopover()
            }
            .store(in: &cancellables)

        // ── 关闭 popover 请求（打开窗口 / 需要切界面时） ───────────
        NotificationCenter.default.publisher(for: .rbClosePopover)
            .sink { [weak self] _ in
                guard let self = self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
            .store(in: &cancellables)

        // ── 启动后打开主窗口 ──────────────────────────────────────
        // 「打开软件」的预期是看到界面；关掉窗口后应用仍留在菜单栏。
        WindowManager.shared.showMainWindow()

        // ── 启动后静默检查更新 ────────────────────────────────────
        // 延迟若干秒，避免与首帧渲染、路由同步抢主线程。
        // 失败不打扰用户（只写日志），只有真的发现新版本才弹窗询问。
        if store.autoCheckForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.updateCheckLaunchDelay) {
                Task { @MainActor in
                    await UpdateChecker.shared.check(interactive: false)
                }
            }
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        togglePopover()
    }

    /// 菜单栏图标：用**自家设计**的模板图（`Resources/MenuBarIcon.png`，
    /// 由 `make_menubar_icon.py` 生成；@1x/@2x 两个分辨率一起进包）。
    ///
    /// **为什么必须 `isTemplate = true`**：模板图只取 alpha 通道，由系统决定
    /// 颜色 —— 深色菜单栏渲染白色、浅色菜单栏渲染黑色，并自动跟随高亮与失焦。
    /// 若把 PNG 本身画成纯白，浅色菜单栏上会彻底看不见。
    /// （用户要的「白色」在深色菜单栏下就是这个效果，而且是自适应的。）
    ///
    /// 早期版本这里写的是 SF Symbol `network` —— 那是个"地球/经纬线"造型，
    /// 与 App 的「节点 → 网关」路由母题毫无关系，正是"菜单栏是个地球"的原因。
    private static func menuBarIcon() -> NSImage? {
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            // 按 pt 指定显示尺寸；系统会按需挑 @1x(18) / @2x(36) 那张
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        // 兜底：万一资源没打进包（例如手工编译漏拷 Resources/），
        // 退回系统符号，至少保证菜单栏还能点开快速启动页。
        print("[RouteBar] 未找到 MenuBarIcon 资源，回退到系统符号。")
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        return NSImage(systemSymbolName: "arrow.triangle.branch",
                       accessibilityDescription: "RouteBar")?
            .withSymbolConfiguration(config)
    }

    /// 切换快速启动页显示/隐藏。也可由全局快捷键（菜单栏图标隐藏时）触发。
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // 让 popover 拿到键盘焦点（⌘O/⌘Q 快捷键可用）
        popover.contentViewController?.view.window?.makeKey()
        // 再把焦点交给**搜索框**。顺序不能颠倒：`makeKey()` 会把窗口的
        // firstResponder 重置回默认值，抢在它之前设的焦点会被这一下清掉
        // （"唤起快速启动页时光标不在搜索框"就是这么来的）。
        // 再等一个 runloop 才发，是因为 makeKey 之后 SwiftUI 还要完成这一轮布局，
        // 视图挂进 window 之后再设 `FocusState` 才生效。
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .rbFocusQuickSearch, object: nil)
        }
    }

    // MARK: - 应用级事件

    /// 关掉最后一个窗口不退出应用（保持菜单栏/后台常驻）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 点击 Dock 图标（或重新打开 App）时把主窗口找回来
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.showMainWindow()
        }
        return true
    }

    // MARK: - Carbon 全局快捷键

    /// 注册 ⌥⌘R 全局热键。Carbon `RegisterEventHotKey` 不需要任何权限
    /// （与 `NSEvent.addGlobalMonitorForEvents` 需要辅助功能权限不同），
    /// 但回调可能在任意线程触发，需用 `DispatchQueue.main.async` 切回主线程。
    private func registerGlobalHotKey() {
        var ref: EventHotKeyRef?
        let keyCode = UInt32(kVK_ANSI_R)              // R = 19
        let modifiers = UInt32(cmdKey | optionKey)
        // 四字符签名 'RBRT'（RouteBar Route Toggle），需 OSType 格式
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x5242_5254),
            id: 1
        )

        let regStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard regStatus == noErr, let ref = ref else {
            // 注册失败时仍要让 App 可用 —— 退化为"从菜单栏图标唤起"
            print("[RouteBar] 全局快捷键 ⌥⌘R 注册失败（status=\(regStatus)）。")
            return
        }
        self.hotKeyRef = ref

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // EventHandlerUPP 是 C 函数指针，闭包里不能直接引用 Swift 实例。
        // 用 NotificationCenter 把"任意线程"的消息桥接到"主线程"的订阅者。
        let handler: EventHandlerUPP = { (_, _, _) -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .rbToggleQuickLaunch, object: nil)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(), handler, 1, &eventType, nil, nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

extension Notification.Name {
    /// 唤起/收起快速启动页（全局快捷键和「打开快速启动」菜单项共用）
    static let rbToggleQuickLaunch = Notification.Name("io.routebar.toggleQuickLaunch")

    /// 请求关闭菜单栏 popover（打开窗口 / 切界面时用）
    static let rbClosePopover = Notification.Name("io.routebar.closePopover")

    /// 请求快速启动页把**键盘焦点交给搜索框**。
    ///
    /// 由 `AppDelegate.togglePopover()` 在 `makeKey()` **之后**发出（时序理由见
    /// `RBSearchField.focusNonce`）；订阅方是 `QuickLaunchView`。
    static let rbFocusQuickSearch = Notification.Name("io.routebar.focusQuickSearch")
}
