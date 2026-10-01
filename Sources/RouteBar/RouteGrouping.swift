import Foundation

// MARK: - 分组与排序
//
// 「打开的分组字段怎么在两个界面体现」这件事集中在这里定规则，主窗口和
// 快速启动页都调同一个函数 —— 免得两边各写一套，出现"同一个分组两边排序不同"。

enum RouteGrouping {
    /// 没有填分组的路由，统一归到这个名字下
    static let ungroupedTitle = "未分组"

    /// 把分组名规范化：`nil` / 空串 / 纯空白 **一律** 归一成空串。
    ///
    /// 拖拽改分组、判断"两个路由是不是同一组"时都要用它 —— 否则 `nil` 与 `""`
    /// 会被当成两个不同的组（实测：从输入框来的空分组是 `""`，而代码里新建的
    /// 是 `nil`，不归一就会出现"看起来都在未分组、却互相拖不进去"）。
    static func normalized(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 用于**比较与显示**的组名：未分组统一成 `ungroupedTitle`（而不是空串）。
    static func canonicalTitle(_ raw: String?) -> String {
        let value = normalized(raw)
        return value.isEmpty ? ungroupedTitle : value
    }
}

/// 重命名分组的结果。
///
/// 分组**没有独立实体**（由 `Route.group` 算出来，见 `RouteGroup`），"改名"实际是
/// 一次批量改写，可能的结局比普通改名多几种 —— 尤其是"新名字已被别的组占用"，
/// 那时语义上是**合并**，得让调用方知道并且说给用户听。
enum GroupRenameResult {
    /// 改成功，`count` 条路由跟着换了组名
    case renamed(count: Int)
    /// 新名字已被另一个分组占用 → 两个分组**合并**，`count` 条路由并了过去
    case merged(into: String, count: Int)
    /// 新旧名字相同（规范化后），什么都没做
    case unchanged
    /// 空名字（含纯空白）
    case emptyName
    /// 源分组下一条路由都没有 —— 只在界面状态过期时才会出现
    case sourceMissing
}

/// 列表排序依据。
///
/// 「手动」= **用户拖拽决定的顺序**（把行拖到目标位置即改顺序，落库到 `routes.json`
/// 的数组顺序）；其余四项是按字段自动排序，拖拽不生效（拖了也会被下一次排序覆盖，
/// 所以界面上直接不开启拖拽）。
enum RouteSortKey: String, CaseIterable, Identifiable {
    case manual
    case name
    case destination
    case gateway
    case group

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:      return "手动（可拖拽）"
        case .name:        return "名称"
        case .destination: return "目标网段"
        case .gateway:     return "网关"
        case .group:       return "分组"
        }
    }

    /// 是否允许拖拽调整顺序。只有「手动」可以 —— 其余排序是"算出来的"，
    /// 拖完立刻会被重排回去，开启拖拽只会让人以为坏了。
    var supportsDragging: Bool { self == .manual }
}

/// 主窗口列表的**呈现形态**（张瑜 2026-10-01 要求：一条一条的也能切成卡片）。
///
/// - `list`：一行一条。信息密度最高，适合逐条核对网段/网关，也是默认形态。
/// - `card`：卡片网格，一行多张。路由不多时"看名字就能认出来"，卡片比长条更省眼睛；
///   窗口拉宽会自动多排几列。
///
/// **两者承载的信息与操作完全一致**（名称、网段→网关、启用开关、编辑、删除、
/// 分组标签一个不少），只是排布方式不同 —— 切形态不该丢功能，也不该改变数据。
///
/// 只作用于**主窗口**：快速启动页是"点一下就应用路由"的启动器，它的行高与命中
/// 区域有固定预期（张瑜专门调过窗口尺寸），不做第二套排布。
enum RouteDisplayMode: String, CaseIterable, Identifiable {
    case list
    case card

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "列表"
        case .card: return "卡片"
        }
    }

    /// 分段控件里每一格画的图标 —— **画的是它自己代表的那一档**
    /// （网格格 = 卡片视图、列表格 = 列表视图）。
    ///
    /// 与早期"单按钮切换"的写法不同：那时屏上只有一个图标，只能画**点下去会变成
    /// 什么**（访达的显示方式按钮就是这么做的）；现在两个图标同屏并排、选中的那格
    /// 还有药丸底，所以每一格直接画自己即可，不再需要那层心理换算。
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .card: return "square.grid.2x2"
        }
    }
}

/// 一个分组及其成员。`title` 为空串表示「未分组且不显示分组头」。
struct RouteGroup: Identifiable {
    let title: String
    let routes: [Route]
    var id: String { title }
}

extension Route {
    /// 界面上优先显示名称，没填就用目标网段
    var displayName: String { name.isEmpty ? destination : name }
}

enum RouteGroupBuilder {

