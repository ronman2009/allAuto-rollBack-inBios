# 调研报告 02：BSD 可行性评估 与 Secure Boot 支持设计

日期：2026-09-26 · 状态：调研完成（本轮不做开发）

## 1. BSD 救援系统：结论 = 否决（硬冲突，非工程难度）

**核心事实：没有任何 BSD 支持 btrfs。**

- FreeBSD / OpenBSD / NetBSD 的原生与可选文件系统为 UFS/FFS、ZFS（OpenZFS）、HAMMER2（DragonFly）。
- btrfs 是 GPL 许可证 + Linux 内核专用实现（用户态工具完全依赖内核 ioctl），BSD 社区立场明确
  （FreeBSD 论坛官方口径："Not supported at all"，GPL 许可使其永远进不了 base）。
- 连 FUSE 移植都不存在，没有"读一读"的退路。

这意味着：BSD 救援系统**既不能读快照、也不能做子卷 rename 回滚、更不能 chroot 进 Linux 快照修 GRUB**
——项目三大功能全部落空。

**唯一让 BSD 成立的路径**（列出以示完整，均不推荐）：
| 路径 | 代价 |
|---|---|
| 主系统迁 ZFS + ZFSBootMenu | 推翻"Timeshift 基座"前提（Timeshift 无 ZFS 模式）；需重装系统；与已有 2 个 btrfs 快照作别 |
| BSD 只做"格式化重装器" | 不再是快照回滚，退化为重装工具，项目目标不复存在 |

**"BSD 更稳"的论证在本项目不成立**：
救援系统的稳定性来源已定为：只读 A/B 镜像 + 冻结用户态 + 极少更新 + 不联网。
这套架构下，Linux mini 环境（busybox + btrfs-progs + 单内核，~100MB）每次启动
完全相同——BSD 的 release 工程优势在 squashfs 只读镜像里没有用武之地。
反而 BSD 引入新风险：btrfs 不可用（致命）、UEFI Secure Boot 支持不成熟、
救援目标（btrfs ioctl、efibootmgr、GRUB 修复）全是 Linux 生态工具链。

**采纳 BSD 精神的替代**：救援 userland 用 **musl + 全静态链接**（busybox 静态 +
btrfs-progs 静态编译），零动态库、零 glibc 变数——把"少即是稳"落到工具链层面，
内核照用 Linux（btrfs 唯一来源）。

## 2. Secure Boot 支持：天然兼容，设计预留即可

现状：SB 关闭 → POC 无阻塞。方案升级为 **UKI 优先**，使 SB 成为一个签名步骤而非架构改造：

**UKI（Unified Kernel Image）**：内核 + initramfs + cmdline（+ 微码）打包成单个 .efi，
固件直接引导。签一个文件 = 整个引导载荷可信，无需分别签 GRUB/内核/initramfs。
这正是 ZFSBootMenu 的 EFI 二进制形态（ZBM 官方就提供 signed release）。

**开启 SB 时的三条路**（推荐 a）：
| 路径 | 说明 | 备注 |
|---|---|---|
| a. sbctl 自建密钥 + `enroll-keys -m` | 自签 PK/KEK/db 并**保留 Microsoft 密钥** | 双 NVIDIA 机必须保留 MS 密钥：GPU option ROM 由微软签名，全自管密钥可能黑屏 |
| b. shim + MOK | shim（微软签名预加载）+ MOK 注册自签密钥 | 最通用，发行版标准做法 |
| c. 清 Setup Mode 全自管 | 最激进 | 会破坏 Windows 双启与 option ROM，不推荐 |

**运维要点**：
- 每次更新 UKI 必须重签名 → 构建流水线最后一步固定为 sbsign；救援镜像极少更新，负担≈0。
- dbx/SBAT 撤销列表随系统更新保持刷新（BootHole 类撤销会吊销旧 shim/grub）。
- 主系统的内核/GRUB 若也走 SB，同样需要签名钩子（pacman hook 与 ESP 归档 hook 并列）。

**构建侧预留**（现阶段只写进选型，不实施）：
- initramfs 构建输出 UKI：mkinitcpio `--uki` 或 ukify（systemd-stub）。
- 构建流水线：构建 → sbsign → 写入 ESP/recovery 分区 → efibootmgr。
- SB 关闭时签名步骤可跳过（输出未签名 UKI，功能完全相同）。

## 3. 对主报告（research-01.md）的修订

- §5 选型"引导注册"更新为：**UKI 优先**（内核+initramfs+cmdline 单文件），SB 预留 sbsign 环节。
- §5 新增：救援 userland 采用 **musl + 静态链接**（BSD 精神的 Linux 落地）。
- POC 各阶段不变；SB 签名作为阶段 1 构建流水线的可跳过步骤存在。

## 4. 结论

1. **BSD 方向否决**：btrfs 零支持，硬冲突；"BSD 级稳定"由只读镜像架构 + musl 静态链接实现。
2. **Secure Boot 天然兼容**：UKI + sbctl(-m) / shim+MOK，开启 SB 只是加一步签名，架构零改动。
3. 本轮无开发产出；下轮可进入 POC 阶段 0（Timeshift 配置矛盾排查）。
