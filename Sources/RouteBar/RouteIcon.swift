import SwiftUI
import AppKit

// MARK: - 路由图标
//
// 每条路由可以带一张自定义图标（新增 / 编辑窗口里上传）。没上传时用**自绘的
// 默认路由图标**（`RBDefaultRouteIcon`）。
//
// **为什么不用 SF Symbol 当默认图标**：系统里没有任何一个符号画的是"路由"这件事
// —— `arrow.triangle.branch` 像代码分支、`point.topleft.down.curvedto.point.bottomright.up`
// 像两点连线、`arrow.triangle.turn.up.right.diamond` 像导航，缩到 22pt 之后
// 全都只剩一团笔画。与 `GearIcon` 当初的判断同一条：**语义不对就自绘**。
//
// 落盘格式的选择（为什么存文件而不是塞进 routes.json）见 `RouteIconLibrary`。

// MARK: - 默认图标

/// 默认路由图标：一枚**卡通路由器** —— 圆角方块底板上，白色机身 + 两根圆头天线
/// + 两颗圆圆的指示灯。
///
/// **为什么是路由器而不是抽象符号**（先后试过 Y 形分岔、斜支 Y、wifi 信号弧）：
/// 这个 App 管的是"静态路由"，可列表里绝大多数用户看到的只是"一条条网络配置"，
/// 抽象的分岔图形在这个尺寸上会被读成树枝、三叉戟或者人脸。具象的一台小路由器
/// 一眼就能认出来，也正好呼应菜单栏那个 Wifi 图标 —— 与 `GearIcon`、`MoreIcon`
/// 同一条判断：**语义对不上就自绘，看得懂 > 抽象**。
///
/// 天线端头特意加了两颗小球（先试过平头，像两根天线杆子，冷冰冰），配上两颗
/// 圆形指示灯，整枚图标就有了"小机器人"的可爱劲 —— 这就是"卡通"两个字的落点。
/// **没有再加 wifi 信号弧**：试过，弧线正好压在两根天线中间，三者叠成一团。
///
/// 几何以 **24×24 为设计单位**（与 `GearIcon` 同一约定，便于按比例缩放）：
/// ```
///   底板      24 × 24，连续圆角 6.6
///   天线      线宽 1.9，(7.5,12.7) → (5.6,7.1)，右侧镜像
///   天线球    d = 2.8，圆心 (5.6,7.1) / (18.4,7.1)
///   机身      15.4 × 6.6，圆角 2.3，垂直偏移 +3.1
///   指示灯    d = 2.1，x = 9.7 / 14.3，与机身同一水平中线
/// ```
/// 留白（上 5.7 / 下 5.6 / 左右 4.2、4.3 单位）是按**重心**配的：
/// 一开始机身贴着底边放，整枚图标看着往下坠，天线上方空一大块。
struct RBDefaultRouteIcon: View {
    /// 图标外框边长（pt）
    var size: CGFloat = 22

    /// 1 个设计单位 = 多少 pt
    private var u: CGFloat { size / 24 }

    /// 指示灯的颜色。
    ///
    /// 不写 `.white` 也不写 `.blue`：机身是白的，灯是**机身"透"出来的底板色**
    /// ——也就是那块蓝色渐变落在机身位置的深端。取一个固定的深蓝，既不用为了
    /// 取真实渐变色去写 `GeometryReader`，四档尺寸下的观感也一致。
    private let ledColor = Color(red: 0.21, green: 0.38, blue: 0.87)

