import SwiftUI
import AppKit

// MARK: - 统一视觉风格（RouteBar Design System）
//
// 三个界面（主窗口 / 快速启动 / 设置）共用这里的组件，避免各画各的：
//   · RBGlassDisc        —— Liquid Glass 圆盘底（齿轮 / 排序 / ☰ / 编辑 / 删除 全用它）
//   · RBToolbarIconButton—— 工具栏圆形图标按钮（Button 版）
//   · RBToolbarMenuButton—— 工具栏圆形菜单按钮（Menu 版）
//   · RBGlassGroupButton / RBGlassGroupMenuButton / RBGlassGroupDivider
//                        —— 工具栏「分组胶囊」：几个图标**共享一个**胶囊底，
//                           组内用竖直细线分隔（系统工具栏 `[ⓧ ⓘ]` 的做法）
//   · RBSearchField      —— 统一样式的搜索框（放大镜在最左，置于栏位最右）
//
// **为什么自绘圆盘而不是交给 `.buttonStyle(.glass)`**：见 `RBGlassDisc` 的注释
// —— Menu 拿不到 `.buttonStyle(.glass)`，两者尺寸也不一致。

// MARK: - 规格常量

/// 工具栏/行内圆形玻璃按钮的统一规格。
///
/// **只允许从这里取尺寸**：齿轮、排序、☰、编辑、删除全部同一直径，
/// 这样"排序按钮弄成跟设置图标一样大小"不会再随平台版本漂移。
enum RBGlassMetrics {
    /// 玻璃圆盘直径（pt）。实测当前系统的 `.buttonStyle(.glass)` 会在 26pt
    /// label 外再加约 3.5pt 内边距（圆盘实际 33pt），这里取 28 作为统一值：
    /// 与工具栏搜索框同高、放进列表行也不会把行撑高。
    static let disc: CGFloat = 28

    /// **弹窗顶栏**分组胶囊 / 搜索框的高度（pt）。
    ///
    /// 取 30 而不是 `disc` 的 28：给组内图标上下留一点余量，胶囊边缘不会贴住笔画。
    ///
    /// ⚠️ **别把它当成"主窗口工具栏里图标按钮的大小"**：2026-10-01 用 AX 实测，
    /// 主窗口工具栏上的系统图标按钮（添加路由 / 排序 / 设置）**一律 36 × 36**，
    /// 见下面的 `toolbarIconButton`。本值只服务于快速启动弹窗顶栏那一组胶囊与搜索框。
    static let groupHeight: CGFloat = 30

    /// 主窗口工具栏里**系统图标按钮**的实测边长（pt）。
    ///
    /// 2026-10-01 张瑜反馈"改完后的胶囊跟其他图标不一样大"时用 AX 量的真值：
    /// 添加路由 / 排序 / 设置 **一律 36 × 36**（`AXToolbar` 高 52，按钮上下各留 8）。
    /// 自绘控件想让"图标对图标"看着一样大，就得贴这个数 —— 先前按观感估出来的 30
    /// 小了整整 6pt，与相邻按钮并排一眼就能看出来。
    static let toolbarIconButton: CGFloat = 36

    /// 分组胶囊里**单个图标格子**的宽度（pt）。
    ///
    /// 格子做成略扁的 34 × 30，使组内相邻图标的中心距 ≈ 34pt ——
    /// 这正是系统工具栏 `[ⓧ ⓘ]` 两格组的比例。取 28 会挤得像一个按钮，
    /// 取 40 又会松垮成两个按钮。
    static let groupItemWidth: CGFloat = 34

    /// **分段控件**里单格的宽度（pt）：`40 × 36`，比高度（36）略宽。
    ///
    /// 两格合计 80pt，与相邻 36pt 的方形图标按钮比例相称；
    /// 沿用 `groupItemWidth` 的 34 会让整个胶囊显得比旁边的按钮瘦一圈。
    static let segmentedItemWidth: CGFloat = 40
}

// MARK: - 玻璃圆盘（唯一配方）

