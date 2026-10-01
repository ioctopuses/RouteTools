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
/// **窗口形态对齐 ApexBar 的设置窗口**：
/// 一律用标准 `NSWindow`，SwiftUI 视图用 `NSHostingView` **直接挂成 `contentView`**
/// —— 操作控件由窗口自己的工具栏承载，落在**标题栏那一行、与红绿灯同行**；
/// 主窗口与添加·编辑窗口不再显示标题（设置窗口那一行由分页占据）。
/// **`.fullSizeContentView` 只用来让「背景」延伸到标题栏**（主窗口传 `fullSizeContent: true`）：
/// 标题栏透明、内容视图扩展到标题栏下方，SwiftUI 侧铺的分栏底色（左灰右白）才能一路
/// 画到窗口最顶端 —— 红绿灯那一行也跟着侧栏变色，即张瑜 2026-10-02 要的"macOS 27 风格"。
/// **控件仍全部由系统工具栏承载，没有一处自绘标题行**：早先试过"完全自绘标题行"那条路，
/// 需要让开红绿灯、硬编码几何常量、还要跟 SwiftUI 的 safe area 搏斗（实测标题行被整体
/// 下推 32pt），换来的只是"看起来像原生"；而直接用标准窗口，本来就是原生。
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
            // 与设置窗口完全同构：`NSWindow` + `NSHostingView` 直接挂 contentView，
            // 标题隐藏、工具栏与红绿灯同行（见 `makeHostingWindow`）。
            mainWindow = makeHostingWindow(
                title: "路由管理",
                // 1000 × 575（张瑜 2026-10-01 定，2026-10-02 调整了写法）。
                //
                // 参照物：张瑜同屏打开的 **Windows App 窗口**，实测外框 1000 × 575
                // （CGWindowListCopyWindowInfo 读 kCGWindowBounds）。原先的 2000 × 1150
                // 几乎铺满整块屏（可见区 2056 × 1241），显得太大。
                //
                // ⚠️ **这个值现在是"整窗外框"，不是"内容区"**：开了 `fullSizeContent`
                // （见下）之后 `styleMask` 含 `.fullSizeContentView`，`init(contentRect:)`
                // 传进去的矩形被当作**整个窗口的 frame**，不再自动加上标题栏那 84pt。
                // 实测确认：传 491 得到的外框就是 491；传 575 才是 575。
                //
                // （没有 fullSizeContent 的窗口仍走老规矩：外框高 = contentRect 高 + 84，
                // 那个 84 是 2026-10-01 实测出来的标题栏 + 工具栏高度。）
                size: NSSize(width: 1000, height: 575),
                minSize: NSSize(width: 520, height: 280),
                hidesTitle: true,
                // 主窗口保留**原生全屏**（张瑜 2026-10-01 要求）：
                // 需要真正的全屏空间（独占一个桌面、菜单栏自动隐藏）。
                allowsNativeFullScreen: true,
                // 内容视图延伸到标题栏（张瑜 2026-10-02 要求"侧栏灰一直到顶部红绿灯"）：
                // 分栏底色才能画满整窗。设置 / 编辑窗口不传，保持系统默认的标题栏实底
                // —— 它们没有分栏背景，不需要延伸（编辑窗还是有意做成纯白底的）。
                fullSizeContent: true,
                root: RouteListView().environmentObject(store)
            )
        }
        present(mainWindow)
        // 首次呈现时把位置校正进屏幕可见区域（见 `fitIntoVisibleFrame`）。
        // **只做一次** —— 用户后来自己挪过/缩过窗口，重新打开时不该被弹回原位。
        // 时机在 `present` **之后**：窗口的工具栏（SwiftUI 的 `.toolbar`）是在
        // orderFront 过程中才挂上的，frame 到这时才最终确定。
        if !mainWindowPositioned, let window = mainWindow {
            mainWindowPositioned = true
            fitIntoVisibleFrame(window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.fitIntoVisibleFrame(window)
            }
        }
    }

    /// 打开（或前置）设置窗口
    ///
    /// **完全照搬 ApexBar 的设置窗口**（对照 ApexBar/Sources/ApexBar/AppDelegate.swift
    /// 的 `openSettings()`）：标准 `NSWindow`，SwiftUI 视图用
    /// `window.contentView = NSHostingView(rootView:)` **直接挂成 contentView**。
    ///
    /// **关键差别就是这一行**：不能再走 `NSWindow(contentViewController:)` +
    /// `NSHostingController`。用 hosting controller 时，SwiftUI 的 `TabView`
    /// 会把分页画成内容区里的一条独立 tab bar（标题栏还是"红绿灯 + 居中标题 + 
    /// 下方一条分页条"）；换成直接把视图挂成 contentView 后，分页由窗口自己
    /// 接管，落在**标题栏那一行、与红绿灯同行**，并且不再显示窗口标题 ——
    /// 就是 ApexBar 设置页的样子。
    func showSettings() {
        guard let store else { return }
        if settingsWindow == nil {
            // 内容高度取"最高的那一页装得下"：四页实测内容底边 223 / 245 / 266 / 230pt，
            // 取 290 留出页底 padding 与一点余量。四页只差 40pt 上下，固定高度即可，
            // **不做按页改高度**（那套会让窗口在切页时抖动，还得维护一张常量表）。
            //
            // 标题不隐藏：四个分页本身就占着标题栏那一行，系统不会再画标题文字
            // —— 这也是 ApexBar 设置窗口的形态。
            settingsWindow = makeHostingWindow(
                title: "RouteBar 设置",
                size: NSSize(width: 600, height: 290),
                minSize: NSSize(width: 560, height: 290),
                hidesTitle: false,
                root: SettingsView().environmentObject(store)
            )
        }
        guard let window = settingsWindow else { return }
        present(window)
        // 与添加/编辑窗口一致：落在**主窗口正中间**（见 `centerOverMain`）。
        // 设置窗口的高度是 `NSHostingView` 按内容撑出来的（实测 290 → 342pt），
        // 要等布局跑完才定，所以 present 后立刻一次、下一轮 runloop 再校正一次。
        centerOverMain(window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window else { return }
            self?.centerOverMain(window)
        }
    }

    /// 打开添加（`route == nil`）或编辑路由窗口
    func showEditor(route: Route?) {
        guard let store else { return }
        editWindow?.close()   // 同一时刻只留一个编辑窗口

        let root = RouteEditView(route: route) { [weak self] in
            self?.editWindow?.close()
        }
        .environmentObject(store)

        let window = makeHostingWindow(
            title: route == nil ? "添加路由" : "编辑路由",
            // 440 × 316（张瑜 2026-10-01 加了「图标:」一行）。原先是 440 × 260，
            // 表单里挤进一行 36pt 的图标选择器后，260 会把底部的按钮行压到贴边
            // —— 这里按"多一行 32pt + 行距 12pt"直接加上去。
            size: NSSize(width: 440, height: 316),
            // 无边框窗口不能缩放，`minSize` 在这里只是走过场（接口统一）
            minSize: NSSize(width: 440, height: 316),
            hidesTitle: true,
            // 无边框：没有标题栏、没有红绿灯，尺寸就固定这么大（张瑜 2026-10-01 要求）。
            // 原来的红绿灯在这么小的表单窗口上没有意义 —— 关窗有「取消」和 Esc。
            borderless: true,
            root: root
        )
        editWindow = window
        present(window)
        // 居中到**主窗口**（张瑜 2026-10-01 要求）：编辑窗口比主窗口小，落在主窗口
        // 正中间最符合"从这儿弹出来的"直觉（`makeHostingWindow` 里那次 `center()`
        // 是屏幕居中，这里覆盖掉）。
        centerOverMain(window)
        // 窗口首帧布局后尺寸才最终确定（`NSHostingView` 可能微调高度），再校正一次。
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window else { return }
            self?.centerOverMain(window)
        }
    }

    /// 「关于 RouteBar」（走系统标准面板）
    func showAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// 主窗口（还没创建过时为 `nil`）。
    ///
    /// 给"需要**以主窗口为基准定位**的调用方"用 —— 目前是删除确认弹窗
    /// （`NSAlert.runModal()` 默认居中到**屏幕**，我们要它落在主窗口正中间）。
    /// 主窗口是 `private` 的，这里开一个只读出口，避免调用方去摸 `NSApp.keyWindow`
    /// （那个会随焦点变化，不可靠）。
    var primaryWindow: NSWindow? { mainWindow }

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

    /// 统一创建三个窗口（主窗口 / 设置 / 添加·编辑）。
    ///
    /// **形态与 ApexBar 设置窗口一致**：标准 `NSWindow`（`styleMask` 四件套），
    /// SwiftUI 视图用 `NSHostingView` **直接挂成 `contentView`**。
    ///
    /// **为什么必须是 `NSHostingView` 而不是 `NSHostingController`**：
    /// 走 hosting controller 时，SwiftUI 的 `TabView` / `.toolbar` 内容会退化成
    /// 内容区里自绘的一条横条，标题栏永远是"红绿灯 + 居中标题 + 下面一条"；
    /// 直接把视图挂成 contentView 后，这些内容由**窗口自己**接管，落在标题栏
    /// 那一行、与红绿灯同行。
    ///
    /// `hidesTitle`：是否隐藏窗口标题。隐藏后顶部只剩"红绿灯 + 工具栏控件"，
    /// 不再有"标题一行 + 工具栏又一行"的重复感（标题仍写在 `window.title` 上，
    /// 「窗口」菜单里依然认得出是哪个窗口）。
    ///
    /// `allowsNativeFullScreen`：是否保留**原生全屏**能力。默认 `false`（见
    /// `disableNativeFullScreen` 的说明）；只有主窗口传 `true`。
    ///
    /// `borderless`：**无边框窗口** —— 没有标题栏，也就没有红绿灯，尺寸固定
    /// （`styleMask` 里不含 `.resizable`，边缘拉不动）。添加·编辑路由走这一种。
    /// 圆角、阴影、背景由 SwiftUI 侧自己画（见 `RouteEditView`）。
    ///
    /// `fullSizeContent`：**让内容视图延伸到标题栏下方** —— 标题栏设为透明、不画自带的
    /// 分隔线，于是 SwiftUI 侧的 `contentView` 覆盖整窗（含红绿灯那一行），铺在根视图上的
    /// 底色能一路画到窗口最顶端。只有主窗口传 `true`。
    ///
    /// **为什么需要它**：主窗口用的是"分栏底色"——左侧边栏灰、右侧内容区白。默认形态下
    /// 标题栏由系统画成一层实底，顶格就是一条与下方都不相同的色带，侧栏的灰到不了红绿灯
    /// 那一行；张瑜 2026-10-02 要求的就是"侧栏灰一直延伸到顶部红绿灯"（macOS 27 里系统
    /// 设置 / 访达那种分栏窗口的形态）。
    ///
    /// **这不等于"自绘标题行"**：工具栏、红绿灯、按钮的排布仍全部由系统接管，我们只是
    /// 把底下的**背景**画上去（见类文档里对自绘方案的否掉理由）。
    ///
    /// ⚠️ **它同时改变了 `size` 的含义**：`.fullSizeContentView` 让 `init(contentRect:)`
    /// 传进去的矩形被当作**整个窗口的 frame**，不再自动补上标题栏那一段。所以传了
    /// `fullSizeContent: true` 的窗口，`size` 要**直接写整窗外框尺寸**（主窗口写 575，
    /// 而不是 575 − 84 = 491）。实测：传 491 → 外框 491；传 575 → 外框 575。
    private func makeHostingWindow<Content: View>(title: String,
                                                  size: NSSize,
                                                  minSize: NSSize,
                                                  hidesTitle: Bool,
                                                  allowsNativeFullScreen: Bool = false,
                                                  borderless: Bool = false,
                                                  fullSizeContent: Bool = false,
                                                  root: Content) -> NSWindow {
        let window: NSWindow

        if borderless {
            // **必须用子类**：`.borderless` 的 `NSWindow` 默认 `canBecomeKey == false`，
            // 直接建出来的窗口**输入框点不进焦点**（整个表单等于废掉）。
            let w = RBBorderlessWindow(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: [.borderless],
                                       backing: .buffered,
                                       defer: false)
            // 圆角与阴影交给 SwiftUI 画（`RouteEditView` 的 `clipShape`）：
            // 窗口本身必须是透明的，否则圆角外面会漏出一个方块底。
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            // 没有标题栏 = 没有可拖动的区域。让内容**空白处**可以拖着窗口走；
            // 落在输入框 / 按钮上的拖动仍归控件自己，不会误触。
            w.isMovableByWindowBackground = true
            // 白底窗口必须锁**浅色外观**（张瑜 2026-10-01 要求背景纯白）：
            // 暗色模式下 `Color.primary` 是白字，白底白字直接看不见；而且 AppKit
            // 桥接控件（`NSComboBox`）不吃 SwiftUI 的 `colorScheme` 环境值，只有
            // 窗口自己的 `appearance` 能一并管住它们。`NSHostingView` 会从窗口
            // 外观推导出 light 的 colorScheme，所以 SwiftUI 侧不用再写一遍。
            w.appearance = NSAppearance(named: .aqua)
            window = w
        } else {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered,
                             defer: false)
            // 工具栏与标题栏**共用一行**：控件与红绿灯落在同一水平线上。
            w.toolbarStyle = .unified
            w.contentMinSize = minSize
            // 内容视图延伸到标题栏下方（目前只有主窗口，理由见 `fullSizeContent` 的说明）。
            //
            // 三件事缺一不可：
            //   · `.fullSizeContentView` —— contentView 的 frame 覆盖到标题栏区域，否则
            //     SwiftUI 根本没有"标题栏下面那片"可以画（safe area 也不会给顶部 inset）；
            //   · `titlebarAppearsTransparent` —— 标题栏让开自己的实底，露出下面 SwiftUI
            //     铺的底色（不设的话标题栏仍是一块独立的灰，侧栏颜色到不了顶）；
            //   · `titlebarSeparatorStyle = .none` —— 去掉系统在标题栏下沿画的那条分隔线，
            //     分栏背景是连续的，再来一条横线会把"一整块"切成两段。
            if fullSizeContent {
                w.styleMask.insert(.fullSizeContentView)
                w.titlebarAppearsTransparent = true
                w.titlebarSeparatorStyle = .none
            } else {
                w.titlebarAppearsTransparent = false
            }
            window = w
        }

        window.title = title
        if hidesTitle, !borderless {
            window.titleVisibility = .hidden
        }

        let hosting = NSHostingView(rootView: root)
        // 表达"窗口尺寸归 WindowManager 管"的意图。注意它**拦不住**
        // `NSHostingView` 按内容需要把窗口撑高（实测设置窗口传 290pt → 落到
        // 342pt，正好是最高那页「更新」装得下的高度，符合预期）。
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        window.contentView = hosting

        // 原生全屏能力按窗口区分：
        //   - 主窗口 → 保留（要真·全屏空间）
        //   - 设置 → 摘掉（原生全屏会把标题栏连红绿灯一起自动隐藏，只有把指针
        //     移到屏幕顶端才露出来；设置窗口需要红绿灯常显）
        //   - 添加·编辑路由 → 无边框，本来就不是全屏候选，不用管
        // 设置窗口**必须在成为 key 之前先摘一次**，并在 windowDidBecomeKey 里再摘一次
        // —— AppKit 会"隐式"把可缩放的带标题窗口补成全屏候选。
        if !borderless {
            if allowsNativeFullScreen {
                enableNativeFullScreen(window)
            } else {
                disableNativeFullScreen(window)
            }
        }

        window.center()
        // 关掉窗口不释放对象 —— 下次直接复用同一个窗口
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    /// 保留窗口的**原生全屏**能力（绿灯 = 进入全屏幕空间）。
    ///
    /// 只有主窗口走这里。显式写入 `.fullScreenPrimary` 不是为了"补上"（AppKit 本来就会
    /// 隐式登记），而是给这件事一个**确定的表述**：主窗口就是要进全屏空间。
    /// 顺带把可能残留的 `.fullScreenNone` 摘掉，避免窗口被复用时带着上一个窗口的设置。
    private func enableNativeFullScreen(_ window: NSWindow) {
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)
    }

    /// 摘掉窗口的**原生全屏**能力，让绿灯退化成系统的「缩放（zoom）」。
    ///
    /// **只对设置 / 添加·编辑路由窗口使用**（主窗口现在保留原生全屏）。
    ///
    /// **为什么这么做**（张瑜 2026-10-01 反馈）：原来这两个窗口的绿灯是原生全屏 ——
    /// 一进去系统就把标题栏（含红绿灯）和工具栏一起自动隐藏，必须把指针甩到屏幕顶端
    /// 才显示，观感是"窗口变全屏之后按钮全没了"。
    ///
    /// **依据**（Apple 开发者论坛，AppKit 工程师 Ken Thomases 的答复）：
    /// > When a window does not support full-screen, the green button does the
    /// > traditional zoom behavior … the window will still have its title bar.
    ///
    /// 也就是**不需要**另外去禁用绿灯按钮 —— 把 `.fullScreenPrimary` 摘掉，
    /// 绿灯自己就变成"缩放"：在「理想尺寸 ↔ 用户最后一次设置的尺寸」之间来回切，
    /// 铺满屏幕的可用区域（菜单栏/Dock 之外），标题栏与工具栏全程可见。
    ///
    /// `.fullScreenNone` 一并写上，是给"全屏候选"这件事一个显式的否定；
    /// 不能去 `zoomButton.isEnabled = false`（那会让绿灯变灰、窗口再也放不大）。
    private func disableNativeFullScreen(_ window: NSWindow) {
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.fullScreenNone)
    }

    /// 把 `window` 摆到**主窗口的正中间**。
    ///
    /// 判据（三者缺一就退回屏幕居中）：
    ///   · 主窗口存在且可见；`isOnActiveSpace` —— 主窗口若在别的桌面空间里，
    ///     按它的坐标摆会把编辑窗口摆到当前屏幕外；
    ///   · 主窗口没有最小化（最小化后它的 frame 还是旧值，但用户看不见它）。
    ///
    /// 最后再往屏幕可见区域里**夹一次**：主窗口贴边时，居中点可能落在 Dock /
    /// 菜单栏外侧，夹一下保证编辑窗口整体可见。
    private func centerOverMain(_ window: NSWindow) {
        guard let main = mainWindow,
              main.isVisible,
              main.isOnActiveSpace,
              !main.isMiniaturized else {
            window.center()
            return
        }
        let m = main.frame
        let w = window.frame
        var origin = NSPoint(x: m.minX + (m.width - w.width) / 2,
                             y: m.minY + (m.height - w.height) / 2)
        if let screen = main.screen ?? window.screen {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX), max(v.maxX - w.width, v.minX))
            origin.y = min(max(origin.y, v.minY), max(v.maxY - w.height, v.minY))
        }
        window.setFrameOrigin(origin)
    }

    /// 主窗口是否已经做过"夹进可见区域"的定位校正（只做一次，见 `showMainWindow`）
    private var mainWindowPositioned = false

    /// 把主窗口整体摆进屏幕的**可见区域**（扣掉菜单栏与 Dock 的那一块），只动原点。
    ///
    /// **为什么 `makeHostingWindow` 里的 `center()` 不够**（张瑜 2026-10-01 把主窗口
    /// 改成 2000×1150 后实测）：
    ///   1. 它按**整块屏幕**居中，不管菜单栏与 Dock；
    ///   2. 它跑在 SwiftUI 的 `.toolbar` 挂上窗口**之前** —— 那一刻窗口还矮一截
    ///      （工具栏那一行是后来加上的），等窗口长高，位置却停在按旧高度算出来的地方；
    ///   3. AppKit 的 `constrainFrameRect` **只保证标题栏在屏幕内**，窗口比屏幕高时
    ///      允许底边探出去。
    /// 实测结果：frame 高 1234、可见区域 1241，本该正好装下，却被摆到顶边 138pt、
    /// 底边探出屏幕 43pt —— 底部状态栏被切掉。
    ///
    /// **只调原点，不改尺寸**：用户点名的尺寸优先；只有窗口比可见区域还大时才收窄
    /// （否则无论怎么摆都有一部分看不见）。
    ///
    /// 坐标系说明：`NSWindow.frame` 与 `NSScreen.visibleFrame` 同是**左下角为原点**，
    /// 可直接比较，不要在这里转成 CG 的左上角坐标。
    private func fitIntoVisibleFrame(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        var frame = window.frame
        frame.size.width = min(frame.size.width, visible.width)
        frame.size.height = min(frame.size.height, visible.height)

        var origin = NSPoint(x: visible.midX - frame.size.width / 2,
                             y: visible.midY - frame.size.height / 2)
        // 夹一次兜底：窗口比可见区域还大时，上面的"居中"会算出负偏移
        origin.x = min(max(origin.x, visible.minX),
                       max(visible.maxX - frame.size.width, visible.minX))
        origin.y = min(max(origin.y, visible.minY),
                       max(visible.maxY - frame.size.height, visible.minY))

        frame.origin = origin
        window.setFrame(frame, display: true)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    /// **每次成为 key 都再摘一次全屏能力**（设置 / 编辑窗口）。
    ///
    /// AppKit 对"可缩放 + 带标题"的窗口是**隐式**把它当成全屏候选的，光在创建时摘一次
    /// 并不可靠（切换 Spaces、从全屏回来、窗口重新成为 key 都可能被重新补上）。
    /// 这里兜一道，代价只有几行、没有副作用。
    ///
    /// **主窗口例外**：它就是要原生全屏，在这里摘掉会把"真全屏"能力弄丢
    /// （尤其是从全屏切回来、窗口重新成为 key 的那一次）。
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === mainWindow { return }
        disableNativeFullScreen(window)
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭瞬间 isVisible 还没翻转，等下一轮再算
        DispatchQueue.main.async { [weak self] in
            self?.refreshActivationPolicy()
        }
    }
}

// MARK: - 无边框窗口

/// 无边框窗口：添加 / 编辑路由用它。
///
/// **存在的唯一理由**：`.borderless` 的 `NSWindow` 默认 `canBecomeKey == false`
/// —— 直接建出来的窗口**点不进输入框**（整个表单等于废掉）。覆写这两个属性把它打开。
///
/// 连带的三件事都在 `RouteEditView` 侧处理：
///   · 没有标题栏 → 也就没有红绿灯，关窗靠「取消」按钮与 Esc；
///   · 没有可拖动的标题区 → 窗口开了 `isMovableByWindowBackground`，拖内容空白处即可移动；
///   · 没有系统圆角 / 背景 / 描边 → SwiftUI 画材质底 + `clipShape` 圆角 + 细描边。
final class RBBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
