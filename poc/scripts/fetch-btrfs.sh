#!/bin/sh
# ============================================================
# fetch-btrfs.sh - 从 Alpine 提取 musl 动态 btrfs-progs 及全部依赖库
# 产物: poc/initramfs/bin/btrfs + poc/initramfs/lib/*.so*
# 自检: 逐一核对 btrfs 的 NEEDED 库全部就位（闭合），缺一即失败
# ============================================================
set -eu
POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DL="$POC_DIR/dl"
EX="$DL/extract/btrfs-tree"
DEST="$POC_DIR/initramfs"
BASE="https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64"

# btrfs(sbin/btrfs) 的依赖树: musl + libuuid/libblkid(libmd?) +
# eudev-libs(udev) + zlib + lzo + zstd-libs
PKGS="btrfs-progs musl libuuid libblkid libmd libeconf eudev-libs zlib lzo zstd-libs"

mkdir -p "$EX"
for p in $PKGS; do
    if [ "$p" = "zlib" ]; then
        # 目录里有 minizlib 等同名前缀包，只取 zlib 1.x 真身
        f=$(curl -s "$BASE/" | grep -oE "zlib-[0-9][^\"]*\.apk" | grep '^zlib-1\.' | sort -V | tail -1)
    else
        f=$(curl -s "$BASE/" | grep -oE "$p-[0-9][^\"]*\.apk" | sort -V | tail -1)
    fi
    [ -n "$f" ] || { echo "!! 找不到 $p 的 apk"; exit 1; }
    [ -f "$DL/$f" ] || curl -sfL -o "$DL/$f" "$BASE/$f" || { echo "!! 下载失败: $f"; exit 1; }
    tar xzf "$DL/$f" -C "$EX" 2>/dev/null || true
    echo "  + $f"
done

mkdir -p "$DEST/lib" "$DEST/bin"
cp -a "$EX/lib/ld-musl-x86_64.so.1" "$DEST/lib/" 2>/dev/null || \
    find "$EX" -name "ld-musl*" -exec cp -a {} "$DEST/lib/" \;
# 收集全部共享库（含真实文件与 symlink 目标）
find "$EX" -name "*.so*" -type f -exec cp -a {} "$DEST/lib/" \; 2>/dev/null || true
find "$EX" -name "*.so*" -type l -exec cp -a {} "$DEST/lib/" \; 2>/dev/null || true
cp "$EX/sbin/btrfs" "$DEST/bin/btrfs"
chmod 755 "$DEST/bin/btrfs"

# ---- 闭合自检: btrfs 的每个 NEEDED 都必须能在 initramfs/lib 解析 ----
MISS=0
for lib in $(objdump -p "$DEST/bin/btrfs" | awk '/NEEDED/{print $2}'); do
    if [ ! -e "$DEST/lib/$lib" ]; then
        echo "!! 缺依赖库: $lib"
        MISS=1
    fi
done
# 二级依赖闭包: 对已收集的每个库也查 NEEDED（用真实文件）
for real in $(find "$DEST/lib" -type f -name "*.so*"); do
    for lib in $(objdump -p "$real" 2>/dev/null | awk '/NEEDED/{print $2}'); do
        [ -e "$DEST/lib/$lib" ] || { echo "!! $real 缺二级依赖: $lib"; MISS=1; }
    done
done
[ "$MISS" -eq 0 ] && echo "* btrfs 依赖闭合校验: 全部通过" || exit 1
ls -lh "$DEST/bin/btrfs"
echo "* lib 总大小: $(du -sh "$DEST/lib" | cut -f1)"
