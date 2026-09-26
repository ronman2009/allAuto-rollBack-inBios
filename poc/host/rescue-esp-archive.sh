#!/bin/sh
# ============================================================
# rescue-esp-archive.sh - ESP 寄生归档（打快照前调用）
# 把 ESP（GRUB 盲区）打包写入 @/.recovery/，随后触发的 Timeshift
# btrfs 快照会把它与 @ 原子锁定在同一时刻；retention 清理自动带走。
# 归档格式 .tar.gz：救援系统 busybox 原生可解，零新依赖。
# ============================================================
set -eu
[ "$(id -u)" -eq 0 ] || { echo "need root"; exit 1; }
ESP=/boot/efi
REC=/.recovery
TS=$(date +%Y-%m-%d_%H-%M-%S)

mkdir -p "$REC"
tar czf "$REC/esp-$TS.tar.gz" -C "$ESP" .

# manifest：记录该时刻 GRUB/内核版本与启动项，救援系统回滚时校验与重建用
{
    echo "{"
    echo "  \"created\": \"$(date +%s)\","
    echo "  \"esp_archive\": \"esp-$TS.tar.gz\","
    echo "  \"kernel_running\": \"$(uname -r)\","
    echo "  \"grub_pkg\": \"$(pacman -Q grub 2>/dev/null | awk '{print $2}')\","
    echo "  \"timestamp\": \"$TS\""
    echo "}"
} > "$REC/manifest-$TS.json"

# 只保留最近 5 份（防止 /.recovery 无限增长）
ls -1t "$REC"/esp-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
ls -1t "$REC"/manifest-*.json 2>/dev/null | tail -n +6 | xargs -r rm -f

echo "* ESP archived -> $REC/esp-$TS.tar.gz ($(du -h "$REC/esp-$TS.tar.gz" | cut -f1))"
