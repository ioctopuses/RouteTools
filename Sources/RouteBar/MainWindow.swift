import SwiftUI
import AppKit
// 只为一件事：上传图标时 `NSOpenPanel.allowedContentTypes` 需要 `UTType.image`
// （旧的 `allowedFileTypes = ["png", …]` 已废弃，且漏一个格式就选不中）
import UniformTypeIdentifiers

// MARK: - 主窗口：路由管理
//
// 这个文件只放"看得见的界面"（主窗口 / 路由行 / 添加编辑表单）。
// `@main` 与 `.commands` 留在 `RouteBarApp.swift`，两者拆开的好处是
// 这些视图可以被离屏渲染工具单独复用（做 UI 预览/截图），不必启动整个 App。

/// 主窗口内容。
///
/// **不画页内大标题**：窗口标题栏（系统原生）已经显示「路由管理」，页内再来
/// 一遍就是重复（编辑窗口同理）。标题栏**下方**是一条工具行，只承担操作：
///   `[添加路由] [排序 | 设置]  ← 弹簧 →  [🔍 搜索框(最右)]`
struct RouteListView: View {
    @EnvironmentObject var store: RouteStore

    @State private var query = ""
    /// 拖拽是否正悬在**窗口最下面那条线**（"移出分组"落点）上。只影响那条线与状态栏
    /// 的样式，真正的落点与判据见 `bottomDropTarget` / `canDropToUngrouped`
    @State private var isUngroupedTargeted = false

    var body: some View {
        // 主窗口的筛选来自**左边栏**（`selectedGroups`）。快速启动页后来也有了一套
        // 自己的筛选，但用的是它自己的 `quickLaunchGroups` —— 两边分开存、
        // 各筛各的，在哪儿筛的就只在哪儿生效（理由见 RouteStore 那段注释）。
        let groups = store.groups(query: query, includedGroups: store.selectedGroups)
        HStack(spacing: 0) {
            if store.sidebarVisible {
                RouteGroupSidebar()
                    // 从左边滑入 / 滑出（右侧列表区跟着让位），配上面那个 `.animation`
                    .transition(.move(edge: .leading).combined(with: .opacity))
                // 这里**没有竖分隔线**：两侧底色（左灰右白）本身就把边界交代清楚了，
                // 再加一条线是"两套语言"（系统设置、访达的分栏都没有它）。而且
                // `Divider` 只活在安全区内，标题栏那一行会缺一段 —— 断在半路比没有更碍眼。
            }
            VStack(spacing: 0) {
                listArea(for: groups)
                // 原来是 `Divider() + statusBar` 两条独立视图；现在合成**一个底部落点**：
                // 窗口最下面那条线连同状态栏整块都能接住拖拽（见 `bottomDropTarget`）。
                // 张瑜 2026-10-01：「拖到这里 移出分组」那块虚线框换成**最下面一条线**。
                bottomDropTarget(for: groups)
            }
            // 右侧内容区**白底**。张瑜 2026-10-02 定下的分栏配色：**左灰右白**。
            //
            // `.ignoresSafeArea(.container, edges: .top)` 是这里的关键 —— 主窗口开了
            // `.fullSizeContentView`（见 `WindowManager`），标题栏是透明的，但 SwiftUI
            // 仍把标题栏那一段算作 top safe area（不这样算，列表首行会藏到工具栏底下）。
            // 让**背景**忽略它，底色才能一路铺到窗口最顶端、红绿灯那一行；
            // 内容（列表、状态栏）照旧留在安全区里，不会被工具栏压住。
            .background(Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea(.container, edges: .top))
        }
        // 撑满整窗：列表条数少时内容比窗口矮，HStack 只会占内容那么高，
        // 分栏底色就铺不满（底部会露出一截窗口自己的底色）。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 边栏出入场平滑一点。范围是 Bool 且**只挂在 `sidebarVisible` 上** ——
        // 不会顺手把列表本身的重排也动画化。
        .animation(.easeInOut(duration: 0.18), value: store.sidebarVisible)
        // 操作控件交给**窗口工具栏**（标题栏那一行，与红绿灯同行），页内不再
        // 自绘工具行 —— 与设置窗口同一形态：窗口不显示标题，顶部一行只放控件。
        .toolbar { toolbarItems }
    }

    // MARK: - 工具行

