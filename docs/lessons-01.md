# 全链路复盘 lessons-01：从快照建立到 Timeshift 回滚

日期：2026-09-26 · 来源：incident-01（rollback v2 爆破系统，用户 40 分钟 live USB 自救）

## 1. 全链路职责与依赖

| 环节 | 执行者 | 依赖前提 |
|---|---|---|
| 快照建立 | Timeshift（主系统内） | btrfs 盘 + subvolid=5 可挂 + `@` 存在于根位置 |
| 快照识别 | Timeshift / 救援系统 | `timeshift-btrfs/snapshots/<ts>/` + `info.json` + **根位置有 `@`** |
| 回滚 | 救援系统 | 同上 + btrfs-progs 可执行 + 当前 @ 可 rename |
| 启动 | GRUB | `grubx64.efi` 内嵌 prefix 指向 **`/@/boot/grub`**——`@` 必须在根位置 |

**共同单点：根位置必须有 `@`。** 所有工具（Timeshift、GRUB、我们的救援系统）都以此为大前提。

## 2. 事故因果链（用户实测复原）

```
rollback v2: mv @ 成功 → btrfs 全灭($BTRFS 未定义) → 脚本退出
  ↓ 系统进入"拆解态"：@ 不在根位置
GRUB: prefix /@/boot/grub → normal.mod not found → grub rescue   [照片2]
  ↓ 用户进 live USB
Timeshift(live): 子卷树里没有 @ → "不认盘"                        [用户实测]
  ↓ DeepSeek 指导：从快照复制一个 @ 出来
Timeshift 恢复正常识别 → 回滚到 pre-restore 快照 → 系统救回
```

**结论：事故不是"回滚语义错了"（语义与 Timeshift 源码一致），而是
"拆除操作发生在全部依赖验证之前" + "拆解态没有自愈路径"。**

## 3. 深层设计缺陷与修正

### 缺陷 1：Timeshift 原版序列被照搬，但安全上下文不同
Timeshift 在**运行中的系统**里 mv→snapshot，窗口毫秒级、失败用户当场重试。
救援系统的 mv 失败后，用户面对的是"系统消失"——同样的序列，容错要求完全不同。

**修正（v3 snapshot-first）**：
```
旧: mv @(拆解开始) → snapshot 失败 → 停在拆解态
新: snapshot → @.new-restore（系统完整时完成全部 btrfs ioctl）
    → mv @ → pre-restore 目录   ┐ 两条连续 rename，
    → mv @.new-restore → @      ┘ 毫秒级窗口，任一失败自动逆转
```
任何 btrfs 失败都发生在系统完整时；窗口内失败有自动 revert。

### 缺陷 2：拆解态无自愈路径（用户被迫去 live USB）
**修正（--recover 模式）**：rollback 检测到 @ 缺位自动切换 recover——直接从
所选快照 snapshot 重建 @。init 启动时也会检测并提示 `rollback --recover`。
**这次如果用户重进我们的救援系统而不是 live USB，一条命令就能自救。**

### 缺陷 3：工具链未验证就动破坏性操作（$BTRFS 漏定义）
已落地：preflight 硬门禁 + set -u + 构建自检断言（见 incident-01）。

### 缺陷 4：live 环境的 Timeshift 盲区（教训记录）
live USB 的 `/etc/timeshift` 是 live 自己的（未配置），btrfs 盘也未自动挂载
——live 里用 Timeshift 需要：挂载 subvolid=5 → 手动指定 snapshot device →
且根位置必须有 @。**我们救援系统不存在这些障碍（自带配置与挂载），
这次的正确自救路径本应是 `rollback --recover`。**

## 4. 剩余链路缺口（后续工作）

1. **ESP 寄生归档 pre-hook**：GRUB 的 grub.cfg 已随 @ 覆盖，但 grubx64.efi（ESP）
   仍是盲区——本次事故它恰好无恙（@ 缺位是唯一变量），但不能赌它永远不变。
2. **阶段 4 TUI**：交互体验仍是裸 shell。
3. **rollback 实机验收**：v3 序列需一次成功回滚 + 一次回滚回来，才算闭环。
