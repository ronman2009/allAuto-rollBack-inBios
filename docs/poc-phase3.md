# POC 阶段 3：快照回滚操作手册

日期：2026-09-26 · 状态：**已实机验收通过**（19:49 实测：全链成功，含 ESP 回写）

## 验收记录（2026-09-26 19:49）

```
* loading modules... + nvme-keyring + nvme-auth + nvme-core + nvme + fat + vfat
* root btrfs: /dev/nvme0n1p2 (subvolid=5, RO -> /mnt/rootfs)
rollback -> 选快照 [3] -> PLAN(含 ESP writeback) -> y
* writable copy ready at @.new-restore (system still intact)
* swap done
* verified: new @ active (subvol id 276)
* ESP archive found in snapshot: esp-2026-09-26_19-23-51.tar.gz
* current ESP backed up into pre-restore snapshot
* ESP overwritten from archive
* GRUB blind-spot closed: ESP matches /boot/grub of 2026-09-26_19-23-51
ROLLBACK OK (restore) -> 2026-09-26_19-23-50
```

关键修复史：① initramfs 缺 /dev/console → 黑屏（make-cpio.py 注入设备节点）；
② NVMe/FAT/vfat 均为内核模块 → kernel-store 统一钉入；③ mkdir /mnt/esp 缺失 +
④ 拆解态检测变量误用 → 双双修复后全链通过。完整事故与教训见
[incident-01](incident-01.md)、[lessons-01](lessons-01.md)。

## 语义来源（已核对 Timeshift 源码，ref/ 目录留档）

对照 `linuxmint/timeshift` `Main.vala: restore_execute_btrfs()` 与 `Subvolume.vala: restore()`：

| Timeshift 原操作 | 救援系统实现 | 一致性 |
|---|---|---|
| `mv @ → timeshift-btrfs/snapshots/<now>/@`（pre-restore 备份） | 同（busybox mv = rename） | ✅ |
| 写 info.json（live=true、tags=ondemand、comments=Before restoring …、subvolumes 数组） | 同（字段逐一对齐 Snapshot.vala write_control_file/update_control_file） | ✅ |
| `btrfs subvolume snapshot <snap>/@ /@`（从 ro 快照建可写副本落位） | 同（btrfs-progs musl 版已内置） | ✅ |
| 不碰 @home | 同（白名单） | ✅ |

## 上机测试

```bash
cd /home/ronman/WorkBuddy/allAuto-rollBack-inBios/poc/scripts
sudo ./install-phase1.sh --bootnext && sudo reboot
```

进救援 shell 后：

```
rollback                          # 列出快照 → 输入快照名（如 2026-09-19_13-53-43）
                                  # 阅读执行计划 → 输入 yes 确认
reboot                            # 回主系统
```

## 验收标准

1. 救援环境内回滚全程无报错，输出 pre-restore 快照名。
2. 重启回主系统后：`sudo timeshift --list` 能看到新条目
   （comments = "Before restoring '<所选快照>'"，tags = ondemand）——Timeshift 完全认可救援系统写的快照。
3. 系统正常启动（@ 已是所选快照的可写副本）。
4. （可逆性）再次进救援 `rollback <pre-restore快照名>` 能滚回原状态。

## 边界

- ~~ESP 归档回写 / NVRAM 重建~~：**ESP 回写已实现（第 9 步）**——主系统装 `install-host.sh` 后，
  pacman 事务快照与 `rescue-snapshot` 手动快照均自动携带 ESP 归档（.tar.gz），
  rollback 恢复 @ 后自动备份当前 ESP 进 pre-restore 目录并回写归档，GRUB 与 /boot/grub 同刻一致。
  NVRAM 重建仍待 manifest 落地（启动项重建）。
- 本阶段回滚仅 @ 子卷（@home 白名单排除，用户数据零风险——桌面文件属 @home，回滚不影响）。
- 回滚目标快照必须是含 `@` 子卷的 Timeshift btrfs 快照（脚本已校验）。
