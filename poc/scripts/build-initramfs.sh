#!/bin/sh
# ============================================================
# build-initramfs.sh - 组装 POC 救援镜像（阶段 1）
# 产物: poc/build/initramfs.cpio.gz  +  poc/build/recovery.efi (UKI)
# 依赖: 系统 /boot/vmlinuz-7.1-x86_64, systemd-stub, objcopy, cpio
# busybox 静态二进制来源: Alpine 3.22 busybox-static (musl, 全静态)
# ============================================================
set -eu
POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$POC_DIR/build"
ROOT_UUID="d505eb2e-6552-43d0-aa7a-529d4e046abd"   # nvme0n1p2
KERNEL="/boot/vmlinuz-7.1-x86_64"
STUB="/usr/lib/systemd/boot/efi/linuxx64.efi.stub"

mkdir -p "$BUILD" "$POC_DIR/initramfs/bin" \
         "$POC_DIR/initramfs/dev" "$POC_DIR/initramfs/etc" \
         "$POC_DIR/initramfs/mnt/rootfs" "$POC_DIR/initramfs/proc" \
         "$POC_DIR/initramfs/sys" "$POC_DIR/initramfs/tmp"

# 0. rollback 脚本防线自检: set -u 禁未定义变量 + 关键工具绝对路径（16:11 事故防线）
grep -q "set -u" "$POC_DIR/initramfs/bin/rollback" 2>/dev/null \
    || { echo "!! 自检失败: rollback 缺 set -u 防线"; exit 1; }
grep -q "BTRFS=/bin/btrfs" "$POC_DIR/initramfs/bin/rollback" 2>/dev/null \
    || { echo "!! 自检失败: rollback 缺 BTRFS 定义（16:11 事故根因）"; exit 1; }
grep -q "HARD GATE" "$POC_DIR/initramfs/bin/rollback" 2>/dev/null \
    || { echo "!! 自检失败: rollback 缺 preflight 硬门禁"; exit 1; }

# 1. busybox 静态二进制就位
if [ ! -x "$POC_DIR/initramfs/bin/busybox" ]; then
    [ -f "$POC_DIR/extract/busybox/bin/busybox.static" ] || {
        echo "缺 busybox.static，请先解包 dl/busybox-static-*.apk"; exit 1; }
    cp "$POC_DIR/extract/busybox/bin/busybox.static" "$POC_DIR/initramfs/bin/busybox"
    chmod 755 "$POC_DIR/initramfs/bin/busybox"
fi
chmod 755 "$POC_DIR/initramfs/init"

# 2. 内核与 NVMe 模块：release 模式 = 只认 kernel-store（写死，与 Manjaro 升级解耦）
STORE="$POC_DIR/kernel-store"
if [ ! -f "$STORE/RESCUE_KVER" ]; then
    echo "!! kernel-store 未初始化——先跑一次: scripts/release-pin.sh"
    exit 1
fi
KVER=$(cat "$STORE/RESCUE_KVER")
KERNEL="$STORE/vmlinuz"
echo "* release 模式: 固化内核 $KVER (kernel-store)"
mkdir -p "$POC_DIR/initramfs/modules"
for m in nvme-keyring nvme-auth nvme-core nvme; do
    [ -f "$STORE/modules/$m.ko" ] || { echo "!! 缺 $STORE/modules/$m.ko"; exit 1; }
    cp "$STORE/modules/$m.ko" "$POC_DIR/initramfs/modules/$m.ko"
done
echo "* nvme 模块已就位 (vermagic $KVER, 与 $STORE/vmlinuz 绑定)"

# 2b. reboot/poweroff 对齐传统语义（busybox reboot 无 -f 参数时无效）
cat > "$POC_DIR/initramfs/bin/reboot" <<'EOF'
#!/bin/busybox sh
exec /bin/busybox reboot -f "$@"
EOF
cat > "$POC_DIR/initramfs/bin/poweroff" <<'EOF'
#!/bin/busybox sh
exec /bin/busybox poweroff -f "$@"
EOF
chmod 755 "$POC_DIR/initramfs/bin/reboot" "$POC_DIR/initramfs/bin/poweroff"
[ -f "$POC_DIR/initramfs/bin/rollback" ] && chmod 755 "$POC_DIR/initramfs/bin/rollback"