/// Liquid Glass 圆形底 —— **Button 与 Menu 共用的唯一绘制代码**。
///
/// **实测结论（2026-10-01，macOS 27 / Swift 6.4）**：
/// 1. `Menu` 不会把 `.buttonStyle(.glass)` 传进它内部那个按钮。
///    `Menu {...}.menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.circle)`
///    画出来的是**纯灰平涂圆**（水平剖面上圆内亮度恒为 236、无边缘高光、
///    无背景模糊），也就是用户说的「菜单图标和排序图标都没有 macOS 27 的效果」。
///    `.buttonStyle(.plain)` 也救不了；`GlassEffectContainer` 也一样。
/// 2. `Button` 走 `.buttonStyle(.glass)` 时，系统会在 label 外**额外加内边距**，
///    26pt label 画成约 33pt 圆盘 —— 和 Menu 的 34pt 又不一致。
///
/// 所以两者都不能依赖 `.buttonStyle(.glass)`。改为把玻璃画在 **label 内部**，
/// 由本 modifier 统一负责：Button 与 Menu 走同一段代码，像素级一致。
///
/// 剖面实测（自绘版）：左缘 243（高光）→ 内部 249 → 右缘 203（暗边），
/// 即真正的 Liquid Glass 非对称边缘 + 背景采样，与系统按钮观感相同。
///
/// **2026-10-01 补：光靠 `.glassEffect` 在列表行内会"隐形"。**
/// 液态玻璃的本质是**折射身后的内容**，背景越有层次它越明显：
///   · 工具栏那一行，背后是窗口标题栏的 vibrancy（能透出桌面）→ 玻璃一眼可见；
///   · 列表行，背后是 `Color.primary.opacity(0.05)` 这种**纯色平铺** → 玻璃折射到的
///     还是同一块纯色，渲染出来与"压根没画"没有区别 —— 这就是张瑜反馈的
///     「编辑和删除按钮没有液态玻璃效果」。
/// 因此这里在玻璃**底下**垫一层极淡填充、在**边缘**补一圈方向性高光
/// （左上亮 → 右下暗，与真实玻璃的光照方向一致），让圆盘在任何背景上都立得住。
/// 这不是"放弃玻璃"：`glassEffect` 那一层还在，只是给它一个可见的轮廓。
struct RBGlassDisc: ViewModifier {
    /// 圆盘直径；默认取全应用统一值
    var diameter: CGFloat = RBGlassMetrics.disc

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                // ① 玻璃**底下**垫一层极淡填充：给圆盘一个不会消失的轮廓
                .background(Circle().fill(Color.primary.opacity(0.055)))
                // ② 液态玻璃本体
                .glassEffect(.regular.interactive(), in: .circle)
                // ③ 边缘的方向性高光（左上亮 → 右下暗，与真实光照同向）：
                //    纯色背景上玻璃折射不出东西时，靠这一圈"读出"它是块玻璃
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55),
                                     Color.white.opacity(0.08),
                                     Color.black.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 0.8)
                )
        } else {
            content
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }
}

extension View {
    /// 给任意图标套上统一的圆形玻璃底（**画在 label 内部**，Button / Menu 通用）
    func rbGlassDisc(diameter: CGFloat = RBGlassMetrics.disc) -> some View {
        modifier(RBGlassDisc(diameter: diameter))
    }
}

// MARK: - 通用玻璃底（非圆形，搜索框用）

