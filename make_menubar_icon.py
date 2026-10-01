#!/usr/bin/env python3
"""
生成 RouteBar 的菜单栏图标（template 模板图，随菜单栏自动白/黑）。

设计（与 AppIcon 同源地简化）：
    · 圆角方框   —— 呼应 App 图标那个蓝色圆角方块，保证"一看就是同一个 App"
    · Y 形连线   —— 上方两个节点汇聚到下方网关，即"把流量路由到网关"的母题
    · 底部圆环   —— 网关是"出口"，用空心环与实心端点节点区分

**为什么不用 SF Symbol `network`**：那是个"地球/经纬线"造型，与 App 的
路由母题毫无关系，用户第一眼认不出来。早期版本正是写死了该符号。

**为什么在 18pt 下还要保留外框**：外框是唯一的 App 身份标识。实测把
节点+连线单独放出来（无框）虽然更清爽，但和系统里一堆网络类图标撞脸；
加上外框后 18pt 下仍可辨识（框线 4/88 ≈ 0.8pt，不会糊成一团）。

输出两个分辨率（菜单栏按 Retina 自动选）：
    Resources/MenuBarIcon.png      @1x  18×18
    Resources/MenuBarIcon@2x.png   @2x  36×36

依赖：Pillow  (pip install Pillow)
用法：python3 make_menubar_icon.py
"""
import math
import os

from PIL import Image, ImageDraw

# ── 设计画布与输出尺寸 ──────────────────────────────────────────────
UNIT = 88          # 设计坐标系（下面所有数字都按这个 88×88 画布给）
PT = 18            # 菜单栏里的显示边长（pt）
SUPERSAMPLE = 4    # 超采样倍率，先画大再缩小，边缘更干净

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Resources")

WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

# ── 几何参数（88 坐标系）────────────────────────────────────────────
FRAME_STROKE = 4.0     # 外框线宽
FRAME_RADIUS = 20.0    # 外框圆角
FRAME_INSET = 4.0      # 外框距画布边距

NODE_LINE_W = 7.0      # Y 形连线线宽
TOP_Y = 25.5           # 上方两个节点的 y
JOINT_Y = 63.0         # 汇合点（网关）的 y
SPREAD = 18.5          # 上方两个节点相对中轴的水平偏移
NODE_R = 6.8           # 端点节点半径（实心）
RING_R = 7.6           # 网关环外半径
RING_HOLE_W = 3.4      # 网关环壁厚（环内挖空）

CENTER_X = UNIT / 2


def draw_unit(scale: int) -> Image.Image:
    """按设计坐标画一张 scale 倍放大的母图（RGBA）。"""
    size = UNIT * scale
    img = Image.new("RGBA", (size, size), CLEAR)
    d = ImageDraw.Draw(img)
    s = float(scale)          # 设计单位 → 像素

    # 外框：圆角矩形描边
    w = max(2, int(FRAME_STROKE * s))
    d.rounded_rectangle(
        [w, w, size - 1 - w, size - 1 - w],
        radius=int(FRAME_RADIUS * s),
        outline=WHITE,
        width=w,
    )

    cx = CENTER_X * s
    top = TOP_Y * s
    joint = (cx, JOINT_Y * s)
    left = (CENTER_X * s - SPREAD * s, top)
    right = (CENTER_X * s + SPREAD * s, top)

    node_r = NODE_R * s
    line_w = max(2, int(NODE_LINE_W * s))

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

    # 上方端点节点（实心圆）
    for p in (left, right):
        d.ellipse([p[0] - node_r, p[1] - node_r,
                   p[0] + node_r, p[1] + node_r], fill=WHITE)

    # 网关节点：实心圆挖空中心 = 空心环，强调"出口"
    rr = RING_R * s
    d.ellipse([joint[0] - rr, joint[1] - rr,
               joint[0] + rr, joint[1] + rr], fill=WHITE)
    hole = rr - max(2, int(RING_HOLE_W * s))
    d.ellipse([joint[0] - hole, joint[1] - hole,
               joint[0] + hole, joint[1] + hole], fill=CLEAR)

    return img


def render(pt: int) -> Image.Image:
    """渲染成 pt×pt 的成品（超采样后 LANCZOS 缩小）。"""
    master = draw_unit(SUPERSAMPLE)
    return master.resize((pt, pt), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    targets = [
        (os.path.join(OUT_DIR, "MenuBarIcon.png"), PT),
        (os.path.join(OUT_DIR, "MenuBarIcon@2x.png"), PT * 2),
    ]
    for path, px in targets:
        render(px).save(path)
        print(f"生成：{path}  ({px}×{px})")


if __name__ == "__main__":
    main()
