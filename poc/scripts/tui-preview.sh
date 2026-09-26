#!/bin/sh
# ============================================================
# tui-preview.sh - 在 Manjaro 终端直接预览 TUI（无需重启进救援系统）
# 原理: 把 btrfs 盘根(subvolid=5, 只读)临时挂到 /mnt/rootfs，
#       然后以 bash 运行 TUI 脚本（POSIX 语法，bash 完全兼容）。
# 安全: 只读挂载；预览模式下 ENTER 确认后会因缺少 /bin/rollback 而
#       停止——不会执行真实回滚。Q 退出自动恢复终端并卸载。
# 用法: sudo ./tui-preview.sh
# ============================================================
set -eu
[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TUI="$SRC/initramfs/bin/tui"
M=/mnt/rootfs
DEV=/dev/nvme0n1p2

[ -f "$TUI" ] || { echo "缺 $TUI"; exit 1; }

UM=0
if ! mountpoint -q "$M" 2>/dev/null; then
    mkdir -p "$M"
    mount -o subvolid=5,ro "$DEV" "$M"
    UM=1
    echo "* 预览挂载: $DEV (subvolid=5, RO) -> $M"
fi

echo "* 预览模式: 方向键/回车/R/S/P 可按，但不会执行真实回滚。Q 退出。"
sleep 1
# bash 运行（忽略 shebang；POSIX 语法完全兼容）；失败后恢复终端
bash "$TUI" || true
stty sane 2>/dev/null || true

if [ "$UM" = 1 ]; then
    umount "$M" && echo "* 已卸载 $M"
fi
