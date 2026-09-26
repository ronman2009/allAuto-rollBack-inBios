#!/bin/sh
# ============================================================
# install-phase1.sh  ——  需 root: sudo ./install-phase1.sh [--bootnext]
# 把 POC 救援 UKI 写入 ESP 并注册 UEFI 启动项。
# 行为是"纯新增"：不改 Manjaro 原有启动项，不动 GRUB。
# [--bootnext] 额外设置下次一次性引导进救援（原顺序不变，重启自动还原）
# ============================================================
set -eu

[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }

DISK=/dev/nvme0n1
PART=3
ESP=/boot/efi
SRC=/home/ronman/WorkBuddy/allAuto-rollBack-inBios/poc/build/recovery.efi
DEST_DIR="$ESP/EFI/recovery"
DEST="$DEST_DIR/recovery.efi"
LABEL="BTRFS Rescue POC"

[ -f "$SRC" ] || { echo "缺 $SRC，先跑 build-initramfs.sh"; exit 1; }

# 1. 备份当前 NVRAM 启动项快照（出问题可对照恢复）
efibootmgr -v > /var/tmp/efibootmgr-backup-$(date +%Y%m%d-%H%M%S).txt
echo "* NVRAM 启动项已备份到 /var/tmp/efibootmgr-backup-*.txt"

# 2. 写入 ESP（新增目录，约 18MB）
mkdir -p "$DEST_DIR"
install -m 755 "$SRC" "$DEST"
cmp "$SRC" "$DEST" || { echo "!! ESP 写入校验失败（FAT 可能损坏），中止"; exit 1; }
echo "* 已写入 $DEST（cmp 校验通过）"
df -h "$ESP" | tail -1

# 3. 注册启动项（幂等：先删除同名旧条目再创建，避免重复堆积）
OLD=$(efibootmgr 2>/dev/null | grep -F "$LABEL" | cut -c5-8 || true)
for n in $OLD; do
    efibootmgr -b "$n" -B >/dev/null
    echo "* 已清理旧启动项 Boot$n"
done
efibootmgr --create --disk "$DISK" --part "$PART" \
    --label "$LABEL" --loader '\EFI\recovery\recovery.efi' >/dev/null
BOOTNUM=$(efibootmgr | grep "$LABEL" | head -1 | cut -c5-8)
echo "* 已注册启动项 Boot$BOOTNUM (Manjaro 原有启动项未改动)"

# 4. 可选：下次一次性引导进救援
if [ "${1:-}" = "--bootnext" ]; then
    efibootmgr --bootnext "$BOOTNUM"
    echo "* 已设置 BootNext=$BOOTNUM：下次重启直接进救援，之后自动还原"
fi

cat <<EOF

== 完成。测试方法 ==
  1) 重启，按主板启动菜单键(通常是 F8/F11/F12)
  2) 选择 "BTRFS Rescue POC"
  3) 预期看到救援横幅 + btrfs 根挂载成功 + 快照列表 + 救援 shell
  4) shell 里输入 reboot -f 可回主系统

== 回退方法（完全卸载本 POC）==
  efibootmgr -b $BOOTNUM -B      # 删除 NVRAM 启动项
  rm -rf $DEST_DIR               # 删除 ESP 内文件
EOF
