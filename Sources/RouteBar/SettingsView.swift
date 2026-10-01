import SwiftUI
import AppKit

/// 设置窗口。
///
/// 三个入口都指向这里：主窗口右上角的齿轮、应用菜单「偏好设置… ⌘,」、
/// 快速启动页的齿轮。
///
/// **窗口形态 = ApexBar 设置窗口那一套**：标准 `NSWindow`，SwiftUI 视图直接挂成
/// `contentView`（见 `WindowManager.showSettings()`）。四个分页交给原生 `TabView`，
/// 分页按钮由系统放进**标题栏那一行、与红绿灯同行**，窗口不显示标题。
///
/// 曾经走过一段弯路：为了让"应用图标与红绿灯同行"，改用了
/// `.fullSizeContentView` + 透明标题栏 + 自绘标题行。结果是——要按常量让开
/// 红绿灯、`RBWindowTitleRow` 会被 SwiftUI 的 safe area 整体下推 32pt、
/// 窗口高度还要按页自适应。**这些复杂度全是自绘带来的**。正确做法是照搬
/// ApexBar：什么都不用画，系统自己会把 `TabView` 的分页摆到标题栏那一行。
///
/// **为什么按功能拆成 Tab**：原先是一页长滚动，窗口被拉到 780pt 高还是
/// 一眼望不到底，五个分组混在一起、找东西要滚。拆成分类页后一眼能看全。
///
/// 分页按「用户想干什么」而不是按「代码里有什么」切：
///   · 通用     —— 平时怎么用（菜单栏入口、开机行为）
///   · 快速启动 —— 弹窗长什么样（尺寸）
///   · 更新     —— 版本相关
///   · 权限     —— 授权相关（只在出问题时才会进来）
struct SettingsView: View {
    @EnvironmentObject var store: RouteStore
    @ObservedObject private var updater = UpdateChecker.shared

    /// 授权区域的状态文案（本次会话内有效）
    @State private var authMessage: String?
    @State private var authOK = false

    var body: some View {
        // 原生 `TabView`：分页交给窗口自己接管（标题栏那一行），与 ApexBar
        // 设置窗口的形态一致。窗口大小固定、可拉伸，不按页改高度。
        TabView {
            generalPage
                .tabItem { Label("通用", systemImage: "gearshape") }

            quickLaunchPage
                .tabItem { Label("快速启动", systemImage: "bolt.horizontal") }

            updatesPage
                .tabItem { Label("更新", systemImage: "arrow.triangle.2.circlepath") }

            permissionPage
                .tabItem { Label("权限", systemImage: "hand.raised") }
        }
        .frame(minWidth: 560, minHeight: 290)
    }

    // MARK: - 页：通用