    var body: some View {
        ZStack {
            // 底板：左上亮、右下深。方向与工具栏玻璃的高光一致（同 `RBGlassDisc`），
            // 整块界面才像被同一束光照着。
            RoundedRectangle(cornerRadius: 6.6 * u, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(red: 0.38, green: 0.60, blue: 0.99),
                                            Color(red: 0.19, green: 0.35, blue: 0.85)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )

            // 两根天线。画在机身**之前**，天线根部就被机身盖住，接缝干净。
            Path { path in
                path.move(to: CGPoint(x: 7.5 * u, y: 12.7 * u))
                path.addLine(to: CGPoint(x: 5.6 * u, y: 7.1 * u))
                path.move(to: CGPoint(x: 16.5 * u, y: 12.7 * u))
                path.addLine(to: CGPoint(x: 18.4 * u, y: 7.1 * u))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.9 * u,
                                       lineCap: .round,
                                       lineJoin: .round))
            .foregroundStyle(.white)

            // 天线端头的小球 —— "卡通"主要就靠这两颗
            dot(center: CGPoint(x: 5.6, y: 7.1), diameter: 2.8, color: .white)
            dot(center: CGPoint(x: 18.4, y: 7.1), diameter: 2.8, color: .white)

            // 机身
            RoundedRectangle(cornerRadius: 2.3 * u, style: .continuous)
                .fill(.white)
                .frame(width: 15.4 * u, height: 6.6 * u)
                .offset(y: 3.1 * u)

            // 两颗指示灯（对称 → 读起来像一对眼睛，是这枚图标"卡通"的第二处）
            dot(center: CGPoint(x: 9.7, y: 15.1), diameter: 2.1, color: ledColor)
            dot(center: CGPoint(x: 14.3, y: 15.1), diameter: 2.1, color: ledColor)
        }
        .frame(width: size, height: size)
    }

    /// 一枚圆点（天线球 / 指示灯共用）。
    ///
    /// 用 `offset` 而不是 `position` 定位：`position` 会把自身尺寸并入父容器的
    /// 布局计算，在 `ZStack` 里容易把整体撑到 24×24 之外；`offset` 只做视觉位移，
    /// 不参与尺寸计算。中心点按 24 格坐标给，`12` 是底板正中。
    private func dot(center: CGPoint, diameter: CGFloat, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter * u, height: diameter * u)
            .offset(x: (center.x - 12) * u, y: (center.y - 12) * u)
    }
}

// MARK: - 统一入口视图

/// 一条路由在**任何界面**里显示的那个图标（列表行、卡片、快速启动页、编辑窗口预览）。
///
/// 三处必须走同一个视图，否则"列表里是一个样子、卡片里是另一个样子"这种不一致
/// 迟早会出现（行 / 卡的玻璃底当年就吃过这个亏）。
struct RBRouteIcon: View {
    /// 自定义图标的**文件名**（对应 `Route.icon`）。为空、或文件已丢失 → 用默认图标。
    var custom: String?

    /// 边长（pt）。列表 / 快速启动页 22，卡片 24，编辑窗口预览 36。
    var size: CGFloat = 22

    /// 未启用的路由把图标**去色压暗** —— 与同一行里文字变灰是同一层语义，
    /// 让"这条没生效"在不读文字的情况下也看得出来。
    var dimmed: Bool = false

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.275, style: .continuous))
            .saturation(dimmed ? 0 : 1)
            .opacity(dimmed ? 0.5 : 1)
    }

    @ViewBuilder
    private var content: some View {
        if let name = custom, let image = RouteIconLibrary.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                // 与落盘时的取景一致（居中 aspect-fill 裁成方图），
                // 所以这里 `fill` 不会二次裁掉内容
                .aspectRatio(contentMode: .fill)
        } else {
            RBDefaultRouteIcon(size: size)
        }
    }
}

// MARK: - 自定义图标的落盘与读取

/// 自定义图标的文件管理。
///
/// **为什么存成独立文件，而不是把图片 base64 塞进 `routes.json`**：
/// 图片即使压到 128×128，base64 之后也是好几 KB 一条；`routes.json` 现在是
/// "人可读的纯文本配置"，体积一旦上去，手工查看、对比、备份都变难。
/// 落成独立文件后 JSON 里只多一个文件名，出问题时删掉那个文件即可回退默认图标。
enum RouteIconLibrary {

    /// 归一化后的边长（px）。
    ///
    /// 取 128：界面里最大只用到 44pt（编辑窗口预览），44 × 2（Retina）= 88 < 128，
    /// 够用且不糊；再大就是白占空间 —— 用户传一张 4000×3000 的照片进来，
    /// 落到磁盘上也还是这几 KB。
    private static let pixelSide: CGFloat = 128

    /// 图片缓存。**必须缓存**：列表每次重绘都会对每一行问一次
    /// `image(named:)`，不缓存就是每帧几十次磁盘 IO。
    private static let cache = NSCache<NSString, NSImage>()

