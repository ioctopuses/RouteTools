import SwiftUI

// MARK: - 自绘图标
//
// 三个图标共用同一条「圆形」视觉语言，因此放在一起：
//   · GearIcon   —— 设置：齿圈 + 内环 + 中心孔
//   · MoreIcon   —— 更多（⋯）：三个等距圆点
//   · FilterIcon —— 筛选：三条左对齐、长度递减的横线
//
// 三者都不带底色，底色统一由 `rbGlassDisc()`（单独出现时）或外层的
// `rbGlassGroup()`（并排在一个胶囊里时）提供，这样"齿轮有轮廓、⋯ 没有轮廓"
// 的不一致就被消除了。
//
// 墨色**不统一**，这是刻意的：齿轮走继承的前景色即可，而 ⋯ 与筛选
// 必须显式给纯黑/纯白 —— 原因见 `MoreIcon` 的那一大段注释（popover 的
// vibrancy 会把动态语义色解析成半透明，看着像灰色）。

/// 设置齿轮。
///
/// **为什么不用 `Image(systemName: "gearshape")`**：系统那个「圆圈 + 放射线」
/// 在小尺寸下更像太阳/亮度图标。这里按设计稿自绘：外圈用 `stroke` 的
/// **虚线**（`dash:`）造齿形，再叠内环与中心孔。
///
/// **齿数**：24×24 基准下外圈周长 = π × 18.4 ≈ 57.8 单位，取 `dash` 的
/// 画/空各 3.61 单位（周期 7.22）→ 57.8 ÷ 7.22 ≈ **8 齿**。
/// 早期版本是 12 齿（dash 2.4/2.4），实测在小尺寸下糊成一片、看着"太密"，
/// 故降到 8 齿；再少（6 齿）就会退化成"花瓣/虚线圆"，不再像齿轮。
///
/// 几何比例（以 24×24 为基准单位）：
///   外齿圈 直径 18.4 / 线宽 2.9 / 画空各 3.61
///   内  环 直径 14.6 / 线宽 1.7
///   中心孔 直径  6.2 / 线宽 1.7
struct GearIcon: View {
    /// 图标外框边长（pt）
    var size: CGFloat = 18

    /// 1 个设计单位 = 多少 pt
    private var unit: CGFloat { size / 24 }

    var body: some View {
        ZStack {
            // 外圈：粗虚线 = 齿
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 2.9 * unit,
                                            dash: [3.61 * unit, 3.61 * unit]))
                .frame(width: 18.4 * unit, height: 18.4 * unit)

            // 内环
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.7 * unit))
                .frame(width: 14.6 * unit, height: 14.6 * unit)

            // 中心孔
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.7 * unit))
                .frame(width: 6.2 * unit, height: 6.2 * unit)
        }
        .frame(width: size, height: size)
    }
}

/// 「更多」的 ⋯ 图标（三个横排圆点）。
///
/// **2026-10-01 张瑜要求由 ☰ 改成三点**。旧版是三条横线，当时的顾虑写在
/// 旧注释里 ——「三点在 15pt 下点径只有 3pt，容易糊成一团」—— 实测下来这个
/// 顾虑在我们现在这套底上是多余的：外壳已经换成了 `rbGlassGroup()` 的液态玻璃
/// 胶囊（对比度比早期的平涂灰圆盘高得多），点径收到 2.25pt 依旧认得出；
/// 而 ⋯ 是 macOS 上"更多操作"的第一语汇，比 ☰ 少一层翻译。
///
/// **墨色必须显式给（踩过的坑）**：本图标只出现在 `Menu` 的 label 里。
/// 实测同一个玻璃圆盘里（浅色弹窗、背景约 243）：
///   · `Capsule().fill(Color.primary)`            → 笔画 **192**（用户反馈"是灰色"）
///   · `Capsule()`（空填充，继承前景色）          → **192**
///   · 再加 `.foregroundStyle(.primary)`          → **73**
///   · `Capsule().fill(Color(nsColor: .labelColor))` → **73**
/// 而同排的 `GearIcon`（`Circle().stroke()` 不带颜色）是**纯黑 0**。
///
/// 结论：**动态语义色（`Color.primary` / `NSColor.labelColor`）在 popover 的
/// vibrancy 上下文里会被解析成半透明**（约 70% 甚至 20% 的 alpha），
/// 靠 `foregroundStyle` 层级救不回来。所以这里改用**按外观模式显式取纯黑/纯白**
/// —— 不走动态解析，实测得到纯黑 0，与齿轮一致。
///
/// 用 `Circle` 而非圆角矩形：三点本来就没有方向性，正圆在任何尺寸下都等价，
/// 不会像细长矩形那样在小尺寸上被抗锯齿吃出一圈灰边。
/// 比例：点径 0.15×size、点间距 0.13×size，三点合计约 0.71×size 宽
/// （15pt 下 10.7pt），视觉重量与同排的 `GearIcon(15)` / `FilterIcon(15)` 相当。
struct MoreIcon: View {
    var size: CGFloat = 18

    @Environment(\.colorScheme) private var colorScheme

    /// 笔画墨色：显式纯黑 / 纯白，随外观模式切换，但不经过动态色解析
    private var ink: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        HStack(spacing: size * 0.13) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(ink)
                    .frame(width: size * 0.15, height: size * 0.15)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 「筛选」图标：三条**左对齐、长度递减**的横线。
///
/// **为什么是递减三线**：这是 macOS（Big Sur 起）"筛选 / 过滤"的第一语汇
/// （`line.3.horizontal.decrease` 就是这个形状），一眼可读，不需要图例。
/// 早期曾考虑画漏斗 —— 漏斗在 15pt 下要么只剩一个倒三角（认成"下移"），
/// 要么细脖子糊掉，反而更差。
///
/// **为什么左对齐而不是居中**：左对齐读作"逐层筛掉"，居中递减读作"信号强度"
/// 或"排序"。两者形近义远，靠对齐方式区分。
///
/// **墨色**：同 `MoreIcon`，必须显式取纯黑/纯白（popover 的 vibrancy 会把
/// 动态语义色解析成半透明）。**筛选生效时**改走 `Color.accentColor` ——
/// 这是唯一的例外：它必须是"能一眼看出正在筛选"的信号，而强调色是有色相的
/// 具体颜色，不像 `labelColor` 那样会被 vibrancy 抽成半透明灰。
///
/// 比例：线宽 0.72 / 0.48 / 0.24 ×size（等差），线高 0.115×size，
/// 行距 0.14×size。整体内容宽 0.72×size，在 size 见方的框里居中 ——
/// 于是"最长的那条线"左右各留 0.14×size，视觉重心不偏。
struct FilterIcon: View {
    var size: CGFloat = 18

    /// 是否正在筛选。为 `true` 时整枚图标走强调色。
    var active: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    /// 笔画墨色：筛选态用强调色，否则显式纯黑 / 纯白（不经过动态色解析）
    private var ink: Color {
        if active { return .accentColor }
        return colorScheme == .dark ? .white : .black
    }

    /// 三条线相对 `size` 的宽度（长 → 短），全部左对齐
    private let widths: [CGFloat] = [0.72, 0.48, 0.24]

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.14) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                Capsule()
                    .fill(ink)
                    .frame(width: size * w, height: size * 0.115)
            }
        }
        .frame(width: size, height: size)
    }
}
