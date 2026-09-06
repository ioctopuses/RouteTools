import Foundation
import Combine

/// 路由配置的本地存储 + 实际执行 route 命令。
final class RouteStore: ObservableObject {

    @Published var routes: [Route] = []

    /// 当前正在编辑的路由 id（用于"编辑"窗口复用同一个窗口）。
    @Published var editingRouteID: Route.ID?

    /// 应用启动时是否自动把"已启用"的路由加回系统路由表。
    /// 使用 @Published 确保 Toggle 绑定后能实时响应状态变更（无需重启）。
    @Published var autoApplyOnLaunch: Bool = false {
        didSet {
            // 仅持久化到 UserDefaults；不在此处调用 applyAllEnabled()
            // （避免与 init() 中的延时调用重复弹窗）
            UserDefaults.standard.set(autoApplyOnLaunch, forKey: "autoApplyOnLaunch")
        }
    }

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("RouteBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("routes.json")
        load()
        // 从 UserDefaults 恢复开关状态（init 中赋值不触发 didSet，安全）
        autoApplyOnLaunch = UserDefaults.standard.bool(forKey: "autoApplyOnLaunch")
        
        // 启动时同步系统路由表状态
        syncSystemRoutes()

        if autoApplyOnLaunch {
            // 主线程延时执行，确保 App 完成初始化、授权对话框能正常弹出
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.applyAllEnabled()
            }
        }
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Route].self, from: data) else { return }
        routes = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(routes) {
            try? data.write(to: fileURL)
        }
    }

    // MARK: - 增删改

    func add(_ route: Route) {
        routes.append(route)
        save()
    }

    func update(_ route: Route) {
        if let idx = routes.firstIndex(where: { $0.id == route.id }) {
            routes[idx] = route
            save()
        }
    }

    func remove(_ route: Route) {
        if route.enabled { _ = revoke(route) }
        routes.removeAll { $0.id == route.id }
        save()
    }

    // MARK: - 系统路由表同步

    /// 查询系统路由表中是否存在某条路由
    func isRouteInSystemTable(_ route: Route) -> Bool {
        let command = RouteCommands.getRouteQueryCommand(for: route)
        let (success, output) = PrivilegedRunner.runAsAdmin(command)
        
        // 如果命令失败，路由肯定不存在
        guard success else { return false }
        
        // 检查输出中是否包含预期的网关地址
        // 例如：gateway: 192.168.1.15
        let gatewayPattern = "gateway: \(route.gateway)"
        return output.contains(gatewayPattern)
    }

    /// 同步所有路由的启用状态（根据系统路由表实际状态）
    func syncSystemRoutes() {
        let updatedRoutes = routes.map { route in
            var updated = route
            let inSystem = isRouteInSystemTable(route)
            // 如果配置为启用但系统表中不存在，或配置为禁用但系统表中存在，则同步状态
            if route.enabled != inSystem {
                updated.enabled = inSystem
            }
            return updated
        }
        
        // 如果有状态变化，更新并保存
        if updatedRoutes != routes {
            routes = updatedRoutes
            save()
        }
    }

    // MARK: - 实际执行系统命令

    /// 把路由加入系统路由表（需要管理员权限）。
    @discardableResult
    func apply(_ route: Route) -> Bool {
        let (ok, out) = PrivilegedRunner.runAsAdmin(RouteCommands.addCommand(for: route))
        return ok
            || out.localizedCaseInsensitiveContains("file exists")
            || out.localizedCaseInsensitiveContains("exist")
    }

    /// 把路由从系统路由表删除（需要管理员权限）。
    @discardableResult
    func revoke(_ route: Route) -> Bool {
        let (ok, out) = PrivilegedRunner.runAsAdmin(RouteCommands.deleteCommand(for: route))
        return ok
            || out.localizedCaseInsensitiveContains("not in table")
            || out.localizedCaseInsensitiveContains("not exist")
    }

    /// 切换某条路由的启用/禁用状态。
    /// 命令执行失败时保持原状态（开关会自动回弹）。
    func setEnabled(id: UUID, enabled: Bool) {
        guard let idx = routes.firstIndex(where: { $0.id == id }) else { return }
        let original = routes[idx]
        guard original.enabled != enabled else { return }

        // 乐观更新，便于失败时回滚触发界面重绘
        var optimistic = original
        optimistic.enabled = enabled
        routes[idx] = optimistic

        let ok = enabled ? apply(original) : revoke(original)
        if !ok {
            routes[idx] = original   // 失败回滚
        }
        save()
    }

    func applyAllEnabled() {
        let enabled = routes.filter { $0.enabled }
        guard !enabled.isEmpty else { return }
        // 逐条应用：授权已通过 Authorization Services 缓存，
        // 仅在首次（约 5 分钟缓存过期）后才会再次弹窗，不会每条各弹一次。
        for route in enabled {
            _ = apply(route)
        }
    }
}
