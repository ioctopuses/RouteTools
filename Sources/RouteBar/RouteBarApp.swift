import SwiftUI

// MARK: - 读取应用版本号

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}

/// 应用入口。
///
/// 三个 Window Scene：
///   - `routeList` 主窗口（路由列表 + 工具栏，App 启动时自动打开）
///   - `addRoute`  添加路由窗口（由主窗口或菜单栏「添加路由…」唤起）
///   - `editRoute` 编辑路由窗口（复用同一个窗口，目标路由由 `store.editingRouteID` 决定）
///
/// 菜单栏 UI 由 `AppDelegate`（`NSStatusItem` + `NSPopover`）管理，
/// 这里不暴露 `MenuBarExtra`，因为 SwiftUI 的 `MenuBarExtra`
/// 没有公开的可见性绑定，无法支持「在菜单栏显示图标」开关。
@main
struct RouteBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 主窗口：路由列表（App 启动时自动打开，用户关掉后可从菜单栏再次唤起）
        Window("路由管理", id: "routeList") {
            RouteListView()
                .environmentObject(appDelegate.store)
        }
        .defaultSize(width: 560, height: 380)
        .windowResizability(.contentMinSize)

        // 添加路由窗口
        Window("添加路由", id: "addRoute") {
            RouteEditView(route: nil)
                .environmentObject(appDelegate.store)
        }
        .defaultSize(width: 420, height: 240)

        // 编辑路由窗口（复用同一个窗口，目标路由由 store.editingRouteID 决定）
        Window("编辑路由", id: "editRoute") {
            if let id = appDelegate.store.editingRouteID,
               let route = appDelegate.store.routes.first(where: { $0.id == id }) {
                RouteEditView(route: route)
                    .environmentObject(appDelegate.store)
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 420, height: 240)
    }
}

// MARK: - 主窗口：路由列表

struct RouteListView: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Text("RouteBar · 路由管理")
                    .font(.headline)
                Spacer()
                Button {
                    openWindow(id: "addRoute")
                } label: {
                    Label("添加路由", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
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
        .frame(minWidth: 520, minHeight: 320)
    }

    private var statusText: String {
        if store.routes.isEmpty {
            return "0 条路由"
        }
        let total = store.routes.count
        let enabled = store.routes.filter { $0.enabled }.count
        return "\(total) 条路由 · 已启用 \(enabled)"
    }
}

// MARK: - 菜单栏下拉内容（精简版：仅设置；路由列表全部在主窗口）

/// 由 AppDelegate 的 NSHostingController 桥接到 NSPopover。
/// v1.8.0 改为「设置面板」：路由列表与所有 CRUD 都在主窗口里，
/// 菜单栏只放开关 + 入口。这样菜单栏高度可控、不再随路由条数增长撑屏。
struct MenuBarContent: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RouteBar")
                    .font(.headline)
                Spacer()
            }
            Divider()

            Toggle("启动时自动应用已启用路由",
                   isOn: $store.autoApplyOnLaunch)
                .font(.caption)
                .onChange(of: store.autoApplyOnLaunch) { newValue in
                    if newValue {
                        store.applyAllEnabled()
                    }
                }

            Toggle("在菜单栏显示图标",
                   isOn: $store.showInMenuBar)
                .font(.caption)

            Text("关闭后按 ⌥⌘R 唤起菜单")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text("v\(Bundle.main.appVersion)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack {
                Button("清除授权缓存") { PrivilegedRunner.resetAuthorization() }
                    .font(.caption)
                Spacer()
                Button("打开主窗口…") { openWindow(id: "routeList") }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

// MARK: - 路由行（主窗口列表里使用）

struct RouteRow: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.openWindow) private var openWindow
    let route: Route

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name.isEmpty ? route.destination : route.name)
                    .font(.system(size: 13, weight: .medium))
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

            Button(action: {
                store.editingRouteID = route.id
                openWindow(id: "editRoute")
            }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button(action: { store.remove(route) }) {
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
    @Environment(\.dismiss) private var dismiss

    let editing: Route?

    @State private var name: String
    @State private var destination: String
    @State private var gateway: String
    @State private var enabled: Bool
    @State private var error: String?

    init(route: Route?) {
        self.editing = route
        _name = State(initialValue: route?.name ?? "")
        _destination = State(initialValue: route?.destination ?? "")
        _gateway = State(initialValue: route?.gateway ?? "")
        _enabled = State(initialValue: route?.enabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "添加路由" : "编辑路由")
                .font(.headline)

            TextField("名称（可选，便于识别）", text: $name)
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
                Button("取消", role: .cancel) { dismiss() }
                Button(editing == nil ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        let dest = destination.trimmingCharacters(in: .whitespaces)
        let gw = gateway.trimmingCharacters(in: .whitespaces)
        guard !dest.isEmpty else { error = "请填写目标网段 / 主机"; return }
        guard !gw.isEmpty else { error = "请填写网关地址"; return }

        let newRoute = Route(id: editing?.id ?? UUID(),
                             name: name.trimmingCharacters(in: .whitespaces),
                             destination: dest,
                             gateway: gw,
                             enabled: enabled,
                             note: editing?.note ?? "")

        if let original = editing {
            // 编辑：撤销旧路由 + 应用新路由，合并为单条命令（只弹一次授权框）
            store.saveEdit(original: original, updated: newRoute)
        } else {
            store.add(newRoute)
            if newRoute.enabled { _ = store.apply(newRoute) }
        }

        dismiss()
    }
}
