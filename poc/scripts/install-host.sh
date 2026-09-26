#!/bin/sh
# ============================================================
# install-host.sh - 安装主系统侧组件（需 root: sudo ./install-host.sh）
# 1) /usr/local/bin/rescue-esp-archive.sh   ESP 归档脚本
# 2) /usr/share/libalpm/hooks/00-rescue-esp-archive.hook
#    pacman 事务前触发（文件名排序在 00-timeshift-autosnap.hook 之前，
#    保证 autosnap 的 timeshift --create 快照携带 ESP 归档）
# 3) /usr/local/bin/rescue-snapshot         手动打整体快照的标准入口
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

== 完成。用法 ==
  手动整体快照:  sudo rescue-snapshot --comments "..." --tags O
  自动:          pacman 升降级时 autosnap 快照自动携带 ESP 归档
  验证:          ls /.recovery/  应看到 esp-*.tar.gz
== 救援系统回滚时将自动回写对应快照的 ESP 归档（GRUB 盲区闭环）==
EOF