    /// 工具栏内容：位于**窗口标题栏那一行**（由系统 `NSToolbar` 承载，红绿灯就在
    /// 它左侧）。窗口标题已隐藏，所以这一行就是"顶部唯一的操作带" —— 不再有
    /// "标题栏一行 + 页内工具行一行"的重复观感。
    ///
    /// **排布**：`[添加路由]`（左，紧挨红绿灯）…… `[⇅]` `[⚙]` `[🔍 搜索框]`
    /// （右，**三枚各自独立**，谁都不并进谁的胶囊）。
    ///
    /// **两段间隔各司其职**：
    ///   - `ToolbarSpacer(.flexible)` —— 先插一个弹性空隙，把右侧三枚整体推到窗口右端；
    ///     工具栏项是**从前往后依次排布**的，没有弹性项时它们会全部挤在红绿灯旁边。
    ///   - `ToolbarSpacer(.fixed)` —— 三枚之间各插一个固定小间隔。`NSToolbar` 会把
    ///     **相邻**的 bordered 项自动并成一个玻璃胶囊（排序 / 设置 / 搜索挨着放会
    ///     糊成一整条），`.fixed` 只划出分组边界、不撑开版面：两侧的项各自拿到
    ///     独立的玻璃底，位置仍留在右上角。
    ///
    /// **一律用系统默认的工具栏按钮样式**（不自绘圆盘）：自绘的 26pt 圆盘与相邻项
    /// 之间没有留白，两枚并排会粘成一个胶囊（实测 `↕ ⚙` 合成了一体）；交给系统画，
    /// 间距与玻璃底由系统统一给，与左右两侧的系统控件也才是一套语汇。
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // 添加：在最左，紧挨红绿灯。
        //
        // **两枚按钮写在同一个 `ToolbarItem` 里**（HStack），不是为了省事 ——
        // `ToolbarContentBuilder` 的 buildBlock **最多只吃 10 个**顶层元素，这个工具栏
        // 加上边栏按钮正好溢出，而报错是一句没头没脑的
        // `error: extra argument in call`（还指向**末尾**那个 `if #available`，
        // 跟真正多出来的那一项毫无关系）。合成一枚正好回到 9 个。
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                // 添加路由
                Button {
                    WindowManager.shared.showEditor(route: nil)
                } label: {
                    Label("添加路由", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("添加一条静态路由（⌘N）")

                // 分组边栏开关。放**左侧**是因为它管的就是左边那一块；
                // 状态落 `UserDefaults`，重启保持（见 `RouteStore.sidebarVisible`）。
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.sidebarVisible.toggle()
                    }
                } label: {
                    Label("分组边栏", systemImage: "sidebar.left")
                }
                .help(store.sidebarVisible ? "隐藏分组边栏" : "显示分组边栏")
            }
        }

        // 弹性空隙：把右侧三枚控件**整组推到窗口右端**。
        // 工具栏项是从前往后依次排布的 —— 没有弹性项时它们会全部挤在红绿灯旁边
        // （实测：加了 `.fixed` 之后排序/设置/搜索跑到了最左边）。
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem(placement: .primaryAction) { Spacer() }
        }

        // 排序：独立一枚
        ToolbarItem(placement: .primaryAction) {
            Menu {
                sortMenuItems
            } label: {
                Label("排序与分组", systemImage: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .help("排序与分组")
        }

        // 固定间隔 → 与「设置」分属两个玻璃底
        // （`ToolbarSpacer` 要 macOS 26+，低版本上退化为相邻项共用一个底）
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }

        // 列表 / 卡片 形态切换：**一个胶囊里并排两个图标**，选中的那一格带药丸底。
        //
        // 以前是一枚"切换"按钮（画点下去会变成的形态）；张瑜 2026-10-01 给了参考图，
        // 要求两档**同时可见、共用一个胶囊**。这也是分段控件相对单按钮的好处：
        // 当前处于哪一档、另一档是什么，一眼都在，不用点一下才知道。
        //
        // `.sharedBackgroundVisibility(.hidden)`：控件自己**已经是一个胶囊**了，
        // 若再让工具栏给它套一层共享背景底，就会变成"胶囊外包着胶囊"（同搜索框）。
        // 该修饰符是 macOS 26+，故与搜索框一样分两个分支写（两个分支只差这一个修饰符）。
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                displayModeSwitch
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                displayModeSwitch
            }
        }

        // 固定间隔 → 切换按钮与「设置」也不共用玻璃底
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }

        // 设置：独立一枚
        ToolbarItem(placement: .primaryAction) {
            Button {
                WindowManager.shared.showSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .help("设置")
        }

        // 固定间隔 → 搜索框也单独一组，落在窗口右上角
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }

        // 搜索框：独立一枚（不属于任何按钮组）
        // macOS 26+ 工具栏会给它再套一个**共享背景胶囊**，看起来像"被一个胶囊套住"；
        // 用 `.sharedBackgroundVisibility(.hidden)` 去掉那一层外底，只留
        // `RBSearchField` 自己的液态玻璃胶囊 —— 它本身就应该是胶囊（搜索字段的
        // 标准形态），"被套住"说的从来都是外面那一层。
        // 宽度必须用 `.frame(width:)` 写死，**不能靠 `RBSearchField` 的 `maxWidth`**
        // —— 那个参数只是"上限"，而工具栏是按视图的**理想尺寸**摆位的：内容
        // （放大镜 + 空输入框）的理想宽度很小，于是搜索框被压到 ~94pt（实测），
        // 传 220 也没用。这里从外面给一个确定宽度，它在工具栏里就真占这么宽。
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                RBSearchField(placeholder: "搜索路由", text: $query)
                    .frame(width: 280)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                RBSearchField(placeholder: "搜索路由", text: $query)
                    .frame(width: 280)
            }
        }
    }

    /// 形态切换分段控件。抽成一个属性是因为工具栏里要为它写两个可用性分支
    /// （macOS 26+ 才能挂掉系统那层共享背景胶囊），控件本身完全一致，不该抄两遍。
    ///
    /// 两格的图标**各自代表自己那一档**（网格 = 卡片、列表 = 列表），与参考图一致。
    private var displayModeSwitch: some View {
        RBGlassSegmented(
            segments: RouteDisplayMode.allCases.map { mode in
                RBSegment(value: mode,
                          icon: mode.icon,
                          help: "切换成\(mode.label)视图")
            },
            selection: $store.displayMode)
    }

    /// 排序 / 分组菜单的**内容**（注意：只返回菜单项，本身不是 Menu）。
    ///
    /// **必踩的坑**：这里**不能**再包一层 `Menu`。早先写成
    /// `Menu { sortMenu }`，而 `sortMenu` 内部是 `RBGlassGroupMenuButton`（它自己
    /// 就是一个 `Menu`）—— SwiftUI 把内层 Menu 解释成"子菜单项"，外层 NSMenu 里
    /// 于是没有任何可选项，AppKit 干脆不弹（实测：AXPress 返回成功、屏幕上
    /// 什么都不出现，就是用户说的「排序点击后没有反应」）。
    ///
    /// 结构参照访达的「整理方式」弹出菜单：
    /// 一组单选（排序依据）+ 分组开关 + 一组单选（升序/降序）。
    @ViewBuilder
    private var sortMenuItems: some View {
        Picker("排序方式", selection: $store.sortKey) {
            ForEach(RouteSortKey.allCases) { key in
                Text(key.label).tag(key)
            }
        }
        .pickerStyle(.inline)

        Divider()

        Toggle("按分组显示", isOn: $store.groupedDisplay)

        // 折叠多了以后逐个点开很烦，给一个总开关。一个组都没折叠时置灰 ——
        // 菜单项状态本身就说明了"现在有没有折叠的组"。
        Button("展开全部分组") {
            withAnimation(.easeInOut(duration: 0.16)) {
                store.collapsedGroups.removeAll()
            }
        }
        .disabled(store.collapsedGroups.isEmpty)

        Divider()

        Picker("顺序", selection: $store.sortAscending) {
            Text("升序").tag(true)
            Text("降序").tag(false)
        }
        .pickerStyle(.inline)
    }

    // MARK: - 列表

    @ViewBuilder
    private func listArea(for groups: [RouteGroup]) -> some View {
        if store.routes.isEmpty {
            emptyState
        } else if groups.isEmpty {
            noMatchState
        } else {
            let showHeaders = RouteGroupBuilder.showsHeaders(groups)
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            // 拖拽只在「手动」排序、且**不在搜索态**时开启：
            //   · 其余四种排序是"算出来的"，拖完立刻被重排回去，开了只会让人以为坏了；
            //   · 搜索时列表是筛选后的子集，"插到某行之前"在完整列表里没有明确落点。
            let canDrag = store.sortKey.supportsDragging && trimmedQuery.isEmpty
            // 搜索时**强制展开**：否则命中的路由藏在折叠着的分组里，用户看到的是
            // "搜了却什么都没有"。折叠状态本身不动，清空搜索框就恢复原样。
            let forceExpand = !trimmedQuery.isEmpty

            ScrollView {
                // 组间距按形态给：卡片形态一行多张，组与组的边界要靠更大留白交代
                LazyVStack(alignment: .leading, spacing: store.displayMode == .card ? 14 : 3) {
                    ForEach(groups) { group in
                        let folded = showHeaders && !forceExpand && store.isCollapsed(group.title)
                        if showHeaders {
                            RBGroupHeader(title: group.title,
                                          count: group.routes.count,
                                          collapsible: true,
                                          collapsed: folded,
                                          onToggle: {
                                              withAnimation(.easeInOut(duration: 0.16)) {
                                                  store.toggleCollapse(group.title)
                                              }
                                          },
                                          // 「未分组」不给改名 —— 那是"没填分组"的收容所，
                                          // 不是用户建出来的组，改了名等于给它换了个马甲
                                          onRename: group.title == RouteGrouping.ungroupedTitle
                                              ? nil
                                              : { presentRenameGroup(group.title, store: store) })
                                // 拖到**分组标题**上 = 放进这个组（置于组内最前）。
                                // 落点用组内第一行的 id，所以**折叠着的组同样收得进来** ——
                                // 那种情况组内一行都没渲染，光靠行上的落点根本够不着。
                                .modifier(RBGroupDropTarget(enabled: canDrag,
                                                            groupTitle: group.title,
                                                            firstRouteID: group.routes.first?.id))
                        }
                        if !folded {
                            routesContent(of: group, canDrag: canDrag)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 一个分组内路由的排布 —— **列表 / 卡片两种形态只在这一处分岔**。
    ///
    /// 放在这里而不是散进上面的循环里，是为了让过滤、分桶、折叠、分组标题落点
    /// 这几套逻辑**完全不必知道当前是哪种形态**；切换形态只换这一个函数的下标，
    /// 其余一律不动。
    ///
    /// 两种形态挂的是**同一个** `RBManualReorder`：拖拽是数据顺序上的事
    /// （`routes` 数组顺序 = 手动顺序），与画成一行还是一张卡无关。
    ///
    /// - Parameters:
    ///   - group: 当前分组
    ///   - canDrag: 是否开启手动拖拽（判据见 `listArea`）
    @ViewBuilder
    private func routesContent(of group: RouteGroup, canDrag: Bool) -> some View {
        // 落点分组名传 nil 的场合见下面的注释：不按分组显示时拖拽只重排、不改分组
        let dropGroupTitle = store.groupedDisplay ? group.title : nil

        switch store.displayMode {
        case .card:
            // `.adaptive` 而不是写死列数：窗口拉宽自动多排一列，窄了自动回落到一列。
            // 210pt 是"卡片里放得下 `172.16.0.0/16 → 192.168.1.15` 且不至于挤"的下限
            // （主窗口默认 620 宽 → 两列）。
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)],
                      alignment: .leading,
                      spacing: 10) {
                ForEach(group.routes) { route in
                    RouteCard(route: route, showGroupChip: !store.groupedDisplay)
                        .modifier(RBManualReorder(route: route,
                                                  groupTitle: dropGroupTitle,
                                                  enabled: canDrag))
                }
            }

        case .list:
            ForEach(group.routes) { route in
                // 关掉分组分段后，用行内小标签继续表明归属
                RouteRow(route: route, showGroupChip: !store.groupedDisplay)
                    .modifier(RBManualReorder(
                        route: route,
                        // 不按分组显示时传 nil：拖拽只重排、**不改分组**
                        // （那时每行的组名都是空串，照写会把分组全清掉）
                        groupTitle: dropGroupTitle,
                        enabled: canDrag))
            }
        }
    }

    /// 窗口**最下面那一条**：既是状态栏的分隔线，也是「把路由移出分组」的落点。
    ///
    /// 张瑜 2026-10-01 的第二版要求：原来列表末尾摆着一块 42pt 高的虚线框（写着
    /// 「拖到这里：移出分组」），占地方、还得先滚到列表底部才够得着；改成**贴着窗口
    /// 最下面的一条线**，拖到底部那条线即刻生效 —— 它**固定在窗口底部**，无论列表
    /// 滚到哪儿、内容够不够一屏，都不用先滚到底。
    ///
    /// **为什么命中区是"线 + 整条状态栏"，而不是光那 1pt 的线**：1pt 窄到几乎拖不中，
    /// 而 `isTargeted` 只认 `contentShape` 圈定的范围。让整条状态栏（约 28pt 高）都
    /// 接住，落点才够宽容；视觉上仍然只是"最下面一条线"。
    ///
    /// **线在固定 3pt 的槽里变粗**：悬停时 1pt → 2pt，槽高不变，状态栏不会因为线
    /// 变粗而往下跳一下。
    ///
    /// 落库走 `moveRouteToUngroupedTail`：没有具体目标行，就落到未分组的末尾。
    private func bottomDropTarget(for groups: [RouteGroup]) -> some View {
        let enabled = canDropToUngrouped(groups)
        let hot = enabled && isUngroupedTargeted
        return VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(hot ? Color.accentColor : Color(nsColor: .separatorColor))
                    .frame(height: hot ? 2 : 1)
            }
            .frame(height: 3)
            statusBar
        }
        // 整块（线槽 + 状态栏）都接得住拖拽，不必精确压在那 1pt 上
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard enabled,
                  let raw = items.first,
                  let id = UUID(uuidString: raw) else { return false }
            withAnimation(.easeInOut(duration: 0.16)) {
                store.moveRouteToUngroupedTail(id)
            }
            return true
        } isTargeted: { targeted in
            isUngroupedTargeted = targeted && enabled
        }
    }

    /// 能不能把某一行拖到**窗口最下面那条线**上（= 移出分组）。
    ///
    /// 判据与 `listArea` 里开拖拽的 `canDrag` 保持一致（手动排序 + 不在搜索态），
    /// 另外还要「按分组显示」且「确实存在真分组」：
    ///   ·「不按分组显示」时拖拽只重排、**不改分组**（见行上的 `groupTitle` 传 nil
    ///     那段），摆一个"移出分组"的落点自相矛盾；
    ///   · 一条分组都没有时它没有意义（本来全在未分组里）。
    private func canDropToUngrouped(_ groups: [RouteGroup]) -> Bool {
        store.sortKey.supportsDragging
            && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.groupedDisplay
            && groups.contains { $0.title != RouteGrouping.ungroupedTitle }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("还没有任何路由")
                .font(.headline)
            Text("点击左上角「添加路由」开始")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 6) {
            Text("没有匹配「\(query)」的路由")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 底部状态栏。正常显示路由计数；**拖拽悬在它上面时**（见 `bottomDropTarget`）
    /// 左端文字换成落点提示 —— 底部那条线只是变个颜色，光靠颜色说不清"放手会发生
    /// 什么"，把结果直接写出来。
    private var statusBar: some View {
        HStack {
            Text(isUngroupedTargeted ? "放开：移出分组" : statusText)
                .font(.system(size: 11))
                .foregroundStyle(isUngroupedTargeted
                                 ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(.secondary))
            Spacer()
            Text("v\(Bundle.main.appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var statusText: String {
        if store.routes.isEmpty { return "0 条路由" }
        let total = store.routes.count
        let enabled = store.routes.filter { $0.enabled }.count
        var text = "\(total) 条路由 · 已启用 \(enabled)"
        if store.groupedDisplay {
            // 用**不受筛选影响**的分组数（`store.groups()` 不传 includedGroups）——
            // 这里要回答的是"一共有几个分组"，不是"当前看得到几个"
            let groupCount = store.groups().count
            if groupCount > 1 { text += " · \(groupCount) 个分组" }
        }
        // 筛选态必须**显式说出来**：否则"12 条路由"配着只显示 5 行的列表，
        // 看起来就像路由丢了
        if !store.selectedGroups.isEmpty {
            text += " · 已筛选 \(store.selectedGroups.count) 组"
        }
        return text
    }
}

// MARK: - 分组边栏（主窗口左侧，可隐藏）

/// 主窗口左侧的**分组边栏**：列出所有分组，点一下就只看这一组（按住 ⌘ 多选）。
///
/// 张瑜 2026-10-01 要求：「主页左边增加一个隐藏的边栏，所有分组、分组1、分组2……
/// 可以在边栏切换分组，支持多选分组」。
///
/// **可隐藏**：工具栏最左那枚 `sidebar.left` 按钮 toggle（`RouteStore.sidebarVisible`
/// 持久化）。主窗口宽 1000pt，边栏占 172pt 后列表区还剩 828pt —— 想看宽列表时收起来。
///
/// **为什么顶部单独一行「所有分组」，而不是一个"全选"复选框**：它就是"取消筛选"，
/// 点它 = 把选择清空，比复选框直白，同时它自己还充当"当前没在筛选"的指示器
/// （高亮在它身上 = 没筛）。
///
/// **列表内容取 `store.allGroups()`，不是 `store.groups()`** —— 后者会应用当前筛选，
/// 那样一点「分组1」，边栏里其余分组就全消失了，再也切不回去。
private struct RouteGroupSidebar: View {
    @EnvironmentObject var store: RouteStore

    /// 边栏宽度（pt）。**固定值**：做成可拖拽的话，"列表区还剩多宽"就变得不可预料，
    /// 而卡片的列数是跟着列表区宽度自动算的。
    ///
    /// 2026-10-02 由 172 调到 186：图标与字号整体调大一档后（见 `RouteSidebarRow`），
    /// 172 会让组名更早开始截断。加宽的量正好抵掉字号增量，组名可见长度与原来持平。
    private let width: CGFloat = 186

    /// 边栏底色：**一档明确的灰**（张瑜 2026-10-02：「边栏颜色调整灰色」）。
    ///
    /// 不再用 `windowBackgroundColor`：它在浅色下是 #ECECEC，与右侧内容区的纯白
    /// 只差一点点，"分栏"这件事交代得很勉强。这里改用自定义动态色 ——
    /// 浅色压到约 #E6E6E6、深色抬到约 #2A2A2A，与内容区（`textBackgroundColor`）
    /// 稳定拉开一档，任何外观下左灰右白都一眼可辨。
    ///
    /// 深色下**比内容区亮**（不是更暗）是刻意的：系统设置 / 访达的侧边栏就是这个
    /// 方向 —— 内容区是最深的那块，侧栏托在上面。
    private var sidebarBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 0.165, alpha: 1)
                : NSColor(white: 0.902, alpha: 1)
        })
    }

    var body: some View {
        let groups = store.allGroups()
        VStack(alignment: .leading, spacing: 0) {
            Text("分组")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 5)

            ScrollView {
                LazyVStack(spacing: 2) {
                    RouteSidebarRow(title: "所有分组",
                                    count: store.routes.count,
                                    selected: store.selectedGroups.isEmpty,
                                    icon: "square.grid.2x2",
                                    isAll: true)

                    // 一个真分组都没有时不画这条分隔线（下面只剩「未分组」一行，
                    // 分隔线会显得没头没尾）
                    if groups.count > 1 {
                        Divider()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                    }

                    ForEach(groups) { group in
                        RouteSidebarRow(title: group.title,
                                        count: group.routes.count,
                                        selected: store.selectedGroups.contains(group.title),
                                        icon: group.title == RouteGrouping.ungroupedTitle
                                            ? "tray" : "folder",
                                        isAll: false)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
        }
        .frame(width: width)
        // 边栏底色见 `sidebarBackground`：与右侧内容区的白配成 macOS 27 那种
        // "左灰右白"的分栏（系统设置 / 访达都是这个结构）。
        //
        // 早先这里是 `Color.primary.opacity(0.04)`（≈ #F5F5F5）：当时主窗口铺着整窗
        // 材质，太重的灰会和材质打架，只能压到极淡；后来换成 `windowBackgroundColor`
        // 仍然偏亮，撑不起"分栏"（张瑜 2026-10-02 要求再调灰一档）。
        //
        // 和右侧内容区一样忽略顶部安全区 —— 灰色要一直铺到窗口最顶端，红绿灯那一行
        // 跟着它变色（这正是上次要求的重点）。
        .background(sidebarBackground
            .ignoresSafeArea(.container, edges: .top))
    }
}

/// 边栏里的一行。
private struct RouteSidebarRow: View {
    let title: String
    let count: Int
    let selected: Bool
    let icon: String
    /// 是否是顶部那行「所有分组」（点它 = 清空筛选）
    let isAll: Bool

    @EnvironmentObject var store: RouteStore
    @State private var hovering = false

    var body: some View {
        // 尺寸整体调大一档（张瑜 2026-10-02：「把图标和字体调大一些」）：
        // 图标 11 → 13、组名 12 → 13、计数 11 → 12；边栏宽度同步 172 → 186
        // （见 `width`），组名的可见长度与放大前持平，不会因为字大了就更早截断。
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 17)
                .foregroundStyle(selected
                                 ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(.secondary))

            Text(title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .lineLimit(1)
                // 组名长了截中间（尾部往往是"组/分组"这类无信息量的后缀）
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected
                      ? Color.accentColor.opacity(0.18)
                      : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        // 整行都能点，不必精确落在文字上
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if isAll {
                store.clearGroupSelection()
            } else {
                // **按住 ⌘ 才是多选**，与 macOS 源列表的习惯一致。
                // 修饰键**不能**靠 `TapGesture().modifiers(.command)` 判断：那样得挂
                // 两个手势才能同时覆盖"普通点"和"⌘ 点"，而两个手势会同时触发。
                // 直接在回调里读当前修饰键最省事也最准 —— 鼠标事件发生时，修饰键
                // 一定处在按下状态。
                store.selectGroup(title, extend: NSEvent.modifierFlags.contains(.command))
            }
        }
        .help(isAll
              ? "显示全部分组"
              : (selected ? "取消选择「\(title)」" : "只看「\(title)」（按住 ⌘ 可多选）"))
    }
}