    private var generalPage: some View {
        page {
            section("菜单栏") {
                row(title: "在菜单栏显示快速启动图标",
                    subtitle: "点击该图标进入快速启动页；关闭后可用 ⌥⌘R 唤起") {
                    Toggle("", isOn: $store.showInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            section("启动") {
                row(title: "启动时自动应用已启用路由",
                    subtitle: "App 启动时把已启用的路由自动写回系统路由表") {
                    Toggle("", isOn: $store.autoApplyOnLaunch)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: store.autoApplyOnLaunch) { newValue in
                            if newValue { store.applyAllEnabled() }
                        }
                }
            }
        }
    }

    // MARK: - 页：快速启动

    private var quickLaunchPage: some View {
        page {
            section("窗口尺寸") {
                sliderRow(title: "窗口宽度",
                          subtitle: "菜单栏图标点开后弹窗的宽度",
                          value: $store.quickLaunchWidth,
                          range: QuickLaunchLimits.widthRange)

                cardDivider

                sliderRow(title: "列表高度",
                          subtitle: "列表区的固定高度；内容超出后滚动查看",
                          value: $store.quickLaunchListHeight,
                          range: QuickLaunchLimits.listHeightRange)

                cardDivider

                actionRow {
                    Button("恢复默认尺寸") {
                        store.quickLaunchWidth = QuickLaunchLimits.widthDefault
                        store.quickLaunchListHeight = QuickLaunchLimits.listHeightDefault
                    }
                    .disabled(store.quickLaunchWidth == QuickLaunchLimits.widthDefault
                              && store.quickLaunchListHeight == QuickLaunchLimits.listHeightDefault)

                    Spacer()

                    Text("默认 \(Int(QuickLaunchLimits.widthDefault)) × \(Int(QuickLaunchLimits.listHeightDefault)) pt")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 页：更新

    private var updatesPage: some View {
        page {
            section("自动更新") {
                row(title: "自动检查更新",
                    subtitle: "每 24 小时在后台检查一次 GitHub Release") {
                    Toggle("", isOn: $store.autoCheckForUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            section("版本") {
                // 副标题只放版本号，状态交给右侧徽标 —— 两处都写"尚未检查"
                // 是重复（同一条信息出现两遍，页面就显脏）。
                row(title: "当前版本",
                    subtitle: "RouteBar \(Bundle.main.appVersion)") {
                    updateBadge
                }

                cardDivider

                actionRow {
                    Button("检查更新") {
                        Task { await UpdateChecker.shared.check(interactive: true) }
                    }
                    .disabled(updater.isBusy)

                    if let version = updater.state.availableVersion {
                        Button("立即更新到 \(version)") {
                            Task { await UpdateChecker.shared.installPendingUpdate() }
                        }
                        .rbProminentButton()
                        .disabled(updater.isBusy)
                    }

                    Spacer(minLength: 8)

                    Button("查看更新日志") { openReleasesPage() }
                        .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: - 页：权限

    private var permissionPage: some View {
        page {
            section("授权状态") {
                // 标题不再重复"已授权/未缓存"—— 那是右侧徽标的活
                row(title: "管理员授权",
                    subtitle: authMessage
                        ?? "修改系统路由表需要管理员权限。授权后系统会缓存约 5 分钟，期间反复开关路由不再提示输入密码。") {
                    statusDot(authOK ? .green : .secondary, authOK ? "已授权" : "未缓存")
                }
            }

            section("操作") {
                actionRow {
                    Button("申请授权") { warmUp() }
                        .rbProminentButton()
                    Button("清除授权缓存") { resetAuth() }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 版式

    /// 每一页的外壳：顶部对齐、底部留白吃掉多余高度（不垂直居中）。
    private func page<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 一个设置分组：标题 + 圆角卡片
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    private var cardDivider: some View {
        Divider().padding(.horizontal, 14)
    }

    /// 卡片里的一行：左侧说明，右侧控件
    private func row<Trailing: View>(title: String,
                                     subtitle: String? = nil,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// 卡片里的一行：纯按钮区
    private func actionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
    }

    /// 卡片里的一行：标题 + 副标题 + 右侧当前值，下方通栏滑块。
    ///
    /// 滑块不能塞进 `row()` 的右侧（那栏只有百来点宽，拖不出精度），
    /// 所以单独做成"上下两段"的布局。
    private func sliderRow(title: String,
                           subtitle: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("\(Int(value.wrappedValue)) pt")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var updateBadge: some View {
        statusDot(updateColor, updater.statusText)
    }

    /// 只看状态给颜色；文案统一用 `statusText`（它比短标签更具体，
    /// 例如"上次检查：08-14 23:50"）。
    private var updateColor: Color {
        switch updater.state {
        case .available: .blue
        case .upToDate: .green
        case .failed: .red
        case .checking, .downloading, .installing: .orange
        case .idle: .secondary
        }
    }

    private func statusDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: - 动作

    private func warmUp() {
        let ok = PrivilegedRunner.warmUpAuthorization()
        authOK = ok
        authMessage = ok
            ? "已申请授权，约 5 分钟内修改路由不再提示输入密码。"
            : "授权已取消或失败，可再次点击重试。"
    }

    private func resetAuth() {
        PrivilegedRunner.resetAuthorization()
        authOK = false
        authMessage = "已清除授权缓存，下次修改路由需要重新输入密码。"
    }

    private func openReleasesPage() {
        guard let url = URL(string: "https://github.com/\(AppConfig.updateFeedRepo)/releases") else { return }
        NSWorkspace.shared.open(url)
    }
}
