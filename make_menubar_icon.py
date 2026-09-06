#!/usr/bin/env python3
"""
生成 RouteBar 的菜单栏图标 MenuBarIcon.png（template 模式，自适应深浅色）。
设计：与 AppIcon 同源的「网络节点 → 网关节点」路由母题，去掉蓝色渐变底，
仅保留白色描边/填充，置于透明背景上，供 macOS 菜单栏以模板图标渲染。
依赖：Pillow  (pip install Pillow)
用法：python3 make_menubar_icon.py
"""
import math
import os

from PIL import Image, ImageDraw

SIZE = 88  # 输出分辨率（@2x，菜单栏渲染约 22pt）
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Resources", "MenuBarIcon.png")

WHITE = (255, 255, 255, 255)


def draw(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 圆角矩形描边（不填充，避免菜单栏里出现实心方块）
    s = size / SIZE
    radius = int(18 * s)
    lw = max(2, int(5 * s))
    d.rounded_rectangle([lw, lw, size - 1 - lw, size - 1 - lw],
                        radius=radius, outline=WHITE, width=lw)

    # 节点坐标（与 AppIcon 同源比例）
    left = (30 * s, 34 * s)
    right = (62 * s, 34 * s)
    gw = (46 * s, 70 * s)
    r_node = 7 * s
    r_gw = 9 * s

    line_w = max(2, int(3 * s))

    def norm(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        m = math.hypot(dx, dy) or 1
        return dx / m, dy / m

    # 连线
    d.line([left, gw], fill=WHITE, width=line_w)
    d.line([right, gw], fill=WHITE, width=line_w)

    # 箭头（指向网关）
    def arrowhead(tip, base, sz):
        ang = math.atan2(tip[1] - base[1], tip[0] - base[0])
        a1 = ang + math.radians(150)
        a2 = ang - math.radians(150)
        p1 = (tip[0] + sz * math.cos(a1), tip[1] + sz * math.sin(a1))
        p2 = (tip[0] + sz * math.cos(a2), tip[1] + sz * math.sin(a2))
        d.polygon([tip, p1, p2], fill=WHITE)

    for ep in (left, right):
        ux, uy = norm(ep, gw)
        tip = (gw[0] - ux * (r_gw + 2 * s), gw[1] - uy * (r_gw + 2 * s))
        base = (tip[0] - ux * 7 * s, tip[1] - uy * 7 * s)
        arrowhead(tip, base, 6 * s)

    # 端点节点（实心白点）
    for ep in (left, right):
        d.ellipse([ep[0] - r_node, ep[1] - r_node, ep[0] + r_node, ep[1] + r_node],
                  fill=WHITE)

    # 网关节点（环形，强调出口）
    d.ellipse([gw[0] - r_gw, gw[1] - r_gw, gw[0] + r_gw, gw[1] + r_gw],
              fill=WHITE)
    # 网关内挖空一个小圆，形成"出口"环
    hole = 4 * s
    d.ellipse([gw[0] - hole, gw[1] - hole, gw[0] + hole, gw[1] + hole],
              fill=(0, 0, 0, 0))
    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # 2x 超采样提升清晰度
    master = draw(int(SIZE * 2)).resize((SIZE, SIZE), Image.LANCZOS)
    master.save(OUT)
    print("生成菜单栏图标：", OUT)


if __name__ == "__main__":
    main()
