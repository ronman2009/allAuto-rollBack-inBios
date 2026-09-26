#!/bin/bash
# ============================================================
# check-snapshot.sh - 快照完整性检查（挂盘根只读检查）
# 用法:
#   sudo ./check-snapshot.sh              # 检查最新快照
#   sudo ./check-snapshot.sh <快照名>      # 检查指定快照
#   sudo ./check-snapshot.sh <快照名> --deep  # 附带 tar 归档内容抽查
# 检查项: 目录结构 / info.json / @ 系统完整性 / ESP 归档 / GRUB 抽查
# ============================================================
set -u
[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }
DEV=/dev/nvme0n1p2
MNT=/mnt/rootcheck

SNAP="${1:-}"
DEEP=0
[ "${2:-}" = "--deep" ] && DEEP=1

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount -o subvolid=5,ro "$DEV" "$MNT"
UM=1
mountpoint -q "$MNT" || UM=0

SNAP_DIR=$MNT/timeshift-btrfs/snapshots
if [ -z "$SNAP" ]; then
    SNAP=$(ls -1t "$SNAP_DIR" | head -1)
fi
D="$SNAP_DIR/$SNAP"
[ -d "$D" ] || { echo "!! 快照不存在: $SNAP"; [ "$UM" = 1 ] && umount "$MNT"; exit 1; }

PASS=0; FAIL=0
ok()  { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== 检查快照: $SNAP ==="
echo
echo "-- 1. 结构 --"
[ -d "$D/@" ] && ok "@ 子卷存在" || bad "@ 子卷缺失"
[ -f "$D/info.json" ] && ok "info.json 存在" || bad "info.json 缺失"

echo
echo "-- 2. info.json 元数据 --"
if [ -f "$D/info.json" ]; then
    grep -q '"type": "btrfs"' "$D/info.json" && ok "type=btrfs" || bad "type 非 btrfs"
    grep -q '"sys-uuid"' "$D/info.json" && ok "sys-uuid 记录" || bad "sys-uuid 缺失"
    grep -q '"tags"' "$D/info.json" && ok "tags 记录 ($(grep -o '"tags": "[^"]*"' "$D/info.json" | cut -d'"' -f4))" || bad "tags 缺失"
fi

echo
echo "-- 3. @ 系统完整性 --"
[ -f "$D/@/etc/os-release" ] && ok "etc/os-release" || bad "etc/os-release 缺失"
[ -d "$D/@/boot/grub" ] && ok "boot/grub (GRUB 配置+模块)" || bad "boot/grub 缺失"
[ -f "$D/@/boot/grub/grub.cfg" ] && ok "grub.cfg" || bad "grub.cfg 缺失"
[ -f "$D/@/boot/vmlinuz-"* ] && ok "内核 vmlinuz" || bad "内核缺失"
[ -d "$D/@/usr/lib/modules" ] && ok "内核模块目录" || bad "模块目录缺失"
[ -f "$D/@/etc/fstab" ] && ok "fstab" || bad "fstab 缺失"

echo
echo "-- 4. ESP 归档（GRUB 盲区）--"
if ls "$D/@/.recovery/"esp-*.tar.gz >/dev/null 2>&1; then
    ARC=$(ls -1t "$D/@/.recovery/"esp-*.tar.gz | head -1)
    ok "归档存在: $(basename "$ARC") ($(du -h "$ARC" | cut -f1))"
    GRUB_CNT=$(tar tzf "$ARC" 2>/dev/null | grep -ci grub)
    EFI_CNT=$(tar tzf "$ARC" 2>/dev/null | grep -ci "\.efi$")
    [ "$GRUB_CNT" -gt 0 ] && ok "归档内 grub 相关文件: $GRUB_CNT 个" || bad "归档内无 grub 文件"
    [ "$EFI_CNT" -gt 0 ] && ok "归档内 .efi 二进制: $EFI_CNT 个" || bad "归档内无 .efi"
    if [ "$DEEP" = 1 ]; then
        echo "  -- 归档内容清单 (前 20) --"
        tar tzf "$ARC" | head -20 | sed 's/^/    /'
    fi
else
    bad "无 ESP 归档（该快照早于 autoBack，或归档时失败）"
fi

echo
echo "-- 5. 用户数据豁免（设计约定）--"
[ ! -d "$D/@home" ] && ok "快照不含 @home（用户数据不在回滚范围）" || echo "  [INFO] 含 @home"

echo
echo "==============================================="
echo "  结果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "  该快照可用于回滚" || echo "  该快照存在缺失项，慎用"
echo "==============================================="

[ "$UM" = 1 ] && umount "$MNT" && echo "* 已卸载 $MNT"
