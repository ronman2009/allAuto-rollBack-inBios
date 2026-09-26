#!/bin/sh
# ============================================================
# install-host.sh - 安装主系统侧组件（需 root: sudo ./install-host.sh）
# 1) /usr/local/bin/rescue-esp-archive.sh   ESP 归档脚本
# 2) /usr/share/libalpm/hooks/00-rescue-esp-archive.hook
#    pacman 事务前触发（排序在 00-timeshift-autosnap.hook 之前）
# 3) /usr/local/bin/rescue-snapshot         手动打整体快照的入口
# 兼容两种布局：开发布局(../host) 与 安装布局(./host)
# 卸载: 删除上述三个文件即可
# ============================================================
set -eu
[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC=""
[ -d "$SELF_DIR/../host" ] && SRC="$SELF_DIR/../host"
[ -d "$SELF_DIR/host" ] && SRC="$SELF_DIR/host"
[ -n "$SRC" ] || { echo "!! 找不到 host/ 组件目录"; exit 1; }

install -m 755 "$SRC/rescue-esp-archive.sh" /usr/local/bin/rescue-esp-archive.sh
install -m 644 "$SRC/00-rescue-esp-archive.hook" /usr/share/libalpm/hooks/00-rescue-esp-archive.hook
install -m 755 "$SRC/rescue-snapshot" /usr/local/bin/rescue-snapshot

echo "* 已安装 3 个组件"
echo "* 执行顺序确认（rescue 应在 timeshift-autosnap 之前）:"
ls -1 /usr/share/libalpm/hooks/ | grep -E '^00'

echo "* 验证归档功能:"
/usr/local/bin/rescue-esp-archive.sh
ls -lh /.recovery/
cat <<'EOF'

============================================================
  autoBack 主系统侧组件安装完成
    整体快照:  sudo rescue-snapshot --comments "..." --tags O
    自动:      pacman 事务快照自动携带 ESP 归档
    验证:      ls /.recovery/
============================================================
EOF
