#!/usr/bin/env python3
"""
把现有的 AppIcon.icns 重排到 Apple 图标网格（内容 824/1024，四周留白 100px）。

只改"大小/占比"，不改设计 —— 图形本身原样保留，只是缩到规范比例再居中。

用法：
    python3 reflow_icon.py            # 原地修正 AppIcon.icns
    python3 reflow_icon.py --check    # 只测量，不修改
"""

import os
import shutil
import sys

from PIL import Image

import icon_grid

HERE = os.path.dirname(os.path.abspath(__file__))
ICNS = os.path.join(HERE, "AppIcon.icns")
PREVIEW_BEFORE = "/tmp/routebar_icon_before.png"
PREVIEW_AFTER = "/tmp/routebar_icon_after.png"


def main():
    check_only = "--check" in sys.argv

    art = icon_grid.loads_icns(ICNS)
    c, w, pct, pad = icon_grid.measure(art)
    print(f"当前图标：画布 {c}px，内容 {w}px，占比 {pct:.1f}%，留白 {pad}")
    print(f"Apple 规范：占比 80.5%，四边各留 {round(1024 * (1 - icon_grid.CONTENT_RATIO) / 2)}px")

    if check_only:
        print("（--check 模式，未修改文件）")
        return

    if abs(pct - icon_grid.CONTENT_RATIO * 100) < 0.5:
        print("占比已经合规，无需处理。")
        return

    art.resize((400, 400), Image.LANCZOS).save(PREVIEW_BEFORE)

    fixed = icon_grid.reframe_to_grid(art)
    icon_grid.write_icns(fixed, ICNS)
    fixed.resize((400, 400), Image.LANCZOS).save(PREVIEW_AFTER)

    c2, w2, pct2, pad2 = icon_grid.measure(icon_grid.loads_icns(ICNS))
    print(f"修正后：  画布 {c2}px，内容 {w2}px，占比 {pct2:.1f}%，留白 {pad2}")
    print(f"已写回：{ICNS}")
    print(f"预览（修正前 / 修正后）：{PREVIEW_BEFORE} | {PREVIEW_AFTER}")


if __name__ == "__main__":
    main()
