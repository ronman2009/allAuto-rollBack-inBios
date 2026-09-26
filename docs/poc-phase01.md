# POC 阶段 0 + 1 操作手册

日期：2026-09-26 · 状态：工件已构建，待上机执行（需 sudo 的两步）

## 已完成的构建（无需 root，已产出）

| 工件 | 路径 | 说明 |
|---|---|---|
| 救援 initramfs | `poc/build/initramfs.cpio.gz` (626K) | musl 静态 busybox 1.37 + rescue `/init` |
| 救援 UKI | `poc/build/recovery.efi` (18M) | Manjaro 7.1 内核 + initramfs + cmdline 单文件 .efi（systemd-stub 打包） |
| 构建脚本 | `poc/scripts/build-initramfs.sh` | 可重复构建 |
| 阶段 0 脚本 | `poc/scripts/phase0-timeshift-fix.sh` | **需 sudo** |
| 安装脚本 | `poc/scripts/install-phase1.sh` | **需 sudo** |

`/init` 行为：挂载 proc/sys/dev → 按 UUID 找 nvme0n1p2 → `subvolid=5` 挂载 btrfs 盘根 →
列出 `timeshift-btrfs/snapshots/` 下全部快照 → 落入 busybox 救援 shell。
全程不碰 GRUB、不碰 @ 子卷（只读性质操作，挂载为 rw 但不做任何写）。

## 上机步骤（按顺序）

### 步骤 A —— 阶段 0：修复 Timeshift 配置

```bash
cd /home/ronman/WorkBuddy/allAuto-rollBack-inBios/poc/scripts
sudo ./phase0-timeshift-fix.sh          # 先只验证，不打快照
```

**通过标准**：`timeshift --list` 列出 2026-09-19、2026-09-23 两个快照。
通过后可加打一个验证快照：

```bash
sudo ./phase0-timeshift-fix.sh --create
```

若 `--list` 失败：脚本已自动备份原配置（`timeshift.json.bak.*`），照提示回滚后把输出发回来。

### 步骤 B —— 阶段 1：安装救援启动项

```bash
sudo ./install-phase1.sh                # 只注册启动项
# 或（推荐首次测试用，不改变默认启动顺序）：
sudo ./install-phase1.sh --bootnext     # 下次重启一次性进救援
```

脚本会先备份 NVRAM 启动项到 `/var/tmp/efibootmgr-backup-*.txt`。
写入内容为纯新增：ESP 里新建 `EFI/recovery/recovery.efi`（18M）+ NVRAM 新条目，
Manjaro 原启动项与 GRUB 不受任何改动。

### 步骤 C —— 实机验证

`--bootnext` 路线：`sudo reboot` → 自动进救援。
手动路线：重启按启动菜单键（F8/F11/F12 看主板），选 "BTRFS Rescue POC"。

**通过标准（阶段 1）**：GRUB 完全不参与，直接看到 "BTRFS RESCUE" 横幅和救援 shell。
**通过标准（阶段 2 前置）**：自动列出 ≥2 个 Timeshift 快照名。

救援 shell 速查：
```
ls /mnt/rootfs                              # btrfs 盘根（可见 @ @home timeshift-btrfs 等）
cat /mnt/rootfs/timeshift-btrfs/snapshots/*/info.json
reboot -f                                   # 回主系统
```

## 已知边界 / 下阶段预告

- ~~救援 shell 进不去~~（2026-09-26 第四次实测：**通过**，阶段 1 达成）。
- ~~设备未找到~~：根因 = `CONFIG_BLK_DEV_NVME=m`（NVMe 驱动是模块）。v2 initramfs 已内置
  nvme-keyring/auth/core/nvme 四个裸 .ko（构建期从当前内核 /lib/modules 解压，vermagic 匹配），
  init 启动即 insmod；另加双路径设备发现（blkid UUID 命中 → 失败则逐个试探挂载并验证
  timeshift-btrfs 目录）。
- ~~reboot 语义怪~~：已加 /bin/reboot、/bin/poweroff 包装脚本（自动带 -f），用法与常规 Linux 一致。
- `can't access tty; job control turned off`：已改 `setsid -c` 接管控制台，job control 正常。
- **阶段 4 界面方向（用户已确认）**：先做 ANSI 全屏 TUI 快照菜单（ZFSBootMenu 同款哲学：
  fzf 风格上下键选择快照→执行回滚），shell 级实现、零依赖；rEFInd 式 fbdev 图形直绘
  作为正式版演进目标。
- 阶段 3 回滚前需解决 btrfs-progs 二进制（musl-gcc 自编译静态版，或捆绑 Alpine 动态版 + musl libc）。
- Secure Boot 当前关闭；开启时在 build 脚本尾部追加 sbsign 步骤即可（UKI 单文件签名）。
- 完全卸载：见 install-phase1.sh 末尾"回退方法"，两条命令干净移除。
