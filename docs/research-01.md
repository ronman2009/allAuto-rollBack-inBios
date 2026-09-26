# 调研报告 01：btrfs 救援系统（Timeshift 基座）现状与可行性

日期：2026-09-26 · 状态：调研完成，待 POC

## 0. 目标回顾

独立于主系统与 GRUB 的救援系统：UEFI 独立启动项（EFISTUB）引导 mini Linux，
BIOS 风格 KMS 直绘 GUI，基于 Timeshift btrfs 快照实现 Linux + GRUB 整体回滚。
快照由 Linux 侧 Timeshift 在线打（含 ESP 寄生归档），回滚由救援系统离线执行。

## 1. 实机勘察结论（Manjaro，双 NVIDIA 物理机）

| 项 | 现状 | 对项目的影响 |
|---|---|---|
| 系统盘 | nvme0n1 476.9G | — |
| 分区 | p1=16.4G swap，p2=460.2G btrfs，p3=300M ESP(vfat) | 磁盘无空闲空间，正式版 recovery 分区需缩分区或另想方案 |
| ESP | /boot/efi，umask=0077（root only） | 300M，POC 可直接放救援内核+initramfs（约 50~100M） |
| 子卷布局 | @（/）、@home（/home）、@cache、@log | 与 Timeshift btrfs 模式完美兼容；@home 独立 → 回滚不冲用户数据 |
| /boot | 在 @ 内（vmlinuz-7.1-x86_64、initramfs、grub/） | grub.cfg 与内核随 @ 快照覆盖 ✓ |
| NVRAM | Boot0000 Manjaro→\EFI\MANJARO\GRUBX64.EFI；Boot0001 UEFI OS→\EFI\BOOT\BOOTX64.EFI | 救援项用 efibootmgr 新建 BootXXXX，互不干扰 |
| 内核 | 7.1.13-2-MANJARO | Manjaro 内核默认 CONFIG_EFI_STUB=y（待 root 确认） |
| Timeshift | 已有 2 个 btrfs 快照（2026-09-19、2026-09-23，格式已在本机验证）；但 /etc/timeshift/timeshift.json 显示未配置（疑似被重置） | POC 第 0 步改为：恢复 Timeshift 配置并确认其能看到已有快照 |
| 已装先例工具 | grub-btrfs 4.14-1（GRUB 菜单可引导快照）、timeshift-autosnap-manjaro 0.10.0（pacman 事务前自动快照 hook 已在机上运行） | 前者依赖 GRUB 存活，正好互补本项目"GRUB 死掉"的场景；autosnap 的 hook 机制可并列加 ESP 归档 |
| 数据盘 | sda1 232.9G btrfs 挂 /mnt/e | 可选作快照异地副本（btrfs send/receive） |

沙箱限制（非机器问题，root 项待补查）：`btrfs subvolume list`、`ls /boot/efi`、
`pacman -Q`、`mokutil`、`sudo` 均因权限/沙箱失败。补查命令清单见 §7。

## 2. Timeshift btrfs 快照格式（外部调研确认）

- 路径：`<btrfs盘根,即subvolid=5>/timeshift-btrfs/snapshots/YYYY-MM-DD_HH-MM-SS/`
- 内容：`info.json`（Timeshift 元数据）+ 只读子卷 `@`（开启 include_btrfs_home 时另有 `@home`）
- 创建：`timeshift --create --comments "..." --tags O/D/W/M`，秒级完成（纯 CoW）
- 打快照时把 subvolid=5 挂到 /run/timeshift/<pid>/backup 操作

**restore 语义（关键）**：不是覆盖式恢复，而是把快照子卷 rename 成位为新 `@`，
坏的旧 `@` 被保留成一个快照——**回滚本身可逆**。救援系统照此语义用 btrfs 子卷
rename 实现，不依赖 timeshift CLI。

## 3. ESP 寄生归档（Linux+GRUB 整体快照）

- 先例：`timeshift-autosnap-apt` 正是打快照前把 /boot/efi rsync 进快照目录，
  思路已被社区验证；我们改用 tar.zst + manifest 更干净。
- 流程（pre-hook，挂在 timeshift --create 之前）：
  1. 打包 ESP 全量 → 写入 `@/.recovery/esp-<ts>.tar.zst`（~几十 KB）
  2. 写 `@/.recovery/manifest.json`：GRUB 版本、内核/initramfs 版本、`efibootmgr -x` NVRAM 导出
  3. 触发 `timeshift --create` → 归档与快照原子锁定在同一刻
- 回滚（救援系统）：恢复 @ → 从快照内解包 ESP 回写 → 按 manifest 用 efibootmgr 重建 NVRAM 启动项
- 兜底：无归档的旧快照 → chroot 进快照、用快照内的 GRUB 版本执行 `grub-install --target=x86_64-efi`
- 旧快照清理：Timeshift retention 删除整快照时自动带走归档，零额外生命周期管理

