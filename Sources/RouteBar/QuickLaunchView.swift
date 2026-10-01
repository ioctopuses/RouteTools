import SwiftUI
import AppKit

/// 快速启动页 —— 点击菜单栏图标（或按 ⌥⌘R）弹出。
///
/// 与主窗口「路由管理」是**两个不同的界面**：
///   · 主窗口：完整的增删改查 + 设置入口（重型，可常驻）
///   · 快速启动页：搜索 + 一键开关某条路由（轻量，随手用）
/// 注意它**不是**主界面，所以这里不提供增删改，只提供"开关"和"跳转"。
struct QuickLaunchView: View {
    @EnvironmentObject var store: RouteStore

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private static let ungroupedTitle = "未分组"

    var body: some View {
        VStack(spacing: 0) {

            // ── 顶部：搜索 + 设置齿轮 + 更多菜单 ──────────────────
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("搜索路由", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )

                headerButton(help: "设置") {
                    GearIcon(size: 15)
                } action: {
                    closePopover()
                    WindowManager.shared.showSettings()
                }

                Menu {
                    Button("打开主页面") {
                        closePopover()
                        WindowManager.shared.showMainWindow()
                    }
                    Button("版本更新…") {
                        closePopover()
                        Task { await UpdateChecker.shared.check(interactive: true) }
                    }
                    Button("关于 RouteBar") {
                        closePopover()
                        WindowManager.shared.showAbout()
                    }
                    Divider()
                    Button("退出 RouteBar") {
                        NSApp.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30)
                .help("更多")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // ── 路由列表 ──────────────────────────────────────────
            if store.routes.isEmpty {
                emptyState
            } else if groups.isEmpty {
                noMatchState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(groups, id: \.title) { group in
                            if showsGroupHeaders {
                                Text(group.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)
                            }
                            ForEach(group.routes) { route in
                                routeRow(route)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 420)
            }

            Divider()

            // ── 底部 ─────────────────────────────────────────────
            HStack {
                Button("打开主窗口…") {
                    closePopover()
                    WindowManager.shared.showMainWindow()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))

                Spacer()

                Text("⌥⌘R 唤起")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)
        }
        .frame(width: 340)
        .onAppear { searchFocused = true }
    }

    // MARK: - 子视图

    private func headerButton<Label: View>(help: String,
                                           @ViewBuilder label: () -> Label,
                                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.06))
        )
        .help(help)
    }

    private func routeRow(_ route: Route) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(route.enabled ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(route.name.isEmpty ? route.destination : route.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(route.destination)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { route.enabled },
                set: { store.setEnabled(id: route.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 26))
                .foregroundColor(.secondary)
            Text("还没有任何路由")
                .font(.system(size: 13, weight: .medium))
            Button("打开主窗口添加…") {
                closePopover()
                WindowManager.shared.showMainWindow()
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var noMatchState: some View {
        VStack(spacing: 6) {
            Text("没有匹配「\(query)」的路由")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - 分组与搜索

    private struct Group {
        let title: String
        let routes: [Route]
    }

    /// 是否显示分组标题：只有一组且是「未分组」时不显示（避免无意义的标题占位）
    private var showsGroupHeaders: Bool {
        if groups.count > 1 { return true }
        return groups.first?.title != Self.ungroupedTitle
    }

    private var groups: [Group] {
        let filtered = store.routes.filter(matches)
        var order: [String] = []
        var buckets: [String: [Route]] = [:]

        for route in filtered {
            let raw = (route.group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = raw.isEmpty ? Self.ungroupedTitle : raw
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(route)
        }
        return order.map { Group(title: $0, routes: buckets[$0] ?? []) }
    }

    private func matches(_ route: Route) -> Bool {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return true }
        return route.name.lowercased().contains(keyword)
            || route.destination.lowercased().contains(keyword)
            || route.gateway.lowercased().contains(keyword)
            || (route.group ?? "").lowercased().contains(keyword)
    }

    private func closePopover() {
        NotificationCenter.default.post(name: .rbClosePopover, object: nil)
    }
}
