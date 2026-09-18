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

        if autoApplyOnLaunch {
            // 开启自动恢复：先按用户意图补齐缺失路由，再同步界面状态。
            // 顺序不能颠倒——若先同步，系统表为空时会把启用意图全部抹成禁用，
            // 导致"自动应用"无事可做（这也是此前该开关"不好用"的原因之一）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.applyAllEnabled()
                self?.syncSystemRoutes()
            }
        } else {
            // 未开启自动恢复：直接反映系统路由表真实状态
            syncSystemRoutes()
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

    /// 查询系统路由表中是否存在某条路由。
    ///
    /// 关键：走 `runAsUser`（**非提权**）执行。`route get` 是只读查询，
    /// 普通用户即可完成，原本走提权通道会让每次启动按路由条数连续弹授权框。
    func isRouteInSystemTable(_ route: Route) -> Bool {
        let (addr, mask) = RouteCommands.parse(route.destination)
        let command = RouteCommands.getRouteQueryCommand(for: route)
        let (success, output) = PrivilegedRunner.runAsUser(command)

        // 命令失败（如 "not in table"）说明系统中不存在该路由
        guard success else { return false }

        // 必须同时匹配网关 + 目标网段，避免被更宽泛/更具体的其它路由误判。
        // 例：系统里只有 172.16.0.0/24，不应认为 172.16.0.0/16 已存在。
        guard output.contains("gateway: \(route.gateway)") else { return false }
        guard output.contains("destination: \(addr)") else { return false }
        if let mask = mask {
            guard output.contains("mask: \(mask)") else { return false }
        }
        return true
    }

    /// 根据系统路由表的真实情况同步界面显示状态。
    ///
    /// 注意这里是**单向**同步：只在「系统表中确实存在、但配置为禁用」时改为启用
    /// （反映真实生效状态）。反向情况——「配置为启用、但系统表中缺失」（常见于
    /// 系统重启后路由表被清空）——**保留用户的启用意图**，交由 `applyAllEnabled()`
    /// 去恢复，否则启用意图会在启动瞬间被抹掉，导致"自动应用"永远无事可做。
    func syncSystemRoutes() {
        let updatedRoutes = routes.map { route -> Route in
            var updated = route
            if !route.enabled && isRouteInSystemTable(route) {
                updated.enabled = true
            }
            return updated
        }

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

    /// 保存编辑结果：撤销旧路由 + 应用新路由。
    ///
    /// 两条命令合并为**单条 shell 命令**一次性提权执行，避免编辑一次弹两次授权框
    /// （原先分别调用 revoke + apply，各走一次提权通道）。
    func saveEdit(original: Route, updated: Route) {
        var commands: [String] = []
        if original.enabled { commands.append(RouteCommands.deleteCommand(for: original)) }
        if updated.enabled { commands.append(RouteCommands.addCommand(for: updated)) }

        update(updated)

        guard !commands.isEmpty else { return }
        _ = PrivilegedRunner.runAsAdmin(commands.joined(separator: " ; "))
    }

    /// 把「所有已启用、且当前不在系统路由表中」的路由一次性补齐。
    ///
    /// 两个降弹窗设计：
    /// 1. **先用非提权查询筛选**：已经在系统表里的路由直接跳过。若全部就位，
    ///    整个过程零授权弹窗（系统重启后用不到、路由没变时也用不到）。
    /// 2. **合并为单条 shell 命令**：确实有缺失时，也只在首次弹**一次**授权框，
    ///    而不会按路由条数逐条弹。
    func applyAllEnabled() {
        let enabled = routes.filter { $0.enabled }
        guard !enabled.isEmpty else { return }

        // 步骤 1：非提权筛查，挑出真正缺失的路由
        let missing = enabled.filter { !isRouteInSystemTable($0) }
        guard !missing.isEmpty else { return }   // 全部已就位 → 不弹窗、不执行

        // 步骤 2：合并为单条命令，一次授权完成
        let combined = missing
            .map { RouteCommands.addCommand(for: $0) }
            .joined(separator: " ; ")
        _ = PrivilegedRunner.runAsAdmin(combined)
    }
}
