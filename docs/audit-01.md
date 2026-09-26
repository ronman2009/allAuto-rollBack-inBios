# 稳定性与强度审查（audit-01）

日期：2026-09-26 · 范围：POC 阶段 0-2 产物（initramfs/UKI/安装链路）+ 阶段 3 设计预审
原则（用户要求）：允许代码冗余，兼容性与稳定性优先。

## 实测里程碑（截至本报告）

| 阶段 | 状态 | 证据 |
|---|---|---|
| 0 Timeshift 引擎修复 | ✅ | 新快照 2026-09-26_14-03-31 已由 phase0 脚本产出 |
| 1 独立引导（无 GRUB） | ✅ | 第四次实测进入救援 shell |
| 2 快照枚举 | ✅ | 3 个快照全部列出 |
| 3 回滚 | 未开始 | 备料已完成（见 §4） |
| 4 TUI 菜单 | 未开始 | 方向已定（ANSI TUI，ZBM 同款） |

## A. 引导层（UKI / ESP）

| # | 风险 | 等级 | 处置 |
|---|---|---|---|
| A1 | UKI 节区布局错误（已发生过两次） | 高（已修） | 按 ArchWiki 动态偏移；新增 `verify-uki.py` 固化进构建（SizeOfImage 覆盖/重叠/.linux 最后/四节区齐全），回归必拦截 |
| A2 | ESP FAT 写入损坏 | 中（已修） | install 脚本追加 `cmp` 字节级校验 |
| A3 | NVRAM 条目重复堆积 | 中（已修） | install 幂等：先清同名旧条目 |
| A4 | NVRAM 被固件/主板清空 | 低 | manifest 重建方案在阶段 3 设计内；救援项本身可从固件菜单手工添加（路径固定） |
| A5 | Secure Boot 开启后拒载 | 已预留 | UKI 单文件 sbsign 即可，构建脚本留注释位 |

## B. initramfs / init 层

| # | 风险 | 等级 | 处置 |
|---|---|---|---|
| B1 | 缺 /dev/console → init 无 stdio 黑屏（已发生过） | 高（已修） | make-cpio.py 注入设备节点；新增构建自检强制校验节点存在 |
| B2 | Alpine busybox 精简 applet（cttyhack 事故） | 高（已修） | init 对可选 applet 一律探测后使用（setsid/-c），不复现硬依赖 |
| B3 | NVMe 驱动为内核模块（m）→ 换内核版本后 vermagic 失配 | **高（残余）** | 当前模块与内核 7.1.13 绑定；主系统内核升级后救援镜像必须重建（build 脚本已从 uname -r 自动收集）。**正式版对策：pacman hook 自动重建 + A/B 双镜像**。POC 期间约定：升级内核后重跑 build+install |
| B4 | busybox insmod 不支持 zstd 压缩模块 | 中（已修） | 构建期解压为裸 .ko |
| B5 | init 脚本语法错误 → panic | 中（已修） | 构建流程 sh -n + 自检；无自动测试环境的替代防线 |
| B6 | 挂载为 rw 时救援 shell 误操作损坏系统 | 中（已修） | **v3 改为默认 RO 挂载**，回滚流程内显式 remount rw |
| B7 | blkid 单点失效（已发生过） | 中（已修） | 双路径发现：blkid UUID → 暴力试探挂载 + timeshift-btrfs 目录验证 |

## C. 快照/回滚语义层（阶段 3 设计预审）

| # | 风险 | 等级 | 设计对策 |
|---|---|---|---|
| C1 | 回滚与 Timeshift 语义不一致 → 双工具互斥 | 高 | 实施前必须通读 Timeshift restore 源码（C/Vala），逐 ioctl 对齐；救援系统只做 rename dance，删除/清理留给 Timeshift |
| C2 | 回滚后根子卷只读 → 系统启动后不可写 | 高 | 不直接 rename ro 快照；先 `btrfs subvolume snapshot` 生成可写副本再 rename 成位（需 btrfs-progs，已备料） |
| C3 | 回滚不可逆 | 中 | rename 原子；旧 @ 保留为命名子卷（@.pre-restore-<ts>），一条命令可撤销 |
| C4 | ESP 回写中途断电 | 中 | 解包到 ESP 临时目录 + mv 原子替换；NVRAM 救援项独立于 ESP，断电后仍可再进救援重做 |
| C5 | 回滚后 NVRAM 丢失启动项 | 中 | manifest（含 efibootmgr 导出）随快照走；回滚流程末尾按 manifest 重建 |
| C6 | GRUB 版本错配（项目最初动机） | 高 | ESP 寄生归档方案已定（pre-hook）；阶段 3 末期实现 |
| C7 | @home 误回滚冲掉用户数据 | 高 | 设计上不触碰 @home；回滚操作白名单只含 @ 与 ESP |

## D. 工程链路层

| # | 风险 | 等级 | 处置 |
|---|---|---|---|
| D1 | 构建产物不可信 | 中（已修） | 构建自检 6 项（init/busybox/dev-console/nvme.ko/btrfs/UKI 结构），任一失败即中止 |
| D2 | 依赖库提取不闭合 | 中（已修） | fetch-btrfs.sh 自带一级+二级 NEEDED 闭合校验（实测抓到 libeconf） |
| D3 | btrfs-progs 依赖 glibc | 已规避 | musl 动态版（btrfs 989K + libs 2.1M），已宿主冒烟通过（v6.14 +LZO +ZSTD +UDEV） |
| D4 | 救援镜像陈旧（主系统大版本演进） | 中 | 更新策略待正式化（pacman hook + A/B）；POC 期靠约定 |
| D5 | ESP 容量（300M） | 低 | 当前 UKI 19M，Manjaro 原文件 ~10M，余量充足 |

## 结论

1. **已发生过 3 次的失败模式（B1/B2/A1/B7）全部转为构建自检项**，同类别回归会被构建期拦截而非上机才暴露。
2. **最大残余风险是 B3（内核版本绑定）**，属于正式版 A/B 更新机制的范畴，POC 期以"升级内核后重建镜像"约定缓解。
3. **阶段 3 前置条件已齐**：btrfs-progs musl 动态版 + 全依赖库已入 initramfs 并冒烟通过；实施前先读 Timeshift restore 源码（C1）。
4. 下一步顺序：读 Timeshift 源码 → 阶段 3 回滚 CLI（菜单选快照 → 干跑预览 → 确认执行 → ESP 回写）→ 阶段 4 TUI 包装。
