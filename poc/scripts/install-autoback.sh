#!/bin/sh
# ============================================================
# install-autoback.sh - autoBack 一键安装
#   1) 安装 GUI/CLI（autoback / autoback-gtk / desktop / launcher）
#   2) 安装救援系统构建套件到 /usr/share/autoback/rescue
#      （TUI 面板 "Rescue System" 的三个按钮从这里找脚本）
#   3) 安装 ESP 寄生归档组件（pacman hook + rescue-snapshot）
# 前提：vendor/timeshift/build 已由 meson/ninja 构建完成
# ============================================================
set -eu
[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }

BASE="$(cd "$(dirname "$0")/../.." && pwd)"          # 仓库根
TS="$BASE/vendor/timeshift"
RESCUE_DIR=/usr/share/autoback/rescue

echo "=== 1/4 安装 autoBack GUI/CLI ==="
ninja -C "$TS/build" install

echo "=== 2/4 安装救援系统构建套件 -> $RESCUE_DIR ==="
mkdir -p "$RESCUE_DIR"
# 整树拷贝（保留脚本依赖的目录结构），排除构建产物与第三方留档
for item in scripts initramfs kernel-store; do
    rm -rf "$RESCUE_DIR/$item"
    cp -r "$BASE/poc/$item" "$RESCUE_DIR/$item"
done
# 清理不需要的中间物
rm -rf "$RESCUE_DIR/initramfs/lib" "$RESCUE_DIR/initramfs/modules" \
       "$RESCUE_DIR/initramfs/bin/busybox" "$RESCUE_DIR/initramfs/bin/btrfs" 2>/dev/null || true
chmod 755 "$RESCUE_DIR"/scripts/*.sh 2>/dev/null || true
echo "  已安装: scripts/ initramfs/(源) kernel-store/"

echo "=== 3/4 安装 ESP 寄生归档组件 ==="
sh "$RESCUE_DIR/scripts/install-host.sh"

echo "=== 4/4 刷新桌面数据库 ==="
update-desktop-database 2>/dev/null || true

cat <<'EOF'

============================================================
  autoBack 安装完成
    菜单/终端: autoback-gtk   （CLI: autoback）
    救援面板 : 主窗口工具栏 "Rescue System"
      1. Build Rescue Image  = release-pin + 构建镜像
      2. Install to ESP      = 写 ESP + 注册固件启动项
      3. Check Status        = 检查安装状态
  注: Build 前请确认 kernel-store 与当前内核匹配
      （主系统升级内核后重跑 release-pin + Build）
============================================================
EOF
