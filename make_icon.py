#!/usr/bin/env python3
"""
生成 RouteBar 的 macOS 应用图标 (AppIcon.icns)。

设计：蓝色渐变 squircle + 白色「Y 形路由」母题
    · 上方两个端点节点   —— 流量入口
    · 两条连线向下汇聚   —— 路由
    · 底部「靶心」网关   —— 出口（白环 + 白心点）

**与菜单栏图标同源**：`Y` 的比例直接取自 `make_menubar_icon.py` 那个
88 单位的设计，两边保证"一看就是同一个 App"：

    节点半径 / 臂长 = 6.8 / 41.8 = 0.163
    线宽     / 臂长 = 7.0 / 41.8 = 0.167
    张角（与竖直方向）= atan(18.5 / 37.5) = 26.3°

**为什么网关是「环 + 心点」而不是空心环**：早期版本的网关是
「浅蓝透镜 + 深蓝外圈 + 深蓝瞳」三层结构，视觉上有层次；改成单层
空心环后反而变平。这里用「白环 + 白心点」复刻那套层次，
同时保持整幅图形只有白色一种笔画色。

依赖：Pillow  (pip install Pillow)
用法：
    python3 make_icon.py              # 生成 AppIcon.icns
    python3 make_icon.py --preview    # 另外导出一张 512 的 PNG 便于肉眼核对
"""
import math
import os
import sys

from PIL import Image, ImageDraw

import icon_grid

# ── 画布 ────────────────────────────────────────────────────────────
# Apple 网格：1024 画布里内容只占 824（80.5%），四周各留 100px。
# 所以「设计坐标系」直接用 824，最后交给 icon_grid 摆到 1024 画布中央。
CONTENT = 824
SS = 3                      # 超采样倍率，先画大再 LANCZOS 缩小，边缘更干净
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon.icns")

WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

# ── 配色 ────────────────────────────────────────────────────────────
# 沿用原 AppIcon 的蓝色渐变；顶部比原设计（30,150,255）压深一档，
# 让白色 Y 在渐变最亮处也有足够对比。
TOP_RGB = (16, 138, 252)
BOT_RGB = (0, 78, 188)

# ── Y 形几何（824 坐标系）──────────────────────────────────────────
CX = 412                    # 中轴
NODE_R = 72                 # 上方端点节点半径（= 0.163 × 臂长）
SPREAD = 190                # 上方两节点相对中轴的水平偏移（张角 26.3°）
TOP_Y = 210                 # 上方两节点的 y
JOINT_Y = 594               # 汇合点（网关）的 y
LINE_W = 74                 # 连线线宽（= 0.167 × 臂长）

RING_RO = 88                # 网关外半径
RING_W = 30                 # 网关环壁厚（描边向内）
RING_DOT_R = 26             # 网关中心实心点半径


def gradient(side):
    """竖向蓝色渐变。"""
    img = Image.new("RGB", (side, side), TOP_RGB)
    d = ImageDraw.Draw(img)
    for y in range(side):
        t = y / max(1, side - 1)
        c = tuple(int(TOP_RGB[i] + (BOT_RGB[i] - TOP_RGB[i]) * t) for i in range(3))
        d.line([(0, y), (side, y)], fill=c)
    return img.convert("RGBA")


def sheen_layer(side, strength=46):
    """顶部柔光。

    ⛔ 必须做成**独立图层**再用 `Image.alpha_composite` 叠加。
    PIL 的 `ImageDraw` **不做 alpha 混合** —— 直接 `fill=(255,255,255,28)`
    会把像素连 alpha 一起替换成 28；随后任何"整体覆盖 alpha"的操作
    （`putalpha`）都会把这块近透明白扶正成**不透明纯白**，
    于是图标上半截变成白板、白色笔画全被吃掉。
    """
    ov = Image.new("RGBA", (side, side), CLEAR)
    d = ImageDraw.Draw(ov)
    for y in range(side):
        t = y / max(1, side - 1)
        a = int(strength * max(0.0, 1.0 - t / 0.62) ** 1.6)
        if a:
            d.line([(0, y), (side, y)], fill=(255, 255, 255, a))
    return ov


def draw_art():
    """画内容本体（824×824, RGBA）。"""
    side = CONTENT * SS
    u = float(SS)                       # 内容单位 → 像素
    art = gradient(side)
    art = Image.alpha_composite(art, sheen_layer(side))
    d = ImageDraw.Draw(art)

    cxx = CX * u
    top = TOP_Y * u
    joint = (cxx, JOINT_Y * u)
    left = (cxx - SPREAD * u, top)
    right = (cxx + SPREAD * u, top)
    node_r = NODE_R * u
    line_w = max(2, int(LINE_W * u))

    def unit_vec(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        m = math.hypot(dx, dy) or 1.0
        return dx / m, dy / m

    # Y 形连线：两端各留出节点半径的空隙，避免线"穿"过圆点
    for p in (left, right):
        ux, uy = unit_vec(p, joint)
        start = (p[0] + ux * node_r * 0.95, p[1] + uy * node_r * 0.95)
        end = (joint[0] - ux * node_r * 0.95, joint[1] - uy * node_r * 0.95)
        d.line([start, end], fill=WHITE, width=line_w)

    # 上方端点节点（实心）
    for p in (left, right):
        d.ellipse([p[0] - node_r, p[1] - node_r,
                   p[0] + node_r, p[1] + node_r], fill=WHITE)

    # 网关「靶心」：外环 + 中心点
    # ⛔ 环必须用 outline 描边（向内）画，**不能用 fill + 挖一个 CLEAR 的洞** ——
    #    挖出来的洞是 (0,0,0,0)，一旦后面还有"整体覆盖 alpha"的操作，
    #    它的 RGB 会被原样保留、alpha 被改成 255，于是变成**实心黑点**。
    rr = RING_RO * u
    d.ellipse([joint[0] - rr, joint[1] - rr, joint[0] + rr, joint[1] + rr],
              outline=WHITE, width=max(2, int(RING_W * u)))
    k = RING_DOT_R * u
    d.ellipse([joint[0] - k, joint[1] - k,
               joint[0] + k, joint[1] + k], fill=WHITE)

    art = art.resize((CONTENT, CONTENT), Image.LANCZOS)

    # 圆角遮罩：用 composite 而不是 putalpha（理由同上，putalpha 会覆盖 alpha）
    mask = icon_grid.squircle_mask(CONTENT)
    return Image.composite(art, Image.new("RGBA", (CONTENT, CONTENT), CLEAR), mask)


def main():
    art = draw_art()
    master = icon_grid.reframe_to_grid(art)
    icon_grid.write_icns(master, OUT)

    c, w, pct, pad = icon_grid.measure(icon_grid.loads_icns(OUT))
    print(f"生成图标：{OUT}")
    print(f"  画布 {c}px，内容 {w}px，占比 {pct:.1f}%（规范 80.5%），留白 {pad}")

    if "--preview" in sys.argv:
        p = "/tmp/routebar_icon_preview.png"
        master.resize((512, 512), Image.LANCZOS).save(p)
        print("  预览：", p)


if __name__ == "__main__":
    main()
