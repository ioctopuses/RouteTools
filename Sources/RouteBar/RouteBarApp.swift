import SwiftUI
import AppKit

// MARK: - 读取应用版本号

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}

/// 应用入口。
///
/// **窗口不由 SwiftUI 的 `Window` Scene 管理**，而是统一交给 `WindowManager`
/// （AppKit）。原因见 `WindowManager` 的注释：快速启动页是从 `AppDelegate`
/// 桥接进 `NSPopover` 的，不在任何 Scene 里，拿不到 `openWindow` 环境值。
///
/// 这里只保留一个 `Settings` 场景作为 **Scene 锚点** —— SwiftUI 的 `App`
/// 必须提供至少一个 Scene，且应用菜单（`.commands`）需要挂在它上面。
/// 真正打开窗口时一律走 `WindowManager`。
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

// MARK: - 主窗口：路由管理

struct RouteListView: View {
    @EnvironmentObject var store: RouteStore

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 10) {
                Text("路由管理")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                // 设置齿轮：进设置页
                Button {
                    WindowManager.shared.showSettings()
                } label: {
                    GearIcon(size: 16)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("设置")

                // 添加路由：蓝底高亮
                Button {
                    WindowManager.shared.showEditor(route: nil)
                } label: {
                    Label("添加路由", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help("添加一条静态路由（⌘N）")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // 路由列表
            if store.routes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("还没有任何路由")
                        .font(.headline)
                    Text("点击右上角「添加路由」开始")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.routes) { route in
                        RouteRow(route: route)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()

            // 底部状态栏
            HStack {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text("v\(Bundle.main.appVersion)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var statusText: String {
        if store.routes.isEmpty { return "0 条路由" }
        let total = store.routes.count
        let enabled = store.routes.filter { $0.enabled }.count
        return "\(total) 条路由 · 已启用 \(enabled)"
    }
}

// MARK: - 路由行（主窗口列表里使用）

struct RouteRow: View {
    @EnvironmentObject var store: RouteStore
    let route: Route

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(route.name.isEmpty ? route.destination : route.name)
                        .font(.system(size: 13, weight: .medium))
                    if let group = route.group, !group.isEmpty {
                        Text(group)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.07))
                            )
                    }
                }
                Text("\(route.destination)  →  \(route.gateway)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { route.enabled },
                set: { store.setEnabled(id: route.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            Button {
                WindowManager.shared.showEditor(route: route)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button {
                store.remove(route)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 添加 / 编辑路由窗口

struct RouteEditView: View {
    @EnvironmentObject var store: RouteStore

    let editing: Route?
    /// 关闭本窗口（由 WindowManager 提供）
    let onClose: () -> Void

    @State private var name: String
    @State private var destination: String
    @State private var gateway: String
    @State private var group: String
    @State private var enabled: Bool
    @State private var error: String?

    init(route: Route?, onClose: @escaping () -> Void) {
        self.editing = route
        self.onClose = onClose
        _name = State(initialValue: route?.name ?? "")
        _destination = State(initialValue: route?.destination ?? "")
        _gateway = State(initialValue: route?.gateway ?? "")
        _group = State(initialValue: route?.group ?? "")
        _enabled = State(initialValue: route?.enabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "添加路由" : "编辑路由")
                .font(.system(size: 14, weight: .semibold))

            TextField("名称（可选，便于识别）", text: $name)
            TextField("分组（可选，如：公司 / 家）", text: $group)
            TextField("目标网段，如 172.16.0.0/16 或主机 10.0.0.1", text: $destination)
            TextField("网关地址，如 192.168.1.15", text: $gateway)
            Toggle("保存后立即启用", isOn: $enabled)

            if let error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { onClose() }
                Button(editing == nil ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private func save() {
        let dest = destination.trimmingCharacters(in: .whitespaces)
        let gw = gateway.trimmingCharacters(in: .whitespaces)
        guard !dest.isEmpty else { error = "请填写目标网段 / 主机"; return }
        guard !gw.isEmpty else { error = "请填写网关地址"; return }

        let groupValue = group.trimmingCharacters(in: .whitespaces)

        let newRoute = Route(id: editing?.id ?? UUID(),
                             name: name.trimmingCharacters(in: .whitespaces),
                             destination: dest,
                             gateway: gw,
                             enabled: enabled,
                             note: editing?.note ?? "",
                             group: groupValue.isEmpty ? nil : groupValue)

        if let original = editing {
            // 编辑：撤销旧路由 + 应用新路由，合并为单条命令（只弹一次授权框）
            store.saveEdit(original: original, updated: newRoute)
        } else {
            store.add(newRoute)
            if newRoute.enabled { _ = store.apply(newRoute) }
        }

        onClose()
    }
}