/// 胶囊/任意形状底：macOS 26+ 用 Liquid Glass，更早系统回退「极浅填充 + 细描边」。
struct RBGlassBackground<S: Shape>: ViewModifier {
    let shape: S
    /// 旧系统回退时是否画描边（搜索框这类输入控件要）
    var stroke: Bool = true
    /// 是否让玻璃跟随指针。
    ///
    /// 单个按钮 / 输入框取 `true`（指针悬停时整块微微提亮）；
    /// **分组容器必须取 `false`** —— 组内每个按钮自己会亮，
    /// 容器再亮一层会盖住组内反馈，整块胶囊变成"一个巨大的按钮"。
    var interactive: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(shape.fill(Color.primary.opacity(0.06)))
                .overlay(
                    shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// 给任意形状套上统一的「玻璃 / 描边」底
    func rbGlassBackground<S: Shape>(_ shape: S,
                                     stroke: Bool = true,
                                     interactive: Bool = true) -> some View {
        modifier(RBGlassBackground(shape: shape, stroke: stroke, interactive: interactive))
    }
}

// MARK: - 列表行 / 卡片的玻璃底（带悬停动画）

/// 列表**行**与**卡片**共用的液态玻璃底，并负责「指针移上去」的动画。
///
/// **为什么不直接 `.glassEffect` 了事**：见 `RBGlassDisc` 上方那段说明 ——
/// 液态玻璃折射的是**身后的内容**，而列表区背后是一片纯色平铺，折射到的还是同一
/// 块纯色：面积越小越容易"看着像没画"，面积越大越只剩一层灰。所以这里与圆盘同一
/// 套路，三层叠起来：
///   ① 玻璃**底下**垫一层极淡填充 —— 给整行一个不会消失的轮廓；
///   ② `glassEffect` 本体（`.interactive()`，指针悬停时玻璃自身也会响应）；
///   ③ 边缘一圈**方向性高光**（左上亮 → 右下暗，与真实光照同向）——
///      纯色背景上就靠这一圈"读出"它是块玻璃。
///
/// **2026-10-01 张瑜要求**：原先行 / 卡的底是 `Color.primary.opacity(0.05)`
/// 纯灰平铺，改成液态玻璃质感，并且「光标移动到这条数据上时要有动画」。
///
/// **悬停动画**（同一要求）三件事，同一个 `easeOut 0.16s`，进出对称：
///   · 轻微放大 `1.006` —— 约 1px 量级，不会和相邻行打架；
///   · 浮起一层柔和阴影，让这一行"离屏幕近了一点"；
///   · 描边高光提亮，线宽 `0.8 → 1.0`。
///
/// **动画只挂在 `hovering` 这一个 `value` 上**：SwiftUI 只对这一个状态做插值，
/// 列表数据变化时不会把动画重放一遍。
struct RBGlassRowBackground: ViewModifier {
    /// 行用 8、卡片用 10，与各自原有的圆角一致
    var cornerRadius: CGFloat
    /// 指针是否悬停在本行上（由调用方的 `.onHover` 驱动）
    var hovering: Bool

    func body(content: Content) -> some View {
        glassed(content)
            .scaleEffect(hovering ? 1.006 : 1)
            .shadow(color: .black.opacity(hovering ? 0.16 : 0),
                    radius: hovering ? 7 : 0,
                    y: hovering ? 2 : 0)
            .animation(.easeOut(duration: 0.16), value: hovering)
    }

