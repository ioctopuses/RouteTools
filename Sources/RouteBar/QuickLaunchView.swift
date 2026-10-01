import SwiftUI
import AppKit

/// 快速启动页 —— 点击菜单栏图标（或按 ⌥⌘R）弹出。
///
/// 与主窗口「路由管理」是**两个不同的界面**：
///   · 主窗口：完整的增删改查 + 搜索 + 排序 + 设置入口（重型，可常驻）
///   · 快速启动页：搜索 + 一键开关某条路由（轻量，随手用）
/// 所以这里不提供增删改，只提供"开关"和"跳转"。
///
/// 顶栏规格刻意与主窗口保持一致（也是"所有界面一个风格"的落点）：
///   `[设置齿轮] [⋯ 更多]  ← 弹簧 →  [🔍 搜索框(最右)]`
/// 底部原来那条「打开主窗口… / ⌥⌘R 唤起」已按需求整条删除 ——
/// 「打开主页面」在 ⋯ 菜单里已经有了，快捷键提示属于噪音。
///
/// 窗口宽度与列表高度由**设置页**的滑块决定（`RouteStore` 持久化），
/// 见 `QuickLaunchLimits`。列表高度是**固定值**（不是上限），理由见 `listArea`。
struct QuickLaunchView: View {
    @EnvironmentObject var store: RouteStore

    @State private var query = ""

