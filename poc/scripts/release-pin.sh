#!/bin/sh
# ============================================================
# release-pin.sh - 一次性固化内核与 NVMe 模块到 kernel-store
# 之后救援镜像重建永远使用 kernel-store，与 Manjaro 升级完全解耦。
# 更新救援内核 = 手动重跑本脚本（唯一升级途径，符合"写死不可升级"）
# ============================================================
set -eu
POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STORE="$POC_DIR/kernel-store"
KVER="$(uname -r)"
VMLINUZ="/boot/vmlinuz-7.1-x86_64"

mkdir -p "$STORE/modules"

# 1. 钉内核
cp "$VMLINUZ" "$STORE/vmlinuz"
echo "$KVER" > "$STORE/RESCUE_KVER"
echo "* 内核已钉入: $VMLINUZ ($KVER)"

# 2. 钉 NVMe 模块（解压为裸 .ko，与 initramfs 用法一致）+ FAT/vfat（ESP 挂载）
for m in nvme-keyring nvme-auth nvme-core nvme; do
    src="/lib/modules/$KVER/kernel/drivers/nvme/common/$m.ko.zst"
    [ -f "$src" ] || src="/lib/modules/$KVER/kernel/drivers/nvme/host/$m.ko.zst"
    [ -f "$src" ] || src=$(modinfo -n "$m" 2>/dev/null)
    zstd -d -q -f "$src" -o "$STORE/modules/$m.ko"
    echo "  + $m.ko"
done
for m in fat vfat; do
    src=$(modinfo -n "$m" 2>/dev/null)
    zstd -d -q -f "$src" -o "$STORE/modules/$m.ko"
    echo "  + $m.ko"
done

# 3. 自检: vermagic 一致性（模块与内核必须同版本）
for m in "$STORE"/modules/*.ko; do
    v=$(strings "$m" | grep -m1 '^vermagic=' || true)
    case "$v" in
        *"$KVER"*) ;;
        *) echo "!! vermagic 不匹配: $m -> $v"; exit 1 ;;
    esac
done
echo "* vermagic 全部匹配 $KVER"
echo "* kernel-store 就绪: $STORE"
ls -lh "$STORE" "$STORE/modules"