    @ViewBuilder
    private func glassed(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                // ① 垫层：不依赖背景层次，自己给出一个轮廓
                .background(shape.fill(Color.primary.opacity(hovering ? 0.075 : 0.05)))
                // ② 液态玻璃本体
                .glassEffect(.regular.interactive(), in: shape)
                // ③ 方向性高光
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(hovering ? 0.75 : 0.45),
                                     Color.white.opacity(0.06),
                                     Color.black.opacity(hovering ? 0.18 : 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: hovering ? 1 : 0.8)
                )
        } else {
            content
                .background(shape.fill(Color.primary.opacity(hovering ? 0.09 : 0.06)))
                .overlay(
                    shape.stroke(Color.primary.opacity(hovering ? 0.2 : 0.12), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// 给列表行 / 卡片套上统一的行玻璃底 + 悬停动画
    func rbGlassRow(cornerRadius: CGFloat, hovering: Bool) -> some View {
        modifier(RBGlassRowBackground(cornerRadius: cornerRadius, hovering: hovering))
    }
}

// MARK: - 强调按钮

/// 主操作按钮（「添加路由」）。macOS 26+ 用玻璃强调色，旧系统回退蓝底。
struct RBProminentButton: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    /// 主操作按钮样式（跨系统版本统一入口）
    func rbProminentButton() -> some View {
        modifier(RBProminentButton())
    }
}

// MARK: - 工具栏图标按钮

/// 工具栏/列表行上的圆形图标按钮（齿轮、行内编辑、删除）。
///
/// 外观全部由 `rbGlassDisc()` 提供 —— 与 `RBToolbarMenuButton` 同规格，
/// 因此齿轮、排序、☰、编辑、删除五个按钮并排时圆盘大小与材质完全一致。
struct RBToolbarIconButton<Label: View>: View {
    let help: String
    let action: () -> Void
    let label: Label

    init(help: String,
         action: @escaping () -> Void,
         @ViewBuilder label: () -> Label) {
        self.help = help
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label.rbGlassDisc()
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
    }
}

// MARK: - 工具栏菜单按钮

/// 工具栏上的圆形「菜单」按钮（排序 / ☰ 更多）。
///
/// **必踩的坑**：`.menuStyle(.borderlessButton)` 画不出自定义 SwiftUI label
/// （实测变体全空，用户原话「三个横线的菜单图标也没有了」）。
/// 必须用 `.menuStyle(.button)`，再配 `.buttonStyle(.plain)` 把系统那层
/// 平涂灰底关掉，label 内的 `rbGlassDisc()` 才露得出来。
///
/// 图标本身的墨色问题见 `MoreIcon` 的注释（动态语义色在 popover 里会被
/// vibrancy 变成半透明，必须用显式的黑/白）。
struct RBToolbarMenuButton<Label: View, Content: View>: View {
    let help: String
    let label: Label
    let content: Content

    init(help: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder label: () -> Label) {
        self.help = help
        self.content = content()
        self.label = label()
    }

    var body: some View {
        Menu {
            content
        } label: {
            label.rbGlassDisc()
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
    }
}

// MARK: - 工具栏分组胶囊（macOS 26/27 原生工具栏语汇）

/// 分组胶囊里的**一个图标格子**。
///
/// 与 `RBToolbarIconButton` 的分工：
/// · `RBToolbarIconButton`：**自带**玻璃圆盘，适合单独出现（列表行内、单按钮入栏）
/// · `RBGlassGroupButton`：**不带底**，玻璃由外层 `rbGlassGroup()` 统一画，
///   于是一组按钮共享同一个胶囊，组内靠竖直细线分隔
///
/// 为什么需要分组：一行里并排 4~5 个各自独立的圆盘时，它们尺寸相近、间距也相近，
/// 视觉上会"糊成一条"，看不出主次。系统 App 的做法是把功能相邻的按钮塞进
/// **同一个胶囊**（活动监视器的 `[ⓧ ⓘ]`），一行因此被切成边界清晰的几块。
struct RBGlassGroupButton<Label: View>: View {
    let help: String
    let action: () -> Void
    let label: Label

    init(help: String,
         action: @escaping () -> Void,
         @ViewBuilder label: () -> Label) {
        self.help = help
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(width: RBGlassMetrics.groupItemWidth,
                       height: RBGlassMetrics.groupHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
    }
}

/// 同 `RBGlassGroupButton`，但用于 `Menu`（排序 / ⋯ 更多）。
///
/// 两个必踩的坑（`.menuStyle(.borderlessButton)` 画不出自定义 label、
/// `.buttonStyle(.glass)` 会被系统加上额外内边距）见 `RBToolbarMenuButton` 的注释，
/// 这里同样必须 `.menuStyle(.button)` + `.buttonStyle(.plain)`。
struct RBGlassGroupMenuButton<Label: View, Content: View>: View {
    let help: String
    let label: Label
    let content: Content

    init(help: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder label: () -> Label) {
        self.help = help
        self.content = content()
        self.label = label()
    }

    var body: some View {
        Menu {
            content
        } label: {
            label
                .frame(width: RBGlassMetrics.groupItemWidth,
                       height: RBGlassMetrics.groupHeight)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
    }
}

/// 分组胶囊里两格之间的竖直细线。
///
/// 高度只取 14pt（不到胶囊的一半）—— 系统工具栏的分隔线是"点到为止"的，
/// 通高画满会把一个胶囊又切回成两个独立按钮。
struct RBGlassGroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 14)
    }
}

extension View {
    /// 把一排图标按钮（之间用 `RBGlassGroupDivider()` 分隔）包成**一个**玻璃胶囊。
    ///
    /// `interactive: false`：整块胶囊不跟随指针，指针反馈留给组内每个格子，
    /// 否则悬停时整条胶囊一起亮，反而看不出点的是哪一个。
    func rbGlassGroup() -> some View {
        self
            .frame(height: RBGlassMetrics.groupHeight)
            .rbGlassBackground(Capsule(), interactive: false)
    }
}

// MARK: - 工具栏分段切换（互斥选择，共用一个胶囊）

/// 分段控件里的一格。放在文件作用域而不是嵌套进 `RBGlassSegmented` ——
/// 调用方 `map` 出数组时不必写出完整的泛型嵌套名（`RBGlassSegmented<X>.Segment`）。
struct RBSegment<Value: Hashable>: Identifiable {
    let value: Value
    /// SF Symbol 名
    let icon: String
    /// 悬停提示
    let help: String

    var id: Value { value }
}

/// 工具栏「分段切换」：一组图标**共用同一个胶囊底**，其中**当前选中**的那一格
/// 带一块内嵌的浅色药丸底 —— 张瑜 2026-10-01 给的参考图就是这个形态。
///
/// **与 `rbGlassGroup()` 的区别（这决定了该用哪一个）**：
///   · `rbGlassGroup()` = 几个**动作**按钮挤进一个底，格与格之间画**竖直细线**；
///     每个格子都是"按一下发生一件事"，彼此没有状态关系。
///   · 本控件 = **互斥选择**（选了一个就取消另一个），所以用**选中药丸**而不是
///     分隔线来表达"当前是哪一个"。反过来若给分段控件画分隔线，会被读成
///     两个独立按钮，"当前处于哪一档"就没有视觉载体了。
///
/// 选中药丸走 `matchedGeometryEffect`，在格与格之间**滑动**——这就是系统分段
/// 控件切换时那个位移感的来源；两个格子各自的淡入淡出会显得很生硬。
///
/// 尺寸**必须与相邻的系统图标按钮一致**：图标 15pt、单格 `40 × 36`（高度取
/// `RBGlassMetrics.toolbarIconButton` 的实测值）。张瑜 2026-10-01 一眼看出"胶囊跟
/// 其他图标不一样大"，就是因为先前那版按观感取了 30pt 高 + 13pt 图标，比旁边系统
/// 按钮整整小一号 —— 这类"自绘控件紧挨系统控件"的场合，尺寸只能量、不能估。
/// 选中与否只用**墨色**（`.primary` / `.secondary`）区分，字号字重两边完全一致
/// （否则切换时图标会跳大小）。
struct RBGlassSegmented<Value: Hashable>: View {
    let segments: [RBSegment<Value>]
    @Binding var selection: Value

    /// 只服务于选中药丸的滑动，与外部动画无关
    @Namespace private var pill
    /// 当前被指针悬停的格子（未选中格才用它做淡反馈）
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { seg in
                let isSelected = seg.value == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.easeInOut(duration: 0.18)) { selection = seg.value }
                } label: {
                    Image(systemName: seg.icon)
                        .font(.system(size: 15, weight: .medium))
                        // 三元两侧类型不同（层级色 vs 具体色），用 `AnyShapeStyle` 包一层
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                    : AnyShapeStyle(.secondary))
                        .frame(width: RBGlassMetrics.segmentedItemWidth,
                               height: RBGlassMetrics.toolbarIconButton)
                        .contentShape(Rectangle())
                        .background {
                            // 内层药丸用 **`Capsule()`（圆角 = 高度/2）**，不用圆角矩形。
                            //
                            // 张瑜 2026-10-01：「按钮鼠标放上去的阴影圆角不对，太方了，
                            // 可以参考下新增按钮的效果」。对照的是工具栏上系统画的
                            // 「添加路由」按钮 —— macOS 26 的玻璃控件是**胶囊/圆形语汇**
                            // （搜索框也是 `Capsule`），内层摆一个圆角矩形（原先是 radius 9）
                            // 在一排胶囊里就显得方。改成与容器同一形状族后，
                            // 「胶囊里套胶囊」＝系统分段控件的样子。
                            //
                            // `.padding(2)` 让药丸与胶囊内缘留出 2pt —— 参考图里那块
                            // 底色不是贴边的，浮在胶囊中才有"被按进去"的层次。
                            //
                            // 悬停态与选中态**必须是同一个形状**，否则鼠标移上去的一瞬间
                            // 会出现"方的变圆的"跳变。
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.12))
                                    .padding(2)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            } else if hovered == seg.value {
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                                    .padding(2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hovered = seg.value }
                    else if hovered == seg.value { hovered = nil }
                }
                .help(seg.help)
            }
        }
        .frame(height: RBGlassMetrics.toolbarIconButton)
        // 整块胶囊不跟随指针（同 `rbGlassGroup()`）：反馈留给每一格，
        // 否则悬停时整条一起亮，看不出鼠标压在哪个图标上。
        .rbGlassBackground(Capsule(), interactive: false)
        .fixedSize()
    }
}