/// 删除前的**二次确认**（张瑜 2026-10-01 要求，防误删）。
///
/// 按钮按 macOS 惯例排：**「删除」在右、是默认按钮（回车触发）且标红**
/// （`hasDestructiveAction`），**「取消」在左并响应 Esc**。
/// 之所以敢把回车留给「删除」，是因为文案把后果写清楚了 ——
/// 已启用的路由会连带从系统路由表撤销，且需要管理员密码；
/// 换成一句干巴巴的"确定删除吗"，回车确认就退化成走过场了。
///
/// 用 `runModal()`（app 级模态）而不是 sheet：行上的删除按钮拿不到它所属的
/// `NSWindow`，而且模态本身也起到"别在确认期间接着点"的作用。
///
/// - Returns: `true` = 用户确认删除。
@MainActor
private func confirmDeleteRoute(_ route: Route) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "确定要删除「\(route.displayName)」吗？"

    var body = "\(route.destination)  →  \(route.gateway)"
    if let group = route.group, !group.isEmpty {
        body += "\n分组：\(group)"
    }
    if route.enabled {
        body += "\n\n这条路由当前已启用：删除时会同时把它从系统路由表中撤销（需要管理员密码，"
        body += "若在授权框点「取消」则本次删除不会执行）。"
    } else {
        body += "\n\n这条路由当前未启用，只删除列表里的这条配置。"
    }
    alert.informativeText = body

    let deleteButton = alert.addButton(withTitle: "删除")
    deleteButton.hasDestructiveAction = true          // macOS 11+：渲染成红色
    alert.addButton(withTitle: "取消")
    alert.buttons.last?.keyEquivalent = "\u{1b}"      // Esc = 取消

    // 弹在主窗口正中间（`runModal` 默认是屏幕居中，大屏上会飘得老远）
    centerAlertOverMain(alert)

    return alert.runModal() == .alertFirstButtonReturn
}

