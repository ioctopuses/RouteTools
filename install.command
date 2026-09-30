#!/bin/bash
#
# RouteBar 一键安装（macOS）
#
# 用法：
#   A. 一行命令（推荐，无需预先下载任何文件）—— 打开「终端」粘贴：
#      /bin/bash -c "$(curl -fsSL https://github.com/ioctopuses/RouteTools/releases/latest/download/install.command)"
#      终端里执行的内容不经 Gatekeeper 评估，所以这条路**全程没有弹窗**。
#   B. 双击本文件（需与 RouteBar.app 或 RouteBar-*.zip 放在同一目录）：
#      首次运行 macOS 会拦一下「无法验证开发者」—— 在文件上 右键 → 打开 → 再点「打开」确认一次。
#      （只需确认这一次；脚本是单个文件，不是 .app，比放行 App 省事）
#   C. 终端里执行本地副本：
#      xattr -dr com.apple.quarantine install.command && bash install.command
#
# 本地找不到 RouteBar.app 时会自动从 GitHub Release 下载最新版（仓库地址见下方 REPO）。
#
# 为什么要清隔离标记：从浏览器 / 微信 / U 盘 / AirDrop 拿到的文件，会被 macOS
# 打上 com.apple.quarantine 属性，Gatekeeper 一见到它就会要求用户去「系统设置
# → 隐私与安全性」里手动点「仍要打开」。RouteBar 由开发者自签名、未经 Apple
# 公证，必然被拦；清掉这个标记后即可正常启动。本脚本不改动任何系统安全设置，
# 也不需要管理员密码。
#
set -euo pipefail

APP_NAME="RouteBar.app"
EXEC_NAME="RouteBar"
DEST="/Applications/$APP_NAME"
REPO="ioctopuses/RouteTools"
WORK=""

info() { printf '  ·  %s\n' "$*"; }
fail() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

printf '\n=== RouteBar 安装 ===\n\n'

SELF_DIR="$(cd "$(/usr/bin/dirname "$0")" 2>/dev/null && pwd || pwd)"
APP=""

# ── 1. 定位 RouteBar.app ──────────────────────────────────────────────
for dir in "$SELF_DIR" "$PWD"; do
    if [ -d "$dir/$APP_NAME" ]; then APP="$dir/$APP_NAME"; break; fi
done

if [ -z "$APP" ]; then
    ZIP="$(/bin/ls -t "$SELF_DIR"/RouteBar*.zip 2>/dev/null | /usr/bin/head -1 || true)"
    if [ -n "$ZIP" ]; then
        info "解压 $(/usr/bin/basename "$ZIP")"
        WORK="$(/usr/bin/mktemp -d)"
        /usr/bin/ditto -x -k "$ZIP" "$WORK"
        APP="$(/usr/bin/find "$WORK" -maxdepth 3 -name "$APP_NAME" -print -quit)"
    fi
fi

if [ -z "$APP" ]; then
    # 本地没有 → 从 GitHub Release 取最新版资产（RouteBar-*.zip）
    info "本地未找到 ${APP_NAME}，从 GitHub Release 下载最新版"
    WORK="$(/usr/bin/mktemp -d)"
    URL="$(/usr/bin/curl -fsL "https://api.github.com/repos/$REPO/releases/latest" \
           | /usr/bin/grep -o 'https://[^"]*\.zip' | /usr/bin/head -1 || true)"
    [ -n "$URL" ] || fail "没找到可下载的版本。请把 ${APP_NAME}（同名目录 / RouteBar-*.zip）放到本脚本同一目录后重试。"
    info "下载 $(/usr/bin/basename "$URL")"
    /usr/bin/curl -fL --progress-bar "$URL" -o "$WORK/RouteBar.zip"
    /usr/bin/ditto -x -k "$WORK/RouteBar.zip" "$WORK"
    APP="$(/usr/bin/find "$WORK" -maxdepth 3 -name "$APP_NAME" -print -quit)"
fi

if [ -z "$APP" ] || [ ! -f "$APP/Contents/MacOS/$EXEC_NAME" ]; then
    fail "没有找到可用的 ${APP_NAME}。请先运行 bash build.sh 生成，或把 ${APP_NAME}（同名目录 / RouteBar-*.zip）放到本脚本同一目录后重试。"
fi
info "源文件：$APP"

# ── 2. 安装到 /Applications ───────────────────────────────────────────
[ -w /Applications ] || fail "/Applications 不可写，请用管理员账号登录后重试"

/usr/bin/pkill -x "$EXEC_NAME" >/dev/null 2>&1 || true   # 先退出正在运行的旧版本
sleep 1

info "安装到 $DEST"
/usr/bin/ditto "$APP" "$DEST"

# ── 3. 清掉隔离标记（关键一步）───────────────────────────────────────
/usr/bin/xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true
info "已清除隔离标记（Gatekeeper 不会再要求手动放行）"

# ── 3.5 清理外来文件，修复可能被破坏的代码封套 ──────────────────────
# 本机实测：某后台程序（疑似腾讯柠檬的实时监控）会在 /Applications 里
# App 被替换时往 bundle 内塞 ".BC.T_*" 临时副本（二进制 / Info.plist /
# PkgInfo 的拷贝），残留后 codesign 校验报 "a sealed resource is missing
# or invalid"。这些名字在正常构建的 bundle 里不可能是合法内容，删掉即可。
JUNK=$(/usr/bin/find "$DEST" \( -name ".BC.*" -o -name "._*" -o -name ".DS_Store" \) 2>/dev/null)
if [ -n "$JUNK" ]; then
    printf '%s\n' "$JUNK" | while IFS= read -r f; do /bin/rm -f "$f"; done
    info "已清理 bundle 内的外来临时文件（否则签名校验会失败）"
fi

# ── 4. 启动 ───────────────────────────────────────────────────────────
/usr/bin/open "$DEST" >/dev/null 2>&1 || true
info "已启动 RouteBar（若菜单栏没有出现图标，请到「应用程序」里手动打开）"

cat <<'TIP'

使用提示：
    菜单栏会出现一个「网络」图标，点开即可添加 / 开关路由。
    修改路由需要管理员权限，首次会弹出系统授权对话框；之后约 5 分钟内
    重复操作不会再弹（macOS 的授权缓存，无需任何配置）。

注：本版本由开发者自签名、未经 Apple 公证。日后若重新拷贝
    RouteBar.app，隔离标记会再次出现，重跑本脚本即可。
TIP

if [ -n "$WORK" ]; then /bin/rm -rf "$WORK"; fi

if [ -t 0 ]; then printf '\n（按回车立即关闭，或 15 秒后自动关闭）'; read -r -t 15 _ || true; printf '\n'; fi