// MARK: - 可编辑下拉框

/// 可编辑下拉框：既能从**已有项**里挑，也能直接**输入新值**。
///
/// SwiftUI 没有等价控件 —— `Picker` 只能选不能输入，`TextField` 没有候选，
/// `.searchable` 是搜索语义。所以桥接 AppKit 的 `NSComboBox`：
/// 这就是 macOS 上"可选可输"的标准控件（系统「网络」设置里加服务、
/// 「钥匙串」里选账户用的都是它）。
///
/// `completes = true` 让输入前缀时自动补全已有分组，减少手打错别字导致
/// 出现「公司」和「公司 」两个分组的情况。
struct RBEditableComboBox: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    /// 候选值（已有分组）
    var options: [String] = []

    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.isEditable = true
        combo.usesDataSource = false      // 用 addItems 直接喂值，无需数据源
        combo.completes = true
        combo.numberOfVisibleItems = 8
        combo.font = .systemFont(ofSize: 13)
        combo.controlSize = .regular
        combo.placeholderString = placeholder
        combo.delegate = context.coordinator
        combo.target = context.coordinator
        combo.action = #selector(Coordinator.editingChanged(_:))
        return combo
    }

    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.parent = self

        if combo.stringValue != text {
            combo.stringValue = text
        }

        // 只在真正变化时重建候选，否则每次刷新都会把下拉列表收起来
        let current = (combo.objectValues as? [String]) ?? []
        if current != options {
            combo.removeAllItems()
            combo.addItems(withObjectValues: options)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: RBEditableComboBox

        init(_ parent: RBEditableComboBox) { self.parent = parent }

        /// **每敲一个字**就把内容回写绑定 —— 这是"新分组存不进去"的根因所在。
        ///
        /// `NSComboBox` 继承 `NSTextField`，它的 `action` 只在**回车 / 选中候选**时
        /// 触发，**不是每次输入都发**。用户输入一个新分组名后直接点「添加」按钮时，
        /// 那段文字还留在 field editor 里没提交到绑定，`RouteEditView.save()`
        /// 读到的 `group` 仍是空串 —— 表现就是"分组增加不了"（实测：新路由写进
        /// `routes.json` 后 group 字段为空）。改为监听 `controlTextDidChange`，
        /// 输入即同步，点按钮时绑定里已经是最新值。
        func controlTextDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox else { return }
            parent.text = combo.stringValue
        }

        /// 回车提交（保留为双保险：回车结束编辑时再同步一次）
        @objc func editingChanged(_ sender: NSComboBox) {
            parent.text = sender.stringValue
        }

        /// 从下拉列表里选中某一项
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox else { return }
            parent.text = combo.stringValue
        }
    }
}