/// 把 alert 摆到**主窗口正中间**。
///
/// `NSAlert.runModal()` 是 app 级模态对话框，默认居中到**屏幕** —— 主窗口在
/// 屏幕一侧时，弹窗会跑到老远，看着跟主窗口没关系（张瑜 2026-10-01 反馈）。
///
/// 三步，缺一不可：
///   1. **先 `alert.layout()`**：不调的话窗口还是初始的零尺寸，算出来的"中心"是错的；
///   2. 按主窗口 frame 求中心，再 **clamp 进 `screen.visibleFrame`** ——
///      主窗口贴边或比弹窗还小时，中心点可能落到屏幕外；
///   3. `alert.window.setFrameOrigin(...)`。`NSAlert` 自己只在窗口**没被摆过**时
///      才自动居中，摆过就照用。
///
/// 主窗口还没建出来（理论上不会：删除入口就在主窗口上）→ 什么都不做，
/// 退回系统的屏幕居中。
@MainActor
private func centerAlertOverMain(_ alert: NSAlert) {
    guard let parent = WindowManager.shared.primaryWindow,
          parent.isVisible else { return }

    alert.layout()

    let size = alert.window.frame.size
    let m = parent.frame
    var origin = NSPoint(x: m.midX - size.width / 2,
                         y: m.midY - size.height / 2)

    if let screen = parent.screen ?? alert.window.screen {
        let v = screen.visibleFrame
        origin.x = min(max(origin.x, v.minX), max(v.maxX - size.width, v.minX))
        origin.y = min(max(origin.y, v.minY), max(v.maxY - size.height, v.minY))
    }
    alert.window.setFrameOrigin(origin)
}

