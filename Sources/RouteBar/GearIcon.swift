import SwiftUI

/// 设置齿轮图标（方案 A：12 齿外圈 + 内环 + 中心孔）。
///
/// 不用 `Image(systemName: "gearshape")` 是因为原设计里那个「圆圈 + 放射线」
/// 看起来像太阳/亮度图标；这里按选定方案自行绘制：外圈用 `stroke` 的
/// **虚线**（`dash:`）造出真实齿形，再叠内环与中心孔。
///
/// 几何比例照搬设计稿（以 24×24 为基准单位）：
///   外齿圈 r=9.2 / 线宽 3.1 / 齿距 2.4   ← 周长 ÷ 4.8 ≈ 12 齿
///   内   环 r=7.3 / 线宽 1.7
///   中心孔  r=3.1 / 线宽 1.7
struct GearIcon: View {
    /// 图标外框边长（pt）
    var size: CGFloat = 18

    /// 1 个设计单位 = 多少 pt
    private var unit: CGFloat { size / 24 }

    var body: some View {
        ZStack {
            // 外圈：粗虚线 = 齿
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 3.1 * unit,
                                            dash: [2.4 * unit, 2.4 * unit]))
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
