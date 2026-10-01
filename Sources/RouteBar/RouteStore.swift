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

    /// 菜单栏图标是否可见（菜单里「在菜单栏显示图标」Toggle 绑定此值）。
    ///
    /// **关闭后的兜底入口**：LSUIElement=true 没有 Dock 图标，菜单栏图标是
    /// 唯一入口。关闭后用全局快捷键 ⌥⌘R 唤起 popover 菜单（AppDelegate
    /// 注册 Carbon RegisterEventHotKey，无需辅助功能权限）。
    ///
    /// 注意：@Published 赋值在 init 阶段不会触发 Combine sink，所以
    /// AppDelegate 在 init 之后通过 store.showInMenuBar 读初值、再订阅变化。
    @Published var showInMenuBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar")
        }
    }

    /// 启动后是否自动检查更新（设置页「更新」分组绑定此值）。
    /// 只影响**启动后**那一次静默检查；设置页里的手动「检查更新」始终可用。
    @Published var autoCheckForUpdates: Bool = true {
        didSet {
            UserDefaults.standard.set(autoCheckForUpdates, forKey: "autoCheckForUpdates")
        }
    }

    // MARK: - 列表排序 / 分组偏好（主窗口排序菜单与快速启动页共用）

    /// 排序依据。默认「手动」= 按添加顺序，行为与老版本一致。
    @Published var sortKey: RouteSortKey = .manual {
        didSet {
            UserDefaults.standard.set(sortKey.rawValue, forKey: "sortKey")
        }
    }

    /// 升序 / 降序
    @Published var sortAscending: Bool = true {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: "sortAscending")
        }
    }

    /// 是否按「分组」分段显示。关掉就退化成一条平铺列表。
    @Published var groupedDisplay: Bool = true {
        didSet {
            UserDefaults.standard.set(groupedDisplay, forKey: "groupedDisplay")
        }
    }

    /// 主窗口列表的呈现形态：一行一条（`list`）或一行多张（`card` 网格）。
    ///
    /// 纯界面偏好，只落 `UserDefaults`，与 `routes.json` 无关 —— 换一种看法而已，
    /// 不该动到路由数据。默认「列表」：信息密度高、与老版本观感一致。
    @Published var displayMode: RouteDisplayMode = .list {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode")
        }
    }

    /// 已折叠的分组名集合（键是 `RouteGroup.title`，「未分组」也是一个普通键）。
    ///
    /// **为什么按键名存、而不是按 UUID**：分组是**由路由的 `group` 字段算出来的**，
    /// 本身没有稳定 id；组名就是它的天然主键。副作用是"改了组名 = 换了新组，
    /// 折叠状态不会跟过去"，对折叠这种弱状态来说可以接受。
    ///
    /// 主窗口与快速启动页**共用**这一份状态 —— 两处对同一组的折叠与否必须一致，
    /// 否则同一个分组在两边一开一合，观感是坏的。
    @Published var collapsedGroups: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(collapsedGroups), forKey: "collapsedGroups")
        }
    }

    /// 某个分组当前是否折叠
    func isCollapsed(_ title: String) -> Bool { collapsedGroups.contains(title) }

    /// 折叠 / 展开某个分组
    func toggleCollapse(_ title: String) {
        if collapsedGroups.contains(title) {
            collapsedGroups.remove(title)
        } else {
            collapsedGroups.insert(title)
        }
    }

    // MARK: - 分组边栏（主窗口左侧，可隐藏）

    /// 边栏是否展开。纯界面偏好，只落 `UserDefaults`。
    ///
    /// **默认展开**：这是张瑜 2026-10-01 新加的功能 —— 默认收起的话他得先去找按钮，
    /// 功能得先看得见，才谈得上"隐藏"。
    @Published var sidebarVisible: Bool = true {
        didSet {
            UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible")
        }
    }

    /// 边栏里**选中的分组** —— 主窗口列表只看这些组。
    ///
    /// **空集 = 不过滤**（= 边栏顶部的「所有分组」）。于是"一个都没选"与"没在筛选"
    /// 是同一件事，不必再另外维护一个 `isFiltering: Bool` 去和它同步。
    ///
    /// 组名就是主键（分组没有实体，见 `RouteGroup`），与 `collapsedGroups` 同理。
    ///
    /// **只作用于主窗口**：快速启动页不传它 —— 那是"点一下就应用"的启动器，
    /// 把它也筛掉会让人以为路由丢了。
    @Published var selectedGroups: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedGroups), forKey: "selectedGroups")
        }
    }

    /// 边栏里点一个分组。
    ///
    /// - Parameter extend: 是否**追加**（按住 ⌘）。`false` 时**独占**这一组；
    ///   独占模式下再点一次已选中的那一组 = 取消选择（退回「所有分组」）——
    ///   边栏里经常只有一行可选，不给"点第二次取消"，用户就没法退出来了。
    func selectGroup(_ title: String, extend: Bool) {
        let key = RouteGrouping.canonicalTitle(title)
        if extend {
            if selectedGroups.contains(key) {
                selectedGroups.remove(key)
            } else {
                selectedGroups.insert(key)
            }
            return
        }
        selectedGroups = (selectedGroups == [key]) ? [] : [key]
    }

    /// 回到「所有分组」（边栏顶部那一行）
    func clearGroupSelection() { selectedGroups = [] }

    // MARK: - 快速启动页顶栏的分组筛选

    /// 快速启动页**顶栏筛选菜单**里选中的分组。
    ///
    /// 与主窗口边栏的 `selectedGroups` **刻意分开存**：两个界面各自记自己的筛选，
    /// 互不影响。这与"筛选只作用于主窗口"是同一条理由的两面 —— 快速启动页是
    /// "点一下就应用"的启动器，不该隔空改掉主窗口的浏览状态（反过来也一样：
    /// 主窗口按分组浏览时，弹出来的快速启动页仍应是完整的）。
    ///
    /// 语义与 `selectedGroups` 完全一致：**空集 = 所有分组**（不过滤），
    /// 于是"一个都没勾"和"没在筛选"是同一件事，不必再维护一个 `isFiltering`。
    @Published var quickLaunchGroups: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(quickLaunchGroups), forKey: "quickLaunchGroups")
        }
    }

    /// 勾选 / 取消勾选快速启动页筛选菜单里的一行。
    ///
    /// 组名就是主键（分组没有实体，见 `RouteGroup`），与 `selectedGroups` 同理，
    /// 因此同样要过一遍 `canonicalTitle` —— 菜单里显示的组名与存下来的键必须一致。
    func setQuickLaunchGroup(_ title: String, on: Bool) {
        let key = RouteGrouping.canonicalTitle(title)
        if on {
            quickLaunchGroups.insert(key)
        } else {
            quickLaunchGroups.remove(key)
        }
    }

    // MARK: - 快速启动窗口尺寸（设置页滑块调节）

    @Published var quickLaunchWidth: Double = QuickLaunchLimits.widthDefault {
        didSet {
            UserDefaults.standard.set(quickLaunchWidth, forKey: "quickLaunchWidth")
        }
    }

    @Published var quickLaunchListHeight: Double = QuickLaunchLimits.listHeightDefault {
        didSet {
            UserDefaults.standard.set(quickLaunchListHeight, forKey: "quickLaunchListHeight")
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
        showInMenuBar = UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true
        autoCheckForUpdates = UserDefaults.standard.object(forKey: "autoCheckForUpdates") as? Bool ?? true

        // 排序 / 分组 / 窗口尺寸偏好（同样是 init 内赋值，不触发 didSet）
        sortKey = RouteSortKey(rawValue: UserDefaults.standard.string(forKey: "sortKey") ?? "") ?? .manual
        sortAscending = UserDefaults.standard.object(forKey: "sortAscending") as? Bool ?? true
        groupedDisplay = UserDefaults.standard.object(forKey: "groupedDisplay") as? Bool ?? true
        displayMode = RouteDisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .list
        collapsedGroups = Set(UserDefaults.standard.stringArray(forKey: "collapsedGroups") ?? [])
        sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
        selectedGroups = Set(UserDefaults.standard.stringArray(forKey: "selectedGroups") ?? [])
        quickLaunchGroups = Set(UserDefaults.standard.stringArray(forKey: "quickLaunchGroups") ?? [])
        quickLaunchWidth = UserDefaults.standard.object(forKey: "quickLaunchWidth") as? Double
            ?? QuickLaunchLimits.widthDefault
        quickLaunchListHeight = UserDefaults.standard.object(forKey: "quickLaunchListHeight") as? Double
            ?? QuickLaunchLimits.listHeightDefault

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
        // 顺手回收没被引用的图标文件（会话内清理覆盖不到的路径见 `RouteIconLibrary.sweep`）。
        // **必须在解码成功之后**：解码失败时 `routes` 会是空数组，若照样扫，
        // 用户的图标会被一次清空。
        RouteIconLibrary.sweep(keeping: Set(decoded.compactMap { $0.icon }))
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

    /// 删除一条路由：**先撤销系统路由，撤销成功才删本地记录**。
    ///
    /// **为什么必须看 `revoke` 的返回值**（张瑜 2026-10-01 反馈的 bug）：
    /// `revoke` 走管理员授权通道，用户在授权框里点「取消」时它返回 `false`，
    /// 此时系统路由表里那条路由**原样还在**。原来的实现写的是 `_ = revoke(route)`
    /// —— 把结果丢掉、照样删本地记录，于是那条路由变成了
    /// **"界面里看不见、列表里也没有、却仍然生效"的残影**（重启前一直存在，
    /// 用户既删不掉它、也改不了它）。
    ///
    /// 现在的语义：**撤销没成功就不删**，记录留在列表里让用户重试，
    /// 由调用方负责把失败原因告诉用户。
    ///
    /// 顺带把另一种残影也清掉：`enabled == false` 但系统表里**其实有**这条
    /// （上次撤销失败留下的）—— 借这次删除再撤销一次。判断走
    /// `isRouteInSystemTable`（`runAsUser`，**非提权、不弹窗**），
    /// 所以只有"确实在表里"才会触发授权弹窗，正常的未启用路由删除仍是零弹窗。
    ///
    /// - Returns: `true` = 已删除；`false` = 撤销失败（多半是用户没授权），
    ///   **本地记录原样保留**。
    @discardableResult
    func remove(_ route: Route) -> Bool {
        let inSystemTable = route.enabled || isRouteInSystemTable(route)
        if inSystemTable && !revoke(route) {
            return false
        }
        routes.removeAll { $0.id == route.id }
        save()
        // 顺带清掉这条路由的自定义图标文件。放在 `save()` **之后**：万一写
        // routes.json 失败，至少记录还在、图标也还在，不会出现"图标没了但路由还
        // 在列表里"的错位。
        RouteIconLibrary.discard(route.icon)
        return true
    }

    // MARK: - 手动排序（拖拽）

    /// 把一条路由拖到 `targetID` 那一行**之前**，必要时顺带改它的分组。
    ///
    /// 这是「手动」排序的唯一写入口。`routes` 数组的顺序**就是**手动顺序
    /// （`RouteGroupBuilder` 在 `.manual` 下原样返回数组的相对顺序），所以只需要
    /// 重排数组，不必再给 `Route` 加一个 order 字段 —— 少一个要维护的字段，
    /// 也就少一处"数组顺序与 order 字段不一致"的隐患。
    ///
    /// - Parameters:
    ///   - id: 被拖动的路由
    ///   - targetID: 落点行，插入到它**之前**
    ///   - targetGroupTitle: 落点行所属的分组显示名。
    ///     `nil` = **不要动分组**（「不按分组显示」模式下所有行的组名都是空串，
    ///     若照常写入会把用户的分组全部清空）；`RouteGrouping.ungroupedTitle`
    ///     = 归入未分组（落库为 `nil`）。
    ///
    /// 一个刻意的不变量：**改分组只写本地 JSON，不碰系统路由表**。分组纯属界面
    /// 归类，既不影响 `route` 命令，也不该为它弹一次授权框。
    func moveRoute(_ id: UUID, before targetID: UUID, intoGroup targetGroupTitle: String?) {
        guard id != targetID else { return }
        guard let from = routes.firstIndex(where: { $0.id == id }) else { return }

        var item = routes[from]
        if let targetGroupTitle {
            let wanted = RouteGrouping.normalized(
                targetGroupTitle == RouteGrouping.ungroupedTitle ? "" : targetGroupTitle)
            if RouteGrouping.normalized(item.group) != wanted {
                item.group = wanted.isEmpty ? nil : wanted
            }
        }

        var copy = routes
        copy.remove(at: from)
        guard let to = copy.firstIndex(where: { $0.id == targetID }) else {
            // 落点行意外不在数组里（正常不会发生）：至少把分组改动落上
            routes[from] = item
            save()
            return
        }
        copy.insert(item, at: to)
        routes = copy
        save()
    }

    /// 把一条路由丢进「未分组」的**末尾**。
    ///
    /// **为什么需要它**：行上的落点只能表达"插到某一行之前"，所以"想退出分组"这件事
    /// 原本**没有地方可拖** —— 除非未分组里已经有别的行可以当落点（张瑜 2026-10-01 反馈）。
    /// 列表末尾那块"不属于任何分组"的区域没有具体的目标行，只能落到收容所的最后一条。
    ///
    /// 落点是"数组末尾"就够了：`RouteGroupBuilder` 在非按组名排序时把「未分组」恒排最末
    /// （见该函数的组间顺序规则），组内顺序又**原样保留数组相对顺序**，所以数组末尾
    /// 就是"未分组内最后一条"。
    func moveRouteToUngroupedTail(_ id: UUID) {
        guard let from = routes.firstIndex(where: { $0.id == id }) else { return }
        var item = routes[from]
        item.group = nil
        var copy = routes
        copy.remove(at: from)
        copy.append(item)
        routes = copy
        save()
    }

    // MARK: - 分组改名

    /// 把一个分组改名（新名字已被占用时 = 并入那个组）。
    ///
    /// **为什么是"改所有成员的 `group` 字段"而不是改一个组对象**：分组是**算出来的**
    /// —— `RouteGroupBuilder.groups` 每次渲染时按 `Route.group` 现分桶，分组自己没有
    /// 实体、也没有稳定 id（`RouteGroup.id` 就是组名）。所以"重命名分组"只能是
    /// "把所有成员路由的组名一起改掉"这一次批量写。副作用是组名同名即同组（这正是
    /// 分组的定义），不需要再维护一张组表。
    ///
    /// 三种正常结局：改名成功 / 新旧名字相同（空操作）/ 新名字已被别的组占用
    /// （**合并**，两条记录并到一组）。空名字一律拒绝 —— 想让成员散回「未分组」，
    /// 用拖拽把它们拖过去，比"改成空名"的语义清楚。
    ///
    /// 顺带把 `collapsedGroups` 里的键**迁移**到新名字：折叠状态按组名存（见该属性
    /// 的说明），不迁移的话折叠记录会挂在旧名字上变成垃圾，而新名字那边莫名是展开的。
    /// 合并时只要**任一方**是折叠的，结果就折叠。
    ///
    /// 一个刻意的不变量：**改分组只写本地 JSON，不碰系统路由表**（与 `moveRoute` 一致）
    /// —— 分组纯属界面归类，不该为它弹一次授权框。
    @discardableResult
    func renameGroup(from oldTitle: String, to newTitle: String) -> GroupRenameResult {
        let oldKey = RouteGrouping.canonicalTitle(oldTitle)
        let newValue = RouteGrouping.normalized(newTitle)
        guard !newValue.isEmpty else { return .emptyName }

        // 「未分组」是保留名（空组名统一显示成它）：改成这个名字 = 把成员散回未分组
        let newKey = RouteGrouping.canonicalTitle(newValue)
        guard oldKey != newKey else { return .unchanged }

        // 目标组是否**本来就有成员** —— 必须在改写之前判断，否则改完就分不清
        // "纯改名"与"两个组合并"了
        let targetExists = routes.contains { RouteGrouping.canonicalTitle($0.group) == newKey }

        var touched = 0
        for idx in routes.indices {
            guard RouteGrouping.canonicalTitle(routes[idx].group) == oldKey else { continue }
            routes[idx].group = (newKey == RouteGrouping.ungroupedTitle) ? nil : newValue
            touched += 1
        }
        guard touched > 0 else { return .sourceMissing }

        let wasCollapsed = collapsedGroups.contains(oldKey)
        let targetWasCollapsed = collapsedGroups.contains(newKey)
        collapsedGroups.remove(oldKey)
        if newKey != RouteGrouping.ungroupedTitle, wasCollapsed || targetWasCollapsed {
            collapsedGroups.insert(newKey)
        }

        // 边栏的选中状态也是按组名存的，同样要跟着搬 —— 不搬的话，改完名边栏里
        // 那一项就"掉了选"，列表会毫无征兆地变回「所有分组」。
        // （与折叠不同：这里**无条件**插入新名字，「未分组」在边栏里也是可选的一项。）
        if selectedGroups.remove(oldKey) != nil {
            selectedGroups.insert(newKey)
        }
        // 快速启动页顶栏的筛选同样是按组名存的，一并搬过去 —— 否则改完名，
        // 那一组会在快速启动页的筛选菜单里"掉了勾"，列表悄悄多出别的组。
        if quickLaunchGroups.remove(oldKey) != nil {
            quickLaunchGroups.insert(newKey)
        }

        save()
        return targetExists ? .merged(into: newKey, count: touched) : .renamed(count: touched)
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

        // 换了图标才删旧文件；没换（或从没上传过）时 `discard` 自己会判空返回。
        // 放在 `update` 之后：新文件名已经落进 routes.json，此刻删旧的绝不会
        // 出现"指向一个已经不存在文件"的中间态。
        if original.icon != updated.icon {
            RouteIconLibrary.discard(original.icon)
        }

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

    // MARK: - 列表视图数据

    /// 当前排序 / 分组偏好下，过滤并整理好的分组列表。
    ///
    /// 主窗口和快速启动页都调这个 —— 两边显示的**分组与顺序必然一致**，
    /// 不会出现"同一个分组在两处排序不同"的困惑。
    ///
    /// - Parameter includedGroups: 边栏的分组筛选。**默认空集 = 不过滤**，所以快速
    ///   启动页（它不传这个参数）看到的永远是全量 —— 筛选是主窗口自己的特性。
    func groups(query: String = "", includedGroups: Set<String> = []) -> [RouteGroup] {
        RouteGroupBuilder.groups(from: routes,
                                 query: query,
                                 by: sortKey,
                                 ascending: sortAscending,
                                 grouped: groupedDisplay,
                                 includedGroups: includedGroups)
    }

    /// 边栏**自己**用的：不受筛选影响的全部分组。
    ///
    /// 必须与 `groups(...)` 分开。若边栏也走 `groups()`，会踩进一个死循环式的坑：
    /// 点选「分组1」后列表筛掉了其余组，**边栏自己也只剩「分组1」** —— 想切到
    /// 「分组2」时，它已经从边栏里消失了。
    ///
    /// 顺带固定 `grouped: true`：边栏本来就是按分组组织的，不该受"列表要不要分段"
    /// （`groupedDisplay`）影响。
    func allGroups() -> [RouteGroup] {
        RouteGroupBuilder.groups(from: routes,
                                 by: sortKey,
                                 ascending: sortAscending,
                                 grouped: true)
    }
}