    private static var directory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport
            .appendingPathComponent("RouteBar", isDirectory: true)
            .appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(of name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// 读图标。文件不存在（用户手工删了 / 换过电脑）时返回 `nil`，
    /// 调用方一律回退到默认图标 —— 不允许因为图标坏了就整行渲染不出来。
    static func image(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let image = NSImage(contentsOf: url(of: name)) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// 把用户选中的图片归一化成 128×128 PNG 落盘，返回**文件名**（失败返回 `nil`）。
    ///
    /// 文件名带时间戳：同一条路由换图时若沿用同一个文件名，`NSImage` 缓存与系统
    /// 文件缓存都可能把旧图再喂回来（页面看着"换了但没换"）。带时间戳等于每次
    /// 都是新名字，旧文件交给调用方删。
    static func store(_ image: NSImage, for routeID: UUID) -> String? {
        guard let data = normalizedPNG(image) else { return nil }
        let name = "\(routeID.uuidString)-\(Int(Date().timeIntervalSince1970)).png"
        do {
            try data.write(to: url(of: name), options: .atomic)
        } catch {
            return nil
        }
        _ = self.image(named: name)   // 预热缓存，避免首帧闪一下默认图标
        return name
    }

    /// 清掉**没有任何路由引用**的图标文件（每次启动扫一遍）。
    ///
    /// **为什么还需要它**（别当成多余的一层）：会话内的清理（取消编辑、移除图标、
    /// 删除路由）覆盖不了所有路径 —— 「打开另一条路由的编辑窗」时前一个窗口是被
    /// 直接 `close()` 掉的，那条路径上 SwiftUI 的 `.onDisappear` 不保证触发；
    /// App 崩溃或强杀时更是完全不会跑。2026-10-01 实测就在这个目录里留下过一个
    /// 791 字节的孤儿文件 —— 界面上再也看不到它，也就永远删不掉。
    ///
    /// **只允许在 routes.json 成功解码之后调用**（见 `RouteStore.load`）：
    /// 读文件失败时 `routes` 是空数组，若照样扫，用户的图标会被一次清空。
    static func sweep(keeping referenced: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for name in names where name.hasSuffix(".png") && !referenced.contains(name) {
            discard(name)
        }
    }

    /// 删除一个图标文件。传 `nil` / 空串直接返回，调用方不必自己判空。
    ///
    /// 三个调用点：删除路由、编辑时换了新图标、取消编辑时清理本次新写入的文件。
    static func discard(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: url(of: name))
    }

    /// 裁剪成正方形并缩到 `pixelSide`，输出 PNG 数据。
    ///
    /// **为什么用 `CGContext` 而不是 `NSImage.lockFocus` + `draw(in:from:)`**：
    /// 后者的 `from` 取的是**点**尺寸，而多表示（Retina）图片的点尺寸与像素尺寸
    /// 差一个倍率，直接画会错位或糊。`CGImage` 的 `width/height` 就是像素，
    /// 算缩放没有歧义。
    ///
    /// 取景用**居中 aspect-fill**（短边铺满、长边裁掉），与界面上那个圆角方块
    /// 的显示方式一致；换成 fit 会在两侧留下透明带，落在行的玻璃底上很脏。
    private static func normalizedPNG(_ image: NSImage) -> Data? {
        guard let cg = cgImage(of: image), cg.width > 0, cg.height > 0 else { return nil }

        let side = pixelSide
        guard let ctx = CGContext(data: nil,
                                  width: Int(side), height: Int(side),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high

        let scale = max(side / CGFloat(cg.width), side / CGFloat(cg.height))
        let w = CGFloat(cg.width) * scale
        let h = CGFloat(cg.height) * scale
        ctx.draw(cg, in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))

        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }

    /// 取图片的 `CGImage`。
    ///
    /// 优先从**像素最多**的那个位图表示取：多表示图片（Retina 截图、
    /// 带 @2x 的 png）里 `image.size` 是点、`NSBitmapImageRep.pixelsWide` 才是像素，
    /// 用 `size` 算缩放会差一个倍率。取不到位图表示（矢量 PDF 等）时再退回
    /// `cgImage(forProposedRect:)`。
    private static func cgImage(of image: NSImage) -> CGImage? {
        if let best = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           let cg = best.cgImage {
            return cg
        }
        var rect = NSRect(x: 0, y: 0,
                          width: max(image.size.width, 1),
                          height: max(image.size.height, 1))
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
