#!/bin/bash
#
# RouteBar 更新替换助手
#
# 由主程序在下载、解压、校验完新版本之后启动，**独立于主进程**运行 ——
# 正在运行的 App 无法安全替换自己（bundle 正被自身占用，直接覆盖会得到半损坏的产物）。
#
# 流程：等主进程退出 → 改名备份旧版 → ditto 写入新版 → 清隔离标记 → 启动。
# 任何一步失败都回滚到旧版并重新打开，保证用户手上始终有一个能用的 App。
#
# 参数：
#   $1 新版本 .app 的路径
#   $2 目标 .app 的路径（当前正在运行的 bundle）
#   $3 主进程 PID（等它退出后再动手）
#
set -uo pipefail

NEW_APP="${1:-}"
DEST="${2:-}"
PID="${3:-}"

log() { printf '[%s] %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if [ -z "${NEW_APP}" ] || [ -z "${DEST}" ] || [ -z "${PID}" ]; then
    log "参数不完整（需要：新版本路径 目标路径 主进程 PID）"
    exit 1
fi

log "等待主进程 ${PID} 退出"
waited=0
while /bin/kill -0 "${PID}" 2>/dev/null; do
    /bin/sleep 0.4
    waited=$((waited + 1))
    if [ "${waited}" -ge 75 ]; then
        log "等待超时（约 30 秒），放弃替换，旧版本保持不动"
        exit 1
    fi
done
/bin/sleep 0.6      # 留一点时间让文件句柄彻底释放

[ -d "${NEW_APP}" ] || { log "新版本不存在：${NEW_APP}"; exit 1; }
[ -d "${DEST}" ] || { log "目标不存在：${DEST}"; exit 1; }

BACKUP="${DEST}.old-$$"
log "备份旧版本 → ${BACKUP}"
if ! /bin/mv "${DEST}" "${BACKUP}"; then
    log "备份失败，放弃替换"
    exit 1
fi

if /usr/bin/ditto "${NEW_APP}" "${DEST}"; then
    /usr/bin/xattr -dr com.apple.quarantine "${DEST}" >/dev/null 2>&1 || true
    log "替换成功，删除备份"
    /bin/rm -rf "${BACKUP}"
else
    log "写入失败，回滚到旧版本"
    /bin/rm -rf "${DEST}"
    if /bin/mv "${BACKUP}" "${DEST}"; then
        log "已回滚到旧版本"
    else
        log "回滚失败，旧版本保留在 ${BACKUP}"
    fi
fi

log "启动 RouteBar"
/usr/bin/open "${DEST}" >/dev/null 2>&1 || log "启动失败，请手动打开 ${DEST}"
log "结束"
