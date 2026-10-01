import SwiftUI
import AppKit

/// 设置窗口。
///
/// 三个入口都指向这里：主窗口右上角的齿轮、应用菜单「偏好设置… ⌘,」、
/// 快速启动页的齿轮。原先散落在菜单栏 popover 里的两个开关（菜单栏图标、
/// 启动时自动应用）以及授权相关操作，全部集中到本页。
struct SettingsView: View {
    @EnvironmentObject var store: RouteStore
    @ObservedObject private var updater = UpdateChecker.shared

    /// 授权区域的状态文案（本次会话内有效）
    @State private var authMessage: String?
    @State private var authOK = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // ── 菜单栏 ──────────────────────────────────────────
                section("菜单栏") {
                    row(title: "在菜单栏显示快速启动图标",
                        subtitle: "点击该图标进入快速启动页；关闭后可用 ⌥⌘R 唤起") {
                        Toggle("", isOn: $store.showInMenuBar)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                // ── 启动 ────────────────────────────────────────────
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

                // ── 更新 ────────────────────────────────────────────
                section("更新") {
                    row(title: "自动检查更新",
                        subtitle: "每 24 小时在后台检查一次 GitHub Release") {
                        Toggle("", isOn: $store.autoCheckForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    cardDivider

                    row(title: "当前版本",
                        subtitle: "RouteBar \(Bundle.main.appVersion) · \(updater.statusText)") {
                        updateBadge
                    }

                    cardDivider

                    actionRow {
                        Button {
                            Task { await UpdateChecker.shared.check(interactive: true) }
                        } label: {
                            Label("检查更新", systemImage: "arrow.clockwise")
                        }
                        .disabled(updater.isBusy)

                        if let version = updater.state.availableVersion {
                            Button("立即更新到 \(version)") {
                                Task { await UpdateChecker.shared.installPendingUpdate() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(updater.isBusy)
                        }

                        Spacer()

                        Button("查看更新日志") { openReleasesPage() }
                            .buttonStyle(.link)
                    }
                }

                // ── 权限与授权 ──────────────────────────────────────
                section("权限与授权") {
                    row(title: "授权状态",
                        subtitle: authMessage
                            ?? "修改系统路由表需要管理员权限；授权后系统会缓存约 5 分钟，期间反复开关路由不再提示。") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(authOK ? Color.green : Color.secondary)
                                .frame(width: 7, height: 7)
                            Text(authOK ? "已授权" : "未缓存")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    cardDivider

                    actionRow {
                        Button("申请授权") { warmUp() }
                        Button("清除授权缓存") { resetAuth() }
                        Spacer()
                    }
                }

                // ── 页脚 ────────────────────────────────────────────
                HStack {
                    Text("RouteBar \(Bundle.main.appVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    // MARK: - 子视图

    /// 一个设置分组：标题 + 圆角卡片
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

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
                        .foregroundColor(.secondary)
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

    @ViewBuilder
    private var updateBadge: some View {
        switch updater.state {
        case .available(let version):
            statusDot(.blue, "发现 v\(version)")
        case .upToDate:
            statusDot(.green, "已是最新")
        case .failed:
            statusDot(.red, "检查失败")
        case .checking, .downloading, .installing:
            statusDot(.orange, "进行中")
        case .idle:
            statusDot(.secondary, "尚未检查")
        }
    }

    private func statusDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12)).foregroundColor(.secondary)
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