// MARK: - 搜索框

/// 统一样式的搜索框：放大镜在框内最左，带一键清除。
///
/// 两个界面都把它放在顶栏最右（「搜索都在右上角，图标在搜索左面」），
/// 图标按钮排在它左边，顺序固定：`[图标…] [搜索框]`。
/// 高度取 `RBGlassMetrics.disc`，与同排的圆形图标按钮**等高**（对齐基线）。
struct RBSearchField: View {
    var placeholder: String = "搜索"
    @Binding var text: String
    /// 出现时是否自动聚焦（快速启动页要，主窗口不要）
    var autoFocus: Bool = false
    /// 外部「把焦点交给搜索框」的信号：**值每变一次就抢一次焦点**。
    ///
    /// 快速启动页每次被唤起都会 +1。为什么光有 `autoFocus` 不够：
    ///   · `onAppear` 只在视图首次出现时触发，而 popover 是**复用同一个 window**
    ///     的，第二次唤起不保证再走一遍；
    ///   · 更要命的是**时机** —— `onAppear` 跑在 popover 的 `makeKey()` **之前**，
    ///     而 `makeKey` 会把 firstResponder 重置回窗口默认值，刚设上的焦点当场被
    ///     抢走（"唤起快速启动页时光标不在搜索框"就是这么来的）。
    /// 由 AppDelegate 在 `makeKey()` **之后**发信号，再等一个 runloop 设焦点，才抢得住。
    var focusNonce: Int = 0
    /// 宽度上限；nil = 随父容器自适应
    var maxWidth: CGFloat? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            // TextField 自己吃掉多余空间 —— 若把 maxWidth 加在最外层，
            // 只是把整个 HStack 撑开并居中，输入区不会变宽（视觉上仍然很短）。
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
        .padding(.horizontal, 9)
        // 高度取工具栏分组胶囊的同一值：搜索框与它左边的 `[⇅|⚙]` 组同排，
        // 差 1~2pt 就会出现肉眼可见的基线错位（`disc` 的 28 只留给列表行内）。
        .frame(height: RBGlassMetrics.groupHeight)
        // 先按调用方给的宽度定形
        .frame(maxWidth: maxWidth)
        // 液态玻璃底（与同排的圆形按钮胶囊同一套语汇）：
        //   · 形状是标准的胶囊（`Capsule()`，圆弧 = 高度/2），跟系统搜索字段
        //     一致 —— 参考用户给的截图就是这个形态，不是圆角矩形；
        //   · "被一个胶囊套住"是工具栏系统给任务再加一层共享背景造成的，**与这个
        //     搜索字段本身的胶囊形状是两件事**：本字段就要胶囊（这是搜索字段
        //     应有的样子），主窗口那边在工具栏层挂掉系统的外层共享胶囊即可。
        //   · 液态玻璃由 `rbGlassBackground` 提供（macOS 26+ 走 `glassEffect`，
        //     旧系统走低透明度填色 + 描边的回退），与全 App 圆盘胶囊同款。
        .rbGlassBackground(Capsule())
        .onAppear {
            guard autoFocus else { return }
            grabFocus()
        }
        // 外部信号（快速启动页每次被唤起）：见 `focusNonce` 的说明
        .onChange(of: focusNonce) { _ in
            guard autoFocus else { return }
            grabFocus()
        }
    }

    /// 把键盘焦点交给输入框。
    ///
    /// 必须 `async` 到下一个 runloop：调用点（`onAppear` / popover 刚 show 完）视图
    /// 往往还没挂进 window，当场设 `focused = true` 会被随后的 `makeKey()` 覆盖掉。
    private func grabFocus() {
        DispatchQueue.main.async { focused = true }
    }
}