/// 重命名分组的弹窗：`NSAlert` + 一个输入框，落点与删除确认一致（主窗口正中心）。
///
/// **为什么不用 SwiftUI 的行内编辑**（把标题就地变成 `TextField`）：分组标题是
/// 列表 `LazyVStack` 里的一行，就地编辑要自己管焦点、提交、失焦取消，还得和
/// "整行点击 = 折叠"那个手势抢事件；弹窗这套在本项目已经有现成落点与模态语义
/// （见 `centerAlertOverMain`），代价小得多。
///
/// **空名字不静默吞掉**：`renameGroup` 会返回 `.emptyName`，但那时弹窗已经关了，
/// 用户看到的就是"点了重命名没反应"。所以校验在**关窗之前**做完，直接带错因再弹
/// 一轮；后端那条判断只作兜底（万一别处调用）。
///
/// - Parameters:
///   - prefill: 输入框初值，默认是当前组名
///   - error: 上一轮的错误说明，只给递归调用用
@MainActor
private func presentRenameGroup(_ title: String,
                               store: RouteStore,
                               prefill: String? = nil,
                               error: String? = nil) {
    let count = store.routes.filter {
        RouteGrouping.canonicalTitle($0.group) == title
    }.count

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "重命名分组"

    let info = "「\(title)」下的 \(count) 条路由会一起改到新名字下。"
    var hint = "若新名字与已有的另一个分组相同，两个分组会合并成一组。"
    if let error {
        hint = error + "\n\n" + hint
    }
    alert.informativeText = info + "\n\n" + hint

    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.stringValue = prefill ?? title
    field.placeholderString = "分组名称"
    field.font = .systemFont(ofSize: 13)
    alert.accessoryView = field
    // 焦点直接进输入框：这一步决定了"弹出后能不能立刻打字"
    alert.window.initialFirstResponder = field

    alert.addButton(withTitle: "重命名")           // 回车 = 确认
    alert.addButton(withTitle: "取消")
    alert.buttons.last?.keyEquivalent = "\u{1b}"   // Esc = 取消（中文标题不会被自动识别）

    centerAlertOverMain(alert)

    // 全选初值，省掉"先删掉旧名字"这一步。用 async 是因为要让 alert 先成为 key
    // 窗口；runModal 的模态循环照样会执行主队列上的这个 block。
    DispatchQueue.main.async { field.selectText(nil) }

    guard alert.runModal() == .alertFirstButtonReturn else { return }

    let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !newName.isEmpty else {
        presentRenameGroup(title, store: store, prefill: "", error: "分组名不能为空。")
        return
    }

    switch store.renameGroup(from: title, to: newName) {
    case .renamed:
        break                       // 列表里立刻看得见，不再多弹一个"成功"
    case .unchanged:
        break                       // 名字没变，等于什么都没做
    case let .merged(into: name, count: moved):
        presentGroupMerged(into: name, moved: moved)
    case .emptyName:
        // 兜底：上面已经拦过，真走到这里说明输入在途中被清掉了
        presentRenameGroup(title, store: store, prefill: "", error: "分组名不能为空。")
    case .sourceMissing:
        break                       // 弹窗开着的时候组被改空了，重绘即可
    }
}

