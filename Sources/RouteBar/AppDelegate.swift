import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

/// AppDelegate 接管菜单栏 UI 生命周期。
///
/// 为什么不用 SwiftUI 的 `MenuBarExtra`：
///   1. SwiftUI 没有公开「可见性」绑定 —— 无法表达"在菜单栏里完全隐藏"。
///      `NSStatusItem.isVisible` 直接支持。
///   2. `NSStatusItem` 切换可见性时无需重建视图。
///
/// 因此 `RouteBarApp` 改为 `@NSApplicationDelegateAdaptor` 接入本类，
/// 这里创建 `NSStatusItem` + `NSPopover`（用 `NSHostingController` 桥接
/// SwiftUI 视图）替代 `MenuBarExtra`。
///
/// **菜单栏图标隐藏时的兜底入口**：LSUIElement=true 没有 Dock 图标，
/// 菜单栏图标是用户唯一能打开菜单的入口。关掉后用 Carbon
/// `RegisterEventHotKey` 注册全局快捷键 ⌥⌘R 唤起 popover。
/// Carbon 热键**无需任何权限**（与 `NSEvent.addGlobalMonitorForEvents`
/// 需要辅助功能权限不同）。
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
        // ── 状态栏按钮 ────────────────────────────────────────────
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // pointSize: 18 让 SF Symbol 与其它 ~22pt 菜单栏 App 大小接近
            // （`NSImage(systemSymbolName:)` 默认按 ~13pt 渲染，瘦一圈）
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            button.image = NSImage(systemSymbolName: "network",
                                    accessibilityDescription: "RouteBar")?
                .withSymbolConfiguration(symbolConfig)
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
        }

        // ── Popover（SwiftUI 内容桥接） ──────────────────────────
        popover.behavior = .transient  // 点击外部自动关闭
        let content = MenuBarContent().environmentObject(store)
        popover.contentViewController = NSHostingController(rootView: content)

        // ── 同步 showInMenuBar → statusItem.isVisible ─────────────
        // 初值：从 store 当前值手动同步一次（init 已从 UserDefaults 恢复）
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
            }
            .store(in: &cancellables)

        // ── 全局快捷键 ⌥⌘R：菜单栏图标隐藏时的兜底入口 ──────────
        registerGlobalHotKey()

        NotificationCenter.default.publisher(for: .rbHotKeyPressed)
            .sink { [weak self] _ in
                self?.togglePopover()
            }
            .store(in: &cancellables)
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        togglePopover()
    }

    /// 切换 popover 显示/隐藏。也可由全局快捷键（菜单栏图标隐藏时）触发。
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
            // 注册失败时仍要让 App 可用 —— 退化为"重启 App" 兜底
            print("[RouteBar] 全局快捷键 ⌥⌘R 注册失败（status=\(regStatus)）。" +
                  "关闭图标后无法用快捷键唤起，需重启 App 恢复显示。")
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
                NotificationCenter.default.post(name: .rbHotKeyPressed, object: nil)
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
    static let rbHotKeyPressed = Notification.Name("io.routebar.hotkey")
}
