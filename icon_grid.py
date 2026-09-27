#!/usr/bin/env python3
"""
macOS 应用图标网格工具。

Apple 的 macOS 图标规范：图标本体（圆角方块 / squircle）只占画布的 824/1024
（≈80.5%），四周各留 100px 透明边距。

若把图形画满整张画布（100%），在 Dock / 访达 / 启动台里就会比系统 App 明显
大一圈 —— 系统不会替你补回边距（旧版 macOS 尤其明显）。

提供：
  measure(img)          → 量出当前图标的"内容占比 + 四边留白"
  reframe_to_grid(img)  → 把满幅图标缩到规范比例并居中放进透明画布
  load_icns(path)       → 取 .icns 里最大的一张位图
  write_icns(master, p) → 由母图生成全部尺寸切片并打包成 .icns
"""

import io
import os
import struct
import subprocess
import tempfile

from PIL import Image

CANVAS = 1024
CONTENT_RATIO = 824 / 1024          # 0.8046875 —— Apple 官方网格
CORNER_RADIUS_RATIO = 0.225         # squircle 圆角 ≈ 内容边长的 22.5%


def measure(img):
    """返回 (画布边长, 内容边长, 占比, 留白(左,上,右,下))。"""
    img = img.convert("RGBA")
    bbox = img.split()[3].getbbox()
    if bbox is None:
        return img.size[0], 0, 0.0, (0, 0, 0, 0)
    c = img.size[0]
    w = bbox[2] - bbox[0]
    pad = (bbox[0], bbox[1], c - bbox[2], c - bbox[3])
    return c, w, w / c * 100, pad


def loads_icns(path):
    """读出 .icns 里最大的一张 PNG 切片。仅支持 PNG 编码的切片。"""
    data = open(path, "rb").read()
    if data[:4] != b"icns":
        raise ValueError(f"{path} 不是 icns 文件")
    pos, best = 8, None
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        if length < 8:
            break
        payload = data[pos + 8:pos + length]
        if payload[:4] == b"\x89PNG":
            im = Image.open(io.BytesIO(payload)).convert("RGBA")
            if best is None or im.size[0] > best.size[0]:
                best = im
        pos += length
    if best is None:
        raise ValueError(f"{path} 里没有 PNG 编码的切片")
    return best


def reframe_to_grid(img, canvas=CANVAS, ratio=CONTENT_RATIO):
    """把满幅（或任意占比）的图标重排到 Apple 网格：缩到 ratio 并居中。"""
    img = img.convert("RGBA")
    side = max(1, round(canvas * ratio))
    art = img.resize((side, side), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    off = (canvas - side) // 2
    out.alpha_composite(art, (off, off))
    return out


def squircle_mask(side, radius_ratio=CORNER_RADIUS_RATIO, supersample=4):
    """生成连续曲率（超椭圆）圆角遮罩，比普通圆角矩形更接近 Apple 的 squircle。"""
    n = 5.0                       # 指数越大越接近方形，5 ≈ Apple squircle
    big = side * supersample
    mask = Image.new("L", (big, big), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(mask)
    a = big / 2.0
    pts = []
    steps = 720
    import math
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = a + a * (abs(ct) ** (2 / n)) * (1 if ct >= 0 else -1)
        y = a + a * (abs(st) ** (2 / n)) * (1 if st >= 0 else -1)
        pts.append((x, y))
    d.polygon(pts, fill=255)
    return mask.resize((side, side), Image.LANCZOS)


def write_icns(master, out_path):
    """由 1024 母图生成全部尺寸切片，打包成 .icns。"""
    master = master.convert("RGBA")
    iconset = tempfile.mkdtemp(suffix=".iconset")
    specs = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for name, px in specs:
        master.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
    subprocess.run(["iconutil", "--convert", "icns",
                    "--output", out_path, iconset], check=True)
    return out_path
