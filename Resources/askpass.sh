#!/bin/bash
# RouteBar SUDO_ASKPASS helper
# 被 sudo -A 调用，用于在 GUI 环境下提供密码。
#
# 当 /etc/pam.d/sudo 配置了 pam_tid.so 时，
# sudo 本身会弹出 Touch ID 指纹验证（由 PAM 模块处理），
# 本脚本仅在指纹不可用时作为密码回退方案被调用。
#
# 用法：sudo -A -S <command>   （环境变量 SUDO_ASKPASS 指向本脚本）

# 尝试用 Python 弹出原生密码对话框（比 osascript 更可靠）
try_python_dialog() {
    local python3
    python3="$(command -v python3 2>/dev/null)" || return 1

    "$python3" -c "
import subprocess, sys
try:
    import tkinter as tk
    from tkinter import simpledialog
    root = tk.Tk()
    root.withdraw()
    root.attributes('-topmost', True)
    pw = simpledialog.askstring(
        'RouteBar',
        '请输入密码以修改路由表\n（已配置 Touch ID 可直接按指纹）',
        show='*',
        parent=root
    )
    if pw:
        print(pw)
    sys.exit(0 if pw else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

# 回退：使用 osascript 文本对话框
try_osascript_dialog() {
    local result
    result=$(osascript -e '
Tell application "System Events"
    display dialog "RouteBar 需要管理员权限来修改路由表" & ¬
        default answer "" & ¬
        with hidden answer & ¬
        giving up after 300 & ¬
        with title "RouteBar"
end tell
' 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$result" ]; then
        # 提取 text returned:xxx 格式中的密码
        echo "$result" | sed -n 's/.*text returned:[[:space:]]*\(.*\)/\1/p'
        return 0
    fi
    return 1
}

# 主逻辑
if pw=$(try_python_dialog); then
    [ -n "$pw" ] && echo "$pw" && exit 0
fi

if pw=$(try_osascript_dialog); then
    [ -n "$pw" ] && echo "$pw" && exit 0
fi

# 全部失败
exit 1
