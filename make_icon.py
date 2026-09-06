#!/usr/bin/env python3
"""
生成 RouteBar 的 macOS 应用图标 (AppIcon.icns)。
设计：蓝色渐变圆角方块 + 网络节点将流量路由到网关节点（带方向箭头）。
依赖：Pillow  (pip install Pillow)
用法：python3 make_icon.py
"""
import math
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

SIZE = 1024  # 主图分辨率
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon.icns")

# ---- 配色 ----
TOP = (30, 150, 255)      # 渐变上：亮蓝
BOTTOM = (0, 92, 200)     # 渐变下：深蓝
NODE_FILL = (255, 255, 255, 46)
NODE_RING = (255, 255, 255, 235)
GATEWAY_FILL = (200, 238, 255, 255)
GATEWAY_RING = (8, 96, 180, 255)
LINE = (255, 255, 255, 165)
PACKET = (255, 255, 255, 230)


def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 渐变背景
    top = TOP
    bot = BOTTOM
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        d.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # 顶部高光
    d.rounded_rectangle([0, -size * 0.35, size, size * 0.55],
                        radius=size * 0.25, fill=(255, 255, 255, 28))

    # 节点坐标（按 SIZE 比例）
    s = size / SIZE
    left = (320 * s, 360 * s)
    right = (704 * s, 360 * s)
    gw = (512 * s, 720 * s)
    r_node = 72 * s
    r_gw = 100 * s

    lw = max(2, int(26 * s))

    def line_between(a, b, width):
        d.line([a, b], fill=LINE, width=width)

    # 连线（先画，节点会盖住端点）
    line_between(left, gw, lw)
    line_between(right, gw, lw)

    # 箭头：指向网关（流量被路由到网关）
    def arrowhead(tip, base, sz, fill):
        dx = tip[0] - base[0]
        dy = tip[1] - base[1]
        ang = math.atan2(dy, dx)
        a1 = ang + math.radians(152)
        a2 = ang - math.radians(152)
        p1 = (tip[0] + sz * math.cos(a1), tip[1] + sz * math.sin(a1))
        p2 = (tip[0] + sz * math.cos(a2), tip[1] + sz * math.sin(a2))
        d.polygon([tip, p1, p2], fill=fill)

    def norm(a, b):
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        m = math.hypot(dx, dy) or 1
        return dx / m, dy / m

    for ep in (left, right):
        ux, uy = norm(ep, gw)
        tip = (gw[0] - ux * (r_gw + 6 * s), gw[1] - uy * (r_gw + 6 * s))
        # 起点稍微离开端点
        base = (tip[0] - ux * 30 * s, tip[1] - uy * 30 * s)
        arrowhead(tip, base, 30 * s, PACKET)

    # 流动的小"数据包"
    for ep in (left, right):
        ux, uy = norm(ep, gw)
        for k in (0.45, 0.7):
            px = ep[0] + (gw[0] - ep[0]) * k
            py = ep[1] + (gw[1] - ep[1]) * k
            d.ellipse([px - 9 * s, py - 9 * s, px + 9 * s, py + 9 * s],
                      fill=PACKET)

    # 端点节点
    for ep in (left, right):
        d.ellipse([ep[0] - r_node, ep[1] - r_node, ep[0] + r_node, ep[1] + r_node],
                  fill=NODE_FILL, outline=NODE_RING, width=max(2, int(14 * s)))

    # 网关节点（更大、更亮）
    d.ellipse([gw[0] - r_gw, gw[1] - r_gw, gw[0] + r_gw, gw[1] + r_gw],
              fill=GATEWAY_FILL, outline=GATEWAY_RING, width=max(2, int(16 * s)))
    # 网关内小圆点，强调"出口"
    d.ellipse([gw[0] - r_gw * 0.42, gw[1] - r_gw * 0.42,
               gw[0] + r_gw * 0.42, gw[1] + r_gw * 0.42],
              fill=GATEWAY_RING)

    # 圆角遮罩
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    radius = int(size * 0.22)
    md.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.putalpha(mask)
    return img


def main():
    master = draw_icon(SIZE)
    # 2x 超采样提升线条质量
    master = draw_icon(SIZE * 2).resize((SIZE, SIZE), Image.LANCZOS)

    iconset = tempfile.mkdtemp(suffix=".iconset")
    specs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, px in specs:
        img = master.resize((px, px), Image.LANCZOS)
        img.save(os.path.join(iconset, name))

    subprocess.run(["iconutil", "--convert", "icns",
                    "--output", OUT, iconset], check=True)
    print("生成图标：", OUT)


if __name__ == "__main__":
    main()