/// 合并提示：新名字已经被另一个分组占用时，两个组会并成一个 —— 这一步必须说出来，
/// 否则用户看到的是"分组数莫名其妙少了一个"。
@MainActor
private func presentGroupMerged(into name: String, moved: Int) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "已并入「\(name)」"
    alert.informativeText = "「\(name)」原本就存在，这个分组下的 \(moved) 条路由已经并了进去。"
    alert.addButton(withTitle: "好")
    centerAlertOverMain(alert)
    alert.runModal()
}

/// 删除失败（撤销系统路由时授权没通过）的提示。
///
/// **为什么要有这一步**：用户拒绝授权后删除会被**主动放弃**，列表里那条路由
/// 不会消失（见 `RouteStore.remove`）。不解释的话，用户看到的现象就是
/// "点了删除没反应"，与之前那个"删了却留残影"的 bug 一样无从判断。
@MainActor
private func presentDeleteFailure(_ route: Route) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "未能删除「\(route.displayName)」"
    // 未启用却删不掉的，是系统表里留着上次没撤干净的残影，措辞要区分开
    let state = route.enabled
        ? "这条路由仍在系统路由表中生效。"
        : "系统路由表里还留着这条路由。"
    alert.informativeText = """
        \(state)把它从系统路由表里撤销需要管理员权限，而刚才的授权没有通过（多半是在授权框里点了「取消」）。

        为了避免留下一条「界面里看不见、却又删不掉」的残留路由，这次删除已经放弃，列表里的记录原样保留。

        你可以再点一次删除，并在授权框里输入管理员密码。
        """
    alert.addButton(withTitle: "好")
    centerAlertOverMain(alert)   // 与确认弹窗同一处落点，观感一致
    alert.runModal()
}

// MARK: - 路由行（主窗口列表里使用）

/// 主窗口的一行。视觉规格与快速启动页的行卡保持一致（同样的圆角、内边距、
/// 状态圆点），保证"两个界面一个风格"。
struct RouteRow: View {
    @EnvironmentObject var store: RouteStore
    let route: Route
    /// 仅在「不按分组显示」时用行内小标签补充分组归属
    var showGroupChip: Bool = false

    /// 指针是否悬停在本行上 —— 驱动玻璃底的悬停动画（见 `RBGlassRowBackground`）
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 路由图标，放在**整行最左边**（张瑜 2026-10-01 要求"给每条数据最左边
            // 增加一个 icon"）。没上传过自定义图标的走自绘的默认路由图标；
            // 未启用时去色压暗 —— 与同一行的文字变灰是同一层语义。
            RBRouteIcon(custom: route.icon, size: 22, dimmed: !route.enabled)