    /// 关键字匹配：名称 / 目标网段 / 网关 / 分组，任一命中即可
    static func matches(_ route: Route, query: String) -> Bool {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return true }
        return route.name.lowercased().contains(keyword)
            || route.destination.lowercased().contains(keyword)
            || route.gateway.lowercased().contains(keyword)
            || (route.group ?? "").lowercased().contains(keyword)
    }

    /// 过滤 → 分组 → 组内排序 → 组间排序。
    ///
    /// - Parameters:
    ///   - grouped: `false` 时不分段，返回**单个** title 为空的分组
    ///   - includedGroups: **只看这些分组**（主窗口边栏的筛选落点）。**空集 = 不过滤**，
    ///     于是"一个都没选"和"没在筛选"是同一件事，不必再多一个 Bool 表示筛选开关。
    ///     集合元素是 `RouteGrouping.canonicalTitle` 规范化后的组名 —— 所以「未分组」
    ///     要写成 `ungroupedTitle`，不能写成空串。
    static func groups(from routes: [Route],
                       query: String = "",
                       by key: RouteSortKey = .manual,
                       ascending: Bool = true,
                       grouped: Bool = true,
                       includedGroups: Set<String> = []) -> [RouteGroup] {
        var filtered = routes.filter { matches($0, query: query) }
        if !includedGroups.isEmpty {
            filtered = filtered.filter {
                includedGroups.contains(RouteGrouping.canonicalTitle($0.group))
            }
        }
        guard !filtered.isEmpty else { return [] }

        guard grouped else {
            return [RouteGroup(title: "", routes: sorted(filtered, by: key, ascending: ascending))]
        }

        // 1) 按分组名分桶，同时记住"首次出现"的顺序
        var order: [String] = []
        var buckets: [String: [Route]] = [:]
        for route in filtered {
            let raw = (route.group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = raw.isEmpty ? RouteGrouping.ungroupedTitle : raw
            if buckets[title] == nil {
                order.append(title)
                buckets[title] = []
            }
            buckets[title]?.append(route)
        }

        // 2) 组内排序
        for (title, items) in buckets {
            buckets[title] = sorted(items, by: key, ascending: ascending)
        }

        // 3) 组间顺序
        if key == .group {
            // 明确按分组名排时，组名也跟着升降序走
            order.sort { lhs, rhs in
                let c = lhs.localizedStandardCompare(rhs)
                return ascending ? c == .orderedAscending : c == .orderedDescending
            }
        } else {
            // 其余情况保持"首次出现"顺序，只把「未分组」挪到最末（用 filter 拼接，
            // 不用 sort —— Swift 的 sorted(by:) 不保证稳定，会打乱相对顺序）
            order = order.filter { $0 != RouteGrouping.ungroupedTitle }
                  + order.filter { $0 == RouteGrouping.ungroupedTitle }
        }

        return order.map { RouteGroup(title: $0, routes: buckets[$0] ?? []) }
    }

    /// 是否需要画分组标题：
    /// 只有一组且是「未分组」（或本来就是不分段模式）时，标题没有信息量，不画。
    static func showsHeaders(_ groups: [RouteGroup]) -> Bool {
        guard let first = groups.first, !first.title.isEmpty else { return false }
        if groups.count > 1 { return true }
        return first.title != RouteGrouping.ungroupedTitle
    }

    // MARK: - 排序

    private static func sorted(_ routes: [Route],
                               by key: RouteSortKey,
                               ascending: Bool) -> [Route] {
        // 手动：完全保留原顺序，只按升降序翻转
        guard key != .manual else {
            return ascending ? routes : routes.reversed()
        }
        return routes.sorted { lhs, rhs in
            let c = compare(lhs, rhs, by: key)
            if c == .orderedSame {
                // 稳定的兜底比较，避免同一分组内顺序随机
                return lhs.destination < rhs.destination
            }
            return ascending ? c == .orderedAscending : c == .orderedDescending
        }
    }

    private static func compare(_ lhs: Route, _ rhs: Route, by key: RouteSortKey) -> ComparisonResult {
        switch key {
        case .manual:
            return .orderedSame
        case .name:
            return lhs.displayName.localizedStandardCompare(rhs.displayName)
        case .destination:
            return compareIPv4(lhs.destination, rhs.destination)
        case .gateway:
            return compareIPv4(lhs.gateway, rhs.gateway)
        case .group:
            let a = (lhs.group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let b = (rhs.group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return a.localizedStandardCompare(b)
        }
    }

    /// 按 IP 数值比较，而不是字符串 —— 否则 "10.0.0.0" 会被排在
    /// "9.0.0.0" 后面（字符串序 '1' < '9'）。掩码长度作为次级键。
    private static func compareIPv4(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let (aAddr, aMask) = RouteCommands.parse(lhs)
        let (bAddr, bMask) = RouteCommands.parse(rhs)

        if let a = RouteCommands.ipv4ToUInt32(aAddr),
           let b = RouteCommands.ipv4ToUInt32(bAddr) {
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
            let pa = aMask.flatMap(RouteCommands.prefixFromNetmask) ?? 32
            let pb = bMask.flatMap(RouteCommands.prefixFromNetmask) ?? 32
            if pa != pb { return pa < pb ? .orderedAscending : .orderedDescending }
            return .orderedSame
        }
        return aAddr.localizedStandardCompare(bAddr)
    }
}

// MARK: - 快速启动窗口尺寸的可选范围

/// 设置页里那两个滑块的取值范围与默认值
enum QuickLaunchLimits {
    static let widthRange: ClosedRange<Double> = 300...560
    static let widthDefault: Double = 340

    static let listHeightRange: ClosedRange<Double> = 180...760
    static let listHeightDefault: Double = 420
}
