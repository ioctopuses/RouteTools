import SwiftUI

// MARK: - 读取应用版本号

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}

/// 应用入口。
///
/// 菜单栏 UI 的实际管理在 `AppDelegate`（`NSStatusItem` + `NSPopover`），
/// 这里只保留两个**独立的 Window**：
///   - 添加路由
///   - 编辑路由
///
/// 这两个 Window 是普通的 SwiftUI 窗口（不常驻菜单栏），菜单栏入口
/// 由 AppDelegate 接管，因为 SwiftUI 的 `MenuBarExtra` 没有公开的
/// 可见性绑定，无法支持「在菜单栏显示图标」开关。
@main
struct RouteBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 添加路由窗口
        Window("添加路由", id: "addRoute") {
            RouteEditView(route: nil)
                .environmentObject(appDelegate.store)
        }

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
    }
}

// MARK: - 菜单栏下拉内容（由 AppDelegate 的 NSHostingController 桥接到 NSPopover）

struct MenuBarContent: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RouteBar · 路由管理")
                    .font(.headline)
                Spacer()
            }
            Divider()

            if store.routes.isEmpty {
                Text("还没有任何路由，点击底部「添加路由」开始。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(store.routes) { route in
                    RouteRow(route: route)
                }
            }

            Divider()

            Toggle("启动时自动应用已启用路由",
                   isOn: $store.autoApplyOnLaunch)
                .font(.caption)
                .onChange(of: store.autoApplyOnLaunch) { newValue in
                    // 用户手动打开开关时立即应用一次（点下去立刻见效）
                    if newValue {
                        store.applyAllEnabled()
                    }
                }

            Toggle("在菜单栏显示图标",
                   isOn: $store.showInMenuBar)
                .font(.caption)

            Text("关闭后按 ⌥⌘R 唤起菜单（图标隐藏时仍可恢复显示）")
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
                Button("添加路由…") { openWindow(id: "addRoute") }
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct RouteRow: View {
    @EnvironmentObject var store: RouteStore
    @Environment(\.openWindow) private var openWindow
    let route: Route

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
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
