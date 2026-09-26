#!/bin/sh
# ============================================================
# phase0-timeshift-fix.sh  ——  需 root: sudo ./phase0-timeshift-fix.sh [--create]
# 修复 timeshift.json 与已有 2 个快照的矛盾：
#   子卷树里有 2026-09-19 / 2026-09-23 两个 btrfs 快照，
#   但配置文件显示未初始化。本脚本恢复配置并验证。
# [--create] 额外打一个验证快照（可选）
# ============================================================
set -eu

[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }

CONF=/etc/timeshift/timeshift.json
ROOT_UUID="d505eb2e-6552-43d0-aa7a-529d4e046abd"   # nvme0n1p2

# 1. 备份原配置
BAK="$CONF.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$CONF" "$BAK"
echo "* 已备份原配置 -> $BAK"

# 2. 修复配置字段（python3 JSON 编辑，比 sed 安全）
python3 - "$CONF" "$ROOT_UUID" <<'EOF'
import json, sys
path, uuid = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["btrfs_mode"] = "true"
cfg["do_first_run"] = "false"
cfg["backup_device_uuid"] = uuid
cfg["include_btrfs_home"] = "false"   # @home 独立子卷，不进快照（回滚不冲用户数据）
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
print("* 配置已修复: btrfs_mode=true, backup_device_uuid=%s" % uuid)
EOF

# 3. 验证：Timeshift 能否看到已有快照
echo "* timeshift --list 输出："
timeshift --list || {
    echo "! timeshift --list 失败，请把上面输出发回排查"
    echo "! 可用以下命令回滚配置: cp $BAK $CONF"
    exit 1
}

# 4. 可选：打验证快照
if [ "${1:-}" = "--create" ]; then
    echo "* 打验证快照..."
    timeshift --create --comments "phase0 verification" --tags O
fi

echo "* 阶段 0 完成"