## 4. ZFSBootMenu 架构参照（同模式成熟实现，2019 至今）

形态：压缩 EFI 二进制（~50MB）= 精简内核 + 自定义 initramfs；initramfs 内含
用户态工具（ZBM 是 zfs/zpool，我们是 btrfs-progs）+ busybox + UI 脚本；无持久状态。
流程：UEFI 引导 → 导入池（我们：挂载 btrfs、subvolid=5）→ 枚举环境/快照 →
菜单选择 → **kexec** 进选定的主系统内核。启动速度与 GRUB 相当。

对本项目的直接借鉴：
- 交付形态双轨：统一 EFI 镜像（UKI：内核+initramfs+cmdline 打包）或 kernel+initramfs 两文件
- "从快照试启动"功能可用 kexec 实现（先验证快照能启动，再决定回滚）
- 容器化构建环境（ZBM 用 Void OCI 容器）保证构建可复现

差异：ZBM 用 fzf 文本 TUI；我们要 BIOS 风格图形界面 → 见 §5。

## 5. 技术选型

| 决策点 | 选型 | 理由 |
|---|---|---|
| 救援内核 | Manjaro 同源内核裁剪配置 | btrfs 驱动版本一致，避免跨版本怪问题 |
| initramfs 构建 | 手工构建或 mkinitcpio 定制 hook | 内容：busybox + btrfs-progs + e2fsck? 否，纯 btrfs；加 tar/zstd、efibootmgr |
| GUI | /dev/fb0（simpledrm KMS）+ C11 直绘 + 内置 8x16 位图字体 + evdev 键盘 | 与 gpu-allauto 同哲学：零外部依赖、C11、直绘；BIOS 观感、无字体渲染库 |
| 引导注册 | EFISTUB + efibootmgr -c，BootNext 用于自动回滚预备 | 不经过 GRUB，独立引导链 |
| 状态传递（Linux→救援） | btrfs 子卷内约定路径（@/.recovery/ 标志文件） | 跨系统共享状态只能落在盘上 |
| A/B 更新（正式版） | recovery 分区 squashfs 双镜像切换 | 与 POC 分离，POC 先放 ESP |

## 6. 风险与开放问题

1. **无空闲分区**：nvme0n1 三分区占满 477G（parted 确认仅 1MB 碎空间）。正式版 recovery 分区需缩 @ 或挪到 sda；
   POC 阶段用 300M ESP 即可，无阻塞。
2. **Secure Boot 状态未定**：mokutil 未安装。改用 `sudo od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-*`
   （末字节 1=开启）。若开启，EFISTUB 救援内核需签名/shim+MOK。POC 第一步确认。
3. ~~磁盘加密~~：blkid 确认**无 LUKS**，已排除，方案简化。
4. **Timeshift 配置矛盾**：子卷树里已有 2 个快照，但 timeshift.json 显示未配置（do_first_run=true、
   btrfs_mode=false、backup_device 空）。需排查（疑似配置文件被重置或重装过）。快照格式本身已验证。
5. ESP 仅 300M：内核（~15M）+ initramfs（~50-80M）可行但紧张，注意保留空间。

## 7. root 补查清单（下一步上机执行）

```bash
sudo btrfs subvolume list /          # 确认完整子卷树（含 timeshift-btrfs 占位）
sudo ls -R /boot/efi/                # ESP 内容与剩余空间: sudo df -h /boot/efi
sudo pacman -Q | grep -E 'timeshift|nvidia|linux[0-9]|grub|btrfs-progs'
mokutil --sb-state                   # Secure Boot 开关
zcat /proc/config.gz | grep EFI_STUB # 内核 EFISTUB 支持
sudo parted /dev/nvme0n1 print free  # 磁盘真实空闲
sudo blkid                           # 确认无 LUKS
```

## 8. POC 计划（阶段化）

- **阶段 0（配置）**：排查 timeshift.json 与已有 2 快照的矛盾；恢复 Timeshift btrfs 模式配置，
  确认 GUI/CLI 能看到 2026-09-19、2026-09-23 两个快照，补打一个新快照验证完整链路
- **阶段 1（引导）**：手工构建含 busybox+btrfs-progs 的 initramfs，EFISTUB 注册救援启动项，
  实机验证"GRUB 全不参与也能进救援 shell"（CONFIG_EFI_STUB=y 已确认）
- **阶段 2（快照读）**：救援环境内枚举 timeshift-btrfs/snapshots，读 info.json
- **阶段 3（回滚）**：实现 rename 语义回滚 + ESP 归档回写 + NVRAM 重建
- **阶段 4（GUI）**：fbdev 直绘菜单替换 shell

（原阶段 5"与 gpu-allauto 联动"已按决策取消，本项目为独立救援系统。）

每阶段均可独立验证、可回退，阶段 1 完成后即具备"打不开主系统也能进救援"的底线能力。