    /// 「请聚焦搜索框」的信号计数：每收到一次 `.rbFocusQuickSearch` 就 +1，
    /// 转手给 `RBSearchField.focusNonce`。之所以用**计数器**而不是 Bool，是因为
    /// 每次唤起都要重新抢一次焦点 —— Bool 只有第一次从 false 变 true 时才算"变化"，
    /// 第二次唤起就不会再触发了。
    @State private var searchFocusNonce = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // 筛选只作用于**本页**：`quickLaunchGroups` 是快速启动页自己的状态，
            // 与主窗口边栏的 `selectedGroups` 分开存 —— 两个界面各记各的，
            // 在哪儿筛的就只在哪儿生效（理由见 RouteStore 里那段注释）。
            listArea(for: store.groups(query: query,
                                       includedGroups: store.quickLaunchGroups))
        }
        .frame(width: CGFloat(store.quickLaunchWidth))
        // 每次被唤起（菜单栏图标 / ⌥⌘R）都把焦点送回搜索框 ——
        // 信号由 AppDelegate 在 popover `makeKey()` 之后发出，原因见 `focusNonce`。
        .onReceive(NotificationCenter.default.publisher(for: .rbFocusQuickSearch)) { _ in
            searchFocusNonce += 1
        }
    }

    // MARK: - 顶栏

    private var toolbar: some View {
        HStack(spacing: 10) {
            // 筛选 + ⋯ 更多合并为**一个**玻璃胶囊组，与主窗口的 [排序 | 设置] 同构：
            // 组内用竖直细线分隔，组与右侧搜索框之间留 10pt。
            //
            // 左格原先是「设置」，2026-10-01 按张瑜要求撤掉 —— 快速启动页是
            // "点一下就应用"的轻量面板，设置属于重决策，回主窗口再进
            // （主窗口工具栏那枚齿轮仍在，入口没丢）。腾出来的格子给了**分组筛选**。
            HStack(spacing: 0) {
                groupFilterMenu

                RBGlassGroupDivider()

                moreMenu
            }
            .rbGlassGroup()

            Spacer(minLength: 8)

            RBSearchField(placeholder: "搜索路由",
                          text: $query,
                          autoFocus: true,
                          focusNonce: searchFocusNonce,
                          maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }

    /// 分组筛选菜单：顶栏玻璃胶囊组的**左格**，与右格（⋯ 更多）共享同一个胶囊底，
    /// 故用 `RBGlassGroupMenuButton`（不自带圆盘底）。
    ///
    /// 语义与主窗口边栏的「所有分组 / 各分组」一致，但**状态是独立的**
    /// （`store.quickLaunchGroups`，见其注释）：两边各记各的筛选，互不影响。
    ///
    /// **每一项都用 `Toggle`**（菜单里渲染成带勾选项），包括首项「所有分组」——
    /// 只有这样，"当前是所有分组"才有视觉载体：默认状态下所有具体分组都不带勾，
    /// 如果「所有分组」也不带勾，整张菜单看着像"什么都没选"，与"正在看全部"
    /// 是两回事（张瑜要的就是"默认选择是所有分组"）。
    ///
    /// 首项的 `set` 只认"勾上"：空集本身就代表所有分组，把它取消勾选没有对应的
    /// 中间状态（那会变成"一组都不选"＝什么都没筛，与所有分组等价）。
    /// 于是点它 = 清空筛选，且勾会留在原处 —— 这正是想要的结果。
    private var groupFilterMenu: some View {
        // 取数必须走 `allGroups()`（**不受筛选影响**的全部分组），不能走带
        // `includedGroups` 的那个口 —— 否则勾掉几组之后，那些组会从菜单里自己消失，
        // 就再也勾不回来了（与主窗口边栏是同一个坑）。
        let groups = store.allGroups()
        let active = !store.quickLaunchGroups.isEmpty
        return RBGlassGroupMenuButton(
            help: active ? "按分组筛选（已选 \(store.quickLaunchGroups.count) 组）"
                         : "按分组筛选"
        ) {
            Toggle("所有分组", isOn: Binding(
                get: { store.quickLaunchGroups.isEmpty },
                set: { on in
                    // 只处理"勾上"（见上面注释：取消勾选没有对应的中间状态）
                    if on { store.quickLaunchGroups = [] }
                }
            ))

            if !groups.isEmpty {
                Divider()
                ForEach(groups) { group in
                    Toggle(group.title, isOn: Binding(
                        get: { store.quickLaunchGroups.contains(group.title) },
                        set: { on in store.setQuickLaunchGroup(group.title, on: on) }
                    ))
                }
            }
        } label: {
            // 筛选生效时图标走强调色 —— 这是"当前这一屏不是全部路由"的唯一可见信号。
            // 少了它，用户会以为路由丢了。
            FilterIcon(size: 15, active: active)
        }
    }

    /// ⋯ 菜单：顶栏玻璃胶囊组的**右格**，与左格（筛选）共享同一个胶囊底，
    /// 故用 `RBGlassGroupMenuButton`（不自带圆盘底）。
    private var moreMenu: some View {
        RBGlassGroupMenuButton(help: "更多") {
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
            MoreIcon(size: 15)
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    // 搜索时强制展开：否则命中的路由藏在折叠的组里，看着像"搜不到"。
                    // 折叠状态与主窗口**共用** `store.collapsedGroups`，两处必须一致。
                    let forceExpand = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ForEach(groups) { group in
                        let folded = showHeaders && !forceExpand && store.isCollapsed(group.title)
                        if showHeaders {
                            RBGroupHeader(title: group.title,
                                          count: group.routes.count,
                                          compact: true,
                                          collapsible: true,
                                          collapsed: folded,
                                          onToggle: {
                                              withAnimation(.easeInOut(duration: 0.16)) {
                                                  store.toggleCollapse(group.title)
                                              }
                                          })
                        }
                        if !folded {
                            ForEach(group.routes) { route in
                                RouteQuickRow(route: route)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            // 列表区高度**就是**设置页那个值（张瑜 2026-10-02：「设置了好像不能变」）。
            //
            // 这里原来是 `.frame(maxHeight:)` —— 那只是**上限**：路由少时列表贴合内容，
            // 上限根本不参与计算。实测 4 条路由时内容自然高度 ≈ 271pt，于是把滑块从
            // 默认的 420 拉到 720 全程看不出任何变化（面板高度一动不动），
            // 被当成"这个设置项坏了"。改成固定 `height:` 之后，拖动滑块立刻能
            // 看到面板变高 / 变矮；内容超出才滚动。代价是路由少时下方有留白 ——
            // 这是明确的取舍，留白区不画任何内容，就是面板底色。
            .frame(height: CGFloat(store.quickLaunchListHeight))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
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

    /// 列表被筛空时的提示。
    ///
    /// 两种空法必须分开说：**搜索没命中** 与 **选中的分组里没有路由**。
    /// 不分开的话，没搜索却被筛空时会显示「没有匹配「」的路由」—— 一对空引号，
    /// 看着像坏了。
    ///
    /// 后一种情况还多给一个「显示所有分组」的出口：筛选状态是持久化的，
    /// 用户下次唤起面板时很可能已经忘了自己筛过 —— 面板里得有路可退。
    private var noMatchState: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 8) {
            Text(q.isEmpty ? "选中的分组里没有路由" : "没有匹配「\(q)」的路由")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if q.isEmpty {
                Button("显示所有分组") { store.quickLaunchGroups = [] }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func closePopover() {
        NotificationCenter.default.post(name: .rbClosePopover, object: nil)
    }
}

// MARK: - 快速启动页的一行

private struct RouteQuickRow: View {
    @EnvironmentObject var store: RouteStore
    let route: Route

    /// 指针是否悬停在本行上 —— 与主窗口的行 / 卡同一套玻璃底悬停动画
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            // 与主窗口的行**同一枚图标、同一个尺寸**（22）—— 两个界面一个风格是
            // 本项目的既有约定，图标这里也不能例外，否则同一路由在两处长得不一样。
            RBRouteIcon(custom: route.icon, size: 22, dimmed: !route.enabled)

            Circle()
                .fill(route.enabled ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(route.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
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
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // 与主窗口的行 / 卡同一套玻璃底 + 悬停动画（圆角 8 保持一致）：
        // 快速启动页原有 `Color.primary.opacity(0.05)` 纯灰平铺，一并换掉
        .rbGlassRow(cornerRadius: 8, hovering: hovering)
        .onHover { hovering = $0 }
    }
}