            Circle()
                .fill(route.enabled ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(route.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if showGroupChip, let group = route.group, !group.isEmpty {
                        Text(group)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { route.enabled },
                set: { store.setEnabled(id: route.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            // 行内的编辑/删除：与工具栏齿轮同一套 Liquid Glass 圆盘
            // （早期版本为了"列表不吵"去掉了圆底，结果这两个按钮完全没有
            //  macOS 26 / macOS 27 的玻璃观感，被反馈为"丢失了效果"）
            RBToolbarIconButton(help: "编辑") {
                WindowManager.shared.showEditor(route: route)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
            }

            RBToolbarIconButton(help: "删除") {
                deleteRoute(route, store: store)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // 行底：液态玻璃 + 指针悬停动画。原先是 `Color.primary.opacity(0.05)`
        // 纯灰平铺（张瑜 2026-10-01 要求换成玻璃质感，并给悬停加动画）。
        .rbGlassRow(cornerRadius: 8, hovering: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - 路由卡片（主窗口「卡片」形态使用）

/// 卡片形态下的一张路由卡。
///
/// **与 `RouteRow` 承载完全相同的信息与操作**（状态点、名称、目标网段 → 网关、
/// 启用开关、编辑、删除、分组标签），只是把"横向铺开的一行"卷成"竖向的一张卡"：
/// 名称那行让位给开关，按钮落到卡片底部。切形态不丢功能。
///
/// **高度写死**（`cardHeight`）：网格里同一行的卡若各自按内容撑高，有分组标签的
/// 会比没标签的高一截，整片网格就参差不齐。固定高度 + 底部对齐按钮，多张卡才对得上。
struct RouteCard: View {
    @EnvironmentObject var store: RouteStore
    let route: Route
    /// 仅在「不按分组显示」时用卡内小标签补充分组归属（与行形态同一判据）
    var showGroupChip: Bool = false

    /// 统一卡高（pt）。够放下三行内容（名称 / 网段 → 网关 / 按钮行）且不显空。
    private let cardHeight: CGFloat = 104

    /// 指针是否悬停在本卡上 —— 驱动玻璃底的悬停动画（与 `RouteRow` 同一套）
    @State private var hovering = false

    var body: some View {
        // 图标挂在**内容最外层**的左上角（张瑜 2026-10-01 要求"切换卡片时候也显示，
        // 在左上角"），右侧那一整列仍是原来的三行 —— 这样卡片的横向内容只是整体
        // 右移 32pt，行内布局、按钮位置、分组标签都不用动。
        //
        // 用 `.top` 对齐而不是 `.center`：图标与三行内容等高（62pt）时会浮到垂直
        // 中间，看着不像"卡片角上的标识"，倒像它自己排在了第二行。
        HStack(alignment: .top, spacing: 8) {
            RBRouteIcon(custom: route.icon, size: 24, dimmed: !route.enabled)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(route.enabled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)

                Text(route.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    // 名称过长时截中间没意义，截尾部更易辨认（前缀往往就够区分了）

                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { route.enabled },
                    set: { store.setEnabled(id: route.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Text("\(route.destination)  →  \(route.gateway)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // 卡片宽度有限，"192.168.1.15" 这种长网段截尾巴会把关键位截掉，
                // 截中间能保住 IP 的前后半段
                .truncationMode(.middle)

            HStack(spacing: 6) {
                // 与 `RouteRow` 的行内标签同规格（同一套观感，两处不能各画各的）
                if showGroupChip, let group = route.group, !group.isEmpty {
                    Text(group)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.07))
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // 与 `RouteRow` 同一套玻璃圆盘按钮
                RBToolbarIconButton(help: "编辑") {
                    WindowManager.shared.showEditor(route: route)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                }

                RBToolbarIconButton(help: "删除") {
                    deleteRoute(route, store: store)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(height: cardHeight, alignment: .top)
        // 卡底：与 `RouteRow` 同一套玻璃 + 悬停动画（圆角 10 与卡片自身一致）
        .rbGlassRow(cornerRadius: 10, hovering: hovering)
        .onHover { hovering = $0 }
    }
}

/// 删除一条路由的完整流程（行形态与卡片形态共用，**不允许各写一份**）。
///
/// ① 二次确认（破坏性操作，防误删）；
/// ② 撤销系统路由需要授权，用户没授权时 `RouteStore.remove` 返回 `false` 且
///    **不动本地记录** —— 这时必须说清楚，否则看起来就是"点了删除没反应"
///    （与之前那个"删了却留残影"的 bug 一样让人无从判断）。
@MainActor
private func deleteRoute(_ route: Route, store: RouteStore) {
    guard confirmDeleteRoute(route) else { return }
    if !store.remove(route) {
        presentDeleteFailure(route)
    }
}

// MARK: - 手动拖拽重排

/// 给主窗口列表的一行加上「拖动改顺序 / 拖到别的组改动分组」的能力。
///
/// **`enabled == false` 时整个修饰符是空操作** —— 一条手势力都不挂。否则会出现
/// "排序明明是按名称来的，行却还能拖、拖完立刻弹回去"这种自相矛盾的状态
/// （判据见 `RouteListView.listArea`）。
///
/// **落点语义统一为"插到本行之前"**：把第 N 行拖到第 M 行上，N 就落到 M 原来的位置。
/// 只定这一条规则，用户最容易猜准 —— 不去判"落点在行的上半区还是下半区"，
/// 那种规则在 30pt 行高下反而很难命中。
///
/// 跨组拖动 = 改分组，拖回「未分组」= 清空分组，都由 `RouteStore.moveRoute` 一并处理。
struct RBManualReorder: ViewModifier {
    @EnvironmentObject var store: RouteStore

    let route: Route
    /// 落点所属的分组名；`nil` = 当前未按分组显示，拖拽**不改分组**
    let groupTitle: String?
    let enabled: Bool

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if enabled {
            content
                // 插入指示线：落在哪一行，就在那一行的**上沿**画一条
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(isTargeted ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                        .offset(y: -2)
                }
                .draggable(route.id.uuidString) { dragPreview }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first,
                          let id = UUID(uuidString: raw) else { return false }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        store.moveRoute(id, before: route.id, intoGroup: groupTitle)
                    }
                    return true
                } isTargeted: { targeted in
                    isTargeted = targeted
                }
        } else {
            content
        }
    }

    /// 拖动时跟着指针的小预览。不给预览的话系统会截整行当预览，
    /// 行的玻璃底与阴影叠在指针旁边，看起来很糊。
    private var dragPreview: some View {
        Text(route.displayName)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(.regularMaterial)
            )
    }
}

// MARK: - 分组标题落点

/// 给**分组标题**加落点：把行拖到标题上 = 放进这个组（置于组内最前）。
///
/// 行上的落点（`RBManualReorder`）只表达"插到某一行之前"，有两种情况够不着：
///   1. **折叠着的组** —— 组内一行都没渲染，压根没有落点可以递给它；
///   2. **想"放进这个组"而不关心插在第几位** —— 挨个对准第一行没必要。
/// 标题落点一次补齐。目标行取**组内第一行的 id**，所以折叠与否、组内多少行都不影响。
struct RBGroupDropTarget: ViewModifier {
    @EnvironmentObject var store: RouteStore

    let enabled: Bool
    let groupTitle: String
    let firstRouteID: UUID?

    @State private var targeted = false

    func body(content: Content) -> some View {
        if enabled, let firstRouteID {
            content
                // 悬停高亮：整条标题垫一层淡色，告诉用户"松手就是进这一组"
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(targeted ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first,
                          let id = UUID(uuidString: raw) else { return false }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        // 拖的本来就是这个组的第一行时，`moveRoute` 内部会因
                        // `id == targetID` 直接返回 —— 等于没动，符合预期
                        store.moveRoute(id, before: firstRouteID, intoGroup: groupTitle)
                    }
                    return true
                } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

// MARK: - 添加 / 编辑路由窗口

/// 添加 / 编辑表单。
///
/// **同样不画页内标题**：窗口标题栏已经是「添加路由」/「编辑路由」。
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

    /// 本条路由的图标（自定义图标的文件名）。`nil` = 用默认路由图标。
    ///
    /// 只是个**待采用的选择**：真正落进 routes.json 要等 `save()`；
    /// 点「移除」只把它清空，**不删文件** —— 否则用户"移除后又取消"，
    /// 原图标文件已经没了，那条路由的图标就莫名其妙消失了。
    @State private var icon: String?

    /// 本次会话**新写入磁盘**的图标文件名。
    ///
    /// 只服务一件事：用户点了「上传…」又「取消」时，把这次写进去的文件删掉。
    /// 不跟踪的话，每次"选图 → 反悔"都会在 Icons 目录里留一个再没人引用的
    /// 孤儿文件 —— 界面上再也看不到它，也就没法删掉它。
    @State private var uploads: [String] = []

    /// 是否已保存。关窗时的清理要跳过已保存的情况 —— 那些文件正是这条路由要用的。
    @State private var saved = false

    /// 本条路由的 id。新增路由时**在这里**就定下来，而不是等 `save()` 才算：
    /// 图标文件名要用它生成，上传那一刻就得知道。
    ///
    /// 必须是 `@State` 而不是 `let`：这个 struct 会被 SwiftUI 反复重建，
    /// `let` 每次都会算出新的 UUID，同一张图会被写成好几个文件。
    @State private var routeID: UUID

    /// 编辑前该路由已有的图标文件名。保存时若被换掉，由 `RouteStore.saveEdit`
    /// 负责删旧文件（这里不删：取消编辑的话旧文件还得留着）。
    private let originalIcon: String?

    init(route: Route?, onClose: @escaping () -> Void) {
        self.editing = route
        self.onClose = onClose
        self.originalIcon = route?.icon
        _routeID = State(initialValue: route?.id ?? UUID())
        _name = State(initialValue: route?.name ?? "")
        _destination = State(initialValue: route?.destination ?? "")
        _gateway = State(initialValue: route?.gateway ?? "")
        _group = State(initialValue: route?.group ?? "")
        _enabled = State(initialValue: route?.enabled ?? true)
        _icon = State(initialValue: route?.icon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题画在**内容左上角**（参考 macOS 原生表单窗口，如「添加电脑」）：
            // 窗口标题栏不显示文字，标题由页面自己出。
            Text(editing == nil ? "添加路由" : "编辑路由")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 12) {
                // 图标放在**第一行**：它是这条路由的"身份"，紧挨标题最自然。
                // 右边那三个控件里，按钮文案随状态变（上传 / 更换），
                // 所以不用另加说明文字 —— 没上传时按钮自己就写着「上传图标…」。
                formRow("图标:") {
                    iconPicker
                }

                formRow("名称:") {
                    TextField("可选，便于识别", text: $name)
                }

                // 分组：可直接输入新分组，也可从已用过的分组里选
                formRow("分组:") {
                    RBEditableComboBox(text: $group,
                                       placeholder: "可选，可直接输入新的",
                                       options: existingGroups)
                }

                formRow("目标网段:") {
                    TextField("如 172.16.0.0/16 或主机 10.0.0.1", text: $destination)
                }

                formRow("网关:") {
                    TextField("如 192.168.1.15", text: $gateway)
                }

                // 空标签同样占位，让勾选框与上面输入框的左边缘对齐
                formRow("") {
                    Toggle("保存后立即启用", isOn: $enabled)
                }

                if let error {
                    formRow("") {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            // 按钮在**页面底部**（不放标题栏）—— 与 macOS 表单窗口一致。
            HStack(spacing: 10) {
                Spacer()
                Button("取消", role: .cancel) { cancel() }
                Button(editing == nil ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        // 这个窗口是**无边框**的（没有标题栏、没有红绿灯），系统不给圆角、背景和描边，
        // 全部由这里补：
        //   · 纯白底（张瑜 2026-10-01 要求）—— 窗口侧锁了浅色外观（见
        //     `makeHostingWindow` 的 borderless 分支），所以白底上的文字必是深色，
        //     不会出现"白底白字"；
        //   · `clipShape` 连续圆角 —— 窗口本身 `isOpaque = false`，四角才会真的透出去；
        //   · 一圈细描边 —— 让窗口边缘落在任何桌面背景上都交代得清。
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        // 兜底清理：除了「取消」按钮，编辑窗口还可能被**下一次 `showEditor` 直接
        // 关掉**（同一时刻只留一个编辑窗口），那条路径不经过 `cancel()`。
        .onDisappear { discardUnusedUploads() }
    }

    // MARK: - 图标选择

    /// 「图标:」那一行的右侧：预览 + 上传 / 更换 + 移除。
    private var iconPicker: some View {
        HStack(spacing: 10) {
            // 预览的就是**列表里会长成的样子**，用的是同一个 `RBRouteIcon`
            // —— 预览与实况走两套代码的话，"预览好看、列表里不对"迟早发生。
            RBRouteIcon(custom: icon, size: 36)
                .help(icon == nil ? "未上传时使用默认的路由图标" : "当前使用的自定义图标")

            Button(icon == nil ? "上传图标…" : "更换…") { chooseIcon() }

            if icon != nil {
                Button("移除") { clearIcon() }
            }

            Spacer(minLength: 0)
        }
        // 三个控件与上面的输入框同高（32），这一行不会比其他行高出一截
        .frame(height: 32)
    }

    /// 选一张图片作为图标。走 `NSOpenPanel` 而不是 SwiftUI 的 `.fileImporter`：
    /// 本窗口是**无边框** `NSWindow`（没有标题栏、不参与常规窗口层级），
    /// `fileImporter` 依赖的 present 路径在这种窗口上不总是接得住。
    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择一张图片作为这条路由的图标"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let image = NSImage(contentsOf: url) else {
            error = "读不出这张图片，换一张试试"
            return
        }
        guard let stored = RouteIconLibrary.store(image, for: routeID) else {
            error = "图标保存失败，换一张再试"
            return
        }
        error = nil
        uploads.append(stored)
        icon = stored
    }

    /// 移除图标 = 回到默认图标。**只清选择、不删文件**：
    /// 旧文件要等真正保存时由 `RouteStore.saveEdit` 删；本次刚上传的那个则立即删
    /// （它还没被任何路由引用）。
    private func clearIcon() {
        if let current = icon, uploads.contains(current) {
            RouteIconLibrary.discard(current)
            uploads.removeAll { $0 == current }
        }
        icon = nil
    }

    /// 关窗（取消 / 被下一次编辑顶掉）时，清掉本次**写入但没被采用**的图标文件。
    private func discardUnusedUploads() {
        guard !saved else { return }
        for name in uploads { RouteIconLibrary.discard(name) }
        uploads.removeAll()
    }

    /// 一行表单：左标签（右对齐、固定宽度）+ 右控件。
    /// 排布参照 macOS 原生表单窗口（如「添加电脑」）。
    private func formRow<Content: View>(_ label: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 62, alignment: .trailing)
            content()
        }
    }

    /// 已被其它路由使用过的分组名（去重后按中文习惯排序），供下拉候选。
    private var existingGroups: [String] {
        let names = store.routes.compactMap { route -> String? in
            let value = (route.group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func save() {
        let dest = destination.trimmingCharacters(in: .whitespaces)
        let gw = gateway.trimmingCharacters(in: .whitespaces)
        guard !dest.isEmpty else { error = "请填写目标网段 / 主机"; return }
        guard !gw.isEmpty else { error = "请填写网关地址"; return }

        let groupValue = group.trimmingCharacters(in: .whitespaces)

        // id 用 `routeID`（init 时定下的那个）而不是现算一个 —— 上传图标时用的
        // 就是它，两边必须是同一个，否则"新增路由 + 上传图标"会存成一个没人
        // 引用的文件 + 一条用默认图标的路由。
        let newRoute = Route(id: routeID,
                             name: name.trimmingCharacters(in: .whitespaces),
                             destination: dest,
                             gateway: gw,
                             enabled: enabled,
                             note: editing?.note ?? "",
                             group: groupValue.isEmpty ? nil : groupValue,
                             icon: icon)

        if let original = editing {
            // 编辑：撤销旧路由 + 应用新路由，合并为单条命令（只弹一次授权框）
            store.saveEdit(original: original, updated: newRoute)
        } else {
            store.add(newRoute)
            if newRoute.enabled { _ = store.apply(newRoute) }
        }

        // 走完这行，`uploads` 里的文件就归这条路由所有了，关窗时不要再清
        saved = true
        onClose()
    }

    /// 取消：先把本次写入但没被采用的图标文件删掉，再关窗。
    private func cancel() {
        discardUnusedUploads()
        onClose()
    }
}
