# 事故报告 incident-01：rollback v2 首次实机回滚致系统不可启动

日期：2026-09-26 16:11 · 严重级：P0 · 用户耗时约 40 分钟自行恢复（Manjaro live USB + timeshift）

## 时间线与根因链

1. rollback v2 执行：PLAN 预览 → y 确认 → remount rw → **mv @ 成功**（当前系统被移入 pre-restore 快照目录）
2. 第一次 btrfs 调用（`$BTRFS subvolume list`）报 `subvolume: not found`
3. snapshot 落位（第 6 步）报 `btrfs: not found` → 脚本按 fail 分支退出
4. 此时系统处于**拆解态**：@ 不在根位置
5. 用户按英文指引手动 mv 回原位，重启遇 GRUB rescue：`/@/boot/grub/x86_64-efi/normal.mod not found`
6. 最终经 Manjaro live USB + Timeshift 恢复到 pre-restore 快照（16-11-13，即回滚前原系统）救回

## 直接根因

- **`BTRFS` 变量在 v2 重写时漏定义**。脚本 4 处引用 `$BTRFS` 全部展开为空，btrfs 功能全灭。
- **结构性缺陷**：第一次 btrfs 调用位于 `mv @` **之后**，且脚本无 `set -u`/`set -e`——带病执行，先拆后发现装不回。

## 已落地防线（本次重建后生效）

| 防线 | 作用 |
|---|---|
| `set -u` | 任何未定义变量引用立即中止，绝不允许带病执行 |
| `BTRFS=/bin/btrfs` 绝对路径 | 消灭 PATH/变量类消失问题 |
| **preflight 硬门禁** | mv 之前验证 btrfs/mv/awk/grep 全部可执行，任一失败拒绝开始破坏性流程 |
| 构建自检 3 项断言 | set -u / BTRFS 定义 / HARD GATE 缺一即拒绝出镜像，防回归 |

## 遗留问题

- 用户系统 GRUB 界面"又小又卡"（恢复过程疑似重新生成 grub.cfg 丢失 Manjaro 主题/分辨率配置）——待实机诊断：
  `grep -E 'GFXMODE|THEME' /etc/default/grub`、`pacman -Q grub-theme-manjaro grub-btrfs`、必要时
  `sudo pacman -S grub-theme-manjaro && sudo update-grub`。
- "normal.mod not found" 的确切机理（mv 回位后仍报错）未完全定案——可能与 live 环境恢复时序有关，留档待查。

## 流程教训

破坏性脚本的铁律：**先验证全部工具可用，再动第一刀**；dry-run 计划与工具验证必须在同一门禁内；带病执行一次都不允许。