// MARK: - 分组标题

/// 分组小标题。主窗口与快速启动页共用，保证"怎么区分分组"两处观感一致。
///
/// **可折叠**：`collapsible` 打开时标题前出现一枚三角（展开朝下、折叠朝右，
/// 与访达侧边栏同一套方向语义），整行都是点击热区，`onToggle` 由调用方接。
/// 关掉 `collapsible`（或根本不传）时就是一枚纯标题 —— 留给"只有一组、
/// 折叠没有意义"的场景。
struct RBGroupHeader: View {
    let title: String
    let count: Int
    /// 紧凑模式（快速启动页）：字号更小、上间距更小
    var compact: Bool = false
    /// 是否可折叠（false = 纯标题，不画三角、不可点）
    var collapsible: Bool = false
    /// 当前是否已折叠
    var collapsed: Bool = false
    /// 点击折叠 / 展开
    var onToggle: (() -> Void)?
    /// 重命名这个分组。`nil` = 不提供改名入口 —— 快速启动页就不提供（那是
    /// "点一下就应用路由"的启动器，不放编辑动作），「未分组」也不提供
    /// （那是"没填分组"的收容所，不是用户建出来的组）。
    var onRename: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        // 只有提供了改名回调才挂右键菜单：SwiftUI 的 `contextMenu` 内容为空时，
        // 在 macOS 上会弹出一个空菜单，很难看。
        if onRename != nil {
            header.contextMenu {
                Button("重命名分组…") { onRename?() }
            }
        } else {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if collapsible {
                // 三角占位固定宽度，折叠与展开时标题的左边缘不会来回跳。
                // hover 的提亮提示挪到三角上（标题已经是 .primary 粗体，再提亮没对比了）。
                // 用 `AnyShapeStyle` 包一层：`.primary` / `.secondary` 虽同属
                // `HierarchicalShapeStyle`，三元表达式里直接混写仍会让类型推断失败。
                Image(systemName: "chevron.right")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(hovering && collapsible
                                     ? AnyShapeStyle(.primary)
                                     : AnyShapeStyle(.secondary))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .frame(width: compact ? 9 : 10)
            }

            // 分组名：**加粗 + 放大 + .primary**，作为列表里的分隔标题要一眼扫得到。
            // 尺寸刻意压过行标题（行是 13pt medium）—— 层级靠"比下级更重"来交代，
            // 不能只靠灰色/彩色这种容易被背景吃掉的手段。
            Text(title)
                .font(.system(size: compact ? 12 : 14, weight: .bold))
                .foregroundStyle(.primary)

            Text("\(count)")
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(.tertiary)

            // 铅笔**紧跟在分组名（含条数）后面**，不再被 `Spacer` 推到行尾：
            // 为了 hover 标题，指针本来就已经在这一带，不用再横跨整行去够它。
            if let onRename {
                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        // 图标本身很小，撑一下命中区域，免得 hover 到字边才点得中
                        .frame(width: 16, height: 14)
                        .contentShape(Rectangle())
                }
                // `.plain` 是必须的：默认样式在 macOS 上会把图标画成一枚带底的小按钮，
                // 跟"分组标题上的一个小提示"完全不是一个量级的东西。
                .buttonStyle(.plain)
                // 平时不显形。分组标题本身只是个分隔符，多一枚常驻图标会跟行上的
                // 编辑/删除抢注意力；hover 才出现也更接近访达的习惯。
                // `allowsHitTesting` 必须跟着关掉 —— 否则一个看不见的按钮仍然可点。
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .help("重命名「\(title)」")
                .accessibilityLabel("重命名分组「\(title)」")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, compact ? 5 : 2)
        .padding(.bottom, 1)
        // padding 之后再定命中区域，空白处也能点（否则只有文字那一小段响应）
        .contentShape(Rectangle())
        // 注意这里**不**再用 `collapsible && inside`：改名铅笔在不可折叠的标题上
        // 也要能 hover 出现。三角的提亮那处自己带着 `collapsible` 判据。
        .onHover { inside in
            hovering = inside
        }
        .onTapGesture {
            guard collapsible else { return }
            onToggle?()
        }
        .help(collapsible ? (collapsed ? "展开「\(title)」" : "折叠「\(title)」") : title)
    }
}