# 3. cpio.gz —— 用 make-cpio.py 构造，注入 /dev/console 等设备节点
#    （GNU cpio + mknod 需要 root；无 /dev/console 会导致 init 无 stdio 黑屏假死）
python3 "$POC_DIR/scripts/make-cpio.py" "$POC_DIR/initramfs" "$BUILD/initramfs.cpio"
gzip -9 -c "$BUILD/initramfs.cpio" > "$BUILD/initramfs.cpio.gz"

# 3. UKI: 按 ArchWiki《Unified kernel image#Manually》现行流程打包
cp "$KERNEL" "$BUILD/vmlinuz-rescue"
printf 'NAME=BTRFS Rescue POC\nVERSION=0.1\nID=btrfs-rescue\nPRETTY_NAME="BTRFS Rescue POC"\n' \
    > "$BUILD/osrel.txt"
printf 'console=tty1 loglevel=4\n' > "$BUILD/cmdline.txt"
#    关键点1: 偏移从 stub 自身节区末尾动态计算并按 SectionAlignment 对齐
#    关键点2: 内核必须是最后一个节区（防原地解压覆盖后续节区）
STUB_SEC=$(objdump -h "$STUB")
align=$(objdump -p "$STUB" | awk '{ if ($1 == "SectionAlignment") {print $2} }')
align=$((16#$align))
osrel_offs=$(echo "$STUB_SEC" | awk 'NF==7 {size=strtonum("0x"$3); offset=strtonum("0x"$4)} END {print size + offset}')
osrel_offs=$((osrel_offs + align - osrel_offs % align))
cmdline_offs=$((osrel_offs + $(stat -Lc%s "$BUILD/osrel.txt")))
cmdline_offs=$((cmdline_offs + align - cmdline_offs % align))
initramfs_offs=$((cmdline_offs + $(stat -Lc%s "$BUILD/cmdline.txt")))
initramfs_offs=$((initramfs_offs + align - initramfs_offs % align))
linux_offs=$((initramfs_offs + $(stat -Lc%s "$BUILD/initramfs.cpio.gz")))
linux_offs=$((linux_offs + align - linux_offs % align))
objcopy \
    --add-section .osrel="$BUILD/osrel.txt" \
    --change-section-vma .osrel=$(printf 0x%x $osrel_offs) \
    --add-section .cmdline="$BUILD/cmdline.txt" \
    --change-section-vma .cmdline=$(printf 0x%x $cmdline_offs) \
    --add-section .initrd="$BUILD/initramfs.cpio.gz" \
    --change-section-vma .initrd=$(printf 0x%x $initramfs_offs) \
    --add-section .linux="$BUILD/vmlinuz-rescue" \
    --change-section-vma .linux=$(printf 0x%x $linux_offs) \
    "$STUB" "$BUILD/recovery.efi"

# 4. 构建自检（冗余但必须：任何一项失败即中止，防止坏镜像流入 ESP）
echo "* 构建自检..."
gzip -dc "$BUILD/initramfs.cpio.gz" | cpio -t 2>/dev/null | grep -qx "init" \
    || { echo "!! 自检失败: initramfs 缺 /init"; exit 1; }
gzip -dc "$BUILD/initramfs.cpio.gz" | cpio -t 2>/dev/null | grep -qx "bin/busybox" \
    || { echo "!! 自检失败: 缺 busybox"; exit 1; }
gzip -dc "$BUILD/initramfs.cpio.gz" | cpio -tv 2>/dev/null | grep -q "crw.*5, *1.*dev/console" \
    || { echo "!! 自检失败: 缺 /dev/console (c 5:1) —— 黑屏假死元凶"; exit 1; }
gzip -dc "$BUILD/initramfs.cpio.gz" | cpio -t 2>/dev/null | grep -qx "modules/nvme.ko" \
    || { echo "!! 自检失败: 缺 nvme 内核模块"; exit 1; }
gzip -dc "$BUILD/initramfs.cpio.gz" | cpio -t 2>/dev/null | grep -qx "bin/btrfs" \
    || { echo "!! 自检失败: 缺 btrfs-progs"; exit 1; }
gzip -dc "$BUILD/initramfs.cpio.gz" | cpio -t 2>/dev/null | grep -qx "bin/rollback" \
    || { echo "!! 自检失败: 缺 rollback"; exit 1; }
python3 "$POC_DIR/scripts/verify-uki.py" "$BUILD/recovery.efi"
echo "* 自检全部通过"

echo "== 产物 =="
ls -lh "$BUILD/initramfs.cpio.gz" "$BUILD/recovery.efi"
echo "(SB 关闭: recovery.efi 无需签名; 开启 SB 时在此追加 sbsign)"
